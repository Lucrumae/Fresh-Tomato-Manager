import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

class SshService {
  SSHClient? _client;
  TomatoConfig? _config;
  bool _connecting = false;

  SSHClient? get client => _client;

  bool get isConnected => _client != null && !(_client!.isClosed);

  // ── Connect ────────────────────────────────────────────────────────────────
  Future<String?> connect(TomatoConfig config) async {
    // Returns null on success, error string on failure
    if (_connecting) return 'Already connecting...';
    _connecting = true;
    _config = config;

    try {
      await disconnect();

      final socket = await SSHSocket.connect(
        config.host,
        config.sshPort,
        timeout: const Duration(seconds: 10),
      );

      _client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: () => config.password,
      );

      // Authenticate
      await _client!.authenticated.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Authentication timed out'),
      );

      _connecting = false;
      return null; // success

    } on SSHAuthAbortError {
      _connecting = false;
      return 'Authentication failed — check username and password';
    } on SSHAuthFailError {
      _connecting = false;
      return 'Wrong username or password';
    } catch (e) {
      _connecting = false;
      _client = null;
      final msg = e.toString().replaceAll('Exception: ', '');
      if (msg.contains('Connection refused')) {
        return 'SSH connection refused. Enable SSH in router: Administration → Admin Access → SSH';
      }
      if (msg.contains('timed out') || msg.contains('timeout')) {
        return 'Connection timed out. Check IP address and WiFi connection.';
      }
      if (msg.contains('No route') || msg.contains('Network')) {
        return 'Cannot reach ${config.host}. Make sure you are connected to the router WiFi.';
      }
      return 'Connection error: $msg';
    }
  }

  Future<void> disconnect() async {
    try { _client?.close(); } catch (_) {}
    _client = null;
  }

  // ── Run command ────────────────────────────────────────────────────────────
  Future<String> run(String command) async {
    if (!isConnected) throw Exception('Not connected');
    try {
      final session = await _client!.execute(command);
      final bytesList = await session.stdout.toList();
      final allBytes = bytesList.expand((b) => b).toList();
      final output = String.fromCharCodes(Uint8List.fromList(allBytes));
      await session.done;
      return output.trim();
    } catch (e) {
      debugPrint('SSH run error [$command]: $e');
      rethrow;
    }
  }

  // ── Router Status ──────────────────────────────────────────────────────────
  Future<RouterStatus> getStatus() async {
    try {
      // Run all commands in one SSH session for efficiency
      final output = await run('''
echo "=CPU="
cat /proc/stat | head -1
echo "=MEM="
cat /proc/meminfo | grep -E "MemTotal|MemFree|Buffers|Cached"
echo "=UPTIME="
cat /proc/uptime
echo "=NVRAM="
nvram get wan_ipaddr
nvram get lan_ipaddr
nvram get wl0_ssid
nvram get t_model_name
nvram get os_version
''');

      return _parseStatus(output);
    } catch (e) {
      debugPrint('getStatus error: $e');
      return RouterStatus.empty();
    }
  }

  RouterStatus _parseStatus(String raw) {
    try {
      final sections = <String, List<String>>{};
      String? current;
      for (final line in raw.split('\n')) {
        final t = line.trim();
        if (t.startsWith('=') && t.endsWith('=')) {
          current = t.replaceAll('=', '');
          sections[current] = [];
        } else if (current != null && t.isNotEmpty) {
          sections[current]!.add(t);
        }
      }

      // CPU %
      double cpuPercent = 0;
      final cpuLine = sections['CPU']?.firstOrNull ?? '';
      final cpuParts = cpuLine.split(RegExp(r'\s+'));
      if (cpuParts.length >= 8) {
        final user = int.tryParse(cpuParts[1]) ?? 0;
        final nice = int.tryParse(cpuParts[2]) ?? 0;
        final system = int.tryParse(cpuParts[3]) ?? 0;
        final idle = int.tryParse(cpuParts[4]) ?? 0;
        final total = user + nice + system + idle;
        if (total > 0) cpuPercent = (user + nice + system) / total * 100;
      }

      // RAM
      final memMap = <String, int>{};
      for (final line in sections['MEM'] ?? []) {
        final parts = line.split(':');
        if (parts.length == 2) {
          final key = parts[0].trim();
          final val = int.tryParse(parts[1].trim().split(' ')[0]) ?? 0;
          memMap[key] = val;
        }
      }
      final memTotal = memMap['MemTotal'] ?? 0;
      final memFree = memMap['MemFree'] ?? 0;
      final buffers = memMap['Buffers'] ?? 0;
      final cached = memMap['Cached'] ?? 0;
      final memUsed = memTotal - memFree - buffers - cached;

      // Uptime
      String uptime = '-';
      final uptimeLine = sections['UPTIME']?.firstOrNull ?? '';
      final uptimeSecs = double.tryParse(uptimeLine.split(' ')[0]) ?? 0;
      if (uptimeSecs > 0) {
        final d = uptimeSecs ~/ 86400;
        final h = (uptimeSecs % 86400) ~/ 3600;
        final m = (uptimeSecs % 3600) ~/ 60;
        uptime = d > 0 ? '${d}d ${h}h ${m}m' : '${h}h ${m}m';
      }

      // NVRAM values (in order)
      final nvram = sections['NVRAM'] ?? [];

      return RouterStatus(
        cpuPercent: cpuPercent.clamp(0, 100),
        ramUsedMB: (memUsed / 1024).round(),
        ramTotalMB: (memTotal / 1024).round(),
        uptime: uptime,
        wanIp: nvram.length > 0 ? nvram[0] : '-',
        lanIp: nvram.length > 1 ? nvram[1] : '-',
        wifiSsid: nvram.length > 2 ? nvram[2] : '-',
        routerModel: nvram.length > 3 ? nvram[3] : 'FreshTomato Router',
        firmware: nvram.length > 4 ? nvram[4] : '-',
        isOnline: true,
      );
    } catch (e) {
      debugPrint('_parseStatus error: $e');
      return RouterStatus.empty();
    }
  }

  // ── Devices ────────────────────────────────────────────────────────────────
  Future<List<ConnectedDevice>> getDevices() async {
    try {
      final output = await run('''
echo "=ARP="
cat /proc/net/arp
echo "=WL="
wl assoclist 2>/dev/null || echo ""
echo "=BLOCK="
nvram get block_mac 2>/dev/null || echo ""
''');

      return _parseDevices(output);
    } catch (e) {
      debugPrint('getDevices error: $e');
      return [];
    }
  }

  List<ConnectedDevice> _parseDevices(String raw) {
    final devices = <ConnectedDevice>[];
    final sections = _parseSections(raw);

    // Blocked MACs
    final blockedMacs = (sections['BLOCK']?.firstOrNull ?? '')
        .split(' ')
        .map((m) => m.trim().toUpperCase())
        .toSet();

    // Wireless clients from wl assoclist
    final wlMacs = <String>{};
    for (final line in sections['WL'] ?? []) {
      final m = RegExp(r'([0-9A-Fa-f:]{17})').firstMatch(line);
      if (m != null) wlMacs.add(m.group(1)!.toUpperCase());
    }

    // ARP table
    for (final line in sections['ARP'] ?? []) {
      if (line.startsWith('IP') || line.trim().isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;
      final ip = parts[0];
      final mac = parts[3].toUpperCase();
      if (mac == '00:00:00:00:00:00' || mac == '') continue;

      final iface = parts.length > 5 ? parts[5] : 'br0';
      final isWifi = wlMacs.contains(mac);

      devices.add(ConnectedDevice(
        mac: mac,
        ip: ip,
        name: '',
        interface: isWifi ? 'wl0' : iface,
        rssi: '-',
        isBlocked: blockedMacs.contains(mac),
        lastSeen: DateTime.now(),
      ));
    }

    return devices;
  }

  // ── Bandwidth ──────────────────────────────────────────────────────────────
  Future<Map<String, int>> getBandwidthRaw() async {
    try {
      // Get WAN interface name first
      final wan = await run("nvram get wan_iface 2>/dev/null || echo 'eth0'");
      final wanIface = wan.trim().isEmpty ? 'eth0' : wan.trim();
      final output = await run("cat /proc/net/dev | grep '$wanIface'");

      // Format: iface: rx_bytes ... tx_bytes
      final parts = output.split(RegExp(r'\s+'));
      if (parts.length >= 10) {
        final rx = int.tryParse(parts[1].replaceAll('${wanIface}:', '')) ??
                   int.tryParse(parts[1]) ?? 0;
        final tx = int.tryParse(parts[9]) ?? 0;
        return {'rx': rx, 'tx': tx};
      }
      return {'rx': 0, 'tx': 0};
    } catch (e) {
      return {'rx': 0, 'tx': 0};
    }
  }

  // ── Block/Unblock device ───────────────────────────────────────────────────
  Future<bool> blockDevice(String mac, bool block) async {
    try {
      if (block) {
        // Add iptables rule to drop traffic from this MAC
        await run('iptables -I FORWARD -m mac --mac-source $mac -j DROP 2>/dev/null');
        // Also save to NVRAM
        final current = await run('nvram get block_mac');
        final macs = current.trim().isEmpty
            ? <String>[]
            : current.trim().split(' ');
        if (!macs.contains(mac)) {
          macs.add(mac);
          await run("nvram set block_mac='${macs.join(' ')}' && nvram commit");
        }
      } else {
        // Remove iptables rule
        await run('iptables -D FORWARD -m mac --mac-source $mac -j DROP 2>/dev/null');
        // Remove from NVRAM
        final current = await run('nvram get block_mac');
        final macs = current.trim().split(' ')
            .where((m) => m.trim() != mac).toList();
        await run("nvram set block_mac='${macs.join(' ')}' && nvram commit");
      }
      return true;
    } catch (e) {
      debugPrint('blockDevice error: $e');
      return false;
    }
  }

  // ── Reboot ─────────────────────────────────────────────────────────────────
  Future<bool> reboot() async {
    try {
      await run('reboot');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Logs ──────────────────────────────────────────────────────────────────
  Future<List<LogEntry>> getLogs() async {
    try {
      final output = await run('logread | tail -200');
      final entries = <LogEntry>[];
      for (final line in output.split('\n')) {
        if (line.trim().isEmpty) continue;
        // Format: "Mon Jan  1 00:00:00 2024 daemon.info process: message"
        final match = RegExp(
          r'^(\w+ \w+ +\d+ \d+:\d+:\d+ \d+) (\S+)\.(\S+) ([^:]+): (.*)'
        ).firstMatch(line);
        if (match != null) {
          entries.add(LogEntry(
            time: _parseLogTime(match.group(1) ?? ''),
            process: match.group(4) ?? '-',
            level: match.group(3) ?? 'info',
            message: match.group(5) ?? line,
          ));
        } else {
          entries.add(LogEntry(
            time: DateTime.now(),
            process: '-',
            level: 'info',
            message: line,
          ));
        }
      }
      return entries.reversed.toList();
    } catch (e) {
      return [];
    }
  }

  // ── QoS (via iptables/tc) ─────────────────────────────────────────────────
  Future<List<QosRule>> getQosRules() async {
    try {
      final output = await run('nvram get qos_bwrates 2>/dev/null || echo ""');
      if (output.trim().isEmpty) return [];
      return output.trim().split('>').where((s) => s.isNotEmpty).map((s) {
        final parts = s.split('<');
        return QosRule(
          id: parts[0],
          name: parts.length > 4 ? parts[4] : 'Rule',
          mac: parts.length > 1 ? parts[1] : '',
          downloadKbps: int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
          uploadKbps: int.tryParse(parts.length > 3 ? parts[3] : '0') ?? 0,
          enabled: true,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<bool> saveQosRule(QosRule rule) async {
    try {
      final current = await run('nvram get qos_bwrates 2>/dev/null || echo ""');
      final rules = current.trim().isEmpty ? <String>[] : current.trim().split('>');
      final newRule = '${rule.id}<${rule.mac}<${rule.downloadKbps}<${rule.uploadKbps}<${rule.name}';
      final idx = rules.indexWhere((r) => r.startsWith('${rule.id}<'));
      if (idx >= 0) rules[idx] = newRule; else rules.add(newRule);
      await run("nvram set qos_bwrates='${rules.join('>')}' && nvram commit");
      return true;
    } catch (_) { return false; }
  }

  // ── Port Forward ──────────────────────────────────────────────────────────
  Future<List<PortForwardRule>> getPortForwardRules() async {
    try {
      final output = await run('nvram get portforward 2>/dev/null || echo ""');
      if (output.trim().isEmpty) return [];
      return output.trim().split('>').where((s) => s.isNotEmpty).map((s) {
        final parts = s.split('<');
        return PortForwardRule(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: parts.length > 5 ? parts[5] : '',
          protocol: parts.length > 1 ? parts[1] : 'tcp',
          externalPort: int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
          internalPort: int.tryParse(parts.length > 3 ? parts[3] : '0') ?? 0,
          internalIp: parts.length > 4 ? parts[4] : '',
          enabled: s.startsWith('on'),
        );
      }).toList();
    } catch (e) { return []; }
  }

  Future<bool> savePortForwardRules(List<PortForwardRule> rules) async {
    try {
      final data = rules.map((r) =>
        '${r.enabled ? 'on' : 'off'}<${r.protocol}<${r.externalPort}<${r.internalPort}<${r.internalIp}<${r.name}'
      ).join('>');
      await run("nvram set portforward='$data' && nvram commit");
      return true;
    } catch (_) { return false; }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Map<String, List<String>> _parseSections(String raw) {
    final sections = <String, List<String>>{};
    String? current;
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.startsWith('=') && t.endsWith('=')) {
        current = t.replaceAll('=', '');
        sections[current] = [];
      } else if (current != null && t.isNotEmpty) {
        sections[current]!.add(t);
      }
    }
    return sections;
  }

  DateTime _parseLogTime(String s) {
    try {
      return DateTime.parse(s);
    } catch (_) {
      return DateTime.now();
    }
  }
}

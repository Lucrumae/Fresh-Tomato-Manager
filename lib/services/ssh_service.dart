import 'dart:async';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

class SshService {
  SSHClient? _client;
  TomatoConfig? _config;
  bool _connecting = false;

  bool get isConnected => _client != null && !(_client!.isClosed);
  SSHClient? get client => _client;

  // ── Connect ────────────────────────────────────────────────────────────────
  Future<String?> connect(TomatoConfig config) async {
    if (_connecting) return 'Already connecting...';
    _connecting = true;
    _config = config;

    try {
      await disconnect();
      final socket = await SSHSocket.connect(
        config.host, config.sshPort,
        timeout: const Duration(seconds: 10),
      );
      _client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: () => config.password,
      );
      await _client!.authenticated.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception('Authentication timed out'),
      );
      _connecting = false;
      return null;
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
        return 'SSH connection refused. Enable SSH: Administration → Admin Access → SSH';
      }
      if (msg.contains('timed out') || msg.contains('timeout')) {
        return 'Connection timed out. Check IP and WiFi.';
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
      await session.done;
      return String.fromCharCodes(Uint8List.fromList(allBytes)).trim();
    } catch (e) {
      debugPrint('SSH run error [$command]: $e');
      rethrow;
    }
  }

  Future<String> runWithStderr(String command) async {
    if (!isConnected) throw Exception('Not connected');
    try {
      final session = await _client!.execute(command);
      final outBytes = await session.stdout.toList();
      final errBytes = await session.stderr.toList();
      await session.done;
      final out = String.fromCharCodes(Uint8List.fromList(outBytes.expand((b) => b).toList()));
      final err = String.fromCharCodes(Uint8List.fromList(errBytes.expand((b) => b).toList()));
      return (out + err).trim();
    } catch (e) {
      rethrow;
    }
  }

  // ── Router Status ──────────────────────────────────────────────────────────
  Future<RouterStatus> getStatus() async {
    try {
      final output = await run('''
echo "=CPU="
cat /proc/stat | head -1
echo "=MEM="
cat /proc/meminfo | grep -E "MemTotal|MemFree|Buffers|^Cached"
echo "=UPTIME="
cat /proc/uptime
echo "=TEMP="
cat /proc/dmu/temperature 2>/dev/null || cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0
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

  // ── Traffic history (daily / monthly from nvram) ──────────────────────────
  Future<Map<String, dynamic>> getTrafficHistory() async {
    try {
      final raw = await run(r'''
echo "=DAILY="
nvram get traff-$(date +%Y-%m) 2>/dev/null || nvram get wan_ctrafd 2>/dev/null || echo ""
echo "=MONTHLY="
for m in $(seq 0 5); do
  key=$(date -d "-${m} month" +%Y-%m 2>/dev/null || date -v-${m}m +%Y-%m 2>/dev/null)
  val=$(nvram get "traff-${key}" 2>/dev/null)
  if [ -n "$val" ]; then echo "${key}:${val}"; fi
done
''');
      return _parseTrafficHistory(raw);
    } catch (e) {
      return {};
    }
  }

  Map<String, dynamic> _parseTrafficHistory(String raw) {
    final result = <String, dynamic>{
      'daily': <Map<String, double>>[],
      'monthly': <Map<String, dynamic>>[],
    };
    try {
      final sections = _parseSections(raw);
      // Daily: "day:rxGB rxKB:txGB txKB[...]" format
      final dailyStr = sections['DAILY']?.firstOrNull ?? '';
      if (dailyStr.isNotEmpty) {
        final days = dailyStr.split('[').where((s) => s.isNotEmpty).toList();
        final dailyList = <Map<String, double>>[];
        for (int i = 0; i < days.length && i < 31; i++) {
          final parts = days[i].replaceAll(']','').trim().split(':');
          if (parts.length >= 2) {
            final rxParts = parts[0].split(' ');
            final txParts = parts[1].split(' ');
            final rxGB = (double.tryParse(rxParts[0]) ?? 0);
            final rxKB = (double.tryParse(rxParts.length > 1 ? rxParts[1] : '0') ?? 0);
            final txGB = (double.tryParse(txParts[0]) ?? 0);
            final txKB = (double.tryParse(txParts.length > 1 ? txParts[1] : '0') ?? 0);
            dailyList.add({
              'rx': rxGB + rxKB / (1024 * 1024),
              'tx': txGB + txKB / (1024 * 1024),
              'day': (i + 1).toDouble(),
            });
          }
        }
        result['daily'] = dailyList;
      }
      // Monthly: "YYYY-MM:rxGB rxKB:txGB txKB"
      final monthlyList = <Map<String, dynamic>>[];
      for (final line in sections['MONTHLY'] ?? []) {
        final idx = line.indexOf(':');
        if (idx < 0) continue;
        final month = line.substring(0, idx);
        final rest = line.substring(idx + 1).split(':');
        if (rest.length < 2) continue;
        final rxParts = rest[0].trim().split(' ');
        final txParts = rest[1].trim().split(' ');
        final rxGB = (double.tryParse(rxParts[0]) ?? 0);
        final rxKB = (double.tryParse(rxParts.length > 1 ? rxParts[1] : '0') ?? 0);
        final txGB = (double.tryParse(txParts[0]) ?? 0);
        final txKB = (double.tryParse(txParts.length > 1 ? txParts[1] : '0') ?? 0);
        monthlyList.add({
          'month': month,
          'rx': rxGB + rxKB / (1024 * 1024),
          'tx': txGB + txKB / (1024 * 1024),
        });
      }
      result['monthly'] = monthlyList;
    } catch (_) {}
    return result;
  }

  RouterStatus _parseStatus(String raw) {
    try {
      final sections = _parseSections(raw);

      // CPU
      double cpuPercent = 0;
      final cpuLine = sections['CPU']?.firstOrNull ?? '';
      final cpuParts = cpuLine.split(RegExp(r'\s+'));
      if (cpuParts.length >= 5) {
        final user   = int.tryParse(cpuParts[1]) ?? 0;
        final nice   = int.tryParse(cpuParts[2]) ?? 0;
        final system = int.tryParse(cpuParts[3]) ?? 0;
        final idle   = int.tryParse(cpuParts[4]) ?? 0;
        final total  = user + nice + system + idle;
        if (total > 0) cpuPercent = (user + nice + system) / total * 100;
      }

      // RAM
      final memMap = <String, int>{};
      for (final line in sections['MEM'] ?? []) {
        final parts = line.split(':');
        if (parts.length == 2) {
          final val = int.tryParse(parts[1].trim().split(' ')[0]) ?? 0;
          memMap[parts[0].trim()] = val;
        }
      }
      final memTotal = memMap['MemTotal'] ?? 0;
      final memFree  = memMap['MemFree'] ?? 0;
      final buffers  = memMap['Buffers'] ?? 0;
      final cached   = memMap['Cached'] ?? 0;
      final memUsed  = memTotal - memFree - buffers - cached;

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

      // CPU Temp
      double cpuTempC = 0;
      final tempLine = (sections['TEMP'] ?? []).firstOrNull ?? '0';
      final tempVal = double.tryParse(tempLine.trim()) ?? 0;
      // /proc/dmu/temperature returns value like "temperature: 52000" or raw "52000"
      // /sys/class/thermal returns millidegrees e.g. 52000
      if (tempVal > 1000) {
        cpuTempC = tempVal / 1000; // millidegrees -> degrees
      } else if (tempVal > 0) {
        cpuTempC = tempVal; // already in degrees
      }

      final nvram = sections['NVRAM'] ?? [];
      return RouterStatus(
        cpuPercent: cpuPercent.clamp(0, 100),
        ramUsedMB: (memUsed / 1024).round(),
        ramTotalMB: (memTotal / 1024).round(),
        uptime: uptime,
        wanIp: nvram.length > 0 ? nvram[0] : '-',
        lanIp: nvram.length > 1 ? nvram[1] : '-',
        wifiSsid: nvram.length > 2 ? nvram[2] : '-',
        routerModel: nvram.length > 3 ? nvram[3] : 'FreshTomato',
        firmware: nvram.length > 4 ? nvram[4] : '-',
        isOnline: true,
        cpuTempC: cpuTempC,
      );
    } catch (e) {
      return RouterStatus.empty();
    }
  }

  // ── Devices ────────────────────────────────────────────────────────────────
  Future<List<ConnectedDevice>> getDevices() async {
    try {
      final output = await run(r'''
echo "=ARP="
cat /proc/net/arp
echo "=WL0="
wl -i eth1 assoclist 2>/dev/null || wl assoclist 2>/dev/null || echo ""
echo "=WL1="
wl -i eth2 assoclist 2>/dev/null || echo ""
echo "=LEASES="
cat /var/lib/misc/dnsmasq.leases 2>/dev/null || cat /tmp/dnsmasq.leases 2>/dev/null || echo ""
echo "=NAMES="
nvram get dhcp_static_leases 2>/dev/null || echo ""
echo "=BLOCK="
iptables -L FORWARD -n 2>/dev/null | grep "MAC" | awk '{print $NF}' | sed 's/MAC //' || echo ""
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

    // Blocked MACs dari iptables
    final blockedMacs = <String>{};
    for (final line in sections['BLOCK'] ?? []) {
      final m = RegExp(r'([0-9A-Fa-f:]{17})').firstMatch(line);
      if (m != null) blockedMacs.add(m.group(1)!.toUpperCase());
    }

    // Wireless MACs
    final wlMacs = <String>{};
    for (final line in [...(sections['WL0'] ?? []), ...(sections['WL1'] ?? [])]) {
      final m = RegExp(r'([0-9A-Fa-f:]{17})').firstMatch(line);
      if (m != null) wlMacs.add(m.group(1)!.toUpperCase());
    }

    // dnsmasq.leases: "expiry MAC IP hostname clientid"
    final hostnameMap = <String, String>{};
    for (final line in sections['LEASES'] ?? []) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        final mac = parts[1].toUpperCase();
        final host = parts[3] == '*' ? '' : parts[3];
        if (host.isNotEmpty) hostnameMap[mac] = host;
      }
    }

    // DHCP static leases untuk nama (format: MAC:IP:hostname:lease>...)
    final nameMap = <String, String>{};
    for (final entry in (sections['NAMES']?.firstOrNull ?? '').split('>')) {
      final parts = entry.split(':');
      if (parts.length >= 3) {
        nameMap[parts[0].toUpperCase()] = parts[2];
      }
    }

    // ARP table
    for (final line in sections['ARP'] ?? []) {
      if (line.startsWith('IP') || line.trim().isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;
      final ip  = parts[0];
      final mac = parts[3].toUpperCase();
      if (mac == '00:00:00:00:00:00' || mac.isEmpty || mac == '(INCOMPLETE)') continue;
      final iface = parts.length > 5 ? parts[5] : 'br0';

      devices.add(ConnectedDevice(
        mac: mac, ip: ip,
        name: nameMap[mac] ?? '',
        hostname: hostnameMap[mac] ?? '',
        interface: wlMacs.contains(mac) ? 'wl0' : iface,
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
      final wan = (await run("nvram get wan_iface 2>/dev/null || echo 'vlan2'")).trim();
      final wanIface = wan.isEmpty ? 'vlan2' : wan;
      // Try WAN iface first, fallback to br0
      final output = await run("cat /proc/net/dev | grep -E '$wanIface|br0' | head -1");
      final line = output.split('\n').first;
      final clean = line.replaceAll(RegExp(r'^[^:]+:'), '').trim();
      final parts = clean.split(RegExp(r'\s+'));
      if (parts.length >= 9) {
        return {'rx': int.tryParse(parts[0]) ?? 0, 'tx': int.tryParse(parts[8]) ?? 0};
      }
      return {'rx': 0, 'tx': 0};
    } catch (e) {
      return {'rx': 0, 'tx': 0};
    }
  }

  // ── Block/Unblock ──────────────────────────────────────────────────────────
  Future<bool> blockDevice(String mac, bool block) async {
    try {
      final macLower = mac.toLowerCase();
      if (block) {
        // Add iptables rule - block both directions
        await run('iptables -I FORWARD -m mac --mac-source $macLower -j DROP 2>/dev/null; '
                  'iptables -I FORWARD -m mac --mac-source ${mac.toUpperCase()} -j DROP 2>/dev/null');
        debugPrint('Blocked $mac');
      } else {
        // Remove all rules for this MAC
        await run('iptables -D FORWARD -m mac --mac-source $macLower -j DROP 2>/dev/null; '
                  'iptables -D FORWARD -m mac --mac-source ${mac.toUpperCase()} -j DROP 2>/dev/null; '
                  'iptables -D FORWARD -m mac --mac-source $macLower -j DROP 2>/dev/null');
        debugPrint('Unblocked $mac');
      }
      return true;
    } catch (e) {
      debugPrint('blockDevice error: $e');
      return false;
    }
  }

  // ── Reboot ─────────────────────────────────────────────────────────────────
  Future<bool> reboot() async {
    try { await run('reboot'); return true; } catch (_) { return false; }
  }

  // ── Logs ──────────────────────────────────────────────────────────────────
  Future<List<LogEntry>> getLogs() async {
    try {
      // FreshTomato stores logs in /var/log/messages or via logread
      final output = await runWithStderr(
        'logread 2>/dev/null || cat /var/log/messages 2>/dev/null || dmesg 2>/dev/null | tail -100'
      );
      if (output.trim().isEmpty) return [];
      return _parseLogs(output);
    } catch (e) {
      debugPrint('getLogs error: $e');
      return [];
    }
  }

  List<LogEntry> _parseLogs(String raw) {
    final entries = <LogEntry>[];
    for (final line in raw.split('\n')) {
      if (line.trim().isEmpty) continue;
      // Format 1: "Jan  1 00:00:00 hostname daemon.info process: message"
      final match1 = RegExp(
        r'^(\w+ +\d+ \d+:\d+:\d+) \S+ (\S+)\.(\S+) ([^:]+): (.*)'
      ).firstMatch(line);
      if (match1 != null) {
        entries.add(LogEntry(
          time: _tryParseTime(match1.group(1) ?? ''),
          process: match1.group(4) ?? '-',
          level: match1.group(3) ?? 'info',
          message: match1.group(5) ?? line,
        ));
        continue;
      }
      // Format 2: dmesg "[   0.000000] message"
      final match2 = RegExp(r'^\[\s*[\d.]+\] (.*)').firstMatch(line);
      if (match2 != null) {
        entries.add(LogEntry(
          time: DateTime.now(),
          process: 'kernel',
          level: 'info',
          message: match2.group(1) ?? line,
        ));
        continue;
      }
      // Fallback
      entries.add(LogEntry(
        time: DateTime.now(), process: '-', level: 'info', message: line,
      ));
    }
    return entries; // sudah urut dari atas ke bawah (log lama di atas, baru di bawah)
  }

  DateTime _tryParseTime(String s) {
    try {
      final now = DateTime.now();
      // "Mar  7 11:13:40" → parse with current year
      final parts = s.trim().split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final months = {'Jan':1,'Feb':2,'Mar':3,'Apr':4,'May':5,'Jun':6,
                        'Jul':7,'Aug':8,'Sep':9,'Oct':10,'Nov':11,'Dec':12};
        final month = months[parts[0]] ?? 1;
        final day   = int.tryParse(parts[1]) ?? 1;
        final time  = parts[2].split(':');
        return DateTime(now.year, month, day,
          int.tryParse(time[0]) ?? 0,
          int.tryParse(time[1]) ?? 0,
          int.tryParse(time[2]) ?? 0,
        );
      }
    } catch (_) {}
    return DateTime.now();
  }

  // ── QoS ───────────────────────────────────────────────────────────────────
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
    } catch (e) { return []; }
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
      if (t.startsWith('=') && t.endsWith('=') && t.length > 2) {
        current = t.replaceAll('=', '');
        sections[current] = [];
      } else if (current != null && t.isNotEmpty) {
        sections[current]!.add(t);
      }
    }
    return sections;
  }
}

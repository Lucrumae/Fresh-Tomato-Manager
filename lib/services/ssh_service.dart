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

  //  Connect 
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
      return 'Authentication failed - check username and password';
    } on SSHAuthFailError {
      _connecting = false;
      return 'Wrong username or password';
    } catch (e) {
      _connecting = false;
      _client = null;
      final msg = e.toString().replaceAll('Exception: ', '');
      if (msg.contains('Connection refused')) {
        return 'SSH connection refused. Enable SSH: Administration -> Admin Access -> SSH';
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

  //  Run command 
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

  //  Router Status 
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
( cat /proc/dmu/temperature 2>/dev/null | grep -oE '[0-9]+' | tail -1 ) || \
( cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null ) || \
( cat /sys/class/hwmon/hwmon0/temp1_input 2>/dev/null ) || \
echo 0
echo "=NVRAM="
nvram get wan_ipaddr
nvram get lan_ipaddr
nvram get wl0_ssid
nvram get t_model_name
nvram get os_version
nvram get wl1_ssid
nvram get wl0_radio
nvram get wl1_radio
nvram get wl0_channel
nvram get wl1_channel
nvram get wl0_security_mode
nvram get wl1_security_mode
nvram get wl0_crypto
nvram get wl1_crypto
''');
      return _parseStatus(output);
    } catch (e) {
      debugPrint('getStatus error: $e');
      return RouterStatus.empty();
    }
  }

  // Fast poll - only CPU/RAM/temp, reuses existing nvram fields from [current]
  // CPU jiffies from previous sample - used to compute delta for accurate %
  List<int> _prevCpuJiffies = [];

  Future<RouterStatus> getStatusFast(RouterStatus current) async {
    try {
      // Use separate commands - most reliable, no raw string escaping issues
      final cpuRaw  = (await run('cat /proc/stat | head -1')).trim();
      final memRaw  = (await run('cat /proc/meminfo | grep -E "MemTotal|MemFree|Buffers|Cached"')).trim();
      final tempRaw = (await run(
        'cat /proc/dmu/temperature 2>/dev/null || '
        'cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || '
        'cat /sys/class/hwmon/hwmon0/temp1_input 2>/dev/null || echo 0'
      )).trim();

      // CPU: use delta between samples for accurate per-interval %
      // /proc/stat line: cpu user nice system idle iowait irq softirq steal...
      double cpuPercent = current.cpuPercent;
      final cpuParts = cpuRaw.split(RegExp(r'\s+'));
      if (cpuParts.length >= 5) {
        final jiffies = cpuParts.skip(1).take(8)
            .map((s) => int.tryParse(s) ?? 0).toList();
        if (_prevCpuJiffies.length == jiffies.length) {
          final deltas = List.generate(jiffies.length, (i) =>
              (jiffies[i] - _prevCpuJiffies[i]).clamp(0, 999999));
          final idleDelta   = deltas[3] + (deltas.length > 4 ? deltas[4] : 0); // idle+iowait
          final totalDelta  = deltas.fold(0, (a, b) => a + b);
          if (totalDelta > 0) cpuPercent = (1 - idleDelta / totalDelta) * 100;
        }
        _prevCpuJiffies = jiffies;
      }

      // RAM
      int memTotal = current.ramTotalMB * 1024;
      int memFree = 0, memBuffers = 0, memCached = 0;
      for (final line in memRaw.split('\n')) {
        final p = line.trim().split(RegExp(r'\s+'));
        if (p.length >= 2) {
          final val = int.tryParse(p[1]) ?? 0;
          if (line.startsWith('MemTotal'))  memTotal   = val;
          if (line.startsWith('MemFree'))   memFree    = val;
          if (line.startsWith('Buffers'))   memBuffers = val;
          if (line.startsWith('Cached') && !line.startsWith('SwapCached')) memCached = val;
        }
      }
      final memUsed = (memTotal - memFree - memBuffers - memCached).clamp(0, memTotal);

      // Temp: strip non-numeric prefix, handle millidegrees
      double cpuTempC = current.cpuTempC;
      final tempStr = tempRaw.split('\n').first.replaceAll(RegExp(r'[^0-9.]'), '').trim();
      final tempVal = double.tryParse(tempStr) ?? 0;
      if (tempVal > 1000) cpuTempC = tempVal / 1000;
      else if (tempVal > 0) cpuTempC = tempVal;

      return RouterStatus(
        cpuPercent:    cpuPercent.clamp(0.0, 100.0),
        ramUsedMB:     (memUsed / 1024).round(),
        ramTotalMB:    (memTotal / 1024).round(),
        uptime:        current.uptime,
        wanIp:         current.wanIp,
        lanIp:         current.lanIp,
        wifiSsid:      current.wifiSsid,
        wifiSsid5:     current.wifiSsid5,
        wifi24enabled: current.wifi24enabled,
        wifi5enabled:  current.wifi5enabled,
        wifi5present:  current.wifi5present,
        routerModel:   current.routerModel,
        firmware:      current.firmware,
        isOnline:      true,
        cpuTempC:      cpuTempC,
      );
    } catch (_) { return current; }
  }

  //  Traffic history - reads rstats shared memory signal + /proc/net/dev fallback
  Future<Map<String, dynamic>> getTrafficHistory() async {
    try {
      // FreshTomato rstats daemon stores data in shared memory, also writes to
      // nvram traff-YYYY-MM keys. Try multiple methods.
      final raw = await run(
        // Signal rstats to flush current data to nvram
        r'kill -USR1 $(cat /var/run/rstats.pid 2>/dev/null || pidof rstats 2>/dev/null) 2>/dev/null; '
        r'sleep 1; '
        r'echo "=MONTHS="; '
        // Try to read traff- keys for last 6 months
        r'for M in $(seq 0 5); do '
        r'  KEY=$(date -d "-${M} month" +%Y-%m 2>/dev/null); '
        r'  [ -z "$KEY" ] && continue; '
        r'  VAL=$(nvram get "traff-${KEY}" 2>/dev/null); '
        r'  [ -n "$VAL" ] && echo "${KEY}:${VAL}"; '
        r'done; '
        r'echo "=DEV="; '
        // Fallback: read /proc/net/dev for current WAN interface
        r'WAN=$(nvram get wan_iface 2>/dev/null || echo usb0); '
        r'cat /proc/net/dev | grep -E "${WAN}|br0" | head -3'
      );
      return _parseTrafficHistory(raw);
    } catch (e) {
      return {};
    }
  }

  Map<String, dynamic> _parseTrafficHistory(String raw) {
    final result = <String, dynamic>{
      'daily':   <Map<String, dynamic>>[],
      'monthly': <Map<String, dynamic>>[],
    };
    try {
      final lines = raw.split('\n');
      String section = '';
      final monthData = <String, String>{};
      int devRxBytes = 0, devTxBytes = 0;

      for (final line in lines) {
        final t = line.trim();
        if (t == '=MONTHS=' || t == '=DEV=') { section = t; continue; }
        if (t.isEmpty) continue;

        if (section == '=MONTHS=') {
          final colonIdx = t.indexOf(':');
          if (colonIdx < 7) continue;
          final key = t.substring(0, colonIdx);
          final val = t.substring(colonIdx + 1).trim();
          // Validate key is YYYY-MM format
          if (RegExp(r'\d{4}-\d{2}').hasMatch(key) && val.isNotEmpty) {
            monthData[key] = val;
          }
        } else if (section == '=DEV=') {
          // /proc/net/dev line: "  iface: rx_bytes ... tx_bytes..."
          final clean = t.replaceAll(RegExp(r'^[^:]+:'), '').trim();
          final parts = clean.split(RegExp(r'\s+'));
          if (parts.length >= 9) {
            devRxBytes += int.tryParse(parts[0]) ?? 0;
            devTxBytes += int.tryParse(parts[8]) ?? 0;
          }
        }
      }

      // Build monthly totals from traff- keys
      if (monthData.isNotEmpty) {
        final sortedKeys = monthData.keys.toList()..sort((a, b) => b.compareTo(a));
        final monthlyList = <Map<String, dynamic>>[];

        for (final key in sortedKeys) {
          // FreshTomato traff- format: "rxGB rxKB txGB txKB[...]"
          // Each bracket = one day's data
          final entries = monthData[key]!
              .split('[').where((s) => s.isNotEmpty).toList();
          double totalRx = 0, totalTx = 0;
          for (final entry in entries) {
            final parts = entry.replaceAll(']', '').trim().split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              totalRx += (double.tryParse(parts[0]) ?? 0)
                  + (double.tryParse(parts[1]) ?? 0) / (1024.0 * 1024.0);
              totalTx += (double.tryParse(parts[2]) ?? 0)
                  + (double.tryParse(parts[3]) ?? 0) / (1024.0 * 1024.0);
            } else if (parts.length >= 2) {
              totalRx += (double.tryParse(parts[0]) ?? 0) / 1024.0;
              totalTx += (double.tryParse(parts[1]) ?? 0) / 1024.0;
            }
          }
          if (totalRx > 0 || totalTx > 0) {
            monthlyList.add({'month': key, 'rx': totalRx, 'tx': totalTx});
          }
        }
        result['monthly'] = monthlyList;

        // Daily from most recent month
        if (sortedKeys.isNotEmpty) {
          final entries = monthData[sortedKeys.first]!
              .split('[').where((s) => s.isNotEmpty).toList();
          final dailyList = <Map<String, dynamic>>[];
          for (int i = 0; i < entries.length && i < 31; i++) {
            final parts = entries[i].replaceAll(']', '').trim().split(RegExp(r'\s+'));
            double rx = 0, tx = 0;
            if (parts.length >= 4) {
              rx = (double.tryParse(parts[0]) ?? 0) + (double.tryParse(parts[1]) ?? 0) / (1024.0 * 1024.0);
              tx = (double.tryParse(parts[2]) ?? 0) + (double.tryParse(parts[3]) ?? 0) / (1024.0 * 1024.0);
            } else if (parts.length >= 2) {
              rx = (double.tryParse(parts[0]) ?? 0) / 1024.0;
              tx = (double.tryParse(parts[1]) ?? 0) / 1024.0;
            }
            dailyList.add({'day': i + 1, 'rx': rx, 'tx': tx});
          }
          result['daily'] = dailyList;
        }
      } else if (devRxBytes > 0 || devTxBytes > 0) {
        // Fallback: show current session from /proc/net/dev as today's data
        final now = DateTime.now();
        final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        final rxGB = devRxBytes / (1024.0 * 1024.0 * 1024.0);
        final txGB = devTxBytes / (1024.0 * 1024.0 * 1024.0);
        result['monthly'] = [{'month': monthKey, 'rx': rxGB, 'tx': txGB}];
        result['daily']   = [{'day': now.day, 'rx': rxGB, 'tx': txGB}];
      }
    } catch (_) {}
    return result;
  }

  //  Device connections (conntrack) 
  Future<List<Map<String, dynamic>>> getDeviceConnections(String deviceIp) async {
    try {
      // Use conntrack to get active connections for this device IP
      final raw = await run(
        'conntrack -L 2>/dev/null | grep "src=$deviceIp " || '
        'cat /proc/net/ip_conntrack 2>/dev/null | grep "src=$deviceIp " || echo ""'
      );
      if (raw.trim().isEmpty) return [];

      final conns = <Map<String, dynamic>>[];
      for (final line in raw.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        // Parse: ipv4 2 tcp 6 TTL STATE src=IP dst=IP sport=N dport=N ...
        final proto  = RegExp(r'\btcp\b|\budp\b|\bicmp\b').firstMatch(t)?.group(0) ?? '?';
        final srcIp  = RegExp(r'src=(\S+)').firstMatch(t)?.group(1) ?? '';
        final dstIp  = RegExp(r'dst=(\S+)').firstMatch(t)?.group(1) ?? '';
        final dport  = RegExp(r'dport=(\d+)').firstMatch(t)?.group(1) ?? '?';
        final sport  = RegExp(r'sport=(\d+)').firstMatch(t)?.group(1) ?? '?';
        final state  = RegExp(r'\b(ESTABLISHED|TIME_WAIT|SYN_SENT|CLOSE_WAIT|LISTEN)\b').firstMatch(t)?.group(0) ?? '';
        final rxB    = RegExp(r'bytes=(\d+)').firstMatch(t)?.group(1) ?? '0';
        final pkts   = RegExp(r'packets=(\d+)').firstMatch(t)?.group(1) ?? '0';
        // Only show connections FROM the device (not reply direction)
        if (srcIp != deviceIp) continue;
        if (dstIp.isEmpty || dstIp == '127.0.0.1') continue;
        conns.add({
          'proto':  proto.toUpperCase(),
          'dst':    dstIp,
          'dport':  int.tryParse(dport) ?? 0,
          'sport':  int.tryParse(sport) ?? 0,
          'state':  state,
          'rxBytes': int.tryParse(rxB) ?? 0,
          'packets': int.tryParse(pkts) ?? 0,
        });
      }
      // Sort by port (well-known ports first)
      conns.sort((a, b) => (a['dport'] as int).compareTo(b['dport'] as int));
      return conns;
    } catch (e) {
      return [];
    }
  }

  //  QoS per-device bandwidth limit
  Future<bool> setDeviceBandwidth(String mac, int dlKbps, int ulKbps) async {
    try {
      // qos_bwrates format: mac<dl_kbps<ul_kbps<name>...
      final current = await run('nvram get qos_bwrates 2>/dev/null || echo ""');
      final rules   = current.trim().isEmpty
          ? <String>[]
          : current.trim().split('>').where((s) => s.isNotEmpty).toList();
      final macUp   = mac.toUpperCase();
      // Remove existing rule for this MAC
      rules.removeWhere((r) => r.toUpperCase().startsWith(macUp));
      if (dlKbps > 0 || ulKbps > 0) {
        rules.add('$macUp<$dlKbps<$ulKbps<Device');
      }
      await run("nvram set qos_bwrates='${rules.join('>')}' && nvram commit");
      return true;
    } catch (_) { return false; }
  }

  // Get current bandwidth limit for a device
  Future<Map<String, int>> getDeviceBandwidth(String mac) async {
    try {
      final current = await run('nvram get qos_bwrates 2>/dev/null || echo ""');
      final macUp = mac.toUpperCase();
      for (final rule in current.trim().split('>').where((s) => s.isNotEmpty)) {
        final parts = rule.split('<');
        if (parts.isNotEmpty && parts[0].toUpperCase() == macUp) {
          return {
            'dl': int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
            'ul': int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
          };
        }
      }
      return {'dl': 0, 'ul': 0};
    } catch (_) { return {'dl': 0, 'ul': 0}; }
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

      // CPU Temp - try multiple sources and formats
      double cpuTempC = 0;
      final tempLines = sections['TEMP'] ?? [];
      for (final tl in tempLines) {
        // Strip prefix like "temperature: 52000" or "Temp: 52.0"
        final cleaned = tl.replaceAll(RegExp(r'[a-zA-Z:=\s]+'), '').trim();
        final tempVal = double.tryParse(cleaned) ?? 0;
        if (tempVal > 1000) {
          cpuTempC = tempVal / 1000; // millidegrees
          break;
        } else if (tempVal > 0) {
          cpuTempC = tempVal; // already celsius
          break;
        }
      }

      final nvram = sections['NVRAM'] ?? [];
      final ssid5  = nvram.length > 5 ? nvram[5].trim() : '';
      final r24    = nvram.length > 6 ? nvram[6].trim() : '1';
      final r5     = nvram.length > 7 ? nvram[7].trim() : '1';
      final ch24   = nvram.length > 8 ? nvram[8].trim() : '';
      final ch5    = nvram.length > 9 ? nvram[9].trim() : '';
      final sec24  = nvram.length > 10 ? nvram[10].trim() : '';
      final sec5   = nvram.length > 11 ? nvram[11].trim() : '';
      final cry24  = nvram.length > 12 ? nvram[12].trim() : '';
      final cry5   = nvram.length > 13 ? nvram[13].trim() : '';
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
        wifiSsid5: ssid5,
        wifi24enabled: r24 != '0',
        wifi5enabled: r5 != '0',
        wifi5present: ssid5.isNotEmpty,
        isOnline: true,
        cpuTempC: cpuTempC,
      );
    } catch (e) {
      return RouterStatus.empty();
    }
  }

  //  Devices 
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
cat /var/lib/misc/dnsmasq.leases 2>/dev/null || cat /tmp/var/lib/misc/dnsmasq.leases 2>/dev/null || cat /tmp/dnsmasq.leases 2>/dev/null || echo ""
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

  //  Bandwidth 
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

  //  Block/Unblock 
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

  //  Reboot 
  Future<bool> reboot() async {
    try { await run('reboot'); return true; } catch (_) { return false; }
  }

  //  Logs 
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
      // "Mar  7 11:13:40"  parse with current year
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

  //  QoS 
  // QoS per-device bandwidth rules - main QoS is in bandwidth_screen
  Future<List<QosRule>> getQosRules() async {
    try {
      final output = await run('nvram get qos_bwrates 2>/dev/null || echo ""');
      if (output.trim().isEmpty) return [];
      return output.trim().split('>').where((s) => s.isNotEmpty).map((s) {
        final parts = s.split('<');
        return QosRule(
          id: parts.isNotEmpty ? parts[0] : DateTime.now().millisecondsSinceEpoch.toString(),
          mac: parts.isNotEmpty ? parts[0] : '',
          downloadKbps: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
          uploadKbps: int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
          name: parts.length > 3 ? parts[3] : 'Device',
          enabled: true,
        );
      }).toList();
    } catch (e) { return []; }
  }

  Future<bool> saveQosRule(QosRule rule) async {
    try {
      final current = await run('nvram get qos_bwrates 2>/dev/null || echo ""');
      final rules = current.trim().isEmpty ? <String>[] : current.trim().split('>');
      final newRule = '${rule.mac}<${rule.downloadKbps}<${rule.uploadKbps}<${rule.name}';
      final idx = rules.indexWhere((r) => r.startsWith('${rule.mac}<'));
      if (idx >= 0) rules[idx] = newRule; else rules.add(newRule);
      await run("nvram set qos_bwrates='${rules.join('>')}' && nvram commit");
      return true;
    } catch (_) { return false; }
  }


  //  Port Forward 
  Future<List<PortForwardRule>> getPortForwardRules() async {
    try {
      final output = await run('nvram get portforward 2>/dev/null || echo ""');
      if (output.trim().isEmpty) return [];
      // FreshTomato format: enabled<proto<src_ip<ext_port<int_port<int_ip<desc
      // enabled: 0=disabled, 1=enabled; proto: 1=tcp, 2=udp, 3=both
      final rules = <PortForwardRule>[];
      int i = 0;
      for (final s in output.trim().split('>').where((s) => s.isNotEmpty)) {
        final parts = s.split('<');
        if (parts.length < 5) continue;
        final enabled  = parts[0].trim() != '0';
        final protoNum = parts[1].trim();
        final proto    = protoNum == '2' ? 'udp' : protoNum == '3' ? 'both' : 'tcp';
        // parts[2] = src_ip restriction (often empty)
        final extPort  = parts.length > 3 ? parts[3].trim() : '';
        final intPort  = parts.length > 4 ? parts[4].trim() : '';
        final intIp    = parts.length > 5 ? parts[5].trim() : '';
        final desc     = parts.length > 6 ? parts[6].trim() : '';
        if (extPort.isEmpty && intIp.isEmpty) continue;
        rules.add(PortForwardRule(
          id: 'pf_${i++}',
          name: desc.isNotEmpty ? desc : 'Rule ${i}',
          protocol: proto,
          externalPort: int.tryParse(extPort.split(':').first.split(',').first) ?? 0,
          internalPort: int.tryParse(intPort.split(':').first.split(',').first) ?? 0,
          internalIp: intIp,
          enabled: enabled,
        ));
      }
      return rules;
    } catch (e) { return []; }
  }

  Future<bool> savePortForwardRules(List<PortForwardRule> rules) async {
    try {
      // FreshTomato format: enabled<proto<src_ip<ext_port<int_port<int_ip<desc
      final data = rules.map((r) {
        final protoNum = r.protocol == 'udp' ? '2' : r.protocol == 'both' ? '3' : '1';
        final en = r.enabled ? '1' : '0';
        return '$en<$protoNum<<${r.externalPort}<${r.internalPort}<${r.internalIp}<${r.name}';
      }).join('>');
      await run("nvram set portforward='$data' && nvram commit");
      run('(service firewall restart > /dev/null 2>&1 &)').catchError((_){});
      return true;
    } catch (_) { return false; }
  }


  //  Helpers 
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

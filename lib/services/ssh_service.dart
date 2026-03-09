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

  //  Per-device bandwidth limiting via iptables hashlimit
  // Uses hashlimit module which is reliable on this router's kernel
  // dlKbps/ulKbps in Kbps (0 = remove limit). deviceIp = LAN IP of device
  Future<bool> setDeviceBandwidth(String deviceIp, int dlKbps, int ulKbps) async {
    try {
      final oct = deviceIp.split('.').last;
      final dlName = 'bwdl$oct';
      final ulName = 'bwul$oct';

      // Always remove existing rules first (clean slate)
      await run(
        'iptables -D FORWARD -d $deviceIp -m hashlimit --hashlimit-name $dlName '
        '--hashlimit-above 1kb/s --hashlimit-mode dstip -j DROP 2>/dev/null; '
        'iptables -D FORWARD -s $deviceIp -m hashlimit --hashlimit-name $ulName '
        '--hashlimit-above 1kb/s --hashlimit-mode srcip -j DROP 2>/dev/null; '
        'true'
      );

      if (dlKbps > 0 || ulKbps > 0) {
        final cmds = <String>[];
        if (dlKbps > 0) {
          cmds.add(
            'iptables -I FORWARD -d $deviceIp -m hashlimit '
            '--hashlimit-name $dlName '
            '--hashlimit-above ${dlKbps}kb/s '
            '--hashlimit-mode dstip '
            '--hashlimit-burst ${(dlKbps * 2).clamp(64, 65536)} '
            '-j DROP'
          );
        }
        if (ulKbps > 0) {
          cmds.add(
            'iptables -I FORWARD -s $deviceIp -m hashlimit '
            '--hashlimit-name $ulName '
            '--hashlimit-above ${ulKbps}kb/s '
            '--hashlimit-mode srcip '
            '--hashlimit-burst ${(ulKbps * 2).clamp(64, 65536)} '
            '-j DROP'
          );
        }
        await run(cmds.join(' && '));
      }

      // Persist to nvram
      final key = 'bwl_${deviceIp.replaceAll('.', '_')}';
      run('nvram set ${key}_d=$dlKbps && nvram set ${key}_u=$ulKbps && nvram commit')
        .catchError((_) {});
      return true;
    } catch (e) {
      debugPrint('setDeviceBandwidth error: \$e');
      return false;
    }
  }

  Future<Map<String, int>> getDeviceBandwidth(String deviceIp) async {
    try {
      final key = 'bwl_${deviceIp.replaceAll('.', '_')}';
      final dl = (await run('nvram get ${key}_d 2>/dev/null || echo 0')).trim();
      final ul = (await run('nvram get ${key}_u 2>/dev/null || echo 0')).trim();
      return {
        'dl': int.tryParse(dl.isEmpty || dl == 'null' ? '0' : dl) ?? 0,
        'ul': int.tryParse(ul.isEmpty || ul == 'null' ? '0' : ul) ?? 0,
      };
    } catch (_) { return {'dl': 0, 'ul': 0}; }
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

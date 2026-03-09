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
      final output = await run(\'\'\'
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
nvram get wan_iface
\'\'\');
      return _parseStatus(output);
    } catch (e) {
      debugPrint('getStatus error: $e');
      return RouterStatus.empty();
    }
  }

  RouterStatus _parseStatus(String raw) {
    try {
      final sections = _parseSections(raw);
      final cpu   = sections['CPU']    ?? [];
      final mem   = sections['MEM']    ?? [];
      final upt   = sections['UPTIME'] ?? [];
      final tmp   = sections['TEMP']   ?? [];
      final nvram = sections['NVRAM']  ?? [];

      // CPU %
      double cpuPct = 0;
      if (cpu.isNotEmpty) {
        final parts = cpu[0].split(RegExp(r'\s+'));
        final jiffies = parts.skip(1).take(8)
            .map((s) => int.tryParse(s) ?? 0).toList();
        if (_prevCpuJiffies.length == jiffies.length) {
          final deltas = List.generate(jiffies.length,
              (i) => (jiffies[i] - _prevCpuJiffies[i]).clamp(0, 999999));
          final idle  = deltas[3] + (deltas.length > 4 ? deltas[4] : 0);
          final total = deltas.fold(0, (a, b) => a + b);
          if (total > 0) cpuPct = (1 - idle / total) * 100;
        }
        _prevCpuJiffies = jiffies;
      }

      // RAM
      int memTotal = 0, memFree = 0, memBuf = 0, memCached = 0;
      for (final line in mem) {
        final p = line.split(RegExp(r'\s+'));
        final v = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
        if (line.startsWith('MemTotal'))  memTotal  = v;
        if (line.startsWith('MemFree'))   memFree   = v;
        if (line.startsWith('Buffers'))   memBuf    = v;
        if (line.startsWith('Cached') && !line.startsWith('SwapCached')) memCached = v;
      }
      final memUsed = (memTotal - memFree - memBuf - memCached).clamp(0, memTotal);

      // Uptime
      String uptimeStr = '-';
      if (upt.isNotEmpty) {
        final secs = double.tryParse(upt[0].split(' ').first) ?? 0;
        final d = (secs ~/ 86400);
        final h = (secs ~/ 3600) % 24;
        final m = (secs ~/ 60) % 60;
        uptimeStr = d > 0 ? '${d}d ${h}h ${m}m' : h > 0 ? '${h}h ${m}m' : '${m}m';
      }

      // Temp
      double cpuTemp = 0;
      if (tmp.isNotEmpty) {
        final tv = double.tryParse(
            tmp[0].split('\n').first.replaceAll(RegExp(r'[^0-9.]'), '').trim()) ?? 0;
        cpuTemp = tv > 1000 ? tv / 1000 : tv;
      }

      // NVRAM lines (positional — must match nvram get order above)
      String get(int i) => (i < nvram.length ? nvram[i] : '').trim();
      final wanIp    = get(0);
      final lanIp    = get(1);
      final ssid24   = get(2);
      final model    = get(3);
      final fw       = get(4);
      final ssid5    = get(5);
      final wl0on    = get(6) == '1';
      final wl1on    = get(7) == '1';
      final wanIface = get(14); // wan_iface (15th nvram get)
      final wifi5p   = ssid5.isNotEmpty && ssid5 != 'null';

      return RouterStatus(
        cpuPercent:    cpuPct.clamp(0.0, 100.0),
        ramUsedMB:     (memUsed / 1024).round(),
        ramTotalMB:    (memTotal / 1024).round(),
        uptime:        uptimeStr,
        wanIp:         wanIp.isEmpty ? '-' : wanIp,
        lanIp:         lanIp.isEmpty ? '-' : lanIp,
        wifiSsid:      ssid24,
        wifiSsid5:     ssid5,
        wifi24enabled: wl0on,
        wifi5enabled:  wl1on,
        wifi5present:  wifi5p,
        routerModel:   model.isEmpty ? 'Unknown' : model,
        firmware:      fw.isEmpty ? '-' : fw,
        isOnline:      true,
        cpuTempC:      cpuTemp,
        wanIface:      wanIface.isEmpty ? 'eth0' : wanIface,
      );
    } catch (e) {
      debugPrint('_parseStatus error: $e');
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
        wanIface:      current.wanIface,
      );
    } catch (_) { return current; }
  }

  //  Universal bandwidth bytes from /proc/net/dev
  //  Detects WAN interface from nvram wan_iface, then sums rx/tx bytes.
  //  Falls back through: wan_iface → eth0 → first active non-loopback iface.
  //  Used by bandwidthProvider for realtime 1-second polling.
  //
  //  Skip interfaces that are:
  //    lo, ifb*, sit*, gre*, tun*, tap*, dummy*  (virtual/tunnel)
  //    br0 (LAN bridge — would double-count)
  //  Include: usb*, eth*, vlan*, ppp*, wwan*, rmnet*  (real WAN candidates)
  static const _skipIfaces = ['lo', 'br0', 'ifb', 'sit', 'gre', 'tun', 'tap', 'dummy'];
  static const _wanCandidates = ['usb', 'eth', 'vlan', 'ppp', 'wwan', 'rmnet', 'wan'];

  Future<Map<String, int>> getBandwidthRaw() async {
    try {
      // Read wan_iface from nvram (cached after first getStatus call)
      // and /proc/net/dev in one SSH call
      final raw = await run(
        'echo "=IFACE=\$(nvram get wan_iface 2>/dev/null || echo "")"; '
        'cat /proc/net/dev'
      );

      final lines = raw.split('\n');
      // First line: "=IFACE=usb0"
      String wanIface = '';
      for (final l in lines) {
        if (l.startsWith('=IFACE=')) {
          wanIface = l.substring(7).trim();
          break;
        }
      }

      // Parse /proc/net/dev into map: iface -> {rx, tx}
      final ifaceBytes = <String, Map<String, int>>{};
      for (final line in lines) {
        final t = line.trim();
        if (!t.contains(':')) continue;
        final colonIdx = t.indexOf(':');
        final name = t.substring(0, colonIdx).trim();
        if (name.isEmpty || name == 'face') continue;
        final parts = t.substring(colonIdx + 1).trim().split(RegExp(r'\s+'));
        if (parts.length >= 9) {
          ifaceBytes[name] = {
            'rx': int.tryParse(parts[0]) ?? 0,
            'tx': int.tryParse(parts[8]) ?? 0,
          };
        }
      }

      // 1. Try the explicitly configured WAN interface first
      if (wanIface.isNotEmpty && ifaceBytes.containsKey(wanIface)) {
        return ifaceBytes[wanIface]!;
      }

      // 2. Try known WAN candidates in order of traffic (highest bytes first)
      //    Skip loopback, bridges, and virtual interfaces
      final candidates = ifaceBytes.entries.where((e) {
        final n = e.key;
        if (_skipIfaces.any((skip) => n.startsWith(skip))) return false;
        return _wanCandidates.any((cand) => n.startsWith(cand));
      }).toList()
        ..sort((a, b) =>
          (b.value['rx']! + b.value['tx']!).compareTo(
          (a.value['rx']! + a.value['tx']!)));

      if (candidates.isNotEmpty) return candidates.first.value;

      // 3. Fallback: any non-loopback interface with traffic
      final anyActive = ifaceBytes.entries.where((e) =>
        e.key != 'lo' && !e.key.startsWith('ifb') &&
        (e.value['rx']! + e.value['tx']!) > 0
      ).toList()
        ..sort((a, b) =>
          (b.value['rx']! + b.value['tx']!).compareTo(
          (a.value['rx']! + a.value['tx']!)));

      return anyActive.isNotEmpty ? anyActive.first.value : {'rx': 0, 'tx': 0};
    } catch (_) { return {'rx': 0, 'tx': 0}; }
  }

    //  Traffic history - signal rstats to flush then read traff- nvram keys
  //  Fallback to /proc/net/dev cumulative bytes (session total) if no nvram data
  Future<Map<String, dynamic>> getTrafficHistory() async {
    try {
      // Signal rstats daemon to flush current stats to nvram
      // rstats uses SIGUSR1 to trigger immediate save
      final raw = await run(
        'kill -USR1 \$(pidof rstats 2>/dev/null) 2>/dev/null; '
        'sleep 1; '
        'echo "=MONTHS="; '
        'for M in 0 1 2 3 4 5; do \'
        '  D=$(date +%Y-%m 2>/dev/null); \'
        '  [ -z "\$D" ] && break; \'
        '  V=\$(nvram get "traff-\$D" 2>/dev/null); \'
        '  [ -n "\$V" ] && echo "\$D:\$V"; \'
        '  D=\$(date -d "-\${M} month" +%Y-%m 2>/dev/null || true); \'
        '  [ -n "\$D" ] && { V2=\$(nvram get "traff-\$D" 2>/dev/null); [ -n "\$V2" ] && echo "\$D:\$V2"; } \'
        'done 2>/dev/null; '
        'echo "=DEV="; '
        'cat /proc/net/dev'
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
          if (RegExp(r'\d{4}-\d{2}').hasMatch(key) && val.isNotEmpty) {
            monthData[key] = val;
          }
        } else if (section == '=DEV=') {
          // Universal: find the interface with highest traffic (= WAN)
          // Skip loopback, LAN bridge, and virtual interfaces
          if (!t.contains(':')) continue;
          final ci = t.indexOf(':');
          final n  = t.substring(0, ci).trim();
          if (n.isEmpty || n == 'lo' || n == 'br0' ||
              n.startsWith('ifb') || n.startsWith('sit') ||
              n.startsWith('tun') || n.startsWith('tap')) continue;
          final parts = t.substring(ci + 1).trim().split(RegExp(r'\s+'));
          if (parts.length >= 9) {
            final rx = int.tryParse(parts[0]) ?? 0;
            final tx = int.tryParse(parts[8]) ?? 0;
            if (rx + tx > devRxBytes + devTxBytes) {
              devRxBytes = rx;
              devTxBytes = tx;
            }
          }
        }
      }

      // Build monthly totals from traff- keys
      if (monthData.isNotEmpty) {
        final sortedKeys = monthData.keys.toList()..sort((a, b) => b.compareTo(a));
        final monthlyList = <Map<String, dynamic>>[];
        for (final key in sortedKeys) {
          // FreshTomato traff- format: "rxGB rxKB txGB txKB[rxGB rxKB txGB txKB[..."
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

        // Daily breakdown from the most recent month
        if (sortedKeys.isNotEmpty) {
          final entries = monthData[sortedKeys.first]!
              .split('[').where((s) => s.isNotEmpty).toList();
          final dailyList = <Map<String, dynamic>>[];
          for (int i = 0; i < entries.length && i < 31; i++) {
            final parts = entries[i].replaceAll(']', '').trim()
                .split(RegExp(r'\s+'));
            double rx = 0, tx = 0;
            if (parts.length >= 4) {
              rx = (double.tryParse(parts[0]) ?? 0)
                  + (double.tryParse(parts[1]) ?? 0) / (1024.0 * 1024.0);
              tx = (double.tryParse(parts[2]) ?? 0)
                  + (double.tryParse(parts[3]) ?? 0) / (1024.0 * 1024.0);
            } else if (parts.length >= 2) {
              rx = (double.tryParse(parts[0]) ?? 0) / 1024.0;
              tx = (double.tryParse(parts[1]) ?? 0) / 1024.0;
            }
            dailyList.add({'day': i + 1, 'rx': rx, 'tx': tx});
          }
          result['daily'] = dailyList;
        }
      } else if (devRxBytes > 0 || devTxBytes > 0) {
        // No traff- nvram data: show cumulative /proc/net/dev session bytes
        // This represents total bytes since last router boot
        final now = DateTime.now();
        final monthKey = '\${now.year}-\${now.month.toString().padLeft(2, "0")}';
        // Convert bytes to GB
        final rxGB = devRxBytes / (1024.0 * 1024.0 * 1024.0);
        final txGB = devTxBytes / (1024.0 * 1024.0 * 1024.0);
        result['monthly'] = [{'month': monthKey, 'rx': rxGB, 'tx': txGB}];
        result['daily']   = [{'day': now.day,    'rx': rxGB, 'tx': txGB}];
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

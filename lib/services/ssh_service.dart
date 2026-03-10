import 'dart:async';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

class SshService {
  SSHClient? _client;
  TomatoConfig? _config;
  bool _connecting = false;

  // Semaphore: only 1 SSH command runs at a time to prevent channel flood
  bool _cmdInFlight = false;
  final _cmdQueue = <_SshCmd>[];

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
        // SSH-level keepalive — works even when Dart timers are suspended by OS
        keepAliveInterval: const Duration(seconds: 20),
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
    _connecting = false;
    // Drain and fail any queued commands
    for (final cmd in _cmdQueue) {
      cmd.completer.completeError(Exception('Disconnected'));
    }
    _cmdQueue.clear();
    _cmdInFlight = false;
    try { _client?.close(); } catch (_) {}
    _client = null;
  }

  //  Run command 
  // Queue SSH commands — only 1 runs at a time, prevents Dropbear channel flood
  Future<String> run(String command) {
    if (!isConnected) return Future.error(Exception('Not connected'));
    final cmd = _SshCmd(command);
    _cmdQueue.add(cmd);
    _drainQueue();
    return cmd.completer.future;
  }

  void _drainQueue() {
    if (_cmdInFlight || _cmdQueue.isEmpty) return;
    // Drop stale auto-poll commands if queue is backing up (keeps UI responsive)
    while (_cmdQueue.length > 3) {
      final dropped = _cmdQueue.removeAt(0);
      dropped.completer.complete(''); // resolve with empty rather than hang
    }
    _cmdInFlight = true;
    final cmd = _cmdQueue.removeAt(0);
    _execRaw(cmd.command).then((result) {
      cmd.completer.complete(result);
    }).catchError((e) {
      cmd.completer.completeError(e);
    }).whenComplete(() {
      _cmdInFlight = false;
      _drainQueue(); // process next
    });
  }

  Future<String> _execRaw(String command) async {
    if (!isConnected) throw Exception('Not connected');
    try {
      final session = await _client!.execute(command)
          .timeout(const Duration(seconds: 15));
      final bytesList = await session.stdout.toList()
          .timeout(const Duration(seconds: 15));
      final allBytes = bytesList.expand((b) => b).toList();
      await session.done.timeout(const Duration(seconds: 5), onTimeout: () {});
      return String.fromCharCodes(Uint8List.fromList(allBytes)).trim();
    } on TimeoutException {
      debugPrint('SSH timeout [$command]');
      return '';
    } catch (e) {
      debugPrint('SSH error [$command]: $e');
      rethrow;
    }
  }

  Future<String> runWithStderr(String command) {
    return run(command); // uses queue — stderr merged via shell 2>&1 if needed
  }

  Future<String> _runWithStderrLegacy(String command) async {
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
      // Run each command separately to avoid triple-quote escaping issues
      final cpuRaw    = await run('cat /proc/stat | head -1');
      final memRaw    = await run('cat /proc/meminfo | grep -E "MemTotal|MemFree|Buffers|Cached"');
      final uptimeRaw = await run('cat /proc/uptime');
      final tempRaw   = await run(
        'cat /proc/dmu/temperature 2>/dev/null || '
        'cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || '
        'cat /sys/class/hwmon/hwmon0/temp1_input 2>/dev/null || echo 0'
      );
      // Wireless phy temperature — single run to avoid queue buildup
      final wlTempRaw  = await run(
        'wl -i eth1 phy_tempsense_reading 2>/dev/null || echo 0; '
        'wl -i eth2 phy_tempsense_reading 2>/dev/null || echo 0'
      );
      final nvramRaw  = await run(
        'nvram get wan_ipaddr; '
        'nvram get lan_ipaddr; '
        'nvram get wl0_ssid; '
        'nvram get t_model_name; '
        'nvram get os_version; '
        'nvram get wl1_ssid; '
        'nvram get wl0_radio; '
        'nvram get wl1_radio; '
        'nvram get wl0_channel; '
        'nvram get wl1_channel; '
        'nvram get wl0_security_mode; '
        'nvram get wl1_security_mode; '
        'nvram get wl0_crypto; '
        'nvram get wl1_crypto; '
        'nvram get wan_iface; '
        'nvram get wl0_txpwr; '
        'nvram get wl1_txpwr; '
        'nvram get wl0_nbw; '
        'nvram get wl1_nbw; '
        'nvram get wl0_net_mode; '
        'nvram get wl1_net_mode; '
        'nvram get wl0_closed; '
        'nvram get wl1_closed; '
        'nvram get wl0_chanspec; '
        'nvram get wl1_chanspec; '
        'nvram get wl0_akm; '
        'nvram get wl1_akm; '
        'nvram get wl0_auth_mode; '
        'nvram get wl1_auth_mode; '
        'nvram get wl0_wpa_psk; '
        'nvram get wl1_wpa_psk; '
        'nvram get wl0_mode; '
        'nvram get wl1_mode; '
        'nvram get wl0_nctrlsb; '
        'nvram get wl1_nctrlsb'
      );

      final combined = '=CPU=\n$cpuRaw\n=MEM=\n$memRaw\n=UPTIME=\n$uptimeRaw\n=TEMP=\n$tempRaw\n=WLTEMP=\n$wlTempRaw\n=NVRAM=\n$nvramRaw';
      return _parseStatus(combined);
    } catch (e) {
      debugPrint('getStatus error: $e');
      return RouterStatus.empty();
    }
  }

  RouterStatus _parseStatus(String raw) {
    try {
      final sections = _parseSections(raw);
      final cpu    = sections['CPU']    ?? [];
      final wlt    = sections['WLTEMP'] ?? [];
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

      // Wireless phy temperatures (Broadcom formula: raw/2 + 20)
      double wifiTemp24 = 0, wifiTemp5 = 0;
      if (wlt.length >= 1) {
        final raw24 = int.tryParse(wlt[0].trim().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
        if (raw24 > 0) wifiTemp24 = raw24 / 2.0 + 20;
      }
      if (wlt.length >= 2) {
        final raw5 = int.tryParse(wlt[1].trim().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
        if (raw5 > 0) wifiTemp5 = raw5 / 2.0 + 20;
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
      final ch24     = get(8);
      final ch5      = get(9);
      final sec24    = get(10);
      final sec5     = get(11);
      final wanIface   = get(14);
      final txpwr24    = get(15);
      final txpwr5     = get(16);
      final nbw24      = get(17);
      final nbw5       = get(18);
      final netmode24  = get(19);
      final netmode5   = get(20);
      final closed24   = get(21); // 0=broadcast, 1=hidden
      final closed5    = get(22);
      final chanspec24 = get(23);
      final chanspec5  = get(24);
      final akm24      = get(25);
      final akm5       = get(26);
      final authmode24 = get(27);
      final authmode5  = get(28);
      final psk24      = get(29);
      final psk5       = get(30);
      final wlmode24   = get(31);
      final wlmode5    = get(32);
      final nctrlsb24  = get(33); // upper/lower
      final nctrlsb5   = get(34);
      final wifi5p     = ssid5.isNotEmpty && ssid5 != 'null';

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
        wifiChannel24:  ch24,
        wifiChannel5:   ch5,
        wifiSecurity24: sec24,
        wifiSecurity5:  sec5,
        wifiTxpower24:  txpwr24.isNotEmpty ? '${txpwr24} mW' : '',
        wifiTxpower5:   txpwr5.isNotEmpty  ? '${txpwr5} mW' : '',
        wifiNetMode24:  netmode24,
        wifiNetMode5:   netmode5,
        wifiBroadcast24: closed24.isEmpty ? '1' : (closed24 == '0' ? '1' : '0'),
        wifiBroadcast5:  closed5.isEmpty  ? '1' : (closed5  == '0' ? '1' : '0'),
        wifiChanspec24:  chanspec24,
        wifiChanspec5:   chanspec5,
        wifiAkm24:      akm24,
        wifiAkm5:       akm5,
        wifiAuthMode24:  authmode24,
        wifiAuthMode5:   authmode5,
        wifiPassword24:  psk24,
        wifiPassword5:   psk5,
        wifiCrypto24:    get(12), // wl0_crypto
        wifiCrypto5:     get(13), // wl1_crypto
        wifiMode24:      wlmode24,
        wifiMode5:       wlmode5,
        wifiNctrlsb24:   nctrlsb24,
        wifiNctrlsb5:    nctrlsb5,
        wifiTemp24:      wifiTemp24,
        wifiTemp5:       wifiTemp5,
      );
    } catch (e) {
      debugPrint('_parseStatus error: $e');
      return RouterStatus.empty();
    }
  }

  // Fast poll - only CPU/RAM/temp, reuses existing nvram fields from [current]
  List<int> _prevCpuJiffies = [];

  Future<RouterStatus> getStatusFast(RouterStatus current) async {
    try {
      final cpuRaw  = (await run('cat /proc/stat | head -1')).trim();
      final memRaw  = (await run('cat /proc/meminfo | grep -E "MemTotal|MemFree|Buffers|Cached"')).trim();
      final tempRaw = (await run(
        'cat /proc/dmu/temperature 2>/dev/null || '
        'cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || '
        'cat /sys/class/hwmon/hwmon0/temp1_input 2>/dev/null || echo 0'
      )).trim();

      double cpuPercent = current.cpuPercent;
      final cpuParts = cpuRaw.split(RegExp(r'\s+'));
      if (cpuParts.length >= 5) {
        final jiffies = cpuParts.skip(1).take(8)
            .map((s) => int.tryParse(s) ?? 0).toList();
        if (_prevCpuJiffies.length == jiffies.length) {
          final deltas = List.generate(jiffies.length, (i) =>
              (jiffies[i] - _prevCpuJiffies[i]).clamp(0, 999999));
          final idleDelta  = deltas[3] + (deltas.length > 4 ? deltas[4] : 0);
          final totalDelta = deltas.fold(0, (a, b) => a + b);
          if (totalDelta > 0) cpuPercent = (1 - idleDelta / totalDelta) * 100;
        }
        _prevCpuJiffies = jiffies;
      }

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
  static const _skipIfaces = ['lo', 'br0', 'ifb', 'sit', 'gre', 'tun', 'tap', 'dummy'];
  static const _wanCandidates = ['usb', 'eth', 'vlan', 'ppp', 'wwan', 'rmnet', 'wan'];

  Future<Map<String, int>> getBandwidthRaw() async {
    try {
      final raw = await run(
        'echo "=IFACE=\$(nvram get wan_iface 2>/dev/null || echo \"\")"; '
        'cat /proc/net/dev'
      );

      final lines = raw.split('\n');
      String wanIface = '';
      for (final l in lines) {
        if (l.startsWith('=IFACE=')) {
          wanIface = l.substring(7).trim();
          break;
        }
      }

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

      if (wanIface.isNotEmpty && ifaceBytes.containsKey(wanIface)) {
        return ifaceBytes[wanIface]!;
      }

      final candidates = ifaceBytes.entries.where((e) {
        final n = e.key;
        if (_skipIfaces.any((skip) => n.startsWith(skip))) return false;
        return _wanCandidates.any((cand) => n.startsWith(cand));
      }).toList()
        ..sort((a, b) =>
          (b.value['rx']! + b.value['tx']!).compareTo(
          (a.value['rx']! + a.value['tx']!)));

      if (candidates.isNotEmpty) return candidates.first.value;

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

  //  Traffic history — reads data accumulated since firmware boot (rstats nvram keys)
  Future<Map<String, dynamic>> getTrafficHistory() async {
    try {
      // 1. Signal rstats to flush its in-memory data to nvram
      // 2. List all traff-YYYY-MM keys directly from nvram show output
      // 3. Also grab current /proc/net/dev for this session
      // Flush rstats in-memory data to nvram (USR1) and to file (USR2)
      // Then read traff-YYYY-MM keys from nvram (persistent across reboots)
      final raw = await run(
        'PID=\$(cat /var/run/rstats.pid 2>/dev/null); '
        'kill -USR1 \$PID 2>/dev/null; kill -USR2 \$PID 2>/dev/null; '
        'sleep 1; '
        'echo "=MONTHS="; '
        'nvram show 2>/dev/null | grep "^traff-" || true; '
        'echo "=DEV="; '
        'cat /proc/net/dev 2>/dev/null'
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
          // Handle both "YYYY-MM:value" and "traff-YYYY-MM=value" formats
          String? key; String? val;
          if (t.contains('=') && t.startsWith('traff-')) {
            final eqIdx = t.indexOf('=');
            key = t.substring(6, eqIdx); // strip "traff-" prefix
            val = t.substring(eqIdx + 1).trim();
          } else if (t.contains(':')) {
            final colonIdx = t.indexOf(':');
            if (colonIdx >= 7) {
              key = t.substring(0, colonIdx);
              val = t.substring(colonIdx + 1).trim();
            }
          }
          if (key != null && val != null && RegExp(r'\d{4}-\d{2}').hasMatch(key) && val.isNotEmpty) {
            monthData[key] = val;
          }
        } else if (section == '=DEV=') {
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

      if (monthData.isNotEmpty) {
        final sortedKeys = monthData.keys.toList()..sort((a, b) => b.compareTo(a));
        final monthlyList = <Map<String, dynamic>>[];
        for (final key in sortedKeys) {
          final entries = monthData[key]!
              .split('[').where((s) => s.isNotEmpty).toList();
          double totalRx = 0, totalTx = 0;
          for (final entry in entries) {
            final parts = entry.replaceAll(']', '').trim().split(RegExp(r'\s+'));
            // rstats format: [upload_MB download_MB] per day
            // swap so rx=download, tx=upload to match FreshTomato web UI
            if (parts.length >= 4) {
              totalTx += (double.tryParse(parts[0]) ?? 0) / 1024.0
                  + (double.tryParse(parts[1]) ?? 0) / (1024.0 * 1024.0 * 1024.0);
              totalRx += (double.tryParse(parts[2]) ?? 0) / 1024.0
                  + (double.tryParse(parts[3]) ?? 0) / (1024.0 * 1024.0 * 1024.0);
            } else if (parts.length >= 2) {
              totalTx += (double.tryParse(parts[0]) ?? 0) / 1024.0;
              totalRx += (double.tryParse(parts[1]) ?? 0) / 1024.0;
            }
          }
          if (totalRx > 0 || totalTx > 0) {
            monthlyList.add({'month': key, 'rx': totalRx, 'tx': totalTx});
          }
        }
        result['monthly'] = monthlyList;

        if (sortedKeys.isNotEmpty) {
          final entries = monthData[sortedKeys.first]!
              .split('[').where((s) => s.isNotEmpty).toList();
          final dailyList = <Map<String, dynamic>>[];
          for (int i = 0; i < entries.length && i < 31; i++) {
            final parts = entries[i].replaceAll(']', '').trim()
                .split(RegExp(r'\s+'));
            double rx = 0, tx = 0;
            // rstats format: [upload_MB download_MB] — swap to rx=download, tx=upload
            if (parts.length >= 4) {
              tx = (double.tryParse(parts[0]) ?? 0) / 1024.0
                  + (double.tryParse(parts[1]) ?? 0) / (1024.0 * 1024.0 * 1024.0);
              rx = (double.tryParse(parts[2]) ?? 0) / 1024.0
                  + (double.tryParse(parts[3]) ?? 0) / (1024.0 * 1024.0 * 1024.0);
            } else if (parts.length >= 2) {
              tx = (double.tryParse(parts[0]) ?? 0) / 1024.0;
              rx = (double.tryParse(parts[1]) ?? 0) / 1024.0;
            }
            dailyList.add({'day': i + 1, 'rx': rx, 'tx': tx});
          }
          result['daily'] = dailyList;
        }
      } else if (devRxBytes > 0 || devTxBytes > 0) {
        final now = DateTime.now();
        final monthKey = '${now.year}-${now.month.toString().padLeft(2, "0")}';
        final rxGB = devRxBytes / (1024.0 * 1024.0 * 1024.0);
        final txGB = devTxBytes / (1024.0 * 1024.0 * 1024.0);
        result['monthly'] = [{'month': monthKey, 'rx': rxGB, 'tx': txGB}];
        result['daily']   = [{'day': now.day,    'rx': rxGB, 'tx': txGB}];
      }
    } catch (_) {}
    return result;
  }

  //  Device list (ARP table + DHCP leases) 
  Future<List<ConnectedDevice>> getDevices() async {
    try {
      final raw = await run(
        'echo "=ARP="; '
        'cat /proc/net/arp 2>/dev/null; '
        'echo "=LEASES="; '
        'cat /tmp/dnsmasq.leases 2>/dev/null || '
        'cat /tmp/var/lib/misc/dnsmasq.leases 2>/dev/null || '
        'cat /var/lib/misc/dnsmasq.leases 2>/dev/null || true; '
        'echo "=WIFI="; '
        'wl -i eth1 assoclist 2>/dev/null | awk \'{print "eth1 " \$2}\'; '
        'wl -i eth2 assoclist 2>/dev/null | awk \'{print "eth2 " \$2}\''
      );

      // Parse leases: IP -> hostname
      final leaseNames = <String, String>{};
      // WiFi MACs (lowercase) -> iface
      final wifiMacs = <String, String>{}; // mac -> iface

      String section = '';
      for (final line in raw.split('\n')) {
        final t = line.trim();
        if (t == '=ARP=' || t == '=LEASES=' || t == '=WIFI=') { section = t; continue; }
        if (t.isEmpty) continue;

        if (section == '=LEASES=') {
          // format: expiry MAC IP hostname client-id
          final parts = t.split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            final ip   = parts[2];
            final name = parts[3] == '*' ? '' : parts[3];
            leaseNames[ip] = name;
          }
        } else if (section == '=WIFI=') {
          // format: "eth1 AA:BB:CC:DD:EE:FF"
          final parts = t.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            wifiMacs[parts[1].toLowerCase()] = parts[0]; // uppercase from wl -> lowercase key
          }
        }
      }

      // Parse ARP table
      final devices  = <ConnectedDevice>[];
      final seenMacs = <String>{};
      section = '';
      for (final line in raw.split('\n')) {
        final t = line.trim();
        if (t == '=ARP=' || t == '=LEASES=' || t == '=WIFI=') { section = t; continue; }
        if (section != '=ARP=') continue;
        if (t.isEmpty || t.startsWith('IP')) continue;

        final parts = t.split(RegExp(r'\s+'));
        if (parts.length < 6) continue;
        final ip    = parts[0];
        final flags = parts[2];
        final mac   = parts[3].toLowerCase();
        if (mac == '00:00:00:00:00:00' || mac.length != 17) continue;
        if (flags == '0x0') continue;
        if (seenMacs.contains(mac)) continue;
        seenMacs.add(mac);

        // Determine interface: wifi MACs take priority, fallback to ARP device column
        final iface = wifiMacs[mac] ?? (parts.length > 5 ? parts[5] : '');
        final name  = leaseNames[ip] ?? '';
        devices.add(ConnectedDevice(
          ip:        ip,
          mac:       mac,
          name:      name.isNotEmpty ? name : ip,
          hostname:  name,
          interface: iface,
          rssi:      '',
          isBlocked: false,
          lastSeen:  DateTime.now(),
        ));
      }
      return devices;
    } catch (e) {
      debugPrint('getDevices error: $e');
      return [];
    }
  }

  //  Block/unblock device via iptables 
  // ─── Ethernet port states via robocfg show ────────────────────────────────
  // Returns list of maps: [{port:'LAN0', up:true, speed:'1000', duplex:'full'}, ...]
  // vlan1ports on EA6400: 0 1 2 3 5* (ports 0-3=LAN, 4=WAN, 5=CPU)
  Future<List<Map<String, dynamic>>> getEthernetPorts() async {
    try {
      final raw = await run(
        'robocfg show 2>/dev/null || echo ""; '
        'echo "=VLAN="; '
        'nvram get vlan1ports 2>/dev/null; '
        'echo "=WANVLAN="; '
        'nvram get vlan2ports 2>/dev/null'
      );

      // Parse vlan1ports to know which physical ports are LAN vs WAN
      final lines = raw.split('\n');
      String vlan1 = '', vlan2 = '';
      String section = '';
      final portLines = <String>[];
      for (final line in lines) {
        final t = line.trim();
        if (t == '=VLAN=')    { section = 'vlan1'; continue; }
        if (t == '=WANVLAN=') { section = 'vlan2'; continue; }
        if (section == 'vlan1' && t.isNotEmpty) { vlan1 = t; section = ''; }
        else if (section == 'vlan2' && t.isNotEmpty) { vlan2 = t; section = ''; }
        // robocfg show lines: "Port 0: DOWN enabled ..."
        else if (t.startsWith('Port ') && t.contains(':')) { portLines.add(t); }
      }

      // Build port role map from nvram vlanXports
      // Format: "0 1 2 3 5*" — number=port, *=tagged/CPU
      final lanPorts = <int>{};
      final wanPorts = <int>{};
      for (final tok in vlan1.split(RegExp(r'\s+'))) {
        final n = int.tryParse(tok.replaceAll(RegExp(r'[^0-9]'), ''));
        if (n != null) lanPorts.add(n);
      }
      for (final tok in vlan2.split(RegExp(r'\s+'))) {
        final n = int.tryParse(tok.replaceAll(RegExp(r'[^0-9]'), ''));
        if (n != null) wanPorts.add(n);
      }

      // Parse robocfg port lines
      // "Port 0: DOWN enabled stp: none vlan: 1 jumbo: off mac: ..."
      // "Port 0: UP 1000FD enabled stp: none vlan: 1 ..."
      final portRe = RegExp(r'^Port (\d+):\s+(UP|DOWN)(?:\s+(\d+)(FD|HD))?', caseSensitive: false);
      final result = <Map<String, dynamic>>[];

      if (portLines.isNotEmpty) {
        for (final pl in portLines) {
          final m = portRe.firstMatch(pl);
          if (m == null) continue;
          final portNum = int.parse(m.group(1)!);
          final isUp    = m.group(2)!.toUpperCase() == 'UP';
          final speed   = m.group(3) ?? '';
          final duplex  = m.group(4) ?? '';

          // Skip CPU port (usually port 5 marked with * in vlanports)
          // Determine label
          String label;
          if (wanPorts.contains(portNum)) {
            label = 'WAN';
          } else if (lanPorts.contains(portNum)) {
            // LAN ports: number them 0..N in order of appearance
            final lanList = lanPorts.where((p) => !wanPorts.contains(p)).toList()..sort();
            final idx     = lanList.indexOf(portNum);
            label = 'LAN${idx >= 0 ? idx : portNum}';
          } else {
            continue; // CPU/uplink port, skip
          }
          result.add({'port': label, 'up': isUp, 'speed': speed, 'duplex': duplex.toLowerCase()});
        }
      } else {
        // robocfg not available — fallback: check /proc/net/dev for non-zero traffic
        // Show LAN0-LAN3 + WAN based on vlan config, all unknown state
        final lanList = lanPorts.difference(wanPorts).toList()..sort();
        for (int i = 0; i < lanList.length; i++) {
          result.add({'port': 'LAN$i', 'up': null, 'speed': '', 'duplex': ''});
        }
        if (wanPorts.isNotEmpty) {
          result.add({'port': 'WAN', 'up': null, 'speed': '', 'duplex': ''});
        }
      }

      // Sort: LAN0, LAN1... then WAN last
      result.sort((a, b) {
        final aPort = a['port'] as String;
        final bPort = b['port'] as String;
        if (aPort == 'WAN') return 1;
        if (bPort == 'WAN') return -1;
        return aPort.compareTo(bPort);
      });
      return result;
    } catch (e) {
      return [];
    }
  }

  Future<bool> blockDevice(String mac, bool block) async {
    try {
      if (block) {
        await run(
          'iptables -I FORWARD -m mac --mac-source $mac -j DROP 2>/dev/null; '
          'iptables -I INPUT -m mac --mac-source $mac -j DROP 2>/dev/null; true'
        );
      } else {
        await run(
          'iptables -D FORWARD -m mac --mac-source $mac -j DROP 2>/dev/null; '
          'iptables -D INPUT -m mac --mac-source $mac -j DROP 2>/dev/null; true'
        );
      }
      return true;
    } catch (e) {
      debugPrint('blockDevice error: $e');
      return false;
    }
  }

  //  System logs 
  Future<List<LogEntry>> getLogs() async {
    try {
      final raw = await run(
        'cat /var/log/messages 2>/dev/null | tail -400 || '
        'logread 2>/dev/null | tail -400 || '
        'dmesg 2>/dev/null | tail -200 || echo ""'
      );
      if (raw.trim().isEmpty) return [];

      // BusyBox syslog format: "Jan  1 07:00:03 unknown kern.notice kernel: message"
      // facility.level where facility = kern|daemon|syslog|user|auth|etc
      final syslogRe = RegExp(
        r'^(\w{3}\s+\d+\s+\d+:\d+:\d+)\s+\S+\s+(\S+?)\.(\w+)\s+(\S+?)(?:\[\d+\])?:\s*(.*)$'
      );
      final simpleSyslogRe = RegExp(
        r'^(\w{3}\s+\d+\s+\d+:\d+:\d+)\s+\S+\s+(\S+?)(?:\[\d+\])?:\s*(.*)$'
      );

      final entries = <LogEntry>[];
      for (final line in raw.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;

        String timeStr = '', process = '', levelStr = '', facility = '', message = t;

        final m1 = syslogRe.firstMatch(t);
        final m2 = m1 == null ? simpleSyslogRe.firstMatch(t) : null;

        if (m1 != null) {
          timeStr  = m1.group(1) ?? '';
          facility = m1.group(2) ?? ''; // kern, daemon, syslog...
          levelStr = m1.group(3) ?? ''; // notice, warn, err, debug
          process  = m1.group(4) ?? '';
          message  = m1.group(5) ?? t;
        } else if (m2 != null) {
          timeStr = m2.group(1) ?? '';
          process = m2.group(2) ?? '';
          message = m2.group(3) ?? t;
        }

        // source: kernel if facility=kern OR process=kernel
        final source = (facility == 'kern' || process == 'kernel') ? 'kernel' : 'system';

        // Map syslog severity to our levels
        String level = 'info';
        final lev = levelStr.toLowerCase();
        if (lev == 'err' || lev == 'error' || lev == 'crit' ||
            lev == 'alert' || lev == 'emerg') {
          level = 'err';
        } else if (lev == 'warn' || lev == 'warning') {
          level = 'warn';
        } else if (lev == 'debug') {
          level = 'debug';
        }
        // Fallback text scan if no structured level
        if (levelStr.isEmpty) {
          final lower = message.toLowerCase();
          if (lower.contains('error') || lower.contains('fail') || lower.contains('crit')) {
            level = 'err';
          } else if (lower.contains('warn')) {
            level = 'warn';
          }
        }

        DateTime time = DateTime.now();
        if (timeStr.isNotEmpty) {
          try {
            final withYear = '${timeStr.replaceAll(RegExp(r'\s+'), ' ')} ${DateTime.now().year}';
            time = DateTime.parse(withYear);
          } catch (_) {}
        }

        entries.add(LogEntry(
          time:    time,
          process: process,
          level:   level,
          message: message,
          source:  source,
        ));
      }
      return entries; // oldest first → newest last, ListView scrolls to bottom
    } catch (e) {
      return [];
    }
  }

  //  QoS rules (FreshTomato nvram format) 
  Future<List<QosRule>> getQosRules() async {
    try {
      final raw = await run('nvram get qos_iproute 2>/dev/null || echo ""');
      if (raw.trim().isEmpty) return [];
      final rules = <QosRule>[];
      for (final entry in raw.split('>').where((s) => s.isNotEmpty)) {
        final parts = entry.split('<');
        if (parts.length >= 6) {
          rules.add(QosRule(
            id:          DateTime.now().millisecondsSinceEpoch.toString() + rules.length.toString(),
            name:        parts[0].trim(),
            mac:         parts[1].trim(),
            downloadKbps: int.tryParse(parts[2].trim()) ?? 0,
            uploadKbps:  int.tryParse(parts[3].trim()) ?? 0,
            priority:    int.tryParse(parts[4].trim()) ?? 5,
            enabled:     parts[5].trim() == '1',
          ));
        }
      }
      return rules;
    } catch (e) {
      return [];
    }
  }

  Future<bool> saveQosRule(QosRule rule) async {
    try {
      // Read existing, find and replace or append
      final existing = await getQosRules();
      final idx = existing.indexWhere((r) => r.id == rule.id);
      if (idx >= 0) existing[idx] = rule;
      else existing.add(rule);
      final encoded = existing.map((r) =>
        '${r.name}<${r.mac}<${r.downloadKbps}<${r.uploadKbps}<${r.priority}<${r.enabled ? 1 : 0}'
      ).join('>');
      await run('nvram set qos_iproute="$encoded" && nvram commit');
      return true;
    } catch (e) {
      return false;
    }
  }

  //  Port forwarding rules 
  Future<List<PortForwardRule>> getPortForwardRules() async {
    try {
      final raw = await run('nvram get portforward 2>/dev/null || echo ""');
      if (raw.trim().isEmpty) return [];
      final rules = <PortForwardRule>[];
      for (final entry in raw.split('>').where((s) => s.isNotEmpty)) {
        // FreshTomato format: enabled<proto<src_ip<ext_port<int_port<int_ip<desc
        final parts = entry.split('<');
        if (parts.length >= 6) {
          final protoNum = int.tryParse(parts[1]) ?? 3;
          rules.add(PortForwardRule(
            id:           DateTime.now().millisecondsSinceEpoch.toString() + rules.length.toString(),
            enabled:      parts[0] == '1',
            name:         parts.length > 6 ? parts[6].trim() : '',
            protocol:     protoNum == 1 ? 'tcp' : protoNum == 2 ? 'udp' : 'both',
            externalPort: int.tryParse(parts[3].trim()) ?? 0,
            internalPort: int.tryParse(parts[4].trim()) ?? 0,
            internalIp:   parts[5].trim(),
          ));
        }
      }
      return rules;
    } catch (e) {
      return [];
    }
  }

  Future<bool> savePortForwardRules(List<PortForwardRule> rules) async {
    try {
      final encoded = rules.map((r) {
        final protoNum = r.protocol == 'tcp' ? 1 : r.protocol == 'udp' ? 2 : 3;
        return '${r.enabled ? 1 : 0}<$protoNum<0.0.0.0<${r.externalPort}<${r.internalPort}<${r.internalIp}<${r.name}';
      }).join('>');
      await run('nvram set portforward="$encoded" && nvram commit');
      // Apply rules
      run('service firewall restart 2>/dev/null &').catchError((_) {});
      return true;
    } catch (e) {
      return false;
    }
  }

  //  Reboot 
  Future<void> reboot() async {
    try {
      await run('reboot');
    } catch (_) {}
  }

  //  Device connections (conntrack) 
  Future<List<Map<String, dynamic>>> getDeviceConnections(String deviceIp) async {
    try {
      final raw = await run(
        'conntrack -L 2>/dev/null | grep "src=$deviceIp " || '
        'cat /proc/net/ip_conntrack 2>/dev/null | grep "src=$deviceIp " || echo ""'
      );
      if (raw.trim().isEmpty) return [];

      final conns = <Map<String, dynamic>>[];
      for (final line in raw.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        final proto  = RegExp(r'\btcp\b|\budp\b|\bicmp\b').firstMatch(t)?.group(0) ?? '?';
        final srcIp  = RegExp(r'src=(\S+)').firstMatch(t)?.group(1) ?? '';
        final dstIp  = RegExp(r'dst=(\S+)').firstMatch(t)?.group(1) ?? '';
        final dport  = RegExp(r'dport=(\d+)').firstMatch(t)?.group(1) ?? '?';
        final sport  = RegExp(r'sport=(\d+)').firstMatch(t)?.group(1) ?? '?';
        final state  = RegExp(r'\b(ESTABLISHED|TIME_WAIT|SYN_SENT|CLOSE_WAIT|LISTEN)\b').firstMatch(t)?.group(0) ?? '';
        final rxB    = RegExp(r'bytes=(\d+)').firstMatch(t)?.group(1) ?? '0';
        final pkts   = RegExp(r'packets=(\d+)').firstMatch(t)?.group(1) ?? '0';
        if (srcIp != deviceIp) continue;
        if (dstIp.isEmpty || dstIp == '127.0.0.1') continue;
        conns.add({
          'proto':   proto.toUpperCase(),
          'dst':     dstIp,
          'dport':   int.tryParse(dport) ?? 0,
          'sport':   int.tryParse(sport) ?? 0,
          'state':   state,
          'rxBytes': int.tryParse(rxB) ?? 0,
          'packets': int.tryParse(pkts) ?? 0,
        });
      }
      conns.sort((a, b) => (a['dport'] as int).compareTo(b['dport'] as int));
      return conns;
    } catch (e) {
      return [];
    }
  }

  //  Per-device bandwidth limiting via iptables hashlimit 
  Future<bool> setDeviceBandwidth(String deviceIp, int dlKbps, int ulKbps) async {
    try {
      final oct = deviceIp.split('.').last;
      final dlName = 'bwdl$oct';
      final ulName = 'bwul$oct';

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

      final key = 'bwl_${deviceIp.replaceAll('.', '_')}';
      run('nvram set ${key}_d=$dlKbps && nvram set ${key}_u=$ulKbps && nvram commit')
        .catchError((_) {});
      return true;
    } catch (e) {
      debugPrint('setDeviceBandwidth error: $e');
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

  // ── WiFi toggle ─────────────────────────────────────────────────────────────
  Future<bool> toggleWifi(String band, bool enable) async {
    try {
      final iface = band == '5' ? 'eth2' : 'eth1';
      final wlIface = band == '5' ? 'wl1' : 'wl0';
      final val = enable ? '1' : '0';
      await run(
        'nvram set ${wlIface}_radio=$val; '
        'nvram commit; '
        'wl -i $iface radio ${enable ? "on" : "off"} 2>/dev/null; true'
      );
      return true;
    } catch (e) {
      debugPrint('toggleWifi error: $e');
      return false;
    }
  }

  // ── Save WiFi settings ───────────────────────────────────────────────────────
  Future<bool> saveWifiSettings({
    required String band,   // '2.4' or '5'
    String? ssid,
    String? channel,
    String? security,    // disabled/wep/wpa-personal/wpa2-personal/wpa-enterprise/wpa2-enterprise/wpa-wpa2/radius
    String? crypto,      // aes/tkip/tkip+aes
    String? password,
    String? txpower,
    String? netMode,     // auto/b-only/g-only/bg-mixed/n-only (2.4G) or auto/a-only/n-only/ac-only (5G)
    String? broadcast,   // '1'=visible, '0'=hidden
    String? chanWidth,   // 20/40/80
    String? sideband,    // upper/lower (for 40MHz 2.4G)
    String? wlMode,      // ap/sta/wet/wds
  }) async {
    try {
      final iface  = band == '5' ? 'wl1' : 'wl0';
      final ethif  = band == '5' ? 'eth2' : 'eth1';
      final cmds   = <String>[];

      if (ssid != null && ssid.isNotEmpty)         cmds.add("nvram set ${iface}_ssid='$ssid'");
      if (channel != null)                          cmds.add("nvram set ${iface}_channel='$channel'");
      if (txpower != null)                          cmds.add("nvram set ${iface}_txpwr='$txpower'");
      if (netMode != null && netMode.isNotEmpty) {
        // Tomato stores 'mixed' for what the UI calls 'Auto' — translate back
        final nvramNetMode = netMode == 'auto' ? 'mixed' : netMode;
        cmds.add("nvram set \${iface}_net_mode='\$nvramNetMode'");
      }
      if (wlMode != null && wlMode.isNotEmpty)      cmds.add("nvram set ${iface}_mode='$wlMode'");
      if (broadcast != null) {
        // wl_closed: 0=broadcast(visible), 1=hidden — inverse of our "broadcast" param
        final closed = broadcast == '1' ? '0' : '1';
        cmds.add("nvram set ${iface}_closed='$closed'");
      }

      // Channel width + sideband → chanspec
      if (chanWidth != null && channel != null) {
        String spec = '';
        if (chanWidth == '20') {
          spec = channel;
        } else if (chanWidth == '40' && band == '2.4') {
          final sb = sideband ?? 'upper';
          spec = '${channel}${sb == 'upper' ? 'u' : 'l'}';
          cmds.add("nvram set ${iface}_nbw='40'");
        } else if (chanWidth == '40' && band == '5') {
          spec = '$channel/40';
          cmds.add("nvram set ${iface}_nbw='40'");
        } else if (chanWidth == '80') {
          spec = '$channel/80';
          cmds.add("nvram set ${iface}_nbw='80'");
        }
        if (spec.isNotEmpty) cmds.add("nvram set ${iface}_chanspec='$spec'");
        if (chanWidth == '20') cmds.add("nvram set ${iface}_nbw='20'");
      }

      // Security: set security_mode + akm + auth_mode + crypto
      if (security != null) {
        switch (security) {
          case 'disabled':
            cmds.addAll(["nvram set ${iface}_security_mode='disabled'",
              "nvram set ${iface}_akm=''", "nvram set ${iface}_auth_mode='none'",
              "nvram set ${iface}_crypto=''"]);
          case 'wep':
            cmds.addAll(["nvram set ${iface}_security_mode='wep'",
              "nvram set ${iface}_akm=''", "nvram set ${iface}_auth_mode='none'"]);
          case 'wpa-personal':
            cmds.addAll(["nvram set ${iface}_security_mode='wpa_personal'",
              "nvram set ${iface}_akm='psk'", "nvram set ${iface}_auth_mode='none'",
              "nvram set ${iface}_crypto='${crypto ?? 'aes'}'"]);
          case 'wpa2-personal':
            cmds.addAll(["nvram set ${iface}_security_mode='wpa2_personal'",
              "nvram set ${iface}_akm='psk2'", "nvram set ${iface}_auth_mode='none'",
              "nvram set ${iface}_crypto='${crypto ?? 'aes'}'"]);
          case 'wpa-wpa2':
            cmds.addAll(["nvram set ${iface}_security_mode='wpa_personal'",
              "nvram set ${iface}_akm='psk psk2'", "nvram set ${iface}_auth_mode='none'",
              "nvram set ${iface}_crypto='${crypto ?? 'aes'}'"]);
          case 'wpa2-enterprise':
            cmds.addAll(["nvram set ${iface}_security_mode='wpa2_enterprise'",
              "nvram set ${iface}_akm='wpa2'", "nvram set ${iface}_auth_mode='radius'"]);
          case 'radius':
            cmds.addAll(["nvram set ${iface}_security_mode='radius'",
              "nvram set ${iface}_akm=''", "nvram set ${iface}_auth_mode='radius'"]);
        }
      } else if (crypto != null && crypto.isNotEmpty) {
        cmds.add("nvram set ${iface}_crypto='$crypto'");
      }

      if (password != null && password.isNotEmpty) cmds.add("nvram set ${iface}_wpa_psk='$password'");

      if (cmds.isEmpty) return true;
      cmds.add('nvram commit');
      // Soft-apply: restart wireless interface
      cmds.add('service wireless restart 2>/dev/null; true');
      await run(cmds.join('; '));
      return true;
    } catch (e) {
      debugPrint('saveWifiSettings error: $e');
      return false;
    }
  }

  // Bandwidth limit (bwl) per device
  Future<bool> setBandwidthLimit({
    required String mac,
    required int dlKbps,   // 0 = unlimited
    required int ulKbps,   // 0 = unlimited
  }) async {
    try {
      // Read existing bwl_rules, remove old entry for this mac, add new
      final existing = (await run('nvram get bwl_rules 2>/dev/null')).trim();
      final parts = existing.split(' ').where((s) => s.isNotEmpty && !s.startsWith('${mac.toUpperCase()}>') && !s.startsWith('${mac.toLowerCase()}>') && !s.startsWith(mac.replaceAll(':', '-').toUpperCase() + '>')).toList();
      if (dlKbps > 0 || ulKbps > 0) {
        // Format: MAC>dlceil>dlrate>ulceil>ulrate (0 = unlimited)
        parts.add('${mac.toUpperCase()}>$dlKbps>$dlKbps>$ulKbps>$ulKbps');
      }
      final newRules = parts.join(' ');
      final enable = parts.isNotEmpty ? '1' : '0';
      await run("nvram set bwl_rules='$newRules'; nvram set bwl_enable='$enable'; nvram commit; service bwlimit restart 2>/dev/null; true");
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, Map<String, int>>> getBandwidthLimits() async {
    try {
      final raw = (await run('nvram get bwl_rules 2>/dev/null')).trim();
      final result = <String, Map<String, int>>{};
      for (final part in raw.split(' ').where((s) => s.contains('>'))) {
        final fields = part.split('>');
        if (fields.length >= 5) {
          result[fields[0].toLowerCase().replaceAll('-', ':')] = {
            'dl': int.tryParse(fields[1]) ?? 0,
            'ul': int.tryParse(fields[3]) ?? 0,
          };
        }
      }
      return result;
    } catch (e) {
      return {};
    }
  }
}

// ── SSH command queue entry ───────────────────────────────────────────────────
class _SshCmd {
  final String command;
  final completer = Completer<String>();
  _SshCmd(this.command);
}
import 'dart:convert';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/models.dart';

class RouterApiService {
  Dio? _dio;
  RouterConfig? _config;

  // ── Setup ──────────────────────────────────────────────────────────────────
  void configure(RouterConfig config) {
    _config = config;
    _dio = Dio(BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'Authorization': 'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    ));

    // Ignore self-signed SSL certs (common on routers)
    (_dio!.httpClientAdapter as dynamic).onHttpClientCreate = (client) {
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    };
  }

  bool get isConfigured => _config != null && _dio != null;

  // ── Test connection ────────────────────────────────────────────────────────
  Future<bool> testConnection() async {
    try {
      final res = await _dio!.get('/');
      return res.statusCode == 200 || res.statusCode == 302;
    } catch (_) {
      return false;
    }
  }

  // ── Fetch router status via update.cgi ────────────────────────────────────
  Future<RouterStatus> getStatus() async {
    try {
      // Get sysinfo (CPU, RAM, uptime, etc)
      final sysRes = await _dio!.post('/update.cgi',
        data: '_http_id=TID&exec=sysinfo',
      );
      final nvramRes = await _dio!.post('/update.cgi',
        data: '_http_id=TID&exec=nvramdump',
      );

      final sysinfo = _parseKeyValue(sysRes.data.toString());
      final nvram = _parseKeyValue(nvramRes.data.toString());

      return RouterStatus.fromNvram(nvram, sysinfo);
    } catch (e) {
      debugPrint('getStatus error: $e');
      return RouterStatus.empty();
    }
  }

  // ── Get connected devices via arp table + wireless clients ─────────────────
  Future<List<ConnectedDevice>> getDevices() async {
    try {
      final res = await _dio!.post('/update.cgi',
        data: '_http_id=TID&exec=devlist',
      );

      final List<ConnectedDevice> devices = [];
      final lines = res.data.toString().split('\n');

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        // Format: IP MAC IFACE RSSI TX RX
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          final mac = parts[1].toUpperCase();
          devices.add(ConnectedDevice(
            mac: mac,
            ip: parts[0],
            name: '',
            interface: parts.length > 2 ? parts[2] : 'br0',
            txRate: int.tryParse(parts.length > 4 ? parts[4] : '0') ?? 0,
            rxRate: int.tryParse(parts.length > 5 ? parts[5] : '0') ?? 0,
            rssi: parts.length > 3 ? parts[3] : '-',
            isBlocked: await _isBlocked(mac),
            firstSeen: DateTime.now(),
            lastSeen: DateTime.now(),
          ));
        }
      }
      return devices;
    } catch (e) {
      debugPrint('getDevices error: $e');
      return [];
    }
  }

  // ── Bandwidth realtime ─────────────────────────────────────────────────────
  Future<Map<String, double>> getBandwidth() async {
    try {
      final res = await _dio!.post('/update.cgi',
        data: '_http_id=TID&exec=netdev',
      );
      final data = _parseKeyValue(res.data.toString());
      return {
        'rx': double.tryParse(data['wanRx'] ?? '0') ?? 0,
        'tx': double.tryParse(data['wanTx'] ?? '0') ?? 0,
      };
    } catch (e) {
      return {'rx': 0, 'tx': 0};
    }
  }

  // ── Reboot ─────────────────────────────────────────────────────────────────
  Future<bool> reboot() async {
    try {
      await _dio!.post('/tomato.cgi',
        data: '_http_id=TID&_nextar=%2F&action=Reboot',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Block / Unblock device ─────────────────────────────────────────────────
  // Uses iptables via FreshTomato's NVRAM mac_block list
  Future<bool> blockDevice(String mac, bool block) async {
    try {
      // Get current block list
      final nvramRes = await _dio!.post('/update.cgi',
        data: '_http_id=TID&exec=nvramdump',
      );
      final nvram = _parseKeyValue(nvramRes.data.toString());
      final blockList = nvram['block_mac'] ?? '';

      String newList;
      if (block) {
        // Add MAC to block list
        final macs = blockList.isEmpty ? <String>[] : blockList.split(' ');
        if (!macs.contains(mac)) macs.add(mac);
        newList = macs.join(' ');
      } else {
        // Remove MAC from block list
        final macs = blockList.split(' ').where((m) => m != mac).toList();
        newList = macs.join(' ');
      }

      // Save to NVRAM
      await _dio!.post('/tomato.cgi', data:
        '_http_id=TID&_nextar=%2F&action=Apply'
        '&block_mac=${Uri.encodeComponent(newList)}'
        '&block_mac_enable=${block ? '1' : '0'}',
      );
      return true;
    } catch (e) {
      debugPrint('blockDevice error: $e');
      return false;
    }
  }

  Future<bool> _isBlocked(String mac) async {
    try {
      final res = await _dio!.post('/update.cgi',
        data: '_http_id=TID&exec=nvramdump',
      );
      final nvram = _parseKeyValue(res.data.toString());
      final blockList = nvram['block_mac'] ?? '';
      return blockList.contains(mac);
    } catch (_) {
      return false;
    }
  }

  // ── QoS ───────────────────────────────────────────────────────────────────
  Future<List<QosRule>> getQosRules() async {
    try {
      final res = await _dio!.post('/update.cgi',
        data: '_http_id=TID&exec=nvramdump',
      );
      final nvram = _parseKeyValue(res.data.toString());
      final qosData = nvram['qos_bwrates'] ?? '';
      if (qosData.isEmpty) return [];

      return qosData.split('>').where((s) => s.isNotEmpty).map((s) {
        final parts = s.split('<');
        return QosRule(
          id: parts[0],
          name: parts.length > 4 ? parts[4] : 'Rule',
          mac: parts.length > 1 ? parts[1] : '',
          downloadKbps: int.tryParse(parts.length > 2 ? parts[2] : '0') ?? 0,
          uploadKbps: int.tryParse(parts.length > 3 ? parts[3] : '0') ?? 0,
          priority: 5,
          enabled: true,
        );
      }).toList();
    } catch (e) {
      debugPrint('getQosRules error: $e');
      return [];
    }
  }

  Future<bool> saveQosRule(QosRule rule) async {
    try {
      await _dio!.post('/tomato.cgi', data:
        '_http_id=TID&_nextar=%2F&action=Apply'
        '&qos_bwrates=${Uri.encodeComponent('${rule.id}<${rule.mac}<${rule.downloadKbps}<${rule.uploadKbps}<${rule.name}')}',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Port Forwarding ────────────────────────────────────────────────────────
  Future<List<PortForwardRule>> getPortForwardRules() async {
    try {
      final res = await _dio!.post('/update.cgi',
        data: '_http_id=TID&exec=nvramdump',
      );
      final nvram = _parseKeyValue(res.data.toString());
      final pfData = nvram['portforward'] ?? '';
      if (pfData.isEmpty) return [];

      return pfData.split('>').where((s) => s.isNotEmpty)
          .map((s) => PortForwardRule.fromString(s)).toList();
    } catch (e) {
      debugPrint('getPortForwardRules error: $e');
      return [];
    }
  }

  Future<bool> savePortForwardRules(List<PortForwardRule> rules) async {
    try {
      final data = rules.map((r) =>
        '${r.enabled ? 'on' : 'off'}<${r.protocol}<${r.externalPort}<${r.internalPort}<${r.internalIp}<${r.name}'
      ).join('>');

      await _dio!.post('/tomato.cgi', data:
        '_http_id=TID&_nextar=%2F&action=Apply'
        '&portforward=${Uri.encodeComponent(data)}',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Logs ──────────────────────────────────────────────────────────────────
  Future<List<LogEntry>> getLogs({int limit = 200}) async {
    try {
      final res = await _dio!.post('/update.cgi',
        data: '_http_id=TID&exec=showlog',
      );

      final lines = res.data.toString().split('\n');
      final entries = <LogEntry>[];

      for (final line in lines.take(limit)) {
        if (line.trim().isEmpty) continue;
        // Syslog format: "Mar  7 06:00:00 daemon info process: message"
        try {
          final match = RegExp(
            r'^(\w+\s+\d+\s+\d+:\d+:\d+)\s+(\w+)\s+(\w+)\s+([^:]+):\s*(.*)'
          ).firstMatch(line);
          if (match != null) {
            entries.add(LogEntry(
              time: _parseLogTime(match.group(1) ?? ''),
              facility: match.group(2) ?? '',
              level: match.group(3) ?? 'info',
              process: match.group(4) ?? '',
              message: match.group(5) ?? line,
            ));
          } else {
            entries.add(LogEntry(
              time: DateTime.now(),
              facility: '-',
              level: 'info',
              process: '-',
              message: line,
            ));
          }
        } catch (_) {}
      }
      return entries.reversed.toList();
    } catch (e) {
      debugPrint('getLogs error: $e');
      return [];
    }
  }

  // ── Utils ─────────────────────────────────────────────────────────────────
  Map<String, String> _parseKeyValue(String raw) {
    final map = <String, String>{};
    for (final line in raw.split('\n')) {
      final idx = line.indexOf('=');
      if (idx > 0) {
        map[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
    }
    return map;
  }

  DateTime _parseLogTime(String s) {
    try {
      final now = DateTime.now();
      final parts = s.trim().split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final months = {'Jan':1,'Feb':2,'Mar':3,'Apr':4,'May':5,'Jun':6,
                        'Jul':7,'Aug':8,'Sep':9,'Oct':10,'Nov':11,'Dec':12};
        final month = months[parts[0]] ?? now.month;
        final day = int.tryParse(parts[1]) ?? now.day;
        final timeParts = parts[2].split(':');
        return DateTime(now.year, month, day,
          int.tryParse(timeParts[0]) ?? 0,
          int.tryParse(timeParts[1]) ?? 0,
          int.tryParse(timeParts[2]) ?? 0,
        );
      }
    } catch (_) {}
    return DateTime.now();
  }
}

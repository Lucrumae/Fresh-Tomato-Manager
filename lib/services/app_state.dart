import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/models.dart';
import 'router_api.dart';
import 'notification_service.dart';

// ── Singleton API service ─────────────────────────────────────────────────────
final apiServiceProvider = Provider<RouterApiService>((ref) => RouterApiService());

// ── Config provider ────────────────────────────────────────────────────────────
final configProvider = StateNotifierProvider<ConfigNotifier, TomatoConfig?>((ref) {
  return ConfigNotifier();
});

class ConfigNotifier extends StateNotifier<TomatoConfig?> {
  ConfigNotifier() : super(null) { _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('router_config');
    if (json != null) {
      state = TomatoConfig.fromJson(jsonDecode(json));
    }
  }

  Future<void> save(TomatoConfig config) async {
    state = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('router_config', jsonEncode(config.toJson()));
  }

  Future<void> clear() async {
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('router_config');
  }
}

// ── Connection state ───────────────────────────────────────────────────────────
enum ConnectionState { disconnected, connecting, connected, error }

final connectionStateProvider = StateProvider<ConnectionState>(
  (_) => ConnectionState.disconnected,
);

// ── Network type (wifi vs mobile/vpn) ─────────────────────────────────────────
final networkTypeProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity().onConnectivityChanged.map((list) =>
    list.isNotEmpty ? list.first : ConnectivityResult.none);
});

// ── Router status ──────────────────────────────────────────────────────────────
final routerStatusProvider = StateNotifierProvider<RouterStatusNotifier, RouterStatus>((ref) {
  return RouterStatusNotifier(ref);
});

class RouterStatusNotifier extends StateNotifier<RouterStatus> {
  final Ref _ref;
  Timer? _timer;

  RouterStatusNotifier(this._ref) : super(RouterStatus.empty());

  void startPolling() {
    _timer?.cancel();
    fetch();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => fetch());
  }

  void stopPolling() => _timer?.cancel();

  Future<void> fetch() async {
    final api = _ref.read(apiServiceProvider);
    if (!api.isConfigured) return;
    final status = await api.getStatus();
    state = status;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Devices ────────────────────────────────────────────────────────────────────
final devicesProvider = StateNotifierProvider<DevicesNotifier, List<ConnectedDevice>>((ref) {
  return DevicesNotifier(ref);
});

class DevicesNotifier extends StateNotifier<List<ConnectedDevice>> {
  final Ref _ref;
  Timer? _timer;
  Set<String> _knownMacs = {};

  DevicesNotifier(this._ref) : super([]);

  void startPolling() {
    _timer?.cancel();
    fetch();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => fetch());
  }

  void stopPolling() => _timer?.cancel();

  Future<void> fetch() async {
    final api = _ref.read(apiServiceProvider);
    if (!api.isConfigured) return;

    final devices = await api.getDevices();

    // Load saved names from prefs
    final prefs = await SharedPreferences.getInstance();
    for (final d in devices) {
      final saved = prefs.getString('device_name_${d.mac}');
      if (saved != null) d.name = saved;
    }

    // Detect new devices → notify
    final currentMacs = devices.map((d) => d.mac).toSet();
    final newMacs = currentMacs.difference(_knownMacs);
    if (_knownMacs.isNotEmpty && newMacs.isNotEmpty) {
      for (final mac in newMacs) {
        final device = devices.firstWhere((d) => d.mac == mac);
        NotificationService.showNewDeviceNotification(device);
      }
    }
    _knownMacs = currentMacs;
    state = devices;
  }

  Future<void> renameDevice(String mac, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name_$mac', name);
    state = state.map((d) => d.mac == mac ? d.copyWith(name: name) : d).toList();
  }

  Future<void> toggleBlock(String mac) async {
    final api = _ref.read(apiServiceProvider);
    final device = state.firstWhere((d) => d.mac == mac);
    final success = await api.blockDevice(mac, !device.isBlocked);
    if (success) {
      state = state.map((d) =>
        d.mac == mac ? d.copyWith(isBlocked: !d.isBlocked) : d
      ).toList();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Bandwidth ──────────────────────────────────────────────────────────────────
final bandwidthProvider = StateNotifierProvider<BandwidthNotifier, BandwidthStats>((ref) {
  return BandwidthNotifier(ref);
});

class BandwidthNotifier extends StateNotifier<BandwidthStats> {
  final Ref _ref;
  Timer? _timer;
  final List<BandwidthPoint> _history = [];
  Map<String, double> _lastSample = {'rx': 0, 'tx': 0};

  BandwidthNotifier(this._ref) : super(BandwidthStats.empty());

  void startPolling() {
    _timer?.cancel();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  void stopPolling() => _timer?.cancel();

  Future<void> _poll() async {
    final api = _ref.read(apiServiceProvider);
    if (!api.isConfigured) return;

    final sample = await api.getBandwidth();
    final rx = sample['rx'] ?? 0;
    final tx = sample['tx'] ?? 0;

    // Calculate rate (delta bytes / interval → kbps)
    final rxKbps = (rx - _lastSample['rx']!) / 2 / 1024 * 8;
    final txKbps = (tx - _lastSample['tx']!) / 2 / 1024 * 8;
    _lastSample = sample;

    final point = BandwidthPoint(
      time: DateTime.now(),
      rxKbps: rxKbps.clamp(0, double.infinity),
      txKbps: txKbps.clamp(0, double.infinity),
    );

    _history.add(point);
    if (_history.length > 60) _history.removeAt(0); // keep 2 min

    final peakRx = _history.map((p) => p.rxKbps).fold(0.0, (a, b) => a > b ? a : b);
    final peakTx = _history.map((p) => p.txKbps).fold(0.0, (a, b) => a > b ? a : b);

    state = BandwidthStats(
      points: List.from(_history),
      currentRx: rxKbps.clamp(0, double.infinity),
      currentTx: txKbps.clamp(0, double.infinity),
      peakRx: peakRx,
      peakTx: peakTx,
      totalRxMB: rx / 1024 / 1024,
      totalTxMB: tx / 1024 / 1024,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Logs ───────────────────────────────────────────────────────────────────────
final logsProvider = StateNotifierProvider<LogsNotifier, List<LogEntry>>((ref) {
  return LogsNotifier(ref);
});

class LogsNotifier extends StateNotifier<List<LogEntry>> {
  final Ref _ref;

  LogsNotifier(this._ref) : super([]);

  Future<void> fetch() async {
    final api = _ref.read(apiServiceProvider);
    if (!api.isConfigured) return;
    state = await api.getLogs();
  }
}

// ── QoS ────────────────────────────────────────────────────────────────────────
final qosProvider = StateNotifierProvider<QosNotifier, List<QosRule>>((ref) {
  return QosNotifier(ref);
});

class QosNotifier extends StateNotifier<List<QosRule>> {
  final Ref _ref;
  QosNotifier(this._ref) : super([]);

  Future<void> fetch() async {
    final api = _ref.read(apiServiceProvider);
    state = await api.getQosRules();
  }

  Future<bool> saveRule(QosRule rule) async {
    final api = _ref.read(apiServiceProvider);
    final ok = await api.saveQosRule(rule);
    if (ok) await fetch();
    return ok;
  }
}

// ── Port Forward ───────────────────────────────────────────────────────────────
final portForwardProvider = StateNotifierProvider<PortForwardNotifier, List<PortForwardRule>>((ref) {
  return PortForwardNotifier(ref);
});

class PortForwardNotifier extends StateNotifier<List<PortForwardRule>> {
  final Ref _ref;
  PortForwardNotifier(this._ref) : super([]);

  Future<void> fetch() async {
    final api = _ref.read(apiServiceProvider);
    state = await api.getPortForwardRules();
  }

  Future<bool> saveAll() async {
    final api = _ref.read(apiServiceProvider);
    final ok = await api.savePortForwardRules(state);
    return ok;
  }

  void addRule(PortForwardRule rule) => state = [...state, rule];

  void removeRule(String id) => state = state.where((r) => r.id != id).toList();

  void toggleRule(String id) {
    state = state.map((r) => r.id == id
      ? PortForwardRule(
          id: r.id, name: r.name, protocol: r.protocol,
          externalPort: r.externalPort, internalPort: r.internalPort,
          internalIp: r.internalIp, enabled: !r.enabled,
        )
      : r
    ).toList();
  }
}

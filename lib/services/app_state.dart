import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'ssh_service.dart';
import 'notification_service.dart';

//  SSH Service singleton
final sshServiceProvider = Provider<SshService>((ref) => SshService());

//  Dark mode
final darkModeProvider = StateNotifierProvider<DarkModeNotifier, bool>((ref) {
  return DarkModeNotifier();
});

class DarkModeNotifier extends StateNotifier<bool> {
  DarkModeNotifier() : super(false) { _load(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool('dark_mode') ?? false;
  }
  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', state);
  }
}

//  Accent color
final accentProvider = StateNotifierProvider<AccentNotifier, AccentColor>((ref) {
  return AccentNotifier();
});

class AccentNotifier extends StateNotifier<AccentColor> {
  AccentNotifier() : super(AccentColor.green) { _load(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final idx = prefs.getInt('accent_color') ?? 0;
    state = AccentColor.values[idx.clamp(0, AccentColor.values.length - 1)];
  }
  Future<void> set(AccentColor accent) async {
    state = accent;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accent_color', AccentColor.values.indexOf(accent));
  }
}

//  Config
final configProvider = StateNotifierProvider<ConfigNotifier, TomatoConfig?>((ref) {
  return ConfigNotifier();
});

class ConfigNotifier extends StateNotifier<TomatoConfig?> {
  ConfigNotifier() : super(null) { _load(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('router_config');
    if (json != null) state = TomatoConfig.fromJson(jsonDecode(json));
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

//  Network type
final networkTypeProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity().onConnectivityChanged;
});

// ─── Router Status ─────────────────────────────────────────────────────────────
final routerStatusProvider = StateNotifierProvider<RouterStatusNotifier, RouterStatus>((ref) {
  return RouterStatusNotifier(ref);
});

class RouterStatusNotifier extends StateNotifier<RouterStatus> {
  final Ref _ref;
  Timer? _fastTimer;  // 1s  - CPU, RAM, temp
  Timer? _slowTimer;  // 30s - nvram info, ethernet ports
  RouterStatusNotifier(this._ref) : super(RouterStatus.empty());

  void startPolling() {
    _fastTimer?.cancel();
    _slowTimer?.cancel();
    fetchFull();
    _fastTimer = Timer.periodic(const Duration(seconds: 1),  (_) => fetchFast());
    _slowTimer = Timer.periodic(const Duration(seconds: 5), (_) => fetchFull());
  }

  void stopPolling() {
    _fastTimer?.cancel();
    _slowTimer?.cancel();
  }

  Future<void> fetchFast() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    final updated = await ssh.getStatusFast(state);
    if (mounted) state = updated;
  }

  Future<void> fetchFull() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    final status = await ssh.getStatus();
    if (mounted) state = status;
    _ref.read(ethernetPortsProvider.notifier).fetch();
  }

  Future<void> fetch() => fetchFull();

  @override
  void dispose() { _fastTimer?.cancel(); _slowTimer?.cancel(); super.dispose(); }
}

// ─── Devices ───────────────────────────────────────────────────────────────────
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
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => fetch());
  }

  void stopPolling() => _timer?.cancel();

  Future<void> fetch() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    final devices = await ssh.getDevices();
    final prefs = await SharedPreferences.getInstance();
    for (final d in devices) {
      final saved = prefs.getString('device_name_${d.mac}');
      if (saved != null) d.name = saved;
    }
    final currentMacs = devices.map((d) => d.mac).toSet();
    final newMacs = currentMacs.difference(_knownMacs);
    if (_knownMacs.isNotEmpty && newMacs.isNotEmpty) {
      for (final mac in newMacs) {
        final device = devices.firstWhere((d) => d.mac == mac);
        NotificationService.showNewDeviceNotification(device);
      }
    }
    _knownMacs = currentMacs;
    if (mounted) state = devices;
  }

  Future<void> renameDevice(String mac, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name_$mac', name);
    if (mounted) state = state.map((d) => d.mac == mac ? d.copyWith(name: name) : d).toList();
  }

  Future<void> toggleBlock(String mac) async {
    final ssh = _ref.read(sshServiceProvider);
    final device = state.firstWhere((d) => d.mac == mac);
    final success = await ssh.blockDevice(mac, !device.isBlocked);
    if (success && mounted) {
      state = state.map((d) => d.mac == mac ? d.copyWith(isBlocked: !d.isBlocked) : d).toList();
    }
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}

// ─── Bandwidth ─────────────────────────────────────────────────────────────────
final bandwidthProvider = StateNotifierProvider<BandwidthNotifier, BandwidthStats>((ref) {
  return BandwidthNotifier(ref);
});

class BandwidthNotifier extends StateNotifier<BandwidthStats> {
  final Ref _ref;
  Timer? _timer;
  final List<BandwidthPoint> _history = [];
  Map<String, int> _lastSample = {'rx': 0, 'tx': 0};
  bool _firstSample = true;
  double _totalRxMB = 0, _totalTxMB = 0;
  BandwidthNotifier(this._ref) : super(BandwidthStats.empty());

  void startPolling() {
    _timer?.cancel();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  void stopPolling() => _timer?.cancel();

  Future<void> _poll() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    final sample = await ssh.getBandwidthRaw();
    final rx = sample['rx'] ?? 0;
    final tx = sample['tx'] ?? 0;
    if (_firstSample) { _lastSample = sample; _firstSample = false; return; }
    final rxDelta = (rx - _lastSample['rx']!).clamp(0, 999999999);
    final txDelta = (tx - _lastSample['tx']!).clamp(0, 999999999);
    final rxKbps = rxDelta / 1 / 1024 * 8;
    final txKbps = txDelta / 1 / 1024 * 8;
    _totalRxMB += rxDelta / 1024 / 1024;
    _totalTxMB += txDelta / 1024 / 1024;
    _lastSample = sample;
    final point = BandwidthPoint(time: DateTime.now(), rxKbps: rxKbps, txKbps: txKbps);
    _history.add(point);
    if (_history.length > 60) _history.removeAt(0);
    final peakRx = _history.fold(0.0, (a, b) => a > b.rxKbps ? a : b.rxKbps);
    final peakTx = _history.fold(0.0, (a, b) => a > b.txKbps ? a : b.txKbps);
    if (mounted) state = BandwidthStats(
      points: List.from(_history),
      currentRx: rxKbps, currentTx: txKbps,
      peakRx: peakRx, peakTx: peakTx,
      totalRxMB: _totalRxMB, totalTxMB: _totalTxMB,
    );
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}

// ─── Logs ──────────────────────────────────────────────────────────────────────
final logsProvider = StateNotifierProvider<LogsNotifier, List<LogEntry>>((ref) {
  return LogsNotifier(ref);
});

class LogsNotifier extends StateNotifier<List<LogEntry>> {
  final Ref _ref;
  Timer? _timer;
  LogsNotifier(this._ref) : super([]);

  void startPolling() {
    _timer?.cancel();
    fetch();
    // Poll every 3s - logs need to be near-realtime
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => fetch());
  }

  void stopPolling() => _timer?.cancel();

  Future<void> fetch() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    final logs = await ssh.getLogs();
    if (mounted) state = logs;
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}

// ─── QoS Rules ────────────────────────────────────────────────────────────────
final qosProvider = StateNotifierProvider<QosNotifier, List<QosRule>>((ref) {
  return QosNotifier(ref);
});

class QosNotifier extends StateNotifier<List<QosRule>> {
  final Ref _ref;
  Timer? _timer;
  QosNotifier(this._ref) : super([]);

  void startPolling() {
    _timer?.cancel();
    fetch();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => fetch());
  }

  void stopPolling() => _timer?.cancel();

  Future<void> fetch() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    if (mounted) state = await ssh.getQosRules();
  }

  Future<bool> saveRule(QosRule rule) async {
    final ssh = _ref.read(sshServiceProvider);
    final ok = await ssh.saveQosRule(rule);
    if (ok) await fetch();
    return ok;
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}

// ─── Port Forward ──────────────────────────────────────────────────────────────
final portForwardProvider = StateNotifierProvider<PortForwardNotifier, List<PortForwardRule>>((ref) {
  return PortForwardNotifier(ref);
});

class PortForwardNotifier extends StateNotifier<List<PortForwardRule>> {
  final Ref _ref;
  Timer? _timer;
  PortForwardNotifier(this._ref) : super([]);

  void startPolling() {
    _timer?.cancel();
    fetch();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => fetch());
  }

  void stopPolling() => _timer?.cancel();

  Future<void> fetch() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    if (mounted) state = await ssh.getPortForwardRules();
  }

  Future<bool> saveAll() async {
    final ssh = _ref.read(sshServiceProvider);
    return ssh.savePortForwardRules(state);
  }

  void addRule(PortForwardRule rule) { if (mounted) state = [...state, rule]; }
  void removeRule(String id) { if (mounted) state = state.where((r) => r.id != id).toList(); }
  void toggleRule(String id) {
    if (!mounted) return;
    state = state.map((r) => r.id == id ? PortForwardRule(
      id: r.id, name: r.name, protocol: r.protocol,
      externalPort: r.externalPort, internalPort: r.internalPort,
      internalIp: r.internalIp, enabled: !r.enabled,
    ) : r).toList();
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }
}

// ─── Ethernet Ports ────────────────────────────────────────────────────────────
final ethernetPortsProvider = StateNotifierProvider<EthernetPortsNotifier, List<Map<String, dynamic>>>((ref) {
  return EthernetPortsNotifier(ref);
});

class EthernetPortsNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  final Ref _ref;
  EthernetPortsNotifier(this._ref) : super([]);

  Future<void> fetch() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    try {
      final result = await ssh.getEthernetPorts();
      if (mounted) state = result;
    } catch (_) {}
  }
}

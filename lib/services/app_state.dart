import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'ssh_service.dart';
import 'notification_service.dart';

final sshServiceProvider = Provider<SshService>((ref) => SshService());
final networkTypeProvider = StreamProvider<ConnectivityResult>((ref) => Connectivity().onConnectivityChanged);

// Dark mode
final darkModeProvider = StateNotifierProvider<DarkModeNotifier, bool>((ref) => DarkModeNotifier());
class DarkModeNotifier extends StateNotifier<bool> {
  DarkModeNotifier() : super(true) { _load(); }
  Future<void> _load() async { final p = await SharedPreferences.getInstance(); state = p.getBool('dark_mode') ?? false; }
  Future<void> toggle() async { state = !state; (await SharedPreferences.getInstance()).setBool('dark_mode', state); }
}

// Accent
final accentProvider = StateNotifierProvider<AccentNotifier, AccentColor>((ref) => AccentNotifier());
class AccentNotifier extends StateNotifier<AccentColor> {
  AccentNotifier() : super(AccentColor.emerald) { _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final idx = p.getInt('accent_color') ?? 0;
    state = AccentColor.values[idx.clamp(0, AccentColor.values.length - 1)];
  }
  Future<void> set(AccentColor a) async {
    state = a;
    (await SharedPreferences.getInstance()).setInt('accent_color', AccentColor.values.indexOf(a));
  }
}

// Config
final configProvider = StateNotifierProvider<ConfigNotifier, TomatoConfig?>((ref) => ConfigNotifier());
class ConfigNotifier extends StateNotifier<TomatoConfig?> {
  ConfigNotifier() : super(null) { _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final j = p.getString('router_config');
    if (j != null) state = TomatoConfig.fromJson(jsonDecode(j));
  }
  Future<void> save(TomatoConfig c) async {
    state = c;
    (await SharedPreferences.getInstance()).setString('router_config', jsonEncode(c.toJson()));
  }
  Future<void> clear() async {
    state = null;
    (await SharedPreferences.getInstance()).remove('router_config');
  }
}

// Router Status
final routerStatusProvider = StateNotifierProvider<RouterStatusNotifier, RouterStatus>((ref) => RouterStatusNotifier(ref));
class RouterStatusNotifier extends StateNotifier<RouterStatus> {
  final Ref _ref; Timer? _fast; Timer? _slow;
  RouterStatusNotifier(this._ref) : super(RouterStatus.empty());
  void startPolling() {
    _fast?.cancel(); _slow?.cancel();
    fetchFull();
    _fast = Timer.periodic(const Duration(seconds:1),  (_) => fetchFast()); // CPU: 1s
    _slow = Timer.periodic(const Duration(seconds:15), (_) => fetchFull());
  }
  void stopPolling() { _fast?.cancel(); _slow?.cancel(); }
  // Pause all pollers during heavy SSH operations to prevent queue backup/UI freeze
  void pausePolling() { _fast?.cancel(); _slow?.cancel(); }
  void resumePolling() { startPolling(); }
  Future<void> fetchFast() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    final u = await ssh.getStatusFast(state);
    if (mounted) state = u;
  }
  Future<void> fetchFull() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    final s = await ssh.getStatus();
    if (mounted) state = s;
    _ref.read(ethernetPortsProvider.notifier).fetch();
  }
  Future<void> fetch() => fetchFull();
  @override void dispose() { _fast?.cancel(); _slow?.cancel(); super.dispose(); }
}

// Devices — FIX: persist blocked state in SharedPrefs so poll doesn't wipe it
final devicesProvider = StateNotifierProvider<DevicesNotifier, List<ConnectedDevice>>((ref) => DevicesNotifier(ref));
class DevicesNotifier extends StateNotifier<List<ConnectedDevice>> {
  final Ref _ref; Timer? _timer;
  Set<String> _known = {};
  // Blocked MACs persisted locally — source of truth
  Set<String> _blocked = {};
  // Custom names persisted locally
  Map<String, String> _names = {};
  bool _loaded = false;

  DevicesNotifier(this._ref) : super([]) { _loadPersisted(); }

  Future<void> _loadPersisted() async {
    final p = await SharedPreferences.getInstance();
    _blocked = Set.from(p.getStringList('blocked_macs') ?? []);
    // Load all saved names
    final keys = p.getKeys().where((k) => k.startsWith('device_name_'));
    for (final k in keys) {
      final mac = k.substring('device_name_'.length);
      _names[mac] = p.getString(k) ?? '';
    }
    _loaded = true;
  }

  Future<void> _saveBlocked() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList('blocked_macs', _blocked.toList());
  }

  void startPolling() {
    _timer?.cancel(); fetch();
    _timer = Timer.periodic(const Duration(seconds:10), (_) => fetch());
  }
  void stopPolling() => _timer?.cancel();

  Future<void> fetch() async {
    if (!_loaded) await _loadPersisted();
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    final devices = await ssh.getDevices();
    // Only update state if result is non-empty, OR if previous state was also empty
    // This prevents list from flickering to empty on transient SSH errors.
    if (devices.isEmpty && state.isNotEmpty) return;
    // Apply persisted names and blocked state
    for (final d in devices) {
      if (_names.containsKey(d.mac)) d.name = _names[d.mac]!;
      if (_blocked.contains(d.mac)) d.isBlocked = true;
    }
    // Detect new arrivals
    final cur = devices.map((d) => d.mac).toSet();
    final newMacs = cur.difference(_known);
    if (_known.isNotEmpty && newMacs.isNotEmpty) {
      for (final mac in newMacs) {
        final dev = devices.firstWhere((d) => d.mac == mac);
        NotificationService.showNewDeviceNotification(dev);
      }
    }
    _known = cur;
    if (mounted) state = devices;
  }

  Future<void> renameDevice(String mac, String name) async {
    _names[mac] = name;
    final p = await SharedPreferences.getInstance();
    await p.setString('device_name_$mac', name);
    if (mounted) state = state.map((d) => d.mac == mac ? d.copyWith(name: name) : d).toList();
  }

  // Fix: use IP-based block via iptables -s/-d (more reliable than MAC on some firmware)
  // AND persist in SharedPrefs so poll doesn't reset the flag
  Future<bool> toggleBlock(String mac) async {
    final ssh = _ref.read(sshServiceProvider);
    final dev = state.firstWhere((d) => d.mac == mac);
    final shouldBlock = !dev.isBlocked;
    final ok = await ssh.blockDevice(mac, shouldBlock);
    if (ok) {
      if (shouldBlock) {
        _blocked.add(mac);
      } else {
        _blocked.remove(mac);
      }
      await _saveBlocked();
      if (mounted) {
        state = state.map((d) => d.mac == mac ? d.copyWith(isBlocked: shouldBlock) : d).toList();
      }
    }
    return ok;
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }
}

// Bandwidth
final bandwidthProvider = StateNotifierProvider<BandwidthNotifier, BandwidthStats>((ref) => BandwidthNotifier(ref));
class BandwidthNotifier extends StateNotifier<BandwidthStats> {
  final Ref _ref; Timer? _timer;
  final List<BandwidthPoint> _history = [];
  Map<String,int> _last = {'rx':0,'tx':0}; bool _first = true;
  double _totalRxMB = 0, _totalTxMB = 0;
  BandwidthNotifier(this._ref) : super(BandwidthStats.empty());
  void startPolling() { _timer?.cancel(); _poll(); _timer = Timer.periodic(const Duration(seconds:2), (_) => _poll()); } // Bandwidth: 2s
  void stopPolling() => _timer?.cancel();
  Future<void> _poll() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    final s = await ssh.getBandwidthRaw();
    final rx = s['rx']??0; final tx = s['tx']??0;
    if (_first) { _last = s; _first = false; return; }
    final rd = (rx - _last['rx']!).clamp(0, 999999999);
    final td = (tx - _last['tx']!).clamp(0, 999999999);
    final rk = rd / 1024 * 8; final tk = td / 1024 * 8;
    _totalRxMB += rd / 1024 / 1024; _totalTxMB += td / 1024 / 1024;
    _last = s;
    _history.add(BandwidthPoint(time:DateTime.now(), rxKbps:rk, txKbps:tk));
    if (_history.length > 60) _history.removeAt(0);
    final pr = _history.fold(0.0, (a,b) => a > b.rxKbps ? a : b.rxKbps);
    final pt = _history.fold(0.0, (a,b) => a > b.txKbps ? a : b.txKbps);
    if (mounted) state = BandwidthStats(
      points:List.from(_history), currentRx:rk, currentTx:tk,
      peakRx:pr, peakTx:pt, totalRxMB:_totalRxMB, totalTxMB:_totalTxMB);
  }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
}

// Logs
final logsProvider = StateNotifierProvider<LogsNotifier, List<LogEntry>>((ref) => LogsNotifier(ref));
class LogsNotifier extends StateNotifier<List<LogEntry>> {
  final Ref _ref;
  Timer? _timer;
  // Track seen raw lines so we only append new ones (preserves user scroll position)
  final Set<String> _seenKeys = {};

  LogsNotifier(this._ref) : super([]);

  void startPolling() {
    _timer?.cancel();
    fetch();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => fetch());
  }

  void stopPolling() => _timer?.cancel();

  void clear() { _seenKeys.clear(); if (mounted) state = []; }

  Future<void> fetch() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    final all = await ssh.getLogs();
    if (!mounted || all.isEmpty) return;

    // Append-only: only add lines we haven't seen before
    final newEntries = <LogEntry>[];
    for (final e in all) {
      final key = e.rawLine.isNotEmpty ? e.rawLine : '${e.time.millisecondsSinceEpoch}:${e.message}';
      if (_seenKeys.add(key)) newEntries.add(e);
    }
    if (newEntries.isEmpty) return;

    // Cap at 2000 total entries to limit memory
    final combined = [...state, ...newEntries];
    final capped = combined.length > 2000 ? combined.sublist(combined.length - 2000) : combined;
    if (mounted) state = capped;
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }
}

// QoS
final qosProvider = StateNotifierProvider<QosNotifier, List<QosRule>>((ref) => QosNotifier(ref));
class QosNotifier extends StateNotifier<List<QosRule>> {
  final Ref _ref; Timer? _timer;
  QosNotifier(this._ref) : super([]);
  void startPolling() { _timer?.cancel(); fetch(); _timer = Timer.periodic(const Duration(seconds:10), (_) => fetch()); }
  void stopPolling() => _timer?.cancel();
  Future<void> fetch() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    if (mounted) state = await ssh.getQosRules();
  }
  Future<bool> saveRule(QosRule r) async {
    final ok = await _ref.read(sshServiceProvider).saveQosRule(r);
    if (ok) await fetch(); return ok;
  }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
}

// Port Forward
final portForwardProvider = StateNotifierProvider<PortForwardNotifier, List<PortForwardRule>>((ref) => PortForwardNotifier(ref));
class PortForwardNotifier extends StateNotifier<List<PortForwardRule>> {
  final Ref _ref; Timer? _timer;
  PortForwardNotifier(this._ref) : super([]);
  void startPolling() { _timer?.cancel(); fetch(); _timer = Timer.periodic(const Duration(seconds:10), (_) => fetch()); }
  void stopPolling() => _timer?.cancel();
  Future<void> fetch() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    final rules = await ssh.getPortForwardRules();
    // Preserve existing state on empty result to prevent UI flicker
    if (rules.isEmpty && state.isNotEmpty) return;
    if (mounted) state = rules;
  }
  Future<bool> saveAll() => _ref.read(sshServiceProvider).savePortForwardRules(state);
  void addRule(PortForwardRule r) { if (mounted) state = [...state, r]; }
  void removeRule(String id) { if (mounted) state = state.where((r) => r.id != id).toList(); }
  void toggleRule(String id) {
    if (!mounted) return;
    state = state.map((r) => r.id == id ? PortForwardRule(
      id:r.id, name:r.name, protocol:r.protocol,
      externalPort:r.externalPort, internalPort:r.internalPort,
      internalIp:r.internalIp, srcFilter:r.srcFilter, enabled:!r.enabled) : r).toList();
  }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
}

// Ethernet Ports
final ethernetPortsProvider = StateNotifierProvider<EthernetPortsNotifier, List<Map<String,dynamic>>>((ref) => EthernetPortsNotifier(ref));
class EthernetPortsNotifier extends StateNotifier<List<Map<String,dynamic>>> {
  final Ref _ref;
  EthernetPortsNotifier(this._ref) : super([]);
  Future<void> fetch() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    try { final r = await ssh.getEthernetPorts(); if (mounted) state = r; } catch(_){}
  }
}

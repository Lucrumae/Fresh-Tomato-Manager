import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ssh_service.dart';
import 'app_state.dart';
import 'background_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ConnectionKeeper — foreground reconnect + background service lifecycle
//
//  When app is in foreground:  pings every 5s, reconnects on fail
//  When app goes background:   background isolate (BackgroundService) takes over
//  When app returns:           re-ping and restart pollers if needed
// ═══════════════════════════════════════════════════════════════════════════════

typedef OnReconnectFailed = void Function();

class ConnectionKeeper {
  final Ref _ref;
  OnReconnectFailed? onFailed;

  Timer? _pingTimer;
  bool   _inFlight    = false;
  bool   _bgStarted   = false;

  ConnectionKeeper(this._ref);

  // ── Start foreground ping loop + background service ────────────────────────
  void start() {
    stop();
    _startBackground();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  void stop() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _inFlight  = false;
  }

  // ── Stop everything including background ───────────────────────────────────
  Future<void> stopAll() async {
    stop();
    if (_bgStarted) {
      await BackgroundService.stop();
      _bgStarted = false;
    }
  }

  // ── Called when app resumes from background ────────────────────────────────
  void onResume() {
    _tick(); // immediate ping
  }

  // ── Internal ───────────────────────────────────────────────────────────────
  Future<void> _startBackground() async {
    final cfg = _ref.read(configProvider);
    if (cfg == null) return;
    try {
      BackgroundService.onEvent = _onBgEvent;
      await BackgroundService.start(host: cfg.host);
      _bgStarted = true;
      debugPrint('[Keeper] Background service started');
    } catch (e) {
      debugPrint('[Keeper] Background service error: $e');
    }
  }

  void _onBgEvent(Map<String, dynamic> event) {
    final type = event['event'] as String?;
    if (type == 'connected') {
      // Background reconnected — if pollers died, restart them
      _restartPollers();
    } else if (type == 'disconnected') {
      debugPrint('[Keeper] BG reports disconnected: ${event['error']}');
    }
  }

  Future<void> _tick() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final ssh = _ref.read(sshServiceProvider);

      if (ssh.isConnected) {
        try {
          await ssh.run('echo 1').timeout(const Duration(seconds: 4));
          return; // alive
        } catch (_) {
          // ping failed
        }
      }

      // Not connected or ping failed — reconnect
      await _reconnect();
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _reconnect() async {
    final ssh = _ref.read(sshServiceProvider);
    final cfg = _ref.read(configProvider);
    if (cfg == null) return;
    if (ssh.isConnected) return;

    debugPrint('[Keeper] Reconnecting (foreground)…');
    final err = await ssh.connect(cfg).timeout(
      const Duration(seconds: 8), onTimeout: () => 'timeout');

    if (err == null) {
      debugPrint('[Keeper] Reconnected OK');
      _restartPollers();
    } else {
      debugPrint('[Keeper] Reconnect failed: $err');
      stop();
      onFailed?.call();
    }
  }

  void _restartPollers() {
    try {
      _ref.read(routerStatusProvider.notifier).startPolling();
      _ref.read(devicesProvider.notifier).startPolling();
      _ref.read(bandwidthProvider.notifier).startPolling();
      _ref.read(logsProvider.notifier).startPolling();
      _ref.read(qosProvider.notifier).startPolling();
      _ref.read(portForwardProvider.notifier).startPolling();
    } catch (e) {
      debugPrint('[Keeper] restartPollers error: $e');
    }
  }
}

final connectionKeeperProvider = Provider<ConnectionKeeper>((ref) {
  final keeper = ConnectionKeeper(ref);
  ref.onDispose(() => keeper.stopAll());
  return keeper;
});

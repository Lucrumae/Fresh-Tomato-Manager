import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ssh_service.dart';
import 'app_state.dart';
import 'notification_service.dart';
import 'background_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ConnectionKeeper — lightweight reconnect guard
//
//  Checks SSH health every 15s. Only sends a ping if isConnected flag is true
//  but we suspect the channel may be stale (every 60s). This avoids flooding
//  the Dropbear SSH daemon with extra sessions.
// ═══════════════════════════════════════════════════════════════════════════════

typedef OnReconnectFailed = void Function();

class ConnectionKeeper {
  final Ref _ref;
  OnReconnectFailed? onFailed;

  Timer? _pingTimer;
  bool   _inFlight  = false;
  int    _tickCount = 0;

  ConnectionKeeper(this._ref);

  void start() {
    stop();
    // Check every 15s — much less aggressive than before
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _tick()); // Keeper ping: 10s
  }

  void stop() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _inFlight  = false;
    _tickCount = 0;
  }

  Future<void> stopAll() async { stop(); }

  // Called when app resumes from background
  void onResume() {
    _tickCount = 99; // force a real ping on next tick
    Future.delayed(const Duration(seconds: 2), _tick);
  }

  Future<void> _tick() async {
    if (_inFlight) return;
    _inFlight = true;
    _tickCount++;
    try {
      final ssh = _ref.read(sshServiceProvider);
      // With a persistent shell session, isConnected reflects shell liveness.
      // _onShellClosed() in SshService triggers reconnect automatically.
      // We only need to kick a reconnect if the flag is already false.
      if (!ssh.isConnected) {
        await _reconnect();
      }
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _reconnect() async {
    final ssh = _ref.read(sshServiceProvider);
    final cfg = _ref.read(configProvider);
    if (cfg == null) return;
    if (ssh.isConnected) return;

    debugPrint('[Keeper] Reconnecting…');
    BackgroundService.showReconnecting(cfg.host);
    final err = await ssh.connectIfNeeded(cfg).timeout(
      const Duration(seconds: 12), onTimeout: () => 'timeout');

    if (err == null) {
      debugPrint('[Keeper] Reconnected OK');
      _restartPollers();
      final cfg = _ref.read(configProvider);
      if (cfg != null) BackgroundService.showConnected(cfg.host);
    } else {
      debugPrint('[Keeper] Reconnect failed: \$err');
      NotificationService.showOffline();
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
      debugPrint('[Keeper] restartPollers error: \$e');
    }
  }
}

final connectionKeeperProvider = Provider<ConnectionKeeper>((ref) {
  final keeper = ConnectionKeeper(ref);
  ref.onDispose(() => keeper.stopAll());
  return keeper;
});

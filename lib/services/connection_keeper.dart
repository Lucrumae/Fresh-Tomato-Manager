import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ssh_service.dart';
import 'app_state.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  ConnectionKeeper — lightweight reconnect guard
//
//  Checks SSH health every 10s. Only sends a real ping every 10s to verify
//  the channel is alive. Avoids flooding the Dropbear SSH daemon.
// ═══════════════════════════════════════════════════════════════════════════════

typedef OnReconnectFailed = void Function();

class ConnectionKeeper {
  final Ref _ref;
  OnReconnectFailed? onFailed;

  Timer? _pingTimer;
  bool   _inFlight  = false;

  ConnectionKeeper(this._ref);

  void start() {
    stop();
    // Ping every 10s
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
  }

  void stop() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _inFlight  = false;
  }

  Future<void> stopAll() async { stop(); }

  // Called when app resumes from background
  void onResume() {
    Future.delayed(const Duration(seconds: 2), _tick);
  }

  Future<void> _tick() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final ssh = _ref.read(sshServiceProvider);

      // If dartssh2 reports closed, reconnect immediately
      if (!ssh.isConnected) {
        await _reconnect();
        return;
      }

      // Every tick (10s) send a real ping to verify channel is alive
      try {
        await ssh.run('echo 1').timeout(const Duration(seconds: 8));
      } catch (_) {
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
    final err = await ssh.connect(cfg).timeout(
      const Duration(seconds: 12), onTimeout: () => 'timeout');

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
      debugPrint('[Keeper] restartPollers error: \$e');
    }
  }
}

final connectionKeeperProvider = Provider<ConnectionKeeper>((ref) {
  final keeper = ConnectionKeeper(ref);
  ref.onDispose(() => keeper.stopAll());
  return keeper;
});

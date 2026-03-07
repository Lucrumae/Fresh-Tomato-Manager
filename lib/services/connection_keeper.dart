import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ssh_service.dart';
import 'app_state.dart';

// Callback when reconnect fails — main_shell will handle redirect
typedef OnReconnectFailed = void Function();

class ConnectionKeeper {
  final Ref _ref;
  OnReconnectFailed? onFailed;

  Timer? _pingTimer;
  bool _inFlight = false;   // prevent overlapping checks

  ConnectionKeeper(this._ref);

  void start() {
    stop();
    // Ping every 5s — realtime detection
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  void stop() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _inFlight = false;
  }

  Future<void> _tick() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final ssh = _ref.read(sshServiceProvider);

      // Already connected → quick ping to verify
      if (ssh.isConnected) {
        try {
          await ssh.run('echo 1').timeout(const Duration(seconds: 4));
        } catch (_) {
          // Ping failed → try reconnect once immediately
          await _reconnectOnce();
        }
      } else {
        // Was disconnected → try reconnect once immediately
        await _reconnectOnce();
      }
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _reconnectOnce() async {
    final ssh  = _ref.read(sshServiceProvider);
    final cfg  = _ref.read(configProvider);
    if (cfg == null) return;
    if (ssh.isConnected) return; // recovered by other means

    debugPrint('[ConnectionKeeper] Reconnecting...');
    final err = await ssh.connect(cfg).timeout(
      const Duration(seconds: 8), onTimeout: () => 'timeout',
    );

    if (err == null) {
      debugPrint('[ConnectionKeeper] Reconnected OK');
      // Restart pollers
      _ref.read(routerStatusProvider.notifier).startPolling();
      _ref.read(devicesProvider.notifier).startPolling();
      _ref.read(bandwidthProvider.notifier).startPolling();
    } else {
      debugPrint('[ConnectionKeeper] Reconnect failed: $err');
      // Notify UI — only once per disconnect event
      stop(); // stop pinging until user re-logins
      onFailed?.call();
    }
  }
}

final connectionKeeperProvider = Provider<ConnectionKeeper>((ref) {
  final keeper = ConnectionKeeper(ref);
  ref.onDispose(() => keeper.stop());
  return keeper;
});

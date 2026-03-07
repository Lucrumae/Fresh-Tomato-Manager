import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ssh_service.dart';
import 'app_state.dart';
import '../models/models.dart';

// Keeps SSH connection alive and auto-reconnects when app resumes
class ConnectionKeeper extends WidgetsBindingObserver {
  final Ref _ref;
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  bool _wasConnected = false;

  ConnectionKeeper(this._ref);

  void start() {
    WidgetsBinding.instance.addObserver(this);
    // Ping every 30s to keep connection alive (sends empty command)
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (_) => _ping());
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _keepAliveTimer?.cancel();
    _reconnectTimer?.cancel();
  }

  Future<void> _ping() async {
    final ssh = _ref.read(sshServiceProvider);
    if (!ssh.isConnected) {
      _scheduleReconnect();
      return;
    }
    try {
      await ssh.run('echo 1').timeout(const Duration(seconds: 5));
      _wasConnected = true;
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), _reconnect);
  }

  Future<void> _reconnect() async {
    final config = _ref.read(configProvider);
    if (config == null) return;

    final ssh = _ref.read(sshServiceProvider);
    if (ssh.isConnected) return;

    debugPrint('ConnectionKeeper: Reconnecting...');
    final error = await ssh.connect(config);
    if (error == null) {
      debugPrint('ConnectionKeeper: Reconnected!');
      // Restart pollers
      _ref.read(routerStatusProvider.notifier).startPolling();
      _ref.read(devicesProvider.notifier).startPolling();
      _ref.read(bandwidthProvider.notifier).startPolling();
    } else {
      debugPrint('ConnectionKeeper: Reconnect failed: $error');
      // Try again in 10s
      _reconnectTimer = Timer(const Duration(seconds: 10), _reconnect);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // App came back to foreground - check connection immediately
        debugPrint('ConnectionKeeper: App resumed, checking connection...');
        Future.delayed(const Duration(milliseconds: 500), () async {
          final ssh = _ref.read(sshServiceProvider);
          if (!ssh.isConnected) {
            debugPrint('ConnectionKeeper: Disconnected while in background, reconnecting...');
            await _reconnect();
          }
        });
        break;
      case AppLifecycleState.paused:
        // Keep the timer running so SSH stays alive
        debugPrint('ConnectionKeeper: App paused, keeping connection alive...');
        break;
      default:
        break;
    }
  }
}

final connectionKeeperProvider = Provider<ConnectionKeeper>((ref) {
  final keeper = ConnectionKeeper(ref);
  ref.onDispose(() => keeper.stop());
  return keeper;
});

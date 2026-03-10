import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'ssh_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Background keep-alive service
//
//  Architecture:
//  • FlutterForegroundTask runs in a SEPARATE Dart isolate on Android
//  • That isolate creates its own SshService + reconnects independently
//  • Every 20s it pings the router; on fail it reconnects
//  • Sends status back to main isolate via IsolateNameServer port
//  • Persistent notification shows live status (connected / reconnecting)
//
//  The main UI also has ConnectionKeeper which handles foreground reconnects.
//  Both can coexist — SSH is stateless enough that two connects don't conflict.
// ═══════════════════════════════════════════════════════════════════════════════

// Port name for cross-isolate communication
const _kPortName = 'void_bg_port';

// Called in the background isolate — MUST be top-level with vm:entry-point
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_VoidTaskHandler());
}

class _VoidTaskHandler extends TaskHandler {
  SshService? _ssh;
  TomatoConfig? _config;
  int _failCount  = 0;
  bool _inFlight  = false;
  DateTime? _connectedAt;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BG] Task started');
    _config = await _loadConfig();
    if (_config != null) {
      _ssh = SshService();
      await _connect();
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await _tick();
    } finally {
      _inFlight = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[BG] Task destroyed');
    _ssh?.disconnect();
    _ssh = null;
  }

  @override
  void onReceiveData(Object data) {
    // Commands from main isolate
    if (data == 'reconnect') {
      _failCount = 0;
      _connect();
    }
  }

  // ── Core logic ─────────────────────────────────────────────────────────────
  Future<void> _tick() async {
    if (_ssh == null || _config == null) return;

    if (_ssh!.isConnected) {
      // Quick ping
      try {
        final result = await _ssh!.run('echo 1').timeout(const Duration(seconds:5));
        if (result.trim() == '1') {
          _failCount = 0;
          _updateNotification(_statusText());
          _sendToMain({'event':'alive', 'uptime': _uptimeSeconds()});
          return;
        }
      } catch (_) {}
    }

    // Ping failed or not connected
    _failCount++;
    debugPrint('[BG] Ping failed (attempt $_failCount)');
    _updateNotification('Reconnecting…');
    await _connect();
  }

  Future<void> _connect() async {
    if (_config == null) return;
    _ssh ??= SshService();
    try {
      final err = await _ssh!.connect(_config!).timeout(const Duration(seconds:10));
      if (err == null) {
        _failCount  = 0;
        _connectedAt = DateTime.now();
        debugPrint('[BG] Connected OK');
        _updateNotification(_statusText());
        _sendToMain({'event':'connected'});
      } else {
        debugPrint('[BG] Connect error: $err');
        _updateNotification('Offline — retrying…');
        _sendToMain({'event':'disconnected', 'error': err});
      }
    } catch (e) {
      debugPrint('[BG] Connect exception: $e');
      _updateNotification('Offline — retrying…');
      _sendToMain({'event':'disconnected', 'error': '$e'});
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _updateNotification(String text) {
    FlutterForegroundTask.updateService(notificationText: text);
  }

  String _statusText() {
    final up = _uptimeSeconds();
    if (up < 60) return 'Connected · ${up}s';
    if (up < 3600) return 'Connected · ${up ~/ 60}m';
    return 'Connected · ${up ~/ 3600}h ${(up % 3600) ~/ 60}m';
  }

  int _uptimeSeconds() {
    if (_connectedAt == null) return 0;
    return DateTime.now().difference(_connectedAt!).inSeconds;
  }

  void _sendToMain(Map<String, dynamic> data) {
    final port = IsolateNameServer.lookupPortByName(_kPortName);
    port?.send(data);
  }

  Future<TomatoConfig?> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json  = prefs.getString('router_config');
      if (json == null) return null;
      // Minimal JSON parse — avoid dart:convert import issues in isolate
      return TomatoConfig.fromJson(_parseJson(json));
    } catch (e) {
      debugPrint('[BG] loadConfig error: $e');
      return null;
    }
  }

  Map<String, dynamic> _parseJson(String s) {
    return jsonDecode(s) as Map<String, dynamic>;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  BackgroundService — main isolate API
// ═══════════════════════════════════════════════════════════════════════════════
class BackgroundService {
  static bool _initialized = false;
  static ReceivePort? _receivePort;
  static StreamSubscription? _sub;

  // Callback when background reports a status change
  static void Function(Map<String,dynamic>)? onEvent;

  // ── Init (call once in main()) ─────────────────────────────────────────────
  static void init() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId:          'void_keepalive',
        channelName:        'Router Keep-Alive',
        channelDescription: 'Maintains SSH connection to router in background',
        channelImportance:  NotificationChannelImportance.LOW,
        priority:           NotificationPriority.LOW,
        // No vibration / sound — silent persistent notification
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound:        false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Ping every 20s — aggressive enough for keep-alive, gentle on battery
        eventAction:    ForegroundTaskEventAction.repeat(20000),
        autoRunOnBoot:  false,
        allowWifiLock:  true,
      ),
    );
  }

  // ── Start service ──────────────────────────────────────────────────────────
  static Future<void> start({String host = 'router'}) async {
    init();

    // Register receive port so background isolate can send us events
    _receivePort?.close();
    _receivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(_kPortName);
    IsolateNameServer.registerPortWithName(_receivePort!.sendPort, _kPortName);
    _sub?.cancel();
    _sub = _receivePort!.listen((data) {
      if (data is Map<String, dynamic>) {
        onEvent?.call(data);
      }
    });

    if (await FlutterForegroundTask.isRunningService) {
      // Already running — just send reconnect signal
      FlutterForegroundTask.sendDataToTask('reconnect');
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId:        256,
      notificationTitle: 'VOID · $host',
      notificationText: 'Starting…',
      callback:         startCallback,
    );
  }

  // ── Stop service ───────────────────────────────────────────────────────────
  static Future<void> stop() async {
    _sub?.cancel();
    _receivePort?.close();
    _receivePort = null;
    IsolateNameServer.removePortNameMapping(_kPortName);

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  // ── Check if running ───────────────────────────────────────────────────────
  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}

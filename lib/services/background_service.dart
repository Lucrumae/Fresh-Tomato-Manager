import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

// ── Background task handler ────────────────────────────────────────────────────
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  Timer? _timer;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      // Ping sent from main isolate via connection_keeper — just keep alive
      FlutterForegroundTask.updateService(
        notificationText: 'Connected to router',
      );
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _timer?.cancel();
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop') FlutterForegroundTask.stopService();
  }
}

// ── Background Service API ─────────────────────────────────────────────────────
class BackgroundService {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tomato_manager_keepalive',
        channelName: 'Router Connection',
        channelDescription: 'Keeps SSH connection to router active',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        buttons: [
          const NotificationButton(id: 'stop', text: 'Disconnect'),
        ],
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        allowWifiLock: true,
      ),
    );
  }

  static Future<void> start() async {
    init();
    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'Tomato Manager',
      notificationText: 'Connected to router',
      callback: startCallback,
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static Future<void> update(String text) async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(notificationText: text);
    }
  }

  /// Call this in initState of screens that need lifecycle awareness
  static Widget wrapWithTask({required Widget child}) {
    return WithForegroundTask(child: child);
  }
}

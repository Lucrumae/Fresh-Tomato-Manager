import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  BackgroundService
//
//  Uses flutter_foreground_task to run an Android Foreground Service.
//  This prevents Android from killing the process (and SSH socket) when
//  the user switches to another app.
//
//  The foreground service shows a persistent status notification.
//  All SSH logic stays in the main isolate — no separate isolate needed.
//
//  On iOS: flutter_foreground_task is a no-op; wakelock handles it.
//
//  Wakelock: WakelockPlus.enable() dipanggil saat start() agar CPU tidak
//  Keeps CPU awake so the SSH socket stays alive in the background.
// ═══════════════════════════════════════════════════════════════════════════════

// Minimal task handler — just keeps the service alive, does nothing else
@pragma('vm:entry-point')
void _taskCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}
  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

class BackgroundService {
  static bool _fgInited    = false;
  static bool _notifInited = false;

  // Notification plugin (for iOS + action buttons)
  static final _notif    = FlutterLocalNotificationsPlugin();
  static bool  _notifOk  = false;

  // ── One-time init (call in main()) ────────────────────────────────────────
  static Future<void> init({
    DidReceiveBackgroundNotificationResponseCallback? backgroundHandler,
  }) async {
    // Init flutter_local_notifications — guard against double-init
    if (!_notifInited) {
      _notifInited = true;
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false,
      );
      await _notif.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: _onAction,
        onDidReceiveBackgroundNotificationResponse: backgroundHandler,
      );
    }

    // Init foreground task (Android)
    if (!_fgInited) {
      _fgInited = true;
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId:          'tomato_keepalive',
          channelName:        'Router Connection',
          channelDescription: 'Keeps SSH connection alive while app is open',
          channelImportance:  NotificationChannelImportance.LOW,
          priority:           NotificationPriority.LOW,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound:        false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          // Just a heartbeat; no actual work done here
          eventAction:   ForegroundTaskEventAction.repeat(30000),
          autoRunOnBoot: false,
          allowWifiLock: true,
        ),
      );
    }
  }

  // ── Start foreground service (call after successful SSH connect) ──────────
  static Future<void> start({required String host, required String statusText}) async {
    await init();

    // Aktifkan WakeLock agar CPU tidak tidur dan SSH tetap hidup
    try { await WakelockPlus.enable(); } catch (_) {}

    // NOTE: Do NOT call requestNotificationPermission() here.
    // On Android 13+ it triggers an Activity restart after grant which crashes the app.
    // POST_NOTIFICATIONS is declared in AndroidManifest — system handles it at install time.
    _notifOk = true;

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Tomato Manager',
        notificationText: statusText,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId:         100,
      notificationTitle: 'Tomato Manager',
      notificationText:  statusText,
      callback:          _taskCallback,
      notificationButtons: [
        const NotificationButton(id: 'disconnect', text: 'Disconnect'),
      ],
    );
  }

  // ── Update notification text ──────────────────────────────────────────────
  static Future<void> showConnected(String host) async {
    if (!_notifOk) return;
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Tomato Manager',
        notificationText:  'Connected — $host',
      );
    }
  }

  static Future<void> showReconnecting(String host) async {
    if (!_notifOk) return;
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Tomato Manager',
        notificationText:  'Reconnecting to $host\u2026',
      );
    }
  }

  static Future<void> showOffline() async {
    if (!_notifOk) return;
    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.updateService(
        notificationTitle: 'Tomato Manager',
        notificationText:  'Router offline',
      );
    }
  }

  // ── Stop foreground service ───────────────────────────────────────────────
  static Future<void> stop() async {
    _notifOk = false;
    // Matikan WakeLock saat disconnect
    try { await WakelockPlus.disable(); } catch (_) {}
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  // ── Disconnect action from notification ───────────────────────────────────
  static void Function()? onDisconnectAction;

  static void _onAction(NotificationResponse resp) {
    if (resp.actionId == 'disconnect') {
      onDisconnectAction?.call();
    }
  }

  // Legacy / notification_service stubs
  static Future<void> dismiss() async => stop();
  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}

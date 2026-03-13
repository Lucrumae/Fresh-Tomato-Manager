import 'package:flutter/material.dart';
import 'ssh_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/models.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized       = false;
  static bool _permissionGranted = false;

  static const _connId     = 1;
  static const _deviceBase = 100;

  // Called from main() — registers the background action handler
  static SshService? _ssh;

  static void setSsh(SshService ssh) { _ssh = ssh; }

  static Future<void> init({SshService? ssh, DidReceiveBackgroundNotificationResponseCallback? backgroundHandler}) async {
    if (_initialized) return;
    _initialized = true;
    _ssh = ssh;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onAction,
      onDidReceiveBackgroundNotificationResponse: backgroundHandler,
    );
  }

  // Handle notification action tap (foreground)
  static void _onAction(NotificationResponse resp) {
    if (resp.actionId == 'disconnect') _doDisconnect();
  }

  // Handle notification action tap (background) — must be top-level
  static void _doDisconnect() {
    _ssh?.disconnect();
    cancelConnection();
  }

  static Future<bool> requestPermission() async {
    if (_permissionGranted) return true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        _permissionGranted = await android.requestNotificationsPermission() ?? false;
        return _permissionGranted;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        _permissionGranted = await ios.requestPermissions(
            alert: true, badge: false, sound: false) ?? false;
        return _permissionGranted;
      }
    } catch (e) {
      debugPrint('[Notif] requestPermission: $e');
    }
    return false;
  }

  static Future<void> showConnected(String host) async {
    if (!_permissionGranted) return;
    await _show(_connId, 'Tomato Manager', 'Connected to $host',
      channelId: 'void_connection', importance: Importance.low,
      ongoing: true, color: const Color(0xFF00E887),
      actions: const [
        AndroidNotificationAction('disconnect', 'Disconnect',
          cancelNotification: true, showsUserInterface: false),
      ]);
  }

  static Future<void> showReconnecting() async {
    if (!_permissionGranted) return;
    await _show(_connId, 'Tomato Manager', 'Reconnecting to router\u2026',
      channelId: 'void_connection', importance: Importance.low,
      ongoing: true, color: const Color(0xFFFFB700));
  }

  static Future<void> showOffline() async {
    if (!_permissionGranted) return;
    await _show(_connId, 'Tomato Manager', 'Router offline \u2014 tap to reconnect',
      channelId: 'void_connection', importance: Importance.defaultImportance,
      ongoing: false, color: const Color(0xFFFF3B3B));
  }

  static Future<void> cancelConnection() async {
    await _plugin.cancel(_connId);
  }

  static Future<void> showNewDeviceNotification(ConnectedDevice device) async {
    if (!_permissionGranted) return;
    final id = _deviceBase + (device.mac.hashCode.abs() % 900);
    await _show(id, 'New device joined', '${device.displayName}  \u2022  ${device.ip}',
      channelId: 'void_devices', importance: Importance.defaultImportance,
      ongoing: false, color: const Color(0xFF38CFFF));
  }

  static Future<void> showRouterOfflineNotification() async => showOffline();

  static Future<void> _show(int id, String title, String body, {
    required String channelId,
    required Importance importance,
    required bool ongoing,
    required Color color,
    List<AndroidNotificationAction>? actions,
  }) async {
    await _plugin.show(id, title, body, NotificationDetails(
      android: AndroidNotificationDetails(
        channelId, channelId,
        importance:       importance,
        priority:         Priority.low,
        ongoing:          ongoing,
        autoCancel:       !ongoing,
        icon:             '@mipmap/ic_launcher',
        color:            color,
        playSound:        false,
        enableVibration:  false,
        actions:          actions,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: false,
        presentSound: false,
        presentBadge: false,
      ),
    ));
  }
}

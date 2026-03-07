import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/models.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(android: android, iOS: iOS);
    await _plugin.initialize(settings);
    _initialized = true;
  }

  static Future<void> showNewDeviceNotification(ConnectedDevice device) async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'new_device', 'New Device Connected',
        channelDescription: 'Alerts when a new device connects to the router',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true),
    );
    await _plugin.show(
      device.mac.hashCode,
      'New Device Connected',
      '${device.displayName} (${device.ip}) joined your network',
      details,
    );
  }

  static Future<void> showRouterOfflineNotification() async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'router_status', 'Router Status',
        channelDescription: 'Router connectivity alerts',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true),
    );
    await _plugin.show(0, 'Router Offline', 'Cannot reach your router', details);
  }
}

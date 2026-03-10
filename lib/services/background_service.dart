// no-op stub
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

const _kStatusChannelId   = 'tomato_status';
const _kStatusChannelName = 'Router Status';
const _kDeviceChannelId   = 'tomato_devices';
const _kDeviceChannelName = 'Device Alerts';
const _kStatusNotifId     = 1;
const _kDeviceNotifId     = 2;

class BackgroundService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready   = false;
  static bool _allowed = false;

  static Future<void> init() async {
    if (_ready) return;
    _ready = true;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
  }

  static Future<void> requestPermissionAndShow(String host) async {
    await init();
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) _allowed = await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) _allowed = await ios.requestPermissions(alert: true, badge: false, sound: false) ?? false;
    } catch (e) { debugPrint('[Notif] Permission error: $e'); }
    if (_allowed) await showConnected(host);
  }

  static Future<void> showConnected(String host) => _showStatus(
    title: 'Tomato Manager', body: 'Connected \u2014 $host', ongoing: true);

  static Future<void> showReconnecting(String host) => _showStatus(
    title: 'Tomato Manager', body: 'Reconnecting to $host\u2026', ongoing: false);

  static Future<void> showOffline() => _showStatus(
    title: 'Tomato Manager', body: 'Router offline', ongoing: false);

  static Future<void> dismiss() async {
    if (!_ready) return;
    await _plugin.cancel(_kStatusNotifId);
  }

  static Future<void> showNewDevice(String name, String ip) async {
    if (!_ready || !_allowed) return;
    try {
      await _plugin.show(_kDeviceNotifId, 'New device connected', '$name \u2014 $ip',
        const NotificationDetails(
          android: AndroidNotificationDetails(_kDeviceChannelId, _kDeviceChannelName,
            importance: Importance.defaultImportance, priority: Priority.defaultPriority, autoCancel: true),
          iOS: DarwinNotificationDetails()));
    } catch (e) { debugPrint('[Notif] device notif error: $e'); }
  }

  static Future<void> _showStatus({required String title, required String body, required bool ongoing}) async {
    await init();
    if (!_allowed) return;
    try {
      await _plugin.show(_kStatusNotifId, title, body,
        NotificationDetails(
          android: AndroidNotificationDetails(_kStatusChannelId, _kStatusChannelName,
            channelDescription: 'Shows current router connection status',
            importance: Importance.low, priority: Priority.low,
            ongoing: ongoing, autoCancel: false, showWhen: false,
            playSound: false, enableVibration: false, icon: '@mipmap/ic_launcher'),
          iOS: const DarwinNotificationDetails(presentAlert: false)));
    } catch (e) { debugPrint('[Notif] status notif error: $e'); }
  }

  static Future<void> start({String host = 'router'}) async {}
  static Future<void> stop() async {}
  static Future<bool> get isRunning async => false;
  static void Function(Map<String, dynamic>)? onEvent;
}

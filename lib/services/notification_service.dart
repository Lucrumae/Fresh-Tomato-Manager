import '../models/models.dart';

// Notifikasi diimplementasikan via platform channel sederhana
// flutter_local_notifications dihapus karena tidak kompatibel dengan iOS simulator build
class NotificationService {
  static Future<void> init() async {}

  static Future<void> showNewDeviceNotification(ConnectedDevice device) async {
    // TODO: implementasi notifikasi setelah app berjalan
    print('New device: ${device.displayName} (${device.ip})');
  }

  static Future<void> showRouterOfflineNotification() async {
    print('Router offline');
  }
}

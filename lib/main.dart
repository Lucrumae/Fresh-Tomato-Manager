import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'services/app_state.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/notification_service.dart';
import 'services/background_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'screens/setup_screen.dart';
import 'screens/main_shell.dart';

// Top-level handler for notification actions when app is in background/terminated
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  if (response.actionId == 'disconnect') {
    NotificationService.cancelConnection();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundService.init(backgroundHandler: notificationBackgroundHandler);
  // Request notification permission on first launch (Android 13+ / iOS).
  // Must call BOTH systems: FlutterForegroundTask (for foreground service notif)
  // AND NotificationService (for connected/device/offline notifications).
  final permStatus = await FlutterForegroundTask.checkNotificationPermission();
  if (permStatus != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }
  // Sync permission state into NotificationService so it can show notifications.
  await NotificationService.init(backgroundHandler: notificationBackgroundHandler);
  await NotificationService.requestPermission();
  runApp(const ProviderScope(child: VoidApp()));
}

class VoidApp extends ConsumerWidget {
  const VoidApp({super.key});

  @override Widget build(BuildContext context, WidgetRef ref) {
    final dark   = ref.watch(darkModeProvider);
    final accent = ref.watch(accentProvider);
    final config = ref.watch(configProvider);

    return MaterialApp(
      title: 'Tomato Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(false, accent),
      darkTheme: AppTheme.build(true, accent),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: config != null ? const _AutoConnect() : const SetupScreen(),
    );
  }
}

class _AutoConnect extends ConsumerStatefulWidget {
  const _AutoConnect();
  @override ConsumerState<_AutoConnect> createState() => _AutoConnectState();
}
class _AutoConnectState extends ConsumerState<_AutoConnect> {
  @override void initState() {
    super.initState();
    _tryConnect();
  }

  Future<void> _tryConnect() async {
    final config = ref.read(configProvider);
    if (config == null) {
      if (mounted) Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupScreen()));
      return;
    }
    final ssh = ref.read(sshServiceProvider);
    final err = await ssh.connect(config);
    if (mounted) {
      if (err != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SetupScreen(reconnectFailed: true)));
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()));
      }
    }
  }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>();
    final isDark = v?.dark == true;
    return Scaffold(
      backgroundColor: isDark ? V.d0 : const Color(0xFFF7F7F7),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 24, height: 24,
          child: CircularProgressIndicator(color: v?.accent ?? V.ok, strokeWidth: 2)),
        const SizedBox(height: 20),
        Text('Connecting…', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w500,
          color: isDark ? V.mid : const Color(0xFF888888))),
      ])),
    );
  }
}

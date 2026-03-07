import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'screens/setup_screen.dart';
import 'screens/main_shell.dart';
import 'services/app_state.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await NotificationService.init();

  runApp(const ProviderScope(child: TomatoManagerApp()));
}

class TomatoManagerApp extends ConsumerWidget {
  const TomatoManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);

    return MaterialApp(
      title: 'Tomato Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: config == null ? const SetupScreen() : const MainShell(),
    );
  }
}

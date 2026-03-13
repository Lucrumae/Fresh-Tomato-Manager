import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'services/app_state.dart';
import 'screens/setup_screen.dart';
import 'screens/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    // Use connectIfNeeded — avoids force-reconnecting an already-live session
    // which causes race conditions and crashes on app reopen
    final err = await ssh.connectIfNeeded(config);
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

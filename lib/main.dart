import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'theme/app_theme.dart';
import 'services/app_state.dart';
import 'screens/setup_screen.dart';
import 'screens/main_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  runApp(const ProviderScope(child: VoidApp()));
}

class VoidApp extends ConsumerWidget {
  const VoidApp({super.key});

  @override Widget build(BuildContext context, WidgetRef ref) {
    final dark   = ref.watch(darkModeProvider);
    final accent = ref.watch(accentProvider);
    final config = ref.watch(configProvider);

    return MaterialApp(
      title: 'VOID — Router Manager',
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
    return Scaffold(
      backgroundColor: v?.dark == true ? V.d0 : V.l0,
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: v?.accent ?? V.ok, strokeWidth: 2),
        const SizedBox(height: 16),
        Text('CONNECTING...', style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: v?.mid ?? V.mid,
          letterSpacing: 1.5)),
      ])),
    );
  }
}

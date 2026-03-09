import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/background_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../services/connection_keeper.dart';
import 'dashboard_screen.dart';
import 'devices_screen.dart';
import 'bandwidth_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';
import 'terminal_screen.dart';
import 'files_screen.dart';
import 'setup_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    BackgroundService.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(routerStatusProvider.notifier).startPolling();
      ref.read(devicesProvider.notifier).startPolling();
      ref.read(bandwidthProvider.notifier).startPolling();
      ref.read(logsProvider.notifier).startPolling();
      ref.read(qosProvider.notifier).startPolling();
      ref.read(portForwardProvider.notifier).startPolling();
      final keeper = ref.read(connectionKeeperProvider);
      keeper.onFailed = _onReconnectFailed;
      keeper.start();
    });
  }

  @override
  void dispose() {
    ref.read(connectionKeeperProvider).stop();
    ref.read(routerStatusProvider.notifier).stopPolling();
    ref.read(devicesProvider.notifier).stopPolling();
    ref.read(bandwidthProvider.notifier).stopPolling();
    ref.read(logsProvider.notifier).stopPolling();
    ref.read(qosProvider.notifier).stopPolling();
    ref.read(portForwardProvider.notifier).stopPolling();
    super.dispose();
  }

  void _onReconnectFailed() {
    BackgroundService.stop();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _redirectToLogin();
    });
  }

  Future<void> _redirectToLogin() async {
    ref.read(routerStatusProvider.notifier).stopPolling();
    ref.read(devicesProvider.notifier).stopPolling();
    ref.read(bandwidthProvider.notifier).stopPolling();
    ref.read(logsProvider.notifier).stopPolling();
    ref.read(qosProvider.notifier).stopPolling();
    ref.read(portForwardProvider.notifier).stopPolling();
    await ref.read(sshServiceProvider).disconnect();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const SetupScreen(reconnectFailed: true),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final c = Theme.of(context).extension<AppColors>()!;

    // Short labels so they never wrap or get cut
    const tabDefs = [
      (Icons.dashboard_rounded,  'Home'),
      (Icons.devices_rounded,    'Devices'),
      (Icons.show_chart_rounded, 'Bandwidth'),
      (Icons.article_rounded,    'Logs'),
      (Icons.folder_rounded,     'Files'),
      (Icons.terminal_rounded,   'Terminal'),
      (Icons.settings_rounded,   'Settings'),
    ];

    final screens = [
      const DashboardScreen(),
      const DevicesScreen(),
      const BandwidthScreen(),
      const LogsScreen(),
      const FilesScreen(),
      const TerminalScreen(),
      const SettingsScreen(),
    ];

    return WithForegroundTask(
      child: Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          navigationBarTheme: NavigationBarThemeData(
            labelTextStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: c.cardBg,
          indicatorColor: Theme.of(context).extension<AppColors>()!.accent.withOpacity(0.15),
          height: 62,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: tabDefs.map((t) {
            final isTerminal = t.$1 == Icons.terminal_rounded;
            return NavigationDestination(
              icon: Icon(t.$1, size: 22),
              selectedIcon: Icon(t.$1, size: 22),
              label: t.$2,
            );
          }).toList(),
        ),
      ),
    ));
  }
}

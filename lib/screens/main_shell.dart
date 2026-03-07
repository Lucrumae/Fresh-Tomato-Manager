import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Start pollers
      ref.read(routerStatusProvider.notifier).startPolling();
      ref.read(devicesProvider.notifier).startPolling();
      ref.read(bandwidthProvider.notifier).startPolling();

      // Start keeper — wire up the onFailed callback
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
    super.dispose();
  }

  // Called by ConnectionKeeper on background isolate → dispatch to main thread
  void _onReconnectFailed() {
    if (!mounted) return;
    // Use addPostFrameCallback to be safe (may be called from timer callback)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _redirectToLogin();
    });
  }

  Future<void> _redirectToLogin() async {
    ref.read(routerStatusProvider.notifier).stopPolling();
    ref.read(devicesProvider.notifier).stopPolling();
    ref.read(bandwidthProvider.notifier).stopPolling();
    await ref.read(sshServiceProvider).disconnect();
    // Do NOT clear configProvider so "remember me" data is preserved

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

    final tabs = [
      (Icons.dashboard_rounded,  l.dashboard, false),
      (Icons.devices_rounded,    l.devices,   false),
      (Icons.show_chart_rounded, l.bandwidth, false),
      (Icons.article_rounded,    l.logs,      false),
      (Icons.folder_rounded,     'Files',     false),
      (Icons.terminal_rounded,   l.terminal,  true),
      (Icons.settings_rounded,   l.settings,  false),
    ];

    final screens = [
      const DashboardScreen(),
      const DevicesScreen(),
      const BandwidthScreen(),
      const LogsScreen(),
      const FilesScreen(),
      const _TerminalTab(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: c.cardBg,
        indicatorColor: AppTheme.primary.withOpacity(0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: tabs.map((t) => NavigationDestination(
          icon: Icon(t.$1, color: t.$3 ? AppTheme.terminal : null),
          selectedIcon: Icon(t.$1,
            color: t.$3 ? AppTheme.terminal : AppTheme.primary),
          label: t.$2,
        )).toList(),
      ),
    );
  }
}

// ── Terminal tab wrapper ───────────────────────────────────────────────────────
class _TerminalTab extends StatelessWidget {
  const _TerminalTab();
  @override
  Widget build(BuildContext context) => const TerminalScreen();
}

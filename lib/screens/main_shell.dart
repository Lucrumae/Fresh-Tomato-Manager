import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
      MaterialPageRoute(builder: (_) => const SetupScreen(reconnectFailed: true)),
      (_) => false,
    );
  }

  static const _tabs = [
    (Icons.dashboard_rounded,    Icons.dashboard_outlined,      'Home'),
    (Icons.devices_rounded,      Icons.devices_outlined,        'Devices'),
    (Icons.show_chart_rounded,   Icons.show_chart_outlined,     'Bandwidth'),
    (Icons.article_rounded,      Icons.article_outlined,        'Logs'),
    (Icons.folder_rounded,       Icons.folder_outlined,         'Files'),
    (Icons.terminal_rounded,     Icons.terminal_outlined,       'Terminal'),
    (Icons.settings_rounded,     Icons.settings_outlined,       'Settings'),
  ];

  final _screens = const [
    DashboardScreen(), DevicesScreen(), BandwidthScreen(),
    LogsScreen(), FilesScreen(), TerminalScreen(), SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    return WithForegroundTask(
      child: Scaffold(
        body: IndexedStack(index: _index, children: _screens),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(top: BorderSide(color: c.border, width: 1)),
          ),
          child: SafeArea(
            child: SizedBox(
              height: 58,
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final selected = i == _index;
                  final tab = _tabs[i];
                  return Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _index = i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: selected ? c.accent.withOpacity(0.12) : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              selected ? tab.$1 : tab.$2,
                              size: 20,
                              color: selected ? c.accent : c.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(tab.$3,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? c.accent : c.textMuted,
                            )),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

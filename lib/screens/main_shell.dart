import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/connection_keeper.dart';
import '../services/ssh_service.dart';
import 'dashboard_screen.dart';
import 'devices_screen.dart';
import 'bandwidth_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';
import 'terminal_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  int _index = 0;
  bool _isReconnecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(routerStatusProvider.notifier).startPolling();
      ref.read(devicesProvider.notifier).startPolling();
      ref.read(bandwidthProvider.notifier).startPolling();
      // Start connection keeper
      ref.read(connectionKeeperProvider).start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(connectionKeeperProvider).stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndReconnect();
    }
  }

  Future<void> _checkAndReconnect() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) {
      setState(() => _isReconnecting = true);
      final config = ref.read(configProvider);
      if (config != null) {
        final error = await ssh.connect(config);
        if (error == null && mounted) {
          ref.read(routerStatusProvider.notifier).startPolling();
          ref.read(devicesProvider.notifier).startPolling();
          ref.read(bandwidthProvider.notifier).startPolling();
        }
      }
      if (mounted) setState(() => _isReconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final c = Theme.of(context).extension<AppColors>()!;
    // Watch SSH connection state via routerStatus
    final status = ref.watch(routerStatusProvider);

    final tabs = [
      (Icons.dashboard_rounded,  l.dashboard),
      (Icons.devices_rounded,    l.devices),
      (Icons.show_chart_rounded, l.bandwidth),
      (Icons.article_rounded,    l.logs),
      (Icons.terminal_rounded,   l.terminal),
      (Icons.settings_rounded,   l.settings),
    ];

    final screens = [
      const DashboardScreen(),
      const DevicesScreen(),
      const BandwidthScreen(),
      const LogsScreen(),
      const _TerminalTab(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Column(
        children: [
          // Reconnecting banner
          if (_isReconnecting)
            Material(
              color: AppTheme.warning.withOpacity(0.15),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(
                      color: AppTheme.warning, strokeWidth: 1.5)),
                  const SizedBox(width: 10),
                  Text('Reconnecting...',
                    style: TextStyle(
                      color: AppTheme.warning,
                      fontSize: 13, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          Expanded(
            child: IndexedStack(index: _index, children: screens),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: List.generate(tabs.length, (i) {
                final sel = i == _index;
                final isTerminal = i == 4;
                final color = sel
                  ? (isTerminal ? AppTheme.terminal : AppTheme.primary)
                  : c.textMuted;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _index = i),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(tabs[i].$1, size: 22, color: color),
                        const SizedBox(height: 3),
                        Text(tabs[i].$2, style: TextStyle(
                          fontSize: 10,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                          color: color,
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
    );
  }
}

class _TerminalTab extends StatelessWidget {
  const _TerminalTab();
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Color(0xFF0D1117),
    body: SafeArea(child: TerminalScreen()),
  );
}

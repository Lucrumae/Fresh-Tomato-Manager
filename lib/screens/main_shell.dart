import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
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

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(routerStatusProvider.notifier).startPolling();
      ref.read(devicesProvider.notifier).startPolling();
      ref.read(bandwidthProvider.notifier).startPolling();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final c = Theme.of(context).extension<AppColors>()!;

    final tabs = [
      (Icons.dashboard_rounded,  l.dashboard),
      (Icons.devices_rounded,    l.devices),
      (Icons.show_chart_rounded, l.bandwidth),
      (Icons.article_rounded,    l.logs),
      (Icons.terminal_rounded,   l.terminal),
      (Icons.settings_rounded,   l.settings),
    ];

    // Terminal is a Column widget so it needs a Scaffold with body only
    // No WillPopScope needed - it's just another tab
    final screens = [
      const DashboardScreen(),
      const DevicesScreen(),
      const BandwidthScreen(),
      const LogsScreen(),
      const _TerminalTab(),   // wrapped in Scaffold
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
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

// Terminal tab wrapped in Scaffold agar AppBar tetap ada
class _TerminalTab extends StatelessWidget {
  const _TerminalTab();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0D1117),
      body: SafeArea(child: TerminalScreen()),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  static const _tabs = [
    _Tab(Icons.dashboard_rounded,   'Dashboard'),
    _Tab(Icons.devices_rounded,     'Devices'),
    _Tab(Icons.show_chart_rounded,  'Bandwidth'),
    _Tab(Icons.article_rounded,     'Logs'),
    _Tab(Icons.terminal_rounded,    'Terminal'),
    _Tab(Icons.settings_rounded,    'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    // Terminal gets its own full-screen treatment
    if (_index == 4) {
      return WillPopScope(
        onWillPop: () async { setState(() => _index = 0); return false; },
        child: const TerminalScreen(),
      );
    }

    final screens = [
      const DashboardScreen(), const DevicesScreen(),
      const BandwidthScreen(), const LogsScreen(),
      const SizedBox(), // placeholder for terminal (handled above)
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index < 4 ? _index : 5, children: [
        screens[0], screens[1], screens[2], screens[3], screens[5],
      ]),
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
              children: List.generate(_tabs.length, (i) {
                final sel = i == _index;
                final isTerminal = i == 4;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _index = i),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_tabs[i].icon, size: 22,
                          color: sel
                            ? (isTerminal ? AppTheme.terminal : AppTheme.primary)
                            : c.textMuted,
                        ),
                        const SizedBox(height: 3),
                        Text(_tabs[i].label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                            color: sel
                              ? (isTerminal ? AppTheme.terminal : AppTheme.primary)
                              : c.textMuted,
                          ),
                        ),
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

class _Tab {
  final IconData icon;
  final String label;
  const _Tab(this.icon, this.label);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/router_api.dart';
import 'dashboard_screen.dart';
import 'devices_screen.dart';
import 'bandwidth_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final config = ref.read(configProvider);
    if (config == null) return;

    final api = ref.read(apiServiceProvider);
    api.configure(config);

    // Start all polling
    ref.read(routerStatusProvider.notifier).startPolling();
    ref.read(devicesProvider.notifier).startPolling();
    ref.read(bandwidthProvider.notifier).startPolling();
  }

  static const _tabs = [
    _TabItem(icon: Icons.dashboard_rounded, label: 'Dashboard'),
    _TabItem(icon: Icons.devices_rounded, label: 'Devices'),
    _TabItem(icon: Icons.show_chart_rounded, label: 'Bandwidth'),
    _TabItem(icon: Icons.article_rounded, label: 'Logs'),
    _TabItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  final _screens = const [
    DashboardScreen(),
    DevicesScreen(),
    BandwidthScreen(),
    LogsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final selected = i == _index;
                final tab = _tabs[i];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _index = i),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(tab.icon,
                          size: 22,
                          color: selected ? AppTheme.primary : AppTheme.textMuted,
                        ),
                        const SizedBox(height: 3),
                        Text(tab.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected ? AppTheme.primary : AppTheme.textMuted,
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

class _TabItem {
  final IconData icon;
  final String label;
  const _TabItem({required this.icon, required this.label});
}

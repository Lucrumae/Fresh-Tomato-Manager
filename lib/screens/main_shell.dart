import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/background_service.dart';
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
  @override ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _idx = 0;

  @override void initState() {
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
      keeper.onFailed = _onFail;
      keeper.start();
    });
  }

  @override void dispose() {
    ref.read(connectionKeeperProvider).stop();
    ref.read(routerStatusProvider.notifier).stopPolling();
    ref.read(devicesProvider.notifier).stopPolling();
    ref.read(bandwidthProvider.notifier).stopPolling();
    ref.read(logsProvider.notifier).stopPolling();
    ref.read(qosProvider.notifier).stopPolling();
    ref.read(portForwardProvider.notifier).stopPolling();
    super.dispose();
  }

  void _onFail() {
    BackgroundService.stop();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(routerStatusProvider.notifier).stopPolling();
      ref.read(devicesProvider.notifier).stopPolling();
      ref.read(bandwidthProvider.notifier).stopPolling();
      ref.read(logsProvider.notifier).stopPolling();
      ref.read(qosProvider.notifier).stopPolling();
      ref.read(portForwardProvider.notifier).stopPolling();
      ref.read(sshServiceProvider).disconnect();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SetupScreen(reconnectFailed: true)),
        (_) => false,
      );
    });
  }

  // ── Destination table ────────────────────────────────────────────────────────
  static const _tabs = [
    _Tab(Icons.terminal_rounded,       Icons.terminal_rounded,      'DASH'),
    _Tab(Icons.wifi_tethering_rounded, Icons.wifi_tethering_rounded,'NODES'),
    _Tab(Icons.ssid_chart_rounded,     Icons.ssid_chart_rounded,    'TRAFFIC'),
    _Tab(Icons.code_rounded,           Icons.code_rounded,          'SHELL'),
    _Tab(Icons.folder_open_rounded,    Icons.folder_open_rounded,   'FILES'),
    _Tab(Icons.tune_rounded,           Icons.tune_rounded,          'CONFIG'),
  ];

  final _screens = const [
    DashboardScreen(),
    DevicesScreen(),
    BandwidthScreen(),
    TerminalScreen(),
    FilesScreen(),
    SettingsScreen(),
  ];

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: v.dark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: v.dark ? V.d0 : V.l2,
      systemNavigationBarIconBrightness: v.dark ? Brightness.light : Brightness.dark,
    ));

    return WithForegroundTask(child: Scaffold(
      body: IndexedStack(index: _idx, children: _screens),
      bottomNavigationBar: _VoidNavBar(
        tabs: _tabs, selected: _idx,
        onTap: (i) => setState(() => _idx = i),
        v: v,
      ),
    ));
  }
}

class _Tab {
  final IconData icon, iconFill;
  final String label;
  const _Tab(this.icon, this.iconFill, this.label);
}

class _VoidNavBar extends StatelessWidget {
  final List<_Tab> tabs;
  final int selected;
  final ValueChanged<int> onTap;
  final VC v;
  const _VoidNavBar({required this.tabs, required this.selected,
    required this.onTap, required this.v});

  @override Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: v.dark ? V.d0 : V.l2,
        border: Border(top: BorderSide(color: v.wire, width: 1)),
      ),
      child: SafeArea(top: false, child: SizedBox(
        height: 58,
        child: Row(children: List.generate(tabs.length, (i) {
          final sel  = i == selected;
          final tab  = tabs[i];
          final aclr = v.accent;
          return Expanded(child: GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 40, height: 28,
                decoration: BoxDecoration(
                  color: sel ? aclr.withOpacity(0.10) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: sel ? Border.all(color: aclr.withOpacity(0.25)) : null,
                ),
                child: Icon(sel ? tab.iconFill : tab.icon, size: 17,
                  color: sel ? aclr : v.lo),
              ),
              const SizedBox(height: 3),
              Text(tab.label, style: GoogleFonts.outfit(
                fontSize: 8, fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                color: sel ? aclr : v.lo, letterSpacing: 0.5)),
            ]),
          ));
        })),
      )),
    );
  }
}

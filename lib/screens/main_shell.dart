import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/connection_keeper.dart';
import 'setup_screen.dart';
import 'overview_screen.dart';
import 'devices_screen.dart';
import 'network_screen.dart';
import 'terminal_screen.dart';
import 'system_screen.dart';

// ── Navigation: OVERVIEW · DEVICES · NETWORK · TERMINAL · SYSTEM ──────────────

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  int  _tab     = 0;
  bool _booting = true;

  final _tabs = const [
    _NavTab(icon: Icons.grid_view_rounded,   label: 'OVERVIEW'),
    _NavTab(icon: Icons.devices_rounded,      label: 'DEVICES'),
    _NavTab(icon: Icons.lan_rounded,          label: 'NETWORK'),
    _NavTab(icon: Icons.terminal_rounded,     label: 'TERMINAL'),
    _NavTab(icon: Icons.dns_rounded,          label: 'SYSTEM'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── App lifecycle — resume: re-check connection ────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(connectionKeeperProvider).onResume();
    }
  }

  // ── Boot sequence ──────────────────────────────────────────────────────────
  Future<void> _boot() async {
    await Future.delayed(Duration.zero); // let providers settle
    if (!mounted) return;

    final cfg = ref.read(configProvider);
    if (cfg == null) {
      Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const SetupScreen()));
      return;
    }

    // Connect SSH
    final ssh = ref.read(sshServiceProvider);
    await ssh.connect(cfg);

    // Start all pollers
    _startPollers();

    // Start ConnectionKeeper (foreground ping + background service)
    final keeper = ref.read(connectionKeeperProvider);
    keeper.onFailed = _onConnectionFailed;
    keeper.start();

    // Request battery optimization exemption (Android) — so system doesn't kill us
    await _requestBatteryOptimizationExemption();

    if (mounted) setState(() => _booting = false);
  }

  void _startPollers() {
    ref.read(routerStatusProvider.notifier).startPolling();
    ref.read(devicesProvider.notifier).startPolling();
    ref.read(bandwidthProvider.notifier).startPolling();
    ref.read(logsProvider.notifier).startPolling();
    ref.read(qosProvider.notifier).startPolling();
    ref.read(portForwardProvider.notifier).startPolling();
  }

  void _onConnectionFailed() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
      MaterialPageRoute(builder: (_) => const SetupScreen(reconnectFailed: true)),
      (_) => false);
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    // Battery optimization exemption handled by system permissions
    debugPrint('[Shell] Battery optimization: system-managed');
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(darkModeProvider);
    final accent = ref.watch(accentProvider);
    final theme  = AppTheme.build(isDark, accent);
    final v      = theme.extension<VC>()!;

    return Theme(data: theme, child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor:                   Colors.transparent,
        statusBarIconBrightness:          isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor:         v.bg,
        systemNavigationBarIconBrightness:isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: v.bg,
        body: _booting
          ? _Splash(v: v)
          : IndexedStack(index: _tab, children: const [
              OverviewScreen(),
              DevicesScreen(),
              NetworkScreen(),
              TerminalScreen(),
              SystemScreen(),
            ]),
        bottomNavigationBar: _booting ? null : _BottomNav(
          tabs:    _tabs,
          current: _tab,
          onTap:   (i) => setState(() => _tab = i),
          accent:  v.accent,
          v:       v,
        ),
      ),
    ));
  }
}

// ── Splash while booting ──────────────────────────────────────────────────────
class _Splash extends StatelessWidget {
  final VC v;
  const _Splash({required this.v});
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: v.bg,
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 24, height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: v.accent)),
      const SizedBox(height: 16),
      Text('CONNECTING', style: GoogleFonts.outfit(
        color: v.mid, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2)),
    ])),
  );
}

// ── Nav tab model ─────────────────────────────────────────────────────────────
class _NavTab {
  final IconData icon;
  final String   label;
  const _NavTab({required this.icon, required this.label});
}

// ── Bottom nav bar ────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final List<_NavTab> tabs;
  final int           current;
  final ValueChanged<int> onTap;
  final Color         accent;
  final VC            v;
  const _BottomNav({
    required this.tabs, required this.current,
    required this.onTap, required this.accent, required this.v,
  });

  @override Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:  v.bg,
        border: Border(top: BorderSide(color: v.wire, width: 0.5)),
      ),
      child: SafeArea(top: false, child: SizedBox(height: 60,
        child: Row(children: List.generate(tabs.length, (i) {
          final sel = i == current;
          return Expanded(child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:    () => onTap(i),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(tabs[i].icon, size: 20,
                color: sel ? accent : v.lo),
              const SizedBox(height: 3),
              Text(tabs[i].label, style: GoogleFonts.outfit(
                fontSize: 8.5, fontWeight: FontWeight.w700,
                color:    sel ? accent : v.lo, letterSpacing: 0.5)),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width:  sel ? 16 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color:        sel ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(1))),
            ]),
          ));
        })),
      )),
    );
  }
}

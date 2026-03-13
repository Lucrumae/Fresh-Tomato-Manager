import 'dart:async';
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
  String _bootStep = 'Connecting via SSH…';
  int    _bootProgress = 0;

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
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(connectionKeeperProvider).onResume();
      case AppLifecycleState.paused:
        break;
      default:
        break;
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

    // Step 1: Main SSH session (devices, wifi, QoS, port forward, system)
    if (mounted) setState(() { _bootStep = 'Connecting via SSH…'; _bootProgress = 0; });
    final ssh = ref.read(sshServiceProvider);
    final connErr = await ssh.connectIfNeeded(cfg);
    if (connErr != null) {
      if (mounted) Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const SetupScreen(reconnectFailed: true)));
      return;
    }

    // Step 2: Monitor SSH session (bandwidth, CPU/RAM, logs, terminal)
    if (mounted) setState(() { _bootStep = 'Starting monitor session…'; _bootProgress = 1; });
    final monitorSsh = ref.read(monitorSshServiceProvider);
    await monitorSsh.connectIfNeeded(cfg).catchError((_) => 'monitor session failed');

    // Step 3: Start pollers
    if (mounted) setState(() { _bootStep = 'Loading system data…'; _bootProgress = 2; });
    _startPollers();

    // Step 4: Wait for first data from router
    if (mounted) setState(() { _bootStep = 'Fetching router status…'; _bootProgress = 3; });
    await _waitForInitialData();

    // Step 5: Connection keeper
    final keeper = ref.read(connectionKeeperProvider);
    keeper.onFailed = _onConnectionFailed;
    keeper.start();

    if (mounted) setState(() => _booting = false);
    if (mounted) setState(() => _booting = false);
  }

  Future<void> _waitForInitialData() async {
    const maxWait = Duration(seconds: 8);
    final deadline = DateTime.now().add(maxWait);
    while (mounted && DateTime.now().isBefore(deadline)) {
      final status = ref.read(routerStatusProvider);
      if (status.isOnline) return;
      await Future.delayed(const Duration(milliseconds: 300));
    }
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
          ? _Splash(v: v, step: _bootStep, progress: _bootProgress)
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
  final VC     v;
  final String step;
  final int    progress;
  const _Splash({required this.v, required this.step, required this.progress});

  static const _steps = [
    (Icons.lan_rounded,      'SSH'),
    (Icons.monitor_rounded,  'Monitor'),
    (Icons.memory_rounded,   'System'),
    (Icons.router_rounded,   'Router'),
    (Icons.check_rounded,    'Ready'),
  ];

  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: v.bg,
    body: Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: v.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: v.accent.withOpacity(0.25))),
          child: Icon(Icons.router_rounded, color: v.accent, size: 28)),
        const SizedBox(height: 24),
        Text(step, style: GoogleFonts.outfit(
          fontSize: 14, fontWeight: FontWeight.w600, color: v.hi)),
        const SizedBox(height: 20),
        // Progress dots
        Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_steps.length, (i) {
            final done   = i < progress;
            final active = i == progress;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: active ? 28 : 8, height: 8,
                decoration: BoxDecoration(
                  color: done || active ? v.accent : v.wire,
                  borderRadius: BorderRadius.circular(4))));
          })),
        const SizedBox(height: 16),
        // Step icons
        Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_steps.length, (i) {
            final done   = i < progress;
            final active = i == progress;
            final color  = done ? v.accent : active ? v.hi : v.lo;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(done ? Icons.check_circle_rounded : _steps[i].$1,
                  size: 18, color: color),
                const SizedBox(height: 4),
                Text(_steps[i].$2, style: GoogleFonts.outfit(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  color: color, letterSpacing: 0.5)),
              ]));
          })),
      ]),
    )),
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

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/connection_keeper.dart';
import '../services/background_service.dart';
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
        // App came to foreground — trigger reconnect check immediately
        ref.read(connectionKeeperProvider).onResume();
        // Aktifkan kembali WakeLock jika user mengizinkan
        _restoreWakelock();
      case AppLifecycleState.paused:
        // App going to background — pastikan foreground service + wakelock aktif
        final cfg = ref.read(configProvider);
        if (cfg != null) {
          BackgroundService.showConnected(cfg.host).catchError((_) {});
        }
      default:
        break;
    }
  }

  Future<void> _restoreWakelock() async {
    try {
      final p = await SharedPreferences.getInstance();
      final wakelockEnabled = p.getBool('wakelock_enabled') ?? true;
      if (wakelockEnabled) {
        await WakelockPlus.enable();
      }
    } catch (_) {}
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

    // Step 6: Start background service AFTER overview is visible (avoids crash)
    // and show battery optimization popup if not yet granted.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Start wakelock + foreground service — safe here, widget fully mounted
      try {
        WakelockPlus.enable().catchError((_) {});
        await BackgroundService.start(
          host: cfg.host, statusText: 'Connected to ${cfg.host}');
      } catch (_) {}
      // Show battery optimization popup if not exempted
      _checkBatteryOptimization();
    });
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

  // Show battery optimization dialog from overview — reliable because widget is fully mounted
  Future<void> _checkBatteryOptimization() async {
    if (!mounted) return;
    try {
      final exempt = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (exempt) return;
    } catch (_) {
      return; // can't determine — skip silently
    }
    if (!mounted) return;
    final v = Theme.of(context).extension<VC>()!;

    final userAllowed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: v.accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.wifi_tethering_rounded, color: v.accent, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Keep Connection Alive',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Allow Tomato Manager to keep the SSH connection active when switching apps or the screen turns off?',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: v.accent.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: v.accent.withOpacity(0.2)),
            ),
            child: Column(children: [
              _BulletItem(icon: Icons.sync_rounded,       color: v.accent,        title: 'Connection stays active',      desc: 'SSH remains alive while app is in background'),
              const SizedBox(height: 8),
              _BulletItem(icon: Icons.notifications_active_rounded, color: v.accent, title: 'Router status notification', desc: 'Persistent notification while connected'),
              const SizedBox(height: 8),
              _BulletItem(icon: Icons.battery_4_bar_rounded, color: Colors.orange, title: 'Slightly higher battery usage', desc: 'Only active while connected to router'),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withOpacity(0.25)),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: Colors.orange, size: 15),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'An Android system dialog will appear next.',
                  style: TextStyle(fontSize: 11, color: Colors.orange, height: 1.4),
                ),
              ),
            ]),
          ),
        ]),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No thanks', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: v.accent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Allow', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (userAllowed == true) {
      // Fire the Android system battery optimization dialog directly
      try {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      } catch (_) {
        try { await FlutterForegroundTask.openIgnoreBatteryOptimizationSettings(); } catch (_) {}
      }
    }
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

// ── Battery optimization dialog bullet item ────────────────────────────────────
class _BulletItem extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   title, desc;
  const _BulletItem({required this.icon, required this.color, required this.title, required this.desc});
  @override Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, color: color, size: 16),
    const SizedBox(width: 8),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      Text(desc,  style: const TextStyle(fontSize: 11, color: Colors.white54, height: 1.3)),
    ])),
  ]);
}

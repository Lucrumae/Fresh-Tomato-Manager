import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import 'setup_screen.dart';
import 'overview_screen.dart';
import 'devices_screen.dart';
import 'network_screen.dart';
import 'system_screen.dart';
import 'terminal_screen.dart';

// ── Navigation structure ──────────────────────────────────────────────────────
// OVERVIEW  — dashboard: CPU/RAM/temp/bandwidth live bars + wifi toggle
// DEVICES   — connected nodes, block/unblock, rename, kick
// NETWORK   — port forward + QoS rules in one place
// SYSTEM    — logs + config backup/restore + settings
// TERMINAL  — SSH shell
// ─────────────────────────────────────────────────────────────────────────────

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});
  @override ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _tab = 0;
  bool _starting = true;

  final _tabs = const [
    _NavTab(icon: Icons.grid_view_rounded,        label: 'OVERVIEW'),
    _NavTab(icon: Icons.devices_rounded,           label: 'DEVICES'),
    _NavTab(icon: Icons.lan_rounded,               label: 'NETWORK'),
    _NavTab(icon: Icons.dns_rounded,               label: 'SYSTEM'),
    _NavTab(icon: Icons.terminal_rounded,          label: 'TERMINAL'),
  ];

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final cfg = ref.read(configProvider);
    if (cfg == null) {
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder:(_)=>const SetupScreen()));
      }
      return;
    }
    final ssh = ref.read(sshServiceProvider);
    try {
      await ssh.connect(cfg);
    } catch (_) {}
    _startPolling();
    if (mounted) setState(() => _starting = false);
  }

  void _startPolling() {
    ref.read(routerStatusProvider.notifier).startPolling();
    ref.read(devicesProvider.notifier).startPolling();
    ref.read(bandwidthProvider.notifier).startPolling();
    ref.read(logsProvider.notifier).startPolling();
    ref.read(qosProvider.notifier).startPolling();
    ref.read(portForwardProvider.notifier).startPolling();
  }

  @override
  Widget build(BuildContext context) {
    final v      = Theme.of(context).extension<VC>()!;
    final isDark = ref.watch(darkModeProvider);
    final accent = ref.watch(accentProvider);
    final theme  = AppTheme.build(isDark, accent);

    return Theme(data:theme, child:AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor:Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: isDark ? V.d0 : V.l0,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: v.bg,
        body: _starting
          ? Center(child:Column(mainAxisSize:MainAxisSize.min, children:[
              SizedBox(width:24, height:24,
                child:CircularProgressIndicator(strokeWidth:2, color:v.accent)),
              const SizedBox(height:16),
              Text('CONNECTING', style:GoogleFonts.outfit(color:v.mid, fontSize:11, fontWeight:FontWeight.w700, letterSpacing:2)),
            ]))
          : IndexedStack(index:_tab, children: const [
              OverviewScreen(),
              DevicesScreen(),
              NetworkScreen(),
              SystemScreen(),
              TerminalScreen(),
            ]),
        bottomNavigationBar: _BottomNav(
          tabs: _tabs, current: _tab,
          onTap: (i) => setState(() => _tab = i),
          accent: v.accent,
        ),
      ),
    ));
  }
}

class _NavTab { final IconData icon; final String label; const _NavTab({required this.icon, required this.label}); }

class _BottomNav extends StatelessWidget {
  final List<_NavTab> tabs; final int current;
  final ValueChanged<int> onTap; final Color accent;
  const _BottomNav({required this.tabs, required this.current, required this.onTap, required this.accent});

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Container(
      decoration: BoxDecoration(
        color: v.bg,
        border: Border(top:BorderSide(color:v.wire, width:0.5)),
      ),
      child: SafeArea(
        top:false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final sel = i == current;
              return Expanded(child:GestureDetector(
                behavior:HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds:200),
                  child: Column(
                    mainAxisAlignment:MainAxisAlignment.center,
                    children:[
                      Icon(tabs[i].icon, size:20,
                        color: sel ? accent : v.lo),
                      const SizedBox(height:3),
                      Text(tabs[i].label,
                        style:GoogleFonts.outfit(
                          fontSize:8.5, fontWeight:FontWeight.w700,
                          color: sel ? accent : v.lo,
                          letterSpacing:0.5)),
                      const SizedBox(height:2),
                      AnimatedContainer(
                        duration:const Duration(milliseconds:200),
                        width: sel ? 16 : 0, height: 2,
                        decoration:BoxDecoration(
                          color: sel ? accent : Colors.transparent,
                          borderRadius:BorderRadius.circular(1))),
                    ]),
                )));
            }),
          ),
        ),
      ),
    );
  }
}

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
import 'files_screen.dart';

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
    if (state == AppLifecycleState.resumed) _checkReconnect();
  }

  int _reconnectAttempts = 0;

  Future<void> _checkReconnect() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) {
      setState(() => _isReconnecting = true);
      final config = ref.read(configProvider);
      if (config != null) {
        final err = await ssh.connect(config);
        if (err == null && mounted) {
          _reconnectAttempts = 0;
          ref.read(routerStatusProvider.notifier).startPolling();
          ref.read(devicesProvider.notifier).startPolling();
          ref.read(bandwidthProvider.notifier).startPolling();
        } else if (mounted) {
          _reconnectAttempts++;
          // After 3 failed attempts, offer to go back to login
          if (_reconnectAttempts >= 3) {
            setState(() => _isReconnecting = false);
            _showReconnectFailedDialog();
            return;
          }
        }
      }
      if (mounted) setState(() => _isReconnecting = false);
    }
  }

  void _showReconnectFailedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Koneksi Terputus'),
        content: const Text('Tidak dapat terhubung kembali ke router. Kembali ke halaman login?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() { _isReconnecting = false; _reconnectAttempts = 0; });
            },
            child: const Text('Coba Lagi'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              Navigator.pop(context);
              ref.read(routerStatusProvider.notifier).stopPolling();
              ref.read(devicesProvider.notifier).stopPolling();
              ref.read(bandwidthProvider.notifier).stopPolling();
              await ref.read(sshServiceProvider).disconnect();
              await ref.read(configProvider.notifier).clear();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const SetupScreen()),
                  (_) => false,
                );
              }
            },
            child: const Text('Ke Halaman Login'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context);
    final c = Theme.of(context).extension<AppColors>()!;

    // 7 tabs now including Files
    final tabs = [
      (Icons.dashboard_rounded,           l.dashboard,  false),
      (Icons.devices_rounded,             l.devices,    false),
      (Icons.show_chart_rounded,          l.bandwidth,  false),
      (Icons.article_rounded,             l.logs,       false),
      (Icons.folder_rounded,              'Files',      false),
      (Icons.terminal_rounded,            l.terminal,   true),  // green
      (Icons.settings_rounded,            l.settings,   false),
    ];

    final screens = [
      const DashboardScreen(),
      const DevicesScreen(),
      const BandwidthScreen(),
      const LogsScreen(),
      const FilesScreen(),
      const _TerminalTab(),
      const SettingsScreen(),
    ];

    // Auto-focus terminal when tab selected (triggers keyboard)
    // Handled inside TerminalScreen itself via initState postFrameCallback

    return Scaffold(
      body: Column(children: [
        if (_isReconnecting)
          Material(
            color: AppTheme.warning.withOpacity(0.12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal:16, vertical:7),
              child: Row(children: [
                const SizedBox(width:14, height:14,
                  child: CircularProgressIndicator(
                    color: AppTheme.warning, strokeWidth:1.5)),
                const SizedBox(width:10),
                Text('Reconnecting...',
                  style: TextStyle(color:AppTheme.warning,
                    fontSize:13, fontWeight:FontWeight.w500)),
              ]),
            ),
          ),
        Expanded(
          child: IndexedStack(index: _index, children: screens),
        ),
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: List.generate(tabs.length, (i) {
                final sel = i == _index;
                final isGreen = tabs[i].$3;
                final color = sel
                  ? (isGreen ? AppTheme.terminal : AppTheme.primary)
                  : c.textMuted;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _index = i),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(tabs[i].$1, size: 20, color: color),
                        const SizedBox(height: 2),
                        Text(tabs[i].$2,
                          style: TextStyle(
                            fontSize: 9,
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
    backgroundColor: Color(0xFF0B0F1A),
    body: SafeArea(child: TerminalScreen()),
  );
}

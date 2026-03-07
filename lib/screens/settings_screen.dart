import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import 'setup_screen.dart';
import 'qos_screen.dart';
import 'port_forward_screen.dart';
import 'vpn_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Settings', style: Theme.of(context).textTheme.titleLarge),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Connection info card
          AppCard(
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.terminal_rounded, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(config?.host ?? '-',
                    style: Theme.of(context).textTheme.titleSmall),
                  Text('${config?.username ?? 'root'} · SSH :${config?.sshPort ?? 22}',
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              TextButton(
                onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SetupScreen())),
                child: const Text('Change'),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          _SectionLabel('Network'),
          const SizedBox(height: 8),
          _Tile(
            icon: Icons.vpn_lock_rounded, color: AppTheme.primary,
            title: 'VPN', subtitle: 'Akses router dari luar jaringan',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VpnScreen())),
          ),
          const SizedBox(height: 8),
          _Tile(
            icon: Icons.speed_rounded, color: AppTheme.secondary,
            title: 'QoS Rules', subtitle: 'Bandwidth limits per device',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QosScreen())),
          ),
          const SizedBox(height: 8),
          _Tile(
            icon: Icons.lan_rounded, color: AppTheme.success,
            title: 'Port Forwarding', subtitle: 'Kelola open ports',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PortForwardScreen())),
          ),

          const SizedBox(height: 20),
          _SectionLabel('Router'),
          const SizedBox(height: 8),
          _Tile(
            icon: Icons.restart_alt_rounded, color: AppTheme.warning,
            title: 'Reboot Router', subtitle: 'Restart router via SSH',
            onTap: () => _confirmReboot(context, ref),
          ),

          const SizedBox(height: 20),
          _SectionLabel('App'),
          const SizedBox(height: 8),
          _Tile(
            icon: Icons.logout_rounded, color: AppTheme.danger,
            title: 'Disconnect', subtitle: 'Hapus konfigurasi router',
            onTap: () => _confirmDisconnect(context, ref),
          ),
          const SizedBox(height: 32),
          Center(child: Text('Tomato Manager v1.0.0',
            style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _confirmReboot(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reboot Router?'),
        content: const Text('Router akan restart. Koneksi akan terputus sekitar 30-60 detik.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reboot'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final ssh = ref.read(sshServiceProvider);
      await ssh.reboot();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perintah reboot dikirim via SSH')),
        );
      }
    }
  }

  void _confirmDisconnect(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disconnect?'),
        content: const Text('Hapus semua konfigurasi router dari app?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(routerStatusProvider.notifier).stopPolling();
      ref.read(devicesProvider.notifier).stopPolling();
      ref.read(bandwidthProvider.notifier).stopPolling();
      final ssh = ref.read(sshServiceProvider);
      await ssh.disconnect();
      await ref.read(configProvider.notifier).clear();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SetupScreen()), (_) => false,
        );
      }
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) => Text(label,
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: AppTheme.textMuted, fontWeight: FontWeight.w600, letterSpacing: 0.5,
    ));
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.color, required this.title,
    required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      )),
      const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
    ]),
  );
}

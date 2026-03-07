import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import 'setup_screen.dart';
import 'qos_screen.dart';
import 'port_forward_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    final isDark = ref.watch(darkModeProvider);
    final c = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      appBar: AppBar(
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
                  color: AppTheme.primaryLight.withOpacity(c.isDark ? 0.15 : 1),
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
                child: const Text('Ubah'),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          _sectionLabel(context, 'Tampilan'),
          const SizedBox(height: 8),
          AppCard(
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.dark_mode_rounded, color: AppTheme.secondary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dark Mode', style: Theme.of(context).textTheme.titleSmall),
                  Text(isDark ? 'Aktif' : 'Nonaktif',
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              Switch(
                value: isDark,
                activeColor: AppTheme.primary,
                onChanged: (_) => ref.read(darkModeProvider.notifier).toggle(),
              ),
            ]),
          ),

          const SizedBox(height: 20),
          _sectionLabel(context, 'Jaringan'),
          const SizedBox(height: 8),
          _tile(context,
            icon: Icons.speed_rounded, color: AppTheme.secondary,
            title: 'QoS Rules', subtitle: 'Bandwidth limit per device',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QosScreen())),
          ),
          const SizedBox(height: 8),
          _tile(context,
            icon: Icons.lan_rounded, color: AppTheme.success,
            title: 'Port Forwarding', subtitle: 'Kelola open ports',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PortForwardScreen())),
          ),

          const SizedBox(height: 20),
          _sectionLabel(context, 'Router'),
          const SizedBox(height: 8),
          _tile(context,
            icon: Icons.restart_alt_rounded, color: AppTheme.warning,
            title: 'Reboot Router', subtitle: 'Restart router via SSH',
            onTap: () => _confirmReboot(context, ref),
          ),

          const SizedBox(height: 20),
          _sectionLabel(context, 'App'),
          const SizedBox(height: 8),
          _tile(context,
            icon: Icons.logout_rounded, color: AppTheme.danger,
            title: 'Disconnect', subtitle: 'Hapus konfigurasi dan logout',
            onTap: () => _confirmDisconnect(context, ref),
          ),

          const SizedBox(height: 32),
          Center(child: Text('Tomato Manager v1.0.0',
            style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) =>
    Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).extension<AppColors>()!.textMuted,
      fontWeight: FontWeight.w600, letterSpacing: 0.5,
    ));

  Widget _tile(BuildContext context, {
    required IconData icon, required Color color,
    required String title, required String subtitle,
    required VoidCallback onTap,
  }) => AppCard(
    onTap: onTap,
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
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
      Icon(Icons.chevron_right_rounded,
        color: Theme.of(context).extension<AppColors>()!.textMuted),
    ]),
  );

  void _confirmReboot(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reboot Router?'),
        content: const Text('Router akan restart sekitar 30-60 detik.'),
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
      await ref.read(sshServiceProvider).reboot();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perintah reboot dikirim')));
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
      await ref.read(sshServiceProvider).disconnect();
      await ref.read(configProvider.notifier).clear();
      if (context.mounted) Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SetupScreen()), (_) => false,
      );
    }
  }
}

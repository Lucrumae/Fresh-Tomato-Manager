import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(routerStatusProvider);
    final bandwidth = ref.watch(bandwidthProvider);
    final devices = ref.watch(devicesProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            floating: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dashboard', style: Theme.of(context).textTheme.titleLarge),
                Text(status.routerModel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: status.isOnline
                    ? AppTheme.success.withOpacity(0.1)
                    : AppTheme.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                        color: status.isOnline ? AppTheme.success : AppTheme.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      status.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: status.isOnline ? AppTheme.success : AppTheme.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(delegate: SliverChildListDelegate([

              // ── Status cards row ─────────────────────────────────────────
              Row(children: [
                Expanded(child: _StatCard(
                  label: 'CPU',
                  value: status.cpuUsage,
                  percent: status.cpuPercent / 100,
                  color: _percentColor(status.cpuPercent),
                  icon: Icons.memory_rounded,
                ).animate().fadeIn().slideY(begin: 0.1)),
                const SizedBox(width: 12),
                Expanded(child: _StatCard(
                  label: 'RAM',
                  value: status.ramUsage,
                  sublabel: '/ ${status.ramTotal}',
                  percent: status.ramPercent / 100,
                  color: _percentColor(status.ramPercent),
                  icon: Icons.storage_rounded,
                ).animate(delay: 50.ms).fadeIn().slideY(begin: 0.1)),
              ]),
              const SizedBox(height: 12),

              // ── Bandwidth quick view ─────────────────────────────────────
              _BandwidthCard(bandwidth: bandwidth)
                .animate(delay: 100.ms).fadeIn().slideY(begin: 0.1),
              const SizedBox(height: 12),

              // ── Network info ─────────────────────────────────────────────
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Network', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 14),
                    _InfoRow(icon: Icons.language_rounded, label: 'WAN IP', value: status.wanIp),
                    const SizedBox(height: 10),
                    _InfoRow(icon: Icons.home_rounded, label: 'LAN IP', value: status.lanIp),
                    const SizedBox(height: 10),
                    _InfoRow(icon: Icons.wifi_rounded, label: 'WiFi SSID', value: status.wifiSsid),
                    const SizedBox(height: 10),
                    _InfoRow(icon: Icons.schedule_rounded, label: 'Uptime', value: status.uptime),
                  ],
                ),
              ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.1),
              const SizedBox(height: 12),

              // ── Quick stats ──────────────────────────────────────────────
              Row(children: [
                Expanded(child: _QuickStat(
                  icon: Icons.devices_rounded,
                  value: '${devices.length}',
                  label: 'Devices',
                  color: AppTheme.primary,
                ).animate(delay: 200.ms).fadeIn()),
                const SizedBox(width: 12),
                Expanded(child: _QuickStat(
                  icon: Icons.block_rounded,
                  value: '${devices.where((d) => d.isBlocked).length}',
                  label: 'Blocked',
                  color: AppTheme.danger,
                ).animate(delay: 250.ms).fadeIn()),
                const SizedBox(width: 12),
                Expanded(child: _QuickStat(
                  icon: Icons.wifi_rounded,
                  value: '${devices.where((d) => d.isWireless).length}',
                  label: 'WiFi',
                  color: AppTheme.success,
                ).animate(delay: 300.ms).fadeIn()),
              ]),
              const SizedBox(height: 12),

              // ── Firmware ─────────────────────────────────────────────────
              AppCard(
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.system_update_rounded, color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Firmware', style: Theme.of(context).textTheme.titleSmall),
                        Text(status.firmware, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    )),
                  ],
                ),
              ).animate(delay: 350.ms).fadeIn(),

              const SizedBox(height: 80),
            ])),
          ),
        ],
      ),
    );
  }

  Color _percentColor(double p) {
    if (p > 80) return AppTheme.danger;
    if (p > 60) return AppTheme.warning;
    return AppTheme.success;
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final String? sublabel;
  final double percent;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label, required this.value, this.sublabel,
    required this.percent, required this.color, required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: Theme.of(context).extension<AppColors>()!.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              if (sublabel != null)
                Text(sublabel!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent.clamp(0, 1),
              backgroundColor: AppTheme.border,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Text('${(percent * 100).toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _BandwidthCard extends StatelessWidget {
  final BandwidthStats bandwidth;
  const _BandwidthCard({required this.bandwidth});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Bandwidth', style: Theme.of(context).textTheme.titleSmall),
              Text('Live', style: TextStyle(
                fontSize: 11, color: AppTheme.success, fontWeight: FontWeight.w600,
              )),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _BwStat(
              label: '↓ Download',
              value: _fmt(bandwidth.currentRx),
              color: AppTheme.primary,
            )),
            Expanded(child: _BwStat(
              label: '↑ Upload',
              value: _fmt(bandwidth.currentTx),
              color: AppTheme.secondary,
            )),
          ]),
        ],
      ),
    );
  }

  String _fmt(double kbps) {
    if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(1)} Mbps';
    return '${kbps.toStringAsFixed(0)} Kbps';
  }
}

class _BwStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _BwStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w700, color: color,
      )),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: Theme.of(context).extension<AppColors>()!.textMuted),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      Text(value, style: Theme.of(context).textTheme.labelLarge),
    ],
  );
}

class _QuickStat extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color color;
  const _QuickStat({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class BandwidthScreen extends ConsumerWidget {
  const BandwidthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bw = ref.watch(bandwidthProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Bandwidth', style: Theme.of(context).textTheme.titleLarge),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(
                color: AppTheme.success, shape: BoxShape.circle,
              )),
              const SizedBox(width: 5),
              const Text('Live', style: TextStyle(fontSize: 12, color: AppTheme.success, fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Current speed cards
          Row(children: [
            Expanded(child: _SpeedCard(
              label: 'Download', icon: Icons.arrow_downward_rounded,
              value: _fmt(bw.currentRx), color: AppTheme.primary,
              peak: 'Peak: ${_fmt(bw.peakRx)}',
            )),
            const SizedBox(width: 12),
            Expanded(child: _SpeedCard(
              label: 'Upload', icon: Icons.arrow_upward_rounded,
              value: _fmt(bw.currentTx), color: AppTheme.secondary,
              peak: 'Peak: ${_fmt(bw.peakTx)}',
            )),
          ]),
          const SizedBox(height: 16),

          // Realtime chart
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Real-Time', style: Theme.of(context).textTheme.titleSmall),
                    Row(children: [
                      _Legend(color: AppTheme.primary, label: 'Down'),
                      const SizedBox(width: 12),
                      _Legend(color: AppTheme.secondary, label: 'Up'),
                    ]),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(height: 180, child: _RealtimeChart(bw: bw)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Total transfer
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Session Total', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _TotalStat(
                    icon: Icons.arrow_downward_rounded,
                    label: 'Total Downloaded',
                    value: _fmtMB(bw.totalRxMB),
                    color: AppTheme.primary,
                  )),
                  Expanded(child: _TotalStat(
                    icon: Icons.arrow_upward_rounded,
                    label: 'Total Uploaded',
                    value: _fmtMB(bw.totalTxMB),
                    color: AppTheme.secondary,
                  )),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double kbps) {
    if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(2)} Mbps';
    return '${kbps.toStringAsFixed(0)} Kbps';
  }

  String _fmtMB(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }
}

class _RealtimeChart extends StatelessWidget {
  final BandwidthStats bw;
  const _RealtimeChart({required this.bw});

  @override
  Widget build(BuildContext context) {
    if (bw.points.isEmpty) {
      return const Center(child: Text('Waiting for data...', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textMuted)));
    }

    final maxY = [
      bw.peakRx, bw.peakTx, 100.0,
    ].reduce((a, b) => a > b ? a : b) * 1.2;

    final rxSpots = bw.points.asMap().entries.map((e) =>
      FlSpot(e.key.toDouble(), e.value.rxKbps)
    ).toList();

    final txSpots = bw.points.asMap().entries.map((e) =>
      FlSpot(e.key.toDouble(), e.value.txKbps)
    ).toList();

    return LineChart(LineChartData(
      minY: 0,
      maxY: maxY,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
          color: Theme.of(context).extension<AppColors>()!.border,
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 48,
          getTitlesWidget: (v, _) => Text(
            v >= 1024 ? '${(v/1024).toStringAsFixed(1)}M' : '${v.toInt()}K',
            style: const TextStyle(fontSize: 10, color: Theme.of(context).extension<AppColors>()!.textMuted),
          ),
        )),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
          spots: rxSpots,
          isCurved: true,
          color: AppTheme.primary,
          barWidth: 2,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: AppTheme.primary.withOpacity(0.08),
          ),
        ),
        LineChartBarData(
          spots: txSpots,
          isCurved: true,
          color: AppTheme.secondary,
          barWidth: 2,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: AppTheme.secondary.withOpacity(0.08),
          ),
        ),
      ],
    ));
  }
}

class _SpeedCard extends StatelessWidget {
  final String label, value, peak;
  final IconData icon;
  final Color color;
  const _SpeedCard({required this.label, required this.value, required this.peak, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 4),
        Text(peak, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 10, height: 3, decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(2),
    )),
    const SizedBox(width: 5),
    Text(label, style: const TextStyle(fontSize: 11, color: Theme.of(context).extension<AppColors>()!.textSecondary)),
  ]);
}

class _TotalStat extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _TotalStat({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: color),
    const SizedBox(width: 8),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
    ]),
  ]);
}

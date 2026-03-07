import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/ssh_service.dart';
import '../models/models.dart';

// ── Traffic + QoS history provider ───────────────────────────────────────────
final trafficHistoryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final ssh = ref.read(sshServiceProvider);
  if (!ssh.isConnected) return {};
  return ssh.getTrafficHistory();
});

final qosBasicProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final ssh = ref.read(sshServiceProvider);
  if (!ssh.isConnected) return {};
  try {
    final raw = await ssh.run('''
echo "=Q="
nvram get qos_enable
nvram get qos_type
nvram get qos_default
nvram get qos_obw
nvram get qos_ibw
''');
    final lines = raw.split('\n').where((l) => l.trim().isNotEmpty && !l.startsWith('=')).toList();
    return {
      'enable': lines.length > 0 ? lines[0].trim() : '0',
      'type':   lines.length > 1 ? lines[1].trim() : '0',
      'default':lines.length > 2 ? lines[2].trim() : '-',
      'obw':    lines.length > 3 ? lines[3].trim() : '-',
      'ibw':    lines.length > 4 ? lines[4].trim() : '-',
    };
  } catch (_) { return {}; }
});

final qosClassifyProvider = FutureProvider.autoDispose<List<Map<String, String>>>((ref) async {
  final ssh = ref.read(sshServiceProvider);
  if (!ssh.isConnected) return [];
  try {
    final raw = await ssh.run('nvram get qos_orules');
    final rules = <Map<String, String>>[];
    for (final chunk in raw.trim().split('>')) {
      final parts = chunk.split('<');
      if (parts.length >= 7) {
        rules.add({
          'prio': parts[0].trim(), 'src': parts[1], 'dst': parts[2],
          'proto': parts[3], 'srcport': parts[4], 'dstport': parts[5],
          'desc': parts.length > 6 ? parts[6] : '',
        });
      }
    }
    return rules;
  } catch (_) { return []; }
});

final qosConnProvider = FutureProvider.autoDispose<List<Map<String, String>>>((ref) async {
  final ssh = ref.read(sshServiceProvider);
  if (!ssh.isConnected) return [];
  try {
    final raw = await ssh.run(
      'cat /proc/net/nf_conntrack 2>/dev/null | head -80 || '
      'cat /proc/net/ip_conntrack 2>/dev/null | head -80 || echo ""');
    final result = <Map<String, String>>[];
    for (final line in raw.split('\n')) {
      if (line.trim().isEmpty) continue;
      final proto = RegExp(r'^(\w+)').firstMatch(line)?.group(1) ?? '?';
      final srcs = RegExp(r'src=(\S+)').allMatches(line).toList();
      final dsts = RegExp(r'dst=(\S+)').allMatches(line).toList();
      final sports = RegExp(r'sport=(\d+)').allMatches(line).toList();
      final dports = RegExp(r'dport=(\d+)').allMatches(line).toList();
      result.add({
        'proto': proto,
        'src': srcs.isNotEmpty ? srcs[0].group(1)! : '-',
        'dst': dsts.isNotEmpty ? dsts[0].group(1)! : '-',
        'sport': sports.isNotEmpty ? sports[0].group(1)! : '-',
        'dport': dports.isNotEmpty ? dports[0].group(1)! : '-',
      });
    }
    return result;
  } catch (_) { return []; }
});

// ── Main Screen ───────────────────────────────────────────────────────────────
class BandwidthScreen extends ConsumerStatefulWidget {
  const BandwidthScreen({super.key});
  @override
  ConsumerState<BandwidthScreen> createState() => _BandwidthScreenState();
}

class _BandwidthScreenState extends ConsumerState<BandwidthScreen> {
  bool _showQos = false;

  @override
  Widget build(BuildContext context) {
    final bw = ref.watch(bandwidthProvider);
    final history = ref.watch(trafficHistoryProvider);
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        // Title = toggle tabs: Bandwidth | QoS
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: () => setState(() => _showQos = false),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: !_showQos
                ? Theme.of(context).textTheme.titleLarge!
                : Theme.of(context).textTheme.titleLarge!.copyWith(
                    color: c.textMuted, fontWeight: FontWeight.w400),
              child: const Text('Bandwidth'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(width: 1, height: 18, color: c.border),
          ),
          GestureDetector(
            onTap: () => setState(() => _showQos = true),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: _showQos
                ? Theme.of(context).textTheme.titleLarge!.copyWith(color: accent)
                : Theme.of(context).textTheme.titleLarge!.copyWith(
                    color: c.textMuted, fontWeight: FontWeight.w400),
              child: const Text('QoS'),
            ),
          ),
        ]),
        actions: [
          if (!_showQos) Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(children: [
              Container(width: 7, height: 7, decoration: const BoxDecoration(
                color: AppTheme.success, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              const Text('Live', style: TextStyle(fontSize: 11,
                color: AppTheme.success, fontWeight: FontWeight.w600)),
            ]),
          ),
          if (_showQos) IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(qosBasicProvider);
              ref.invalidate(qosClassifyProvider);
              ref.invalidate(qosConnProvider);
            },
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _showQos
          ? _QosFullPage(key: const ValueKey('qos'))
          : _BandwidthBody(key: const ValueKey('bw'), bw: bw, history: history),
      ),
    );
  }
}

// ── Bandwidth Body ────────────────────────────────────────────────────────────
class _BandwidthBody extends StatelessWidget {
  final BandwidthStats bw;
  final AsyncValue<Map<String, dynamic>> history;
  const _BandwidthBody({super.key, required this.bw, required this.history});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c = Theme.of(context).extension<AppColors>()!;
    return ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ── Speed cards ─────────────────────────────────────────────────
          Row(children: [
            Expanded(child: _SpeedCard(
              label: 'Download', icon: Icons.arrow_downward_rounded,
              value: _fmt(bw.currentRx), color: accent,
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

          // ── Real-time chart ──────────────────────────────────────────────
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Real-Time', style: Theme.of(context).textTheme.titleSmall),
                Row(children: [
                  _Legend(color: accent, label: 'Down'),
                  const SizedBox(width: 12),
                  _Legend(color: AppTheme.secondary, label: 'Up'),
                ]),
              ]),
              const SizedBox(height: 16),
              SizedBox(height: 180, child: _RealtimeChart(bw: bw)),
            ]),
          ),
          const SizedBox(height: 16),

          // ── Session total ────────────────────────────────────────────────
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Session Total', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _TotalStat(
                  icon: Icons.arrow_downward_rounded, label: 'Downloaded',
                  value: _fmtMB(bw.totalRxMB), color: accent)),
                Expanded(child: _TotalStat(
                  icon: Icons.arrow_upward_rounded, label: 'Uploaded',
                  value: _fmtMB(bw.totalTxMB), color: AppTheme.secondary)),
              ]),
            ]),
          ),
          const SizedBox(height: 24),

          // ── Daily / Weekly / Monthly usage ──────────────────────────────
          _SectionHeader(title: 'Usage History', icon: Icons.bar_chart_rounded, color: accent),
          const SizedBox(height: 12),

          history.when(
            loading: () => const Center(
              child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
            error: (e, _) => _EmptyCard(message: 'Could not load history: $e'),
            data: (data) {
              final daily  = (data['daily']   as List?) ?? [];
              final monthly = (data['monthly'] as List?) ?? [];
              if (daily.isEmpty && monthly.isEmpty) {
                return _EmptyCard(message: 'No traffic history found.\nEnsure "Traffic Monitoring" is enabled in FreshTomato.');
              }
              return _UsageHistoryCard(daily: daily, monthly: monthly);
            },
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionHeader({required this.title, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: color),
    const SizedBox(width: 8),
    Text(title, style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(width: 8),
    Expanded(child: Divider(color: Theme.of(context).extension<AppColors>()!.border)),
  ]);
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard({required this.message});
  @override
  Widget build(BuildContext context) => AppCard(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(child: Text(message, textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textMuted, fontSize: 13))),
    ),
  );
}

// ── Usage History Card with Daily / Weekly / Monthly tabs ────────────────────
class _UsageHistoryCard extends StatefulWidget {
  final List daily, monthly;
  const _UsageHistoryCard({required this.daily, required this.monthly});
  @override
  State<_UsageHistoryCard> createState() => _UsageHistoryCardState();
}

class _UsageHistoryCardState extends State<_UsageHistoryCard> {
  int _tab = 0; // 0=daily, 1=weekly, 2=monthly

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c = Theme.of(context).extension<AppColors>()!;

    final weekly = widget.daily.length > 7
        ? widget.daily.sublist(widget.daily.length - 7) : widget.daily;
    final data = _tab == 0 ? widget.daily : _tab == 1 ? weekly : widget.monthly;
    final isMonthly = _tab == 2;

    return AppCard(
      padding: const EdgeInsets.all(0),
      child: Column(children: [
        // Tab selector
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            for (int i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: _tab == i ? accent.withOpacity(0.15) : c.cardBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _tab == i ? accent : c.border,
                      width: _tab == i ? 1.5 : 1),
                  ),
                  child: Text(['Daily', 'Weekly', 'Monthly'][i],
                    style: TextStyle(fontSize: 12,
                      fontWeight: _tab == i ? FontWeight.w600 : FontWeight.normal,
                      color: _tab == i ? accent : c.textSecondary)),
                ),
              ),
            ],
          ]),
        ),

        if (data.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('No data', style: TextStyle(color: c.textMuted)),
          )
        else ...[
          // Bar chart
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: SizedBox(height: 140, child: _HistoryBarChart(
              data: data, isMonthly: isMonthly, accent: accent, c: c)),
          ),
          const SizedBox(height: 8),

          // Summary totals
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Expanded(child: _MiniTotal(
                icon: Icons.arrow_downward_rounded, label: 'Total Down', color: accent,
                value: _fmtGB(data.fold(0.0, (s, d) => s + (d['rx'] as num).toDouble())))),
              Expanded(child: _MiniTotal(
                icon: Icons.arrow_upward_rounded, label: 'Total Up', color: AppTheme.secondary,
                value: _fmtGB(data.fold(0.0, (s, d) => s + (d['tx'] as num).toDouble())))),
            ]),
          ),

          // Row list
          const Divider(height: 1),
          ...data.asMap().entries.map((e) {
            final d = e.value;
            final rx = (d['rx'] as num).toDouble();
            final tx = (d['tx'] as num).toDouble();
            final maxRx = data.fold(0.0, (m, x) => (x['rx'] as num).toDouble() > m ? (x['rx'] as num).toDouble() : m);
            final maxTx = data.fold(0.0, (m, x) => (x['tx'] as num).toDouble() > m ? (x['tx'] as num).toDouble() : m);
            final label = isMonthly ? (d['month'] as String) : 'Day ${(d['day'] as num).toInt()}';
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                SizedBox(width: 56,
                  child: Text(label, style: TextStyle(fontSize: 11, color: c.textMuted))),
                Expanded(child: Column(children: [
                  _MiniBar(value: rx, max: maxRx, color: accent),
                  const SizedBox(height: 3),
                  _MiniBar(value: tx, max: maxTx, color: AppTheme.secondary),
                ])),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_fmtGB(rx), style: TextStyle(fontSize: 10, color: accent)),
                  Text(_fmtGB(tx), style: TextStyle(fontSize: 10, color: AppTheme.secondary)),
                ]),
              ]),
            );
          }).toList(),
          const SizedBox(height: 12),
        ],
      ]),
    );
  }
}

class _MiniBar extends StatelessWidget {
  final double value, max;
  final Color color;
  const _MiniBar({required this.value, required this.max, required this.color});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(2),
    child: LinearProgressIndicator(
      value: max > 0 ? (value / max).clamp(0.0, 1.0) : 0,
      color: color, backgroundColor: color.withOpacity(0.12), minHeight: 5,
    ),
  );
}

class _MiniTotal extends StatelessWidget {
  final IconData icon; final String label, value; final Color color;
  const _MiniTotal({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 14, color: color), const SizedBox(width: 4),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).extension<AppColors>()!.textMuted)),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
    ]),
  ]);
}

class _HistoryBarChart extends StatelessWidget {
  final List data;
  final bool isMonthly;
  final Color accent;
  final AppColors c;
  const _HistoryBarChart({required this.data, required this.isMonthly, required this.accent, required this.c});

  @override
  Widget build(BuildContext context) {
    final maxY = data.fold<double>(1, (m, d) {
      final rx = (d['rx'] as num).toDouble();
      final tx = (d['tx'] as num).toDouble();
      return [m, rx, tx].reduce((a, b) => a > b ? a : b);
    }) * 1.2;

    final groups = data.asMap().entries.map((e) {
      final d = e.value;
      final w = data.length <= 7 ? 14.0 : data.length <= 14 ? 8.0 : 5.0;
      return BarChartGroupData(x: e.key, barRods: [
        BarChartRodData(toY: (d['rx'] as num).toDouble(), color: accent, width: w,
          borderRadius: BorderRadius.circular(2)),
        BarChartRodData(toY: (d['tx'] as num).toDouble(), color: AppTheme.secondary, width: w,
          borderRadius: BorderRadius.circular(2)),
      ], barsSpace: 2);
    }).toList();

    return BarChart(BarChartData(
      maxY: maxY,
      gridData: FlGridData(drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(color: c.border, strokeWidth: 0.8)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 18,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (isMonthly) {
              final m = i < data.length ? (data[i]['month'] as String) : '';
              return Text(m.length >= 7 ? m.substring(5) : m,
                style: TextStyle(fontSize: 9, color: c.textMuted));
            }
            if (data.length <= 7) {
              const names = ['M','T','W','T','F','S','S'];
              return Text(i < names.length ? names[i] : '',
                style: TextStyle(fontSize: 9, color: c.textMuted));
            }
            final day = i < data.length ? (data[i]['day'] as num).toInt() : 0;
            return Text(day % 5 == 0 ? '$day' : '',
              style: TextStyle(fontSize: 9, color: c.textMuted));
          },
        )),
        leftTitles: AxisTitles(sideTitles: SideTitles(
          showTitles: true, reservedSize: 40,
          getTitlesWidget: (v, _) => Text(_fmtGB(v),
            style: TextStyle(fontSize: 8, color: c.textMuted)))),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      barGroups: groups,
      barTouchData: BarTouchData(enabled: false),
    ));
  }
}

// ── QoS Section ───────────────────────────────────────────────────────────────
class _QosFullPage extends ConsumerStatefulWidget {
  const _QosFullPage({super.key});
  @override
  ConsumerState<_QosFullPage> createState() => _QosFullPageState();
}

class _QosFullPageState extends ConsumerState<_QosFullPage> {
  int _qosTab = 0;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c = Theme.of(context).extension<AppColors>()!;

    return Column(children: [
      // Sub-tab bar
      Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(children: [
          for (int i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() => _qosTab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _qosTab == i ? accent.withOpacity(0.15) : c.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _qosTab == i ? accent : c.border,
                    width: _qosTab == i ? 1.5 : 1),
                ),
                child: Text(['Basic', 'Classification', 'Connections'][i],
                  style: TextStyle(fontSize: 12,
                    fontWeight: _qosTab == i ? FontWeight.w600 : FontWeight.normal,
                    color: _qosTab == i ? accent : c.textSecondary)),
              ),
            ),
          ],
        ]),
      ),
      Divider(height: 1, color: c.border),
      // Full remaining height for tab content
      Expanded(child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _qosTab == 0
          ? _QosBasicTab(key: const ValueKey(0))
          : _qosTab == 1
            ? _QosClassifyTab(key: const ValueKey(1))
            : _QosConnectionsTab(key: const ValueKey(2)),
      )),
    ]);
  }
}

class _QosBasicTab extends ConsumerWidget {
  const _QosBasicTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basic = ref.watch(qosBasicProvider);
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c = Theme.of(context).extension<AppColors>()!;
    final modeMap = {'0':'HTB (classic)','1':'CAKE AQM','2':'HFSC'};

    return basic.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Error: $e')),
      data: (d) {
        final enabled = (d['enable'] ?? '0') == '1';
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _QRow(label: 'QoS Enabled',
              value: enabled ? 'Enabled' : 'Disabled',
              valueColor: enabled ? AppTheme.success : AppTheme.danger),
            _QRow(label: 'Mode', value: modeMap[d['type'] ?? ''] ?? 'Unknown'),
            _QRow(label: 'Default Class', value: d['default'] ?? '-'),
            _QRow(label: 'Upload Limit', value: '${d['obw'] ?? '-'} kbit/s', valueColor: accent),
            _QRow(label: 'Download Limit', value: '${d['ibw'] ?? '-'} kbit/s', valueColor: accent),
          ]),
        );
      },
    );
  }
}

class _QosClassifyTab extends ConsumerWidget {
  const _QosClassifyTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(qosClassifyProvider);
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c = Theme.of(context).extension<AppColors>()!;
    final prioColors = {
      '1': AppTheme.danger, '2': const Color(0xFFFF8C00),
      '3': const Color(0xFFFFD700), '4': AppTheme.success,
      '5': accent, '6': c.textSecondary,
    };

    return rules.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) return Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No QoS rules configured', style: TextStyle(color: c.textMuted), textAlign: TextAlign.center));
        return Column(
          children: list.map<Widget>((r) {
            final prio = r['prio'] ?? '5';
            final color = prioColors[prio] ?? accent;
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text('P$prio',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color))),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['desc']!.isNotEmpty ? r['desc']! : 'Rule',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary)),
                  Text('${r['proto']} · port: ${r['dstport']!.isNotEmpty ? r['dstport'] : 'any'}',
                    style: TextStyle(fontSize: 11, color: c.textMuted)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text('P$prio', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                ),
              ]),
            );
          }).followedBy([const SizedBox(height: 12)]).toList(),
        );
      },
    );
  }
}

class _QosConnectionsTab extends ConsumerWidget {
  const _QosConnectionsTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conns = ref.watch(qosConnProvider);
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c = Theme.of(context).extension<AppColors>()!;

    return conns.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) return Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No active connections', style: TextStyle(color: c.textMuted), textAlign: TextAlign.center));
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(children: [
                SizedBox(width: 40, child: Text('Proto', style: TextStyle(fontSize: 10, color: c.textMuted, fontWeight: FontWeight.w600))),
                Expanded(child: Text('Source', style: TextStyle(fontSize: 10, color: c.textMuted, fontWeight: FontWeight.w600))),
                Expanded(child: Text('Destination', style: TextStyle(fontSize: 10, color: c.textMuted, fontWeight: FontWeight.w600))),
              ]),
            ),
            ...list.take(30).map((conn) {
              final isTcp = conn['proto'] == 'tcp';
              final color = isTcp ? accent : AppTheme.secondary;
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 5, 12, 0),
                child: Row(children: [
                  SizedBox(width: 40, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                    child: Text(conn['proto']!.toUpperCase(),
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color), textAlign: TextAlign.center),
                  )),
                  Expanded(child: Text('${conn['src']}:${conn['sport']}',
                    style: TextStyle(fontSize: 10, color: c.textPrimary), overflow: TextOverflow.ellipsis)),
                  Expanded(child: Text('${conn['dst']}:${conn['dport']}',
                    style: TextStyle(fontSize: 10, color: c.textSecondary), overflow: TextOverflow.ellipsis)),
                ]),
              );
            }).toList(),
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}

class _QRow extends StatelessWidget {
  final String label, value; final Color? valueColor;
  const _QRow({required this.label, required this.value, this.valueColor});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 13, color: c.textSecondary)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: valueColor ?? c.textPrimary)),
      ]),
    );
  }
}

// ── Shared chart widgets ──────────────────────────────────────────────────────
class _RealtimeChart extends StatelessWidget {
  final BandwidthStats bw;
  const _RealtimeChart({required this.bw});
  @override
  Widget build(BuildContext context) {
    if (bw.points.isEmpty) return Center(child: Text('Waiting for data...',
      style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textMuted)));
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final maxY = [bw.peakRx, bw.peakTx, 100.0].reduce((a, b) => a > b ? a : b) * 1.2;
    final rxSpots = bw.points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.rxKbps)).toList();
    final txSpots = bw.points.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.txKbps)).toList();
    return LineChart(LineChartData(
      minY: 0, maxY: maxY,
      gridData: FlGridData(drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(color: Theme.of(context).extension<AppColors>()!.border, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 48,
          getTitlesWidget: (v, _) => Text(v >= 1024 ? '${(v/1024).toStringAsFixed(1)}M' : '${v.toInt()}K',
            style: TextStyle(fontSize: 10, color: Theme.of(context).extension<AppColors>()!.textMuted)))),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(spots: rxSpots, isCurved: true, color: accent, barWidth: 2,
          dotData: FlDotData(show: false), belowBarData: BarAreaData(show: true, color: accent.withOpacity(0.08))),
        LineChartBarData(spots: txSpots, isCurved: true, color: AppTheme.secondary, barWidth: 2,
          dotData: FlDotData(show: false), belowBarData: BarAreaData(show: true, color: AppTheme.secondary.withOpacity(0.08))),
      ],
    ));
  }
}

class _SpeedCard extends StatelessWidget {
  final String label, value, peak; final IconData icon; final Color color;
  const _SpeedCard({required this.label, required this.value, required this.peak, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall)]),
      const SizedBox(height: 8),
      Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(height: 4),
      Text(peak, style: Theme.of(context).textTheme.bodySmall),
    ]),
  );
}

class _Legend extends StatelessWidget {
  final Color color; final String label;
  const _Legend({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 10, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 5),
    Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).extension<AppColors>()!.textSecondary)),
  ]);
}

class _TotalStat extends StatelessWidget {
  final IconData icon; final String label, value; final Color color;
  const _TotalStat({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: color), const SizedBox(width: 8),
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
    ]),
  ]);
}

String _fmt(double kbps) {
  if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(2)} Mbps';
  return '${kbps.toStringAsFixed(0)} Kbps';
}
String _fmtMB(double mb) {
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
  return '${mb.toStringAsFixed(1)} MB';
}
String _fmtGB(double gb) {
  if (gb >= 1024) return '${(gb / 1024).toStringAsFixed(2)} TB';
  if (gb >= 1) return '${gb.toStringAsFixed(2)} GB';
  return '${(gb * 1024).toStringAsFixed(1)} MB';
}

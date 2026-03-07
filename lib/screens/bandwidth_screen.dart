import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/ssh_service.dart';
import '../models/models.dart';

// Traffic history provider
final trafficHistoryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final ssh = ref.read(sshServiceProvider);
  if (!ssh.isConnected) return {};
  return ssh.getTrafficHistory();
});

// QoS providers
final qosBasicProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final ssh = ref.read(sshServiceProvider);
  if (!ssh.isConnected) return {};
  try {
    final raw = await ssh.run('''
echo "=F="; nvram get qos_enable 2>/dev/null || echo ""
echo "=F="; nvram get qos_type 2>/dev/null || echo ""
echo "=F="; nvram get qos_default 2>/dev/null || echo ""
echo "=F="; nvram get qos_obw 2>/dev/null || echo ""
echo "=F="; nvram get qos_ibw 2>/dev/null || echo ""
''');
    // Split by =F= sentinel to get values reliably
    final parts = raw.split('=F=').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    // Each part: "value" (the line after =F=), skip empty
    final vals = parts.map((p) => p.split('\n').where((l) => l.isNotEmpty).lastOrNull?.trim() ?? '').toList();
    return {
      'enable':  vals.length > 0 ? vals[0] : '0',
      'type':    vals.length > 1 ? vals[1] : '0',
      'default': vals.length > 2 ? vals[2] : '-',
      'obw':     vals.length > 3 ? vals[3] : '-',
      'ibw':     vals.length > 4 ? vals[4] : '-',
    };
  } catch (_) { return {}; }
});

final qosClassifyProvider = FutureProvider.autoDispose<List<Map<String, String>>>((ref) async {
  final ssh = ref.read(sshServiceProvider);
  if (!ssh.isConnected) return [];
  try {
    // Also get qos_classnames for class labels
    final raw = await ssh.run(
      'echo "=RULES="; nvram get qos_orules 2>/dev/null || echo ""; '
      'echo "=CLASSES="; nvram get qos_classnames 2>/dev/null || echo ""; '
      'echo "=IRATES="; nvram get qos_irates 2>/dev/null || echo ""; '
      'echo "=ORATES="; nvram get qos_orates 2>/dev/null || echo ""'
    );
    final rules = <Map<String, String>>[];
    
    // Parse sections
    String rulesStr = '';
    String classStr = '';
    if (raw.contains('=RULES=') && raw.contains('=CLASSES=')) {
      final rIdx = raw.indexOf('=RULES=') + 7;
      final cIdx = raw.indexOf('=CLASSES=');
      rulesStr = raw.substring(rIdx, cIdx).trim();
      classStr = raw.substring(cIdx + 9).trim();
    } else {
      rulesStr = raw.trim();
    }
    
    // Parse class names (space separated: "Highest High Medium Low ...")
    final classNames = classStr.trim().isEmpty ? <String>[] : classStr.trim().split(RegExp(r'\s+'));
    
    // FreshTomato qos_orules: rules delimited by ">", fields by "<"
    // Format: prio<src_ip<dst_ip<proto<src_port<dst_port<desc
    // proto: 0=any, 6=tcp, 17=udp, 1=icmp (numeric)
    final protoMap = {'0':'any','6':'tcp','17':'udp','1':'icmp','58':'icmpv6'};
    int ruleIdx = 0;
    for (final chunk in rulesStr.split('>')) {
      final trimmed = chunk.trim();
      if (trimmed.isEmpty) continue;
      ruleIdx++;
      final parts = trimmed.split('<');
      
      // Try to parse: fields can vary, find prio (numeric 0-7) and desc (last text field)
      String prio = '5', src = '', dst = '', proto = 'any', sport = '', dport = '', desc = '';
      
      if (parts.isNotEmpty) {
        // Field[0] is prio if numeric, else it's proto name
        final f0 = parts[0].trim();
        if (int.tryParse(f0) != null && int.parse(f0) <= 10) {
          // Standard format: prio<src<dst<proto<sport<dport<desc
          prio  = f0;
          src   = parts.length > 1 ? parts[1].trim() : '';
          dst   = parts.length > 2 ? parts[2].trim() : '';
          final protoRaw = parts.length > 3 ? parts[3].trim() : '0';
          proto = protoMap[protoRaw] ?? (protoRaw.isEmpty ? 'any' : protoRaw);
          sport = parts.length > 4 ? parts[4].trim() : '';
          dport = parts.length > 5 ? parts[5].trim() : '';
          // desc is last non-empty field after index 5
          for (int i = 6; i < parts.length; i++) {
            final p = parts[i].trim();
            if (p.isNotEmpty) { desc = p; break; }
          }
        } else {
          // Alt format: proto<desc<src<dst<sport<dport<prio
          proto = protoMap[f0] ?? f0;
          desc  = parts.length > 1 ? parts[1].trim() : '';
          src   = parts.length > 2 ? parts[2].trim() : '';
          dst   = parts.length > 3 ? parts[3].trim() : '';
          sport = parts.length > 4 ? parts[4].trim() : '';
          dport = parts.length > 5 ? parts[5].trim() : '';
          final lastPrio = parts.length > 6 ? parts[6].trim() : '';
          prio  = int.tryParse(lastPrio) != null ? lastPrio : '5';
        }
      }
      
      // Resolve class name from prio index
      final prioIdx = (int.tryParse(prio) ?? 5) - 1;
      final className = (prioIdx >= 0 && prioIdx < classNames.length) ? classNames[prioIdx] : '';
      
      // Build label: prefer desc, then class name, then numbered
      final label = desc.isNotEmpty ? desc 
          : (className.isNotEmpty ? className : 'Rule $ruleIdx');
      
      // Format port display
      final portDisplay = dport.isNotEmpty && dport != '0' ? dport 
          : (sport.isNotEmpty && sport != '0' ? sport : 'any');
      
      rules.add({
        'prio': prio, 'src': src, 'dst': dst,
        'proto': proto, 'srcport': sport, 'dstport': dport,
        'desc': label, 'className': className,
        'portDisplay': portDisplay,
      });
    }
    return rules;
  } catch (_) { return []; }
});

// Realtime connections - auto refreshes every 5s when watched
final _connStreamController = StateProvider<int>((ref) => 0);

final qosConnProvider = FutureProvider.autoDispose<List<Map<String, String>>>((ref) async {
  // Depend on tick to trigger refresh
  ref.watch(_connStreamController);
  final ssh = ref.read(sshServiceProvider);
  if (!ssh.isConnected) return [];
  try {
    final raw = await ssh.run(
        'cat /proc/net/nf_conntrack 2>/dev/null || '
        'cat /proc/net/ip_conntrack 2>/dev/null || echo ""');
    final result = <Map<String, String>>[];
    for (final line in raw.split('\n')) {
      if (line.trim().isEmpty) continue;
      final proto = RegExp(r'^\w+').firstMatch(line)?.group(0) ?? '?';
      final srcs  = RegExp(r'src=(\S+)').allMatches(line).toList();
      final dsts  = RegExp(r'dst=(\S+)').allMatches(line).toList();
      final sp    = RegExp(r'sport=(\d+)').allMatches(line).toList();
      final dp    = RegExp(r'dport=(\d+)').allMatches(line).toList();
      final bytes = RegExp(r'bytes=(\d+)').allMatches(line).toList();
      result.add({
        'proto': proto,
        'src':   srcs.isNotEmpty ? srcs[0].group(1)! : '-',
        'dst':   dsts.isNotEmpty ? dsts[0].group(1)! : '-',
        'sport': sp.isNotEmpty   ? sp[0].group(1)!   : '-',
        'dport': dp.isNotEmpty   ? dp[0].group(1)!   : '-',
        'bytes': bytes.isNotEmpty ? bytes[0].group(1)! : '0',
      });
    }
    return result;
  } catch (_) { return []; }
});

// =============================================================================
// BandwidthScreen - main widget with Bandwidth | QoS toggle in title
// =============================================================================
class BandwidthScreen extends ConsumerStatefulWidget {
  const BandwidthScreen({super.key});
  @override
  ConsumerState<BandwidthScreen> createState() => _BandwidthScreenState();
}

class _BandwidthScreenState extends ConsumerState<BandwidthScreen> {
  bool _showQos = false;

  @override
  Widget build(BuildContext context) {
    final bw      = ref.watch(bandwidthProvider);
    final history = ref.watch(trafficHistoryProvider);
    final accent  = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c       = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
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
          if (!_showQos)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(children: [
                Container(
                    width: 7, height: 7,
                    decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                const Text('Live',
                    style: TextStyle(fontSize: 11, color: AppTheme.success, fontWeight: FontWeight.w600)),
              ]),
            ),
          if (_showQos)
            IconButton(
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

// =============================================================================
// Bandwidth body
// =============================================================================
class _BandwidthBody extends StatelessWidget {
  final BandwidthStats bw;
  final AsyncValue<Map<String, dynamic>> history;
  const _BandwidthBody({super.key, required this.bw, required this.history});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Speed cards
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

        // Real-time chart
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

        // Session total
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Session Total', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _TotalStat(
                icon: Icons.arrow_downward_rounded,
                label: 'Downloaded', value: _fmtMB(bw.totalRxMB), color: accent)),
              Expanded(child: _TotalStat(
                icon: Icons.arrow_upward_rounded,
                label: 'Uploaded', value: _fmtMB(bw.totalTxMB), color: AppTheme.secondary)),
            ]),
          ]),
        ),
        const SizedBox(height: 24),

        // Usage history section
        _SectionHeader(title: 'Usage History', icon: Icons.bar_chart_rounded, color: accent),
        const SizedBox(height: 12),

        history.when(
          loading: () => const Center(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator())),
          error: (e, _) => _EmptyCard(message: 'Could not load history: $e'),
          data: (data) {
            final daily   = (data['daily']   as List?) ?? [];
            final monthly = (data['monthly'] as List?) ?? [];
            if (daily.isEmpty && monthly.isEmpty) {
              return const _EmptyCard(
                  message: 'No traffic data found.\nEnable: Admin > Bandwidth > Traffic Monitoring in FreshTomato.');
            }
            return _UsageHistoryCard(daily: daily, monthly: monthly);
          },
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

// =============================================================================
// Section header row
// =============================================================================
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  const _SectionHeader({required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: Theme.of(context).extension<AppColors>()!.border)),
    ]);
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).extension<AppColors>()!.textMuted,
                  fontSize: 13)),
        ),
      ),
    );
  }
}

// =============================================================================
// Usage history card with Daily / Weekly / Monthly tabs
// =============================================================================
class _UsageHistoryCard extends StatefulWidget {
  final List daily, monthly;
  const _UsageHistoryCard({required this.daily, required this.monthly});

  @override
  State<_UsageHistoryCard> createState() => _UsageHistoryCardState();
}

class _UsageHistoryCardState extends State<_UsageHistoryCard> {
  int _tab = 0; // 0=daily 1=weekly 2=monthly

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c      = Theme.of(context).extension<AppColors>()!;

    final weekly = widget.daily.length > 7
        ? widget.daily.sublist(widget.daily.length - 7)
        : widget.daily;
    final data       = _tab == 0 ? widget.daily : _tab == 1 ? weekly : widget.monthly;
    final isMonthly  = _tab == 2;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        // Tab pills
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
                  child: Text(
                    ['Daily', 'Weekly', 'Monthly'][i],
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: _tab == i ? FontWeight.w600 : FontWeight.normal,
                        color: _tab == i ? accent : c.textSecondary),
                  ),
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
            child: SizedBox(
                height: 140,
                child: _HistoryBarChart(
                    data: data, isMonthly: isMonthly, accent: accent, c: c)),
          ),
          const SizedBox(height: 8),

          // Totals
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Expanded(child: _MiniTotal(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Total Down',
                  color: accent,
                  value: _fmtGB(
                      data.fold(0.0, (s, d) => s + (d['rx'] as num).toDouble())))),
              Expanded(child: _MiniTotal(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Total Up',
                  color: AppTheme.secondary,
                  value: _fmtGB(
                      data.fold(0.0, (s, d) => s + (d['tx'] as num).toDouble())))),
            ]),
          ),

          // Row list
          const Divider(height: 1),
          ...data.asMap().entries.map((e) {
            final d    = e.value;
            final rx   = (d['rx'] as num).toDouble();
            final tx   = (d['tx'] as num).toDouble();
            final maxRx = data.fold(0.0, (m, x) =>
                (x['rx'] as num).toDouble() > m ? (x['rx'] as num).toDouble() : m);
            final maxTx = data.fold(0.0, (m, x) =>
                (x['tx'] as num).toDouble() > m ? (x['tx'] as num).toDouble() : m);
            final label = isMonthly
                ? (d['month'] as String)
                : 'Day ${(d['day'] as num).toInt()}';
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                SizedBox(
                    width: 56,
                    child: Text(label,
                        style: TextStyle(fontSize: 11, color: c.textMuted))),
                Expanded(
                    child: Column(children: [
                      _MiniBar(value: rx, max: maxRx, color: accent),
                      const SizedBox(height: 3),
                      _MiniBar(value: tx, max: maxTx, color: AppTheme.secondary),
                    ])),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_fmtGB(rx),
                      style: TextStyle(fontSize: 10, color: accent)),
                  Text(_fmtGB(tx),
                      style: TextStyle(fontSize: 10, color: AppTheme.secondary)),
                ]),
              ]),
            );
          }),
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
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: max > 0 ? (value / max).clamp(0.0, 1.0) : 0,
        color: color,
        backgroundColor: color.withOpacity(0.12),
        minHeight: 5,
      ),
    );
  }
}

class _MiniTotal extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _MiniTotal(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).extension<AppColors>()!.textMuted)),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      ]),
    ]);
  }
}

class _HistoryBarChart extends StatelessWidget {
  final List data;
  final bool isMonthly;
  final Color accent;
  final AppColors c;
  const _HistoryBarChart(
      {required this.data,
      required this.isMonthly,
      required this.accent,
      required this.c});

  @override
  Widget build(BuildContext context) {
    final maxY = data.fold<double>(1, (m, d) {
      final rx = (d['rx'] as num).toDouble();
      final tx = (d['tx'] as num).toDouble();
      return [m, rx, tx].reduce((a, b) => a > b ? a : b);
    }) * 1.2;

    final w = data.length <= 7 ? 14.0 : data.length <= 14 ? 8.0 : 5.0;

    final groups = data.asMap().entries.map((e) {
      final d = e.value;
      return BarChartGroupData(x: e.key, barRods: [
        BarChartRodData(
            toY: (d['rx'] as num).toDouble(),
            color: accent,
            width: w,
            borderRadius: BorderRadius.circular(2)),
        BarChartRodData(
            toY: (d['tx'] as num).toDouble(),
            color: AppTheme.secondary,
            width: w,
            borderRadius: BorderRadius.circular(2)),
      ], barsSpace: 2);
    }).toList();

    return BarChart(BarChartData(
      maxY: maxY,
      gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: c.border, strokeWidth: 0.8)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 18,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (isMonthly) {
                final m = i < data.length ? (data[i]['month'] as String) : '';
                return Text(m.length >= 7 ? m.substring(5) : m,
                    style: TextStyle(fontSize: 9, color: c.textMuted));
              }
              if (data.length <= 7) {
                const names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                return Text(i < names.length ? names[i] : '',
                    style: TextStyle(fontSize: 9, color: c.textMuted));
              }
              final day =
                  i < data.length ? (data[i]['day'] as num).toInt() : 0;
              return Text(day % 5 == 0 ? '$day' : '',
                  style: TextStyle(fontSize: 9, color: c.textMuted));
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (v, _) => Text(_fmtGB(v),
                style: TextStyle(fontSize: 8, color: c.textMuted)),
          ),
        ),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      barGroups: groups,
      barTouchData: BarTouchData(enabled: false),
    ));
  }
}

// =============================================================================
// QoS full page (shown when _showQos = true)
// =============================================================================
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
    final c      = Theme.of(context).extension<AppColors>()!;

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
                child: Text(
                  ['Basic', 'Classification', 'Connections'][i],
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: _qosTab == i ? FontWeight.w600 : FontWeight.normal,
                      color: _qosTab == i ? accent : c.textSecondary),
                ),
              ),
            ),
          ],
        ]),
      ),
      Divider(height: 1, color: c.border),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _qosTab == 0
              ? const _QosBasicTab(key: ValueKey(0))
              : _qosTab == 1
                  ? const _QosClassifyTab(key: ValueKey(1))
                  : const _QosConnectionsTab(key: ValueKey(2)),
        ),
      ),
    ]);
  }
}

// =============================================================================
// QoS tab widgets
// =============================================================================
class _QosBasicTab extends ConsumerStatefulWidget {
  const _QosBasicTab({super.key});
  @override
  ConsumerState<_QosBasicTab> createState() => _QosBasicTabState();
}

class _QosBasicTabState extends ConsumerState<_QosBasicTab> {
  bool _saving = false;
  String? _saveMsg;

  Future<void> _save(Map<String, String> current, {
    required bool enabled,
    required String type,
    required String obw,
    required String ibw,
    required String defaultClass,
  }) async {
    final ssh = ref.read(sshServiceProvider);
    setState(() { _saving = true; _saveMsg = null; });
    try {
      final cmds = [
        'nvram set qos_enable=${enabled ? 1 : 0}',
        'nvram set qos_type=$type',
        'nvram set qos_default=$defaultClass',
        'nvram set qos_obw=$obw',
        'nvram set qos_ibw=$ibw',
        'nvram commit',
        'service qos restart 2>/dev/null || true',
      ].join(' && ');
      await ssh.run(cmds);
      ref.invalidate(qosBasicProvider);
      setState(() { _saveMsg = 'Saved!'; });
    } catch (e) {
      setState(() { _saveMsg = 'Error: $e'; });
    } finally {
      setState(() { _saving = false; });
    }
  }

  void _showEditDialog(BuildContext ctx, Map<String, String> d) {
    final accent = Theme.of(ctx).extension<AppColors>()?.accent ?? AppTheme.primary;
    bool enabled = (d['enable'] ?? '0') == '1';
    String type  = d['type'] ?? '0';
    String obw   = d['obw'] ?? '';
    String ibw   = d['ibw'] ?? '';
    String def   = d['default'] ?? 'Standard';
    final obwCtrl = TextEditingController(text: obw);
    final ibwCtrl = TextEditingController(text: ibw);
    final defCtrl = TextEditingController(text: def);

    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setS) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: const Text('QoS Settings'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Enable toggle
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('QoS Enabled'),
                Switch(
                  value: enabled,
                  activeColor: accent,
                  onChanged: (v) => setS(() => enabled = v),
                ),
              ]),
              const SizedBox(height: 12),
              // Mode dropdown
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'Mode', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: '0', child: Text('HTB (classic)')),
                  DropdownMenuItem(value: '1', child: Text('CAKE AQM')),
                  DropdownMenuItem(value: '2', child: Text('HFSC')),
                ],
                onChanged: (v) => setS(() => type = v ?? '0'),
              ),
              const SizedBox(height: 12),
              // Upload bandwidth
              TextField(
                controller: obwCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Upload Limit (kbit/s)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 10000',
                ),
              ),
              const SizedBox(height: 12),
              // Download bandwidth
              TextField(
                controller: ibwCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Download Limit (kbit/s)',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 50000',
                ),
              ),
              const SizedBox(height: 12),
              // Default class
              TextField(
                controller: defCtrl,
                decoration: const InputDecoration(
                  labelText: 'Default Class',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Standard',
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accent),
              onPressed: () {
                Navigator.pop(dCtx);
                _save(d,
                  enabled: enabled, type: type,
                  obw: obwCtrl.text.trim(), ibw: ibwCtrl.text.trim(),
                  defaultClass: defCtrl.text.trim());
              },
              child: const Text('Apply', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final basic  = ref.watch(qosBasicProvider);
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c      = Theme.of(context).extension<AppColors>()!;
    final modeMap = {'0': 'HTB (classic)', '1': 'HFSC', '2': 'HFSC (alt)', '3': 'CAKE AQM'};

    return basic.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (d) {
        final enabled = (d['enable'] ?? '0') == '1';
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (_saveMsg != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _saveMsg!.startsWith('Error') ? AppTheme.danger.withOpacity(0.15) : AppTheme.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _saveMsg!.startsWith('Error') ? AppTheme.danger : AppTheme.success),
              ),
              child: Row(children: [
                Icon(_saveMsg!.startsWith('Error') ? Icons.error_outline : Icons.check_circle_outline,
                  size: 16, color: _saveMsg!.startsWith('Error') ? AppTheme.danger : AppTheme.success),
                const SizedBox(width: 8),
                Text(_saveMsg!, style: TextStyle(
                  fontSize: 13,
                  color: _saveMsg!.startsWith('Error') ? AppTheme.danger : AppTheme.success)),
              ]),
            ),
          AppCard(
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Basic Settings', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary)),
                _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      icon: Icon(Icons.edit_rounded, size: 18, color: accent),
                      onPressed: () => _showEditDialog(context, d),
                      tooltip: 'Edit QoS settings',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
              ]),
              const Divider(height: 16),
              _QRow(
                  label: 'QoS Enabled',
                  value: enabled ? 'Enabled' : 'Disabled',
                  valueColor: enabled ? AppTheme.success : AppTheme.danger),
              _QRow(label: 'Mode', value: modeMap[d['type'] ?? ''] ?? 'Unknown'),
              _QRow(label: 'Default Class', value: d['default'] ?? '-'),
              _QRow(
                  label: 'Upload Limit',
                  value: '${d['obw'] ?? '-'} kbit/s',
                  valueColor: accent),
              _QRow(
                  label: 'Download Limit',
                  value: '${d['ibw'] ?? '-'} kbit/s',
                  valueColor: accent),
            ]),
          ),
        ]);
      },
    );
  }
}

class _QosClassifyTab extends ConsumerStatefulWidget {
  const _QosClassifyTab({super.key});
  @override
  ConsumerState<_QosClassifyTab> createState() => _QosClassifyTabState();
}

class _QosClassifyTabState extends ConsumerState<_QosClassifyTab> {
  bool _saving = false;

  // Serialize rules back to nvram qos_orules format: prio<src<dst<proto<srcport<dstport<desc>...
  Future<void> _saveRules(List<Map<String, String>> rules) async {
    final ssh = ref.read(sshServiceProvider);
    setState(() => _saving = true);
    try {
      final encoded = rules.map((r) =>
        '${r['prio']}<${r['src']}<${r['dst']}<${r['proto']}<${r['srcport']}<${r['dstport']}<${r['desc']}>').join('');
      await ssh.run("nvram set qos_orules='$encoded' && nvram commit && service qos restart 2>/dev/null || true");
      ref.invalidate(qosClassifyProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showRuleDialog(BuildContext ctx, List<Map<String, String>> allRules, {Map<String, String>? existing, int? index}) {
    final accent = Theme.of(ctx).extension<AppColors>()?.accent ?? AppTheme.primary;
    final isEdit = existing != null;

    String prio     = existing?['prio']    ?? '5';
    String proto    = existing?['proto']   ?? 'any';
    String srcport  = existing?['srcport'] ?? '';
    String dstport  = existing?['dstport'] ?? '';
    String desc     = existing?['desc']    ?? '';

    final descCtrl    = TextEditingController(text: desc);
    final srcportCtrl = TextEditingController(text: srcport);
    final dstportCtrl = TextEditingController(text: dstport);

    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setS) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: Text(isEdit ? 'Edit Rule' : 'Add Rule'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. YouTube, Gaming',
                ),
              ),
              const SizedBox(height: 12),
              // Priority
              DropdownButtonFormField<String>(
                value: prio,
                decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: '1', child: Text('P1 - Highest')),
                  DropdownMenuItem(value: '2', child: Text('P2 - High')),
                  DropdownMenuItem(value: '3', child: Text('P3 - Medium-High')),
                  DropdownMenuItem(value: '4', child: Text('P4 - Medium')),
                  DropdownMenuItem(value: '5', child: Text('P5 - Standard')),
                  DropdownMenuItem(value: '6', child: Text('P6 - Low')),
                  DropdownMenuItem(value: '7', child: Text('P7 - Lowest')),
                ],
                onChanged: (v) => setS(() => prio = v ?? '5'),
              ),
              const SizedBox(height: 12),
              // Protocol
              DropdownButtonFormField<String>(
                value: proto,
                decoration: const InputDecoration(labelText: 'Protocol', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'any',  child: Text('Any')),
                  DropdownMenuItem(value: 'tcp',  child: Text('TCP')),
                  DropdownMenuItem(value: 'udp',  child: Text('UDP')),
                  DropdownMenuItem(value: 'icmp', child: Text('ICMP')),
                ],
                onChanged: (v) => setS(() => proto = v ?? 'any'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(
                  controller: srcportCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Src Port',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. 80',
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: TextField(
                  controller: dstportCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Dst Port',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. 443',
                  ),
                )),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accent),
              onPressed: () {
                Navigator.pop(dCtx);
                final newRule = <String, String>{
                  'prio': prio, 'src': '', 'dst': '',
                  'proto': proto,
                  'srcport': srcportCtrl.text.trim(),
                  'dstport': dstportCtrl.text.trim(),
                  'desc': descCtrl.text.trim(),
                };
                final updated = List<Map<String, String>>.from(allRules);
                if (isEdit && index != null) {
                  updated[index] = newRule;
                } else {
                  updated.add(newRule);
                }
                _saveRules(updated);
              },
              child: Text(isEdit ? 'Save' : 'Add', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteRule(List<Map<String, String>> allRules, int index, BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: const Text('Delete Rule'),
        content: Text('Delete rule "${allRules[index]['desc']?.isNotEmpty == true ? allRules[index]['desc'] : 'Rule ${index + 1}'}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              Navigator.pop(ctx);
              final updated = List<Map<String, String>>.from(allRules)..removeAt(index);
              _saveRules(updated);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rules  = ref.watch(qosClassifyProvider);
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c      = Theme.of(context).extension<AppColors>()!;

    final prioColors = <String, Color>{
      '1': AppTheme.danger,
      '2': const Color(0xFFFF8C00),
      '3': const Color(0xFFFFD700),
      '4': AppTheme.success,
      '5': accent,
      '6': c.textSecondary,
      '7': c.textMuted,
    };

    return rules.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        return Stack(children: [
          list.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.rule_folder_outlined, size: 48, color: c.textMuted),
                const SizedBox(height: 12),
                Text('No QoS rules configured', style: TextStyle(color: c.textMuted)),
              ]))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final r     = list[i];
                  final prio  = r['prio'] ?? '5';
                  final color = prioColors[prio] ?? accent;
                  return AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10)),
                        child: Center(child: Text('P$prio',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['desc']!.isNotEmpty ? r['desc']! : 'Rule ${i + 1}',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary)),
                        Text('${r['proto']} | port: ${r['dstport']!.isNotEmpty ? r['dstport'] : 'any'}',
                            style: TextStyle(fontSize: 11, color: c.textMuted)),
                      ])),
                      // Edit & delete buttons
                      IconButton(
                        icon: Icon(Icons.edit_outlined, size: 18, color: accent),
                        onPressed: () => _showRuleDialog(context, list, existing: r, index: i),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.danger),
                        onPressed: () => _deleteRule(list, i, context),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ]),
                  );
                },
              ),
          // FAB for adding rule
          Positioned(
            right: 16, bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'addRule',
              backgroundColor: accent,
              onPressed: _saving ? null : () => _showRuleDialog(context, list),
              icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add, color: Colors.white),
              label: Text(_saving ? 'Saving...' : 'Add Rule',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ]);
      },
    );
  }
}

class _QosConnectionsTab extends ConsumerStatefulWidget {
  const _QosConnectionsTab({super.key});
  @override
  ConsumerState<_QosConnectionsTab> createState() => _QosConnectionsTabState();
}

class _QosConnectionsTabState extends ConsumerState<_QosConnectionsTab> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.read(_connStreamController.notifier).state++;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conns  = ref.watch(qosConnProvider);
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c      = Theme.of(context).extension<AppColors>()!;

    return conns.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) {
          return Center(
              child: Text('No active connections',
                  style: TextStyle(color: c.textMuted)));
        }
        return Column(children: [
          Container(
            color: Theme.of(context).colorScheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              SizedBox(
                  width: 44,
                  child: Text('Proto',
                      style: TextStyle(
                          fontSize: 10,
                          color: c.textMuted,
                          fontWeight: FontWeight.w600))),
              Expanded(
                  child: Text('Source',
                      style: TextStyle(
                          fontSize: 10,
                          color: c.textMuted,
                          fontWeight: FontWeight.w600))),
              Expanded(
                  child: Text('Destination',
                      style: TextStyle(
                          fontSize: 10,
                          color: c.textMuted,
                          fontWeight: FontWeight.w600))),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: list.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: c.border),
              itemBuilder: (_, i) {
                final conn  = list[i];
                final isTcp = conn['proto'] == 'tcp';
                final color = isTcp ? accent : AppTheme.secondary;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Row(children: [
                    SizedBox(
                      width: 44,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(conn['proto']!.toUpperCase(),
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: color),
                            textAlign: TextAlign.center),
                      ),
                    ),
                    Expanded(
                        child: Text('${conn['src']}:${conn['sport']}',
                            style: TextStyle(fontSize: 10, color: c.textPrimary),
                            overflow: TextOverflow.ellipsis)),
                    Expanded(
                        child: Text('${conn['dst']}:${conn['dport']}',
                            style: TextStyle(fontSize: 10, color: c.textSecondary),
                            overflow: TextOverflow.ellipsis)),
                  ]),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}

class _QRow extends StatelessWidget {
  final String label, value;
  final Color? valueColor;
  const _QRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 13, color: c.textSecondary)),
        Text(value,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? c.textPrimary)),
      ]),
    );
  }
}

// =============================================================================
// Shared small widgets
// =============================================================================
class _RealtimeChart extends StatelessWidget {
  final BandwidthStats bw;
  const _RealtimeChart({required this.bw});

  @override
  Widget build(BuildContext context) {
    if (bw.points.isEmpty) {
      return Center(
          child: Text('Waiting for data...',
              style: TextStyle(
                  color: Theme.of(context).extension<AppColors>()!.textMuted)));
    }
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c      = Theme.of(context).extension<AppColors>()!;
    final maxY   = [bw.peakRx, bw.peakTx, 100.0].reduce((a, b) => a > b ? a : b) * 1.2;
    final rxSpots = bw.points.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.rxKbps))
        .toList();
    final txSpots = bw.points.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.txKbps))
        .toList();
    return LineChart(LineChartData(
      minY: 0,
      maxY: maxY,
      gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: c.border, strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            getTitlesWidget: (v, _) => Text(
                v >= 1024
                    ? '${(v / 1024).toStringAsFixed(1)}M'
                    : '${v.toInt()}K',
                style: TextStyle(fontSize: 10, color: c.textMuted)),
          ),
        ),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineTouchData: const LineTouchData(enabled: false),
      lineBarsData: [
        LineChartBarData(
            spots: rxSpots,
            isCurved: true,
            color: accent,
            barWidth: 2,
            dotData: FlDotData(show: false),
            belowBarData:
                BarAreaData(show: true, color: accent.withOpacity(0.08))),
        LineChartBarData(
            spots: txSpots,
            isCurved: true,
            color: AppTheme.secondary,
            barWidth: 2,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(
                show: true, color: AppTheme.secondary.withOpacity(0.08))),
      ],
    ));
  }
}

class _SpeedCard extends StatelessWidget {
  final String label, value, peak;
  final IconData icon;
  final Color color;
  const _SpeedCard(
      {required this.label,
      required this.value,
      required this.peak,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 4),
        Text(peak, style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 10,
          height: 3,
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).extension<AppColors>()!.textSecondary)),
    ]);
  }
}

class _TotalStat extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _TotalStat(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value,
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      ]),
    ]);
  }
}

// =============================================================================
// Helpers
// =============================================================================
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
  if (gb >= 1)    return '${gb.toStringAsFixed(2)} GB';
  return '${(gb * 1024).toStringAsFixed(1)} MB';
}

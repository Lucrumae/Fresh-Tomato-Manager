import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/ssh_service.dart';
import '../models/models.dart';

// Traffic history provider
// Traffic tick - increments to trigger realtime refresh
final _trafficTickProvider = StateProvider<int>((ref) => 0);

// History tick refreshes every 60s (not 1s — getTrafficHistory is slow)
final _historyTickProvider = StateProvider<int>((ref) => 0);

final trafficHistoryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  ref.watch(_historyTickProvider);
  final ssh = ref.read(sshServiceProvider);
  if (!ssh.isConnected) return {};
  return ssh.getTrafficHistory();
});

// QoS providers
// Tick controllers for realtime refresh
final _basicTickProvider    = StateProvider<int>((ref) => 0);
final _classifyTickProvider = StateProvider<int>((ref) => 0);

final qosBasicProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  ref.watch(_basicTickProvider); // re-run on tick
  final ssh = ref.read(sshServiceProvider);
  if (!ssh.isConnected) return {};
  try {
    // Read all keys in one shot for efficiency
    final raw = await ssh.run(
      'echo "enable=\$(nvram get qos_enable)"; '
      'echo "mode=\$(nvram get qos_mode)"; '       // 0=disable,1=HTB,2=CAKE,3=CAKE(old)
      'echo "type=\$(nvram get qos_type)"; '        // some builds use qos_type instead
      'echo "default=\$(nvram get qos_default)"; '
      'echo "obw=\$(nvram get qos_obw)"; '          // HTB upload (kbps)
      'echo "ibw=\$(nvram get qos_ibw)"; '          // HTB download (kbps)
      'echo "wanobw=\$(nvram get wan_qos_obw)"; '  // CAKE upload (kbps) ← actual key
      'echo "wanibw=\$(nvram get wan_qos_ibw)"; '  // CAKE download (kbps) ← actual key
      'echo "cmode=\$(nvram get qos_cmode)"; '
      'echo "cakeprio=\$(nvram get qos_cake_prio_mode)"; '
      'echo "ack=\$(nvram get qos_ackfilter)"; '
      'echo "icmp=\$(nvram get qos_icmp)"; '
      'echo "classify=\$(nvram get qos_classify)"; '
      'echo "sched=\$(nvram get qos_sched)"; '
      'echo "cakewash=\$(nvram get qos_cake_wash)"; '
      'echo "udp=\$(nvram get qos_udp)"'
    );
    final kv = <String, String>{};
    for (final line in raw.split('\n')) {
      final idx = line.indexOf('=');
      if (idx < 0) continue;
      kv[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }

    // Resolve the actual mode:
    // qos_mode: 0=disabled, 1=HTB, 2=CAKE, 3=CAKE (FreshTomato >=2024)
    // qos_type: 0=HTB, 3=CAKE (older firmware, may be missing)
    // If qos_mode=2, it's definitely CAKE regardless of qos_type
    final qosMode = kv['mode'] ?? '';
    final qosType = kv['type'] ?? '';
    String resolvedType;
    if (qosMode == '2' || qosMode == '3') {
      resolvedType = '3'; // CAKE
    } else if (qosType == '3') {
      resolvedType = '3'; // CAKE (old key)
    } else {
      resolvedType = '0'; // HTB default
    }

    // Resolve bandwidth: CAKE uses wan_qos_obw/ibw, HTB uses qos_obw/ibw
    final isCake = resolvedType == '3';
    final obw = isCake
        ? (kv['wanobw']?.isNotEmpty == true && kv['wanobw'] != 'null' ? kv['wanobw']! : '')
        : (kv['obw']?.isNotEmpty == true && kv['obw'] != 'null' ? kv['obw']! : '');
    final ibw = isCake
        ? (kv['wanibw']?.isNotEmpty == true && kv['wanibw'] != 'null' ? kv['wanibw']! : '')
        : (kv['ibw']?.isNotEmpty == true && kv['ibw'] != 'null' ? kv['ibw']! : '');

    // CAKE priority mode: qos_cake_prio_mode (0-4)
    final cakeMode = (kv['cakeprio']?.isNotEmpty == true && kv['cakeprio'] != 'null')
        ? kv['cakeprio']! : (kv['cmode'] ?? '0');

    return {
      'enable':    (kv['enable']   ?? '0').isEmpty ? '0' : (kv['enable'] ?? '0'),
      'type':      resolvedType,
      'mode_raw':  qosMode,
      'default':   kv['default'] ?? '',
      'obw':       obw,
      'ibw':       ibw,
      'cmode':     cakeMode.isEmpty ? '0' : cakeMode,
      'ack':       (kv['ack']      ?? '0').isEmpty ? '0' : (kv['ack'] ?? '0'),
      'icmp':      (kv['icmp']     ?? '0').isEmpty ? '0' : (kv['icmp'] ?? '0'),
      'classify':  (kv['classify'] ?? '1').isEmpty ? '1' : (kv['classify'] ?? '1'),
      'sched':     (kv['sched']    ?? 'fq_codel').isEmpty ? 'fq_codel' : (kv['sched'] ?? 'fq_codel'),
      'cake_wash': (kv['cakewash'] ?? '0').isEmpty ? '0' : (kv['cakewash'] ?? '0'),
      'udp_noing': (kv['udp']      ?? '0').isEmpty ? '0' : (kv['udp'] ?? '0'),
    };
  } catch (_) { return {}; }
});

final qosClassifyProvider = FutureProvider.autoDispose<List<Map<String, String>>>((ref) async {
  ref.watch(_classifyTickProvider); // re-run on tick
  final ssh = ref.read(sshServiceProvider);
  if (!ssh.isConnected) return [];
  try {
    final rulesRaw = (await ssh.run('nvram get qos_orules 2>/dev/null || echo')).trim();
    final classRaw = (await ssh.run('nvram get qos_classnames 2>/dev/null || echo')).trim();
    final rules = <Map<String, String>>[];

    // classnames: space-separated
    final classNames = classRaw.isEmpty ? <String>[] : classRaw.split(RegExp(r'\s+'));
    const defClassNames = ['Service','VOIP/Game','Remote','WWW','Media',
        'HTTPS/Msgr','Mail','FileXfer','P2P/Bulk','Crawl'];
    const protoMap = {'0':'Any','6':'TCP','17':'UDP','256':'TCP/UDP','1':'ICMP'};

    // REAL FreshTomato qos_orules format (verified from actual router):
    // prio<src<proto<dst<dport<sport<empty<kb1:kb2<layer7<ipp2p<desc
    // [0]  prio  - 0-indexed class (0=Service,1=VOIP/Game,...)
    // [1]  src   - source address (empty=any)
    // [2]  proto - 0=any,6=tcp,17=udp,256=tcp+udp
    // [3]  dst   - destination address ("d"=any or IP)
    // [4]  dport - destination port (empty=any)
    // [5]  sport - source port (empty=any)
    // [6]  empty field
    // [7]  kb    - kb transferred range "start:end" (-1=no limit)
    // [8]  layer7 pattern (empty=any)
    // [9]  ipp2p flag
    // [10] desc  - description
    // Rules separated by ">" (NO trailing >)

    int ruleIdx = 0;
    for (final chunk in rulesRaw.split('>')) {
      final trimmed = chunk.trim();
      if (trimmed.isEmpty) continue;
      ruleIdx++;
      final f = trimmed.split('<');
      if (f.length < 3) continue;

      final prio  = f.length > 0 ? f[0].trim() : '0';
      final src   = f.length > 1 ? f[1].trim() : '';
      final protoRaw = f.length > 2 ? f[2].trim() : '0';
      final proto = protoMap[protoRaw] ?? (protoRaw.isEmpty ? 'Any' : protoRaw);
      // dst: "d" means any destination - normalize to empty
      final dstRaw = f.length > 3 ? f[3].trim() : '';
      final dst   = (dstRaw == 'd' || dstRaw == 'any') ? '' : dstRaw;
      final dport = f.length > 4 ? f[4].trim() : '';
      final sport = f.length > 5 ? f[5].trim() : '';
      // [6] = empty field, [7] = kb range "start:end"
      final kbRaw = f.length > 7 ? f[7].trim() : '';
      String kb1 = '0', kb2 = '-1';
      if (kbRaw.contains(':')) {
        final kbParts = kbRaw.split(':');
        kb1 = kbParts[0].trim().isEmpty ? '0'  : kbParts[0].trim();
        kb2 = kbParts[1].trim().isEmpty ? '-1' : kbParts[1].trim();
      }
      final desc  = f.length > 10 ? f[10].trim() : '';

      // prio is 0-indexed in storage, but we display as 1-indexed class name
      final prioInt = int.tryParse(prio) ?? 0;
      final className = prioInt < classNames.length   ? classNames[prioInt]
                      : prioInt < defClassNames.length ? defClassNames[prioInt]
                      : 'P${prioInt + 1}';

      final portDisplay = dport.isNotEmpty ? dport : 'Any';
      final label = desc.isNotEmpty ? desc : className;

      rules.add({
        'prio': prio,            // 0-indexed as stored in nvram
        'src': src, 'dst': dst,
        'proto': proto,
        'port1': dport, 'port2': dport,
        'sport': sport,
        'kb1': kb1, 'kb2': kb2,
        'portDisplay': portDisplay,
        'desc': label, 'rawDesc': desc, 'className': className,
        'rawChunk': trimmed,     // store original for safe round-trip
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
      // nf_conntrack line format:
      // ipv4 2 tcp 6 430 ESTABLISHED src=1.2.3.4 dst=5.6.7.8 sport=12345 dport=443 ...
      final proto = RegExp(r'\b(tcp|udp|icmp)\b').firstMatch(line)?.group(1)?.toLowerCase() ?? '';
      if (proto.isEmpty) continue;
      
      // Extract all src/dst/sport/dport - take first pair (outbound)
      final srcs  = RegExp(r'src=([\d\.]+)').allMatches(line).toList();
      final dsts  = RegExp(r'dst=([\d\.]+)').allMatches(line).toList();
      final sp    = RegExp(r'sport=(\d+)').allMatches(line).toList();
      final dp    = RegExp(r'dport=(\d+)').allMatches(line).toList();
      
      final src = srcs.isNotEmpty ? srcs[0].group(1)! : '-';
      final dst = dsts.isNotEmpty ? dsts[0].group(1)! : '-';
      // Skip pure loopback
      if (src.startsWith('127.') && dst.startsWith('127.')) continue;
      
      // State info
      final stateMatch = RegExp(r'\b(ESTABLISHED|SYN_SENT|TIME_WAIT|CLOSE_WAIT|FIN_WAIT)\b').firstMatch(line);
      final state = stateMatch?.group(1) ?? '';
      
      result.add({
        'proto': proto,
        'src':   src,
        'dst':   dst,
        'sport': sp.isNotEmpty ? sp[0].group(1)! : '-',
        'dport': dp.isNotEmpty ? dp[0].group(1)! : '-',
        'state': state,
      });
    }
    // Sort: ESTABLISHED first, then by protocol
    result.sort((a, b) {
      final aE = a['state'] == 'ESTABLISHED' ? 0 : 1;
      final bE = b['state'] == 'ESTABLISHED' ? 0 : 1;
      if (aE != bE) return aE - bE;
      return a['proto']!.compareTo(b['proto']!);
    });
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
  Timer? _trafficTimer;
  Timer? _historyTimer;

  @override
  void initState() {
    super.initState();
    _trafficTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) ref.read(_trafficTickProvider.notifier).state++;
    });
    // History (nvram traff- keys) only needs refresh every 60s
    _historyTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) ref.read(_historyTickProvider.notifier).state++;
    });
  }

  @override
  void dispose() {
    _trafficTimer?.cancel();
    _historyTimer?.cancel();
    super.dispose();
  }

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
                ref.read(_basicTickProvider.notifier).state++;
                ref.read(_classifyTickProvider.notifier).state++;
                ref.read(_connStreamController.notifier).state++;
              },
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _showQos
            ? _QosFullPage(key: const ValueKey('qos'))
            : _BandwidthBody(key: const ValueKey('bw'), bw: bw, history: history, tick: ref.watch(_trafficTickProvider)),
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
  final int tick;
  const _BandwidthBody({super.key, required this.bw, required this.history, required this.tick});

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

        // Usage history section - realtime cumulative
        Row(children: [
          Expanded(child: _SectionHeader(title: 'Usage History', icon: Icons.bar_chart_rounded, color: accent)),
          // Live indicator - blinks every refresh
          _LiveBadge(tick: tick),
        ]),
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
                  message: 'No traffic data.\nMake sure the router is connected.');
            }
            return _UsageHistoryCard(daily: daily, monthly: monthly, isRealtime: monthly.length == 1 && monthly.first['month'] != null);
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
// Live blinking badge for realtime indicators
class _LiveBadge extends StatefulWidget {
  final int tick;
  const _LiveBadge({required this.tick});
  @override State<_LiveBadge> createState() => _LiveBadgeState();
}
class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }
  @override void didUpdateWidget(_LiveBadge old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick) {
      _ctrl.reset(); _ctrl.repeat(reverse: true);
    }
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 7, height: 7,
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(0.4 + 0.6 * _ctrl.value),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Text('Live', style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w600,
        color: AppTheme.success.withOpacity(0.6 + 0.4 * _ctrl.value))),
    ]),
  );
}

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
  final bool isRealtime;
  const _UsageHistoryCard({required this.daily, required this.monthly, this.isRealtime = false});

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
            if (widget.isRealtime) ...[ 
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.success.withOpacity(0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.info_outline_rounded, size: 11, color: AppTheme.success),
                  const SizedBox(width: 4),
                  Text('Since boot', style: TextStyle(
                    fontSize: 10, color: AppTheme.success, fontWeight: FontWeight.w500)),
                ]),
              ),
            ],
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
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Poll every 5 seconds
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.read(_basicTickProvider.notifier).state++;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _kbpsToMbps(String kbps) {
    final v = double.tryParse(kbps) ?? 0;
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)} Mbps';
    return '${v.toStringAsFixed(0)} Kbps';
  }

  Future<void> _save(Map<String, String> current, {
    required bool enabled,
    required String type,
    required String obw,
    required String ibw,
    required String defaultClass,
    String cmode = '0',
  }) async {
    final ssh = ref.read(sshServiceProvider);
    setState(() { _saving = true; _saveMsg = null; });
    try {
      final obwVal = obw.isNotEmpty ? obw : '0';
      final ibwVal = ibw.isNotEmpty ? ibw : '0';
      final isCake = type == '3';
      // qos_mode: 1=HTB, 2=CAKE (FreshTomato >=2024 uses qos_mode not qos_type)
      final qosMode = isCake ? '2' : '1';

      final cmds = <String>[
        'nvram set qos_enable=${enabled ? 1 : 0}',
        'nvram set qos_mode=$qosMode',
        'nvram set qos_type=$type',    // set both for compatibility
      ];
      if (isCake) {
        // CAKE: bandwidth stored in wan_qos_obw / wan_qos_ibw
        cmds.add('nvram set wan_qos_obw=$obwVal');
        cmds.add('nvram set wan_qos_ibw=$ibwVal');
        cmds.add('nvram set qos_cake_prio_mode=$cmode');
        cmds.add('nvram set qos_cmode=$cmode');
      } else {
        // HTB: bandwidth in qos_obw / qos_ibw
        cmds.add('nvram set qos_obw=$obwVal');
        cmds.add('nvram set qos_ibw=$ibwVal');
        if (defaultClass.isNotEmpty) {
          // nvram qos_default expects an index (0-9)
          const _classNames = ['Service','VOIP/Game','Remote','WWW','Media',
              'HTTPS/Msgr','Mail','FileXfer','P2P/Bulk','Crawl'];
          final idx = _classNames.indexOf(defaultClass);
          cmds.add('nvram set qos_default=${idx >= 0 ? idx : 0}');
        }
      }
      cmds.add('nvram commit');

      for (final cmd in cmds) { await ssh.run(cmd); }

      // Restart QoS service to apply changes
      ssh.run(
        '(service qos stop >/dev/null 2>&1; sleep 1; service qos start >/dev/null 2>&1) &'
      ).catchError((_) {});

      ref.invalidate(qosBasicProvider);
      ref.read(_basicTickProvider.notifier).state++;
      setState(() { _saveMsg = isCake
        ? 'Saved! CAKE obw=\${obwVal}k ibw=\${ibwVal}k'
        : 'Saved! HTB obw=\${obwVal}k ibw=\${ibwVal}k'; });
    } catch (e) {
      setState(() { _saveMsg = 'Error: \$e'; });
    } finally {
      setState(() { _saving = false; });
    }
  }

  void _showEditDialog(BuildContext ctx, Map<String, String> d) {
    final accent = Theme.of(ctx).extension<AppColors>()?.accent ?? AppTheme.primary;
    bool enabled = (d['enable'] ?? '0') == '1';
    // type is already resolved by qosBasicProvider: '3'=CAKE, '0'=HTB
    String type  = (d['type'] ?? '0') == '3' ? '3' : '0';
    String cmode = d['cmode'] ?? '0';
    String obw   = d['obw']   ?? '';
    String ibw   = d['ibw']   ?? '';
    const classOpts = ['Service','VOIP/Game','Remote','WWW','Media',
        'HTTPS/Msgr','Mail','FileXfer','P2P/Bulk','Crawl'];
    final rawDef = d['default'] ?? '';
    // nvram qos_default stores an index (0-9), not the name string
    final defIdx = int.tryParse(rawDef);
    String defClass = (defIdx != null && defIdx < classOpts.length)
        ? classOpts[defIdx]
        : (classOpts.contains(rawDef) ? rawDef : 'Service');
    const cakeModeList = [
      MapEntry('0', 'Single class [besteffort]'),
      MapEntry('1', '8 priority [diffserv8] - DSCP'),
      MapEntry('2', '4 priority [diffserv4] - DSCP'),
      MapEntry('3', '3 priority [diffserv3] - DSCP'),
      MapEntry('4', '8 priority [precedence] - ToS'),
    ];
    final obwCtrl = TextEditingController(text: obw);
    final ibwCtrl = TextEditingController(text: ibw);

    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setS) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: const Text('QoS Basic Settings'),
          content: SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('QoS Enabled', style: TextStyle(fontWeight: FontWeight.w500)),
              Switch(value: enabled, activeColor: accent,
                onChanged: (v) => setS(() => enabled = v)),
            ]),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(labelText: 'Mode', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: '0', child: Text('HTB (classic)')),
                DropdownMenuItem(value: '3', child: Text('CAKE AQM')),
              ],
              onChanged: (v) => setS(() => type = v ?? '0'),
            ),
            const SizedBox(height: 14),
            if (type == '0') ...[
              DropdownButtonFormField<String>(
                value: defClass, isExpanded: true,
                decoration: const InputDecoration(labelText: 'Default Class', border: OutlineInputBorder()),
                items: classOpts.map((o) =>
                  DropdownMenuItem(value: o, child: Text(o))).toList(),
                onChanged: (v) => setS(() => defClass = v ?? 'Service'),
              ),
              const SizedBox(height: 14),
            ],
            if (type == '3') ...[
              DropdownButtonFormField<String>(
                value: cakeModeList.any((e) => e.key == cmode) ? cmode : '0',
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'CAKE Mode', border: OutlineInputBorder()),
                items: cakeModeList.map((e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                onChanged: (v) => setS(() => cmode = v ?? '0'),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: obwCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Upload Bandwidth (kbit/s)',
                border: OutlineInputBorder(), hintText: 'e.g. 10000'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ibwCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Download Bandwidth (kbit/s)',
                border: OutlineInputBorder(), hintText: 'e.g. 50000'),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: accent),
              onPressed: () {
                Navigator.pop(dCtx);
                _save(d,
                  enabled: enabled, type: type, cmode: cmode,
                  obw: obwCtrl.text.trim(), ibw: ibwCtrl.text.trim(),
                  defaultClass: type == '0' ? defClass : '');
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
    // FreshTomato: 0=HTB, 3=CAKE AQM (some builds: 1=CAKE)
    final modeMap = {'0':'HTB (classic)','1':'CAKE AQM','2':'CAKE AQM','3':'CAKE AQM'}; // type is pre-resolved to '0' or '3'
    final cakeModeMap = {
      '0': 'Single class [besteffort]',
      '1': '8 priority [diffserv8]',
      '2': '4 priority [diffserv4]',
      '3': '3 priority [diffserv3]',
      '4': '8 priority [precedence]',
    };

    // Use previousData to avoid flicker on refresh
    final basicData = basic.valueOrNull ?? basic.asData?.value ?? {};
    final isFirstLoad = basicData.isEmpty && basic.isLoading;
    if (isFirstLoad) return const Center(child: CircularProgressIndicator());

    return basic.when(
      loading: () {
        // Use last known data while refreshing - no spinner
        if (basicData.isNotEmpty) {
          return _buildBasicContent(context, basicData, accent, c, modeMap, cakeModeMap);
        }
        return const Center(child: CircularProgressIndicator());
      },
      error: (e, _) => basicData.isNotEmpty
          ? _buildBasicContent(context, basicData, accent, c, modeMap, cakeModeMap)
          : Center(child: Text('Error: $e')),
      data: (d) => _buildBasicContent(context, basicData.isEmpty ? d : d, accent, c, modeMap, cakeModeMap),
    );
  }

  Widget _buildBasicContent(BuildContext context, Map<String, String> d,
      Color accent, AppColors c, Map<String,String> modeMap, Map<String,String> cakeModeMap) {
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
                Expanded(child: Text(_saveMsg!, style: TextStyle(
                  fontSize: 12,
                  color: _saveMsg!.startsWith('Error') ? AppTheme.danger : AppTheme.success))),
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
              _QRow(
                  label: 'Mode',
                  value: modeMap[d['type'] ?? ''] ?? 'HTB (classic)'),
              // HTB (type=0): show default class
              if ((d['type'] ?? '0') == '0')
                _QRow(label: 'Default Class',
                  value: d['default']?.isNotEmpty == true ? d['default']! : '-'),
              // CAKE (type=1,2,3): show cake mode
              if (['1','2','3'].contains(d['type'] ?? '0'))
                _QRow(label: 'CAKE Mode',
                  value: cakeModeMap[d['cmode'] ?? ''] ?? 'Single class [besteffort]'),
              _QRow(
                  label: 'Upload Limit',
                  value: (d['obw']?.isNotEmpty == true && d['obw'] != '0')
                    ? '${d['obw']} kbps (${_kbpsToMbps(d['obw']!)})'
                    : 'Not set',
                  valueColor: accent),
              _QRow(
                  label: 'Download Limit',
                  value: (d['ibw']?.isNotEmpty == true && d['ibw'] != '0')
                    ? '${d['ibw']} kbps (${_kbpsToMbps(d['ibw']!)})'
                    : 'Not set',
                  valueColor: accent),
            ]),
          ),
        ]);
  }
}

class _QosClassifyTab extends ConsumerStatefulWidget {
  const _QosClassifyTab({super.key});
  @override
  ConsumerState<_QosClassifyTab> createState() => _QosClassifyTabState();
}

class _QosClassifyTabState extends ConsumerState<_QosClassifyTab> {
  bool _saving = false;
  Timer? _cTimer;

  @override
  void initState() {
    super.initState();
    _cTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      ref.read(_classifyTickProvider.notifier).state++;
    });
  }

  @override
  void dispose() {
    _cTimer?.cancel();
    super.dispose();
  }

  // Serialize rules back to nvram qos_orules format: prio<src<dst<proto<srcport<dstport<desc>...
  Future<void> _saveRules(List<Map<String, String>> rules) async {
    final ssh = ref.read(sshServiceProvider);
    setState(() => _saving = true);
    try {
      // Encode each rule back to FreshTomato nvram format
      // FreshTomato: src<dst<proto<port1<port2<kb1<kb2<prio<ipp2p<layer7<desc<enable>...
      // REAL FreshTomato qos_orules format (verified from actual router debug):
      // prio<src<proto<dst<dport<sport<empty<kb1:kb2<layer7<ipp2p<desc
      // prio is 0-indexed, rules separated by > (NO trailing >)
      const p2n = {'Any':'0','TCP':'6','UDP':'17','TCP/UDP':'256','ICMP':'1'};
      String encRule(Map<String, String> r) {
        // If rawChunk exists and rule was not modified, use it directly
        final raw = r['rawChunk'] ?? '';
        if (raw.isNotEmpty && r['_modified'] != '1') return raw;

        final protoRaw = r['proto'] ?? 'Any';
        final protoNum = p2n[protoRaw] ?? protoRaw;
        final prio  = r['prio'] ?? '0';          // 0-indexed
        final src   = r['src'] ?? '';
        final dst   = r['dst'] ?? '';             // empty = any dst
        final dport = r['port1'] ?? '';
        final sport = r['sport'] ?? '';
        final kb1   = r['kb1'] ?? '0';
        final kb2   = r['kb2'] ?? '-1';
        final desc  = (r['rawDesc']?.isNotEmpty == true) ? r['rawDesc']! : (r['desc'] ?? '');
        // Format: prio<src<proto<dst<dport<sport<empty<kb1:kb2<layer7<ipp2p<desc
        return '$prio<$src<$protoNum<$dst<$dport<$sport<<$kb1:$kb2<<<$desc';
      }
      // Rules separated by > (no trailing >)
      final encoded = rules.map(encRule).join('>');
      // Use nvram + service qos restart (not iptables directly)
      await ssh.run('nvram set qos_orules=' + "'" + encoded + "'" + ' && nvram commit');
      // Apply QoS changes: stop then start in background
      ssh.run('(service qos stop > /dev/null 2>&1; service qos start > /dev/null 2>&1 &)').catchError((_) {});

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

    // FreshTomato class priority names (0-indexed in storage, 1-indexed in display)
    const classNames = ['Service','VOIP/Game','Remote','WWW','Media','HTTPS/Msgr','Mail','FileXfer','P2P/Bulk','Crawl'];

    // prio: stored 0-indexed, display 1-indexed
    final prioStored = int.tryParse(existing?['prio'] ?? '0') ?? 0;
    String prio = ((prioStored + 1).clamp(1, 10)).toString();

    // Address type: Any Address / Dst IP / Src IP / Src MAC
    String addrType = 'any';   // any / dst / src / mac
    String addrVal  = existing?['dst']?.isNotEmpty == true ? existing!['dst']!
                    : existing?['src']?.isNotEmpty == true ? existing!['src']! : '';
    if (existing?['dst']?.isNotEmpty == true) addrType = 'dst';
    else if (existing?['src']?.isNotEmpty == true) addrType = 'src';

    // Protocol
    String proto = existing?['proto'] ?? 'Any';
    if (!['Any','TCP','UDP','TCP/UDP','ICMP'].contains(proto)) proto = 'TCP/UDP';

    // Port type: any / dst / src / srcordst
    String portType = 'dst';
    String port1 = existing?['port1'] ?? '';
    String port2 = existing?['port2'] ?? '';

    // IPP2P
    String ipp2p = 'disabled';
    const ipp2pOptions = ['disabled','All IPP2P filters','AppleJuice','Ares','BitTorrent',
        'Direct Connect','eDonkey','Gnutella','Kazaa','Mute','SoulSeek','Waste','WinMX','XDCC'];

    // Layer 7
    String layer7 = 'disabled';
    const layer7Options = ['disabled','bittorrent','dns','edonkey','fasttrack','gnutella',
        'http','imap','messenger','msnmessenger','pop3','skype','smtp','ssl','xunlei','youtube'];

    // DSCP
    String dscp = 'any';
    const dscpOptions = ['any','BE','CS1','CS2','CS3','CS4','CS5','CS6','CS7',
        'AF11','AF12','AF13','AF21','AF22','AF23','AF31','AF32','AF33',
        'AF41','AF42','AF43','EF'];

    // KB transferred
    String kb1 = existing?['kb1'] ?? '0';
    String kb2 = existing?['kb2'] ?? '-1';
    if (kb1 == '0' && kb2 == '-1') { kb1 = ''; kb2 = ''; }

    // Description
    String desc = existing?['rawDesc'] ?? existing?['desc'] ?? '';
    if (desc.startsWith('Rule ') && int.tryParse(desc.split(' ').last) != null) desc = '';

    final descCtrl  = TextEditingController(text: desc);
    final addrCtrl  = TextEditingController(text: addrVal);
    final port1Ctrl = TextEditingController(text: port1);
    final port2Ctrl = TextEditingController(text: port2);
    final kb1Ctrl   = TextEditingController(text: kb1);
    final kb2Ctrl   = TextEditingController(text: kb2);


    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx2) => StatefulBuilder(
        builder: (dCtx2, setS2) {
          InputDecoration dec2(String label, {String? hint}) => InputDecoration(
            labelText: label, border: const OutlineInputBorder(),
            hintText: hint, isDense: true);
          final tc2 = Theme.of(ctx).extension<AppColors>()!;
          Widget sec2(String t) => Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(t, style: TextStyle(fontSize: 11,
                fontWeight: FontWeight.w600, color: tc2.textSecondary)));

          return AlertDialog(
            backgroundColor: Theme.of(ctx).colorScheme.surface,
            title: Text(isEdit ? 'Edit Rule' : 'Add Rule'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [

                  sec2('Class'),
                  DropdownButtonFormField<String>(
                    value: prio, isExpanded: true,
                    decoration: dec2('Priority / Class'),
                    items: List.generate(classNames.length, (i) =>
                      DropdownMenuItem(value: '${i+1}',
                        child: Text('P${i+1} - ${classNames[i]}', style: const TextStyle(fontSize: 13)))),
                    onChanged: (v) => setS2(() => prio = v ?? '1'),
                  ),
                  sec2('Description'),
                  TextField(controller: descCtrl,
                    decoration: dec2('Description', hint: 'e.g. DNS, Gaming')),

                  sec2('Address'),
                  DropdownButtonFormField<String>(
                    value: addrType, isExpanded: true,
                    decoration: dec2('Address Type'),
                    items: const [
                      DropdownMenuItem(value: 'any', child: Text('Any Address')),
                      DropdownMenuItem(value: 'dst', child: Text('Dst IP')),
                      DropdownMenuItem(value: 'src', child: Text('Src IP')),
                      DropdownMenuItem(value: 'mac', child: Text('Src MAC')),
                    ],
                    onChanged: (v) => setS2(() { addrType = v ?? 'any'; addrCtrl.clear(); }),
                  ),
                  if (addrType != 'any') ...[
                    const SizedBox(height: 8),
                    TextField(controller: addrCtrl,
                      decoration: dec2(
                        addrType == 'mac' ? 'MAC Address' : 'IP / CIDR',
                        hint: addrType == 'mac' ? 'AA:BB:CC:DD:EE:FF' : '192.168.1.0/24')),
                  ],

                  sec2('Protocol'),
                  DropdownButtonFormField<String>(
                    value: proto,
                    decoration: dec2('Protocol'),
                    items: const [
                      DropdownMenuItem(value: 'TCP/UDP', child: Text('TCP/UDP')),
                      DropdownMenuItem(value: 'TCP',     child: Text('TCP')),
                      DropdownMenuItem(value: 'UDP',     child: Text('UDP')),
                      DropdownMenuItem(value: 'Any',     child: Text('Any Protocol')),
                      DropdownMenuItem(value: 'ICMP',    child: Text('ICMP')),
                    ],
                    onChanged: (v) => setS2(() => proto = v ?? 'TCP/UDP'),
                  ),

                  sec2('Port'),
                  DropdownButtonFormField<String>(
                    value: portType, isExpanded: true,
                    decoration: dec2('Port Type'),
                    items: const [
                      DropdownMenuItem(value: 'any',      child: Text('Any Port')),
                      DropdownMenuItem(value: 'dst',      child: Text('Dst Port')),
                      DropdownMenuItem(value: 'src',      child: Text('Src Port')),
                      DropdownMenuItem(value: 'srcordst', child: Text('Src or Dst Port')),
                    ],
                    onChanged: (v) => setS2(() { portType = v ?? 'dst'; port1Ctrl.clear(); port2Ctrl.clear(); }),
                  ),
                  if (portType != 'any') ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextField(controller: port1Ctrl,
                        keyboardType: TextInputType.number,
                        decoration: dec2('Port From', hint: '53'))),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('-')),
                      Expanded(child: TextField(controller: port2Ctrl,
                        keyboardType: TextInputType.number,
                        decoration: dec2('Port To', hint: '53'))),
                    ]),
                  ],

                  sec2('IPP2P'),
                  DropdownButtonFormField<String>(
                    value: ipp2p, isExpanded: true,
                    decoration: dec2('IPP2P Filter'),
                    items: ipp2pOptions.map((o) => DropdownMenuItem(
                      value: o, child: Text(o == 'disabled' ? 'IPP2P (disabled)' : o,
                        style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) => setS2(() => ipp2p = v ?? 'disabled'),
                  ),

                  sec2('Layer 7'),
                  DropdownButtonFormField<String>(
                    value: layer7, isExpanded: true,
                    decoration: dec2('Layer 7 Pattern'),
                    items: layer7Options.map((o) => DropdownMenuItem(
                      value: o, child: Text(o == 'disabled' ? 'Layer 7 (disabled)' : o,
                        style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) => setS2(() => layer7 = v ?? 'disabled'),
                  ),

                  sec2('DSCP'),
                  DropdownButtonFormField<String>(
                    value: dscp, isExpanded: true,
                    decoration: dec2('DSCP'),
                    items: dscpOptions.map((o) => DropdownMenuItem(
                      value: o, child: Text(o == 'any' ? 'DSCP (any)' : 'DSCP Class $o',
                        style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (v) => setS2(() => dscp = v ?? 'any'),
                  ),

                  sec2('KB Transferred (optional)'),
                  Row(children: [
                    Expanded(child: TextField(controller: kb1Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: dec2('From kB', hint: '0'))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('-')),
                    Expanded(child: TextField(controller: kb2Ctrl,
                      keyboardType: TextInputType.number,
                      decoration: dec2('To kB', hint: 'empty=no limit'))),
                  ]),
                ]))),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx2), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: accent),
                onPressed: () {
                  Navigator.pop(dCtx2);
                  final p2n = {'Any':'0','TCP':'6','UDP':'17','TCP/UDP':'256','ICMP':'1'};
                  final protoNum = p2n[proto] ?? '0';
                  final prioIdx  = ((int.tryParse(prio) ?? 1) - 1).toString(); // back to 0-indexed
                  final p1 = portType != 'any' ? port1Ctrl.text.trim() : '';
                  final p2 = portType != 'any' ? (port2Ctrl.text.trim().isEmpty ? p1 : port2Ctrl.text.trim()) : '';
                  final srcAddr  = addrType == 'src' || addrType == 'mac' ? addrCtrl.text.trim() : '';
                  final dstAddr  = addrType == 'dst' ? addrCtrl.text.trim() : '';
                  final kbFrom   = kb1Ctrl.text.trim().isEmpty ? '0'  : kb1Ctrl.text.trim();
                  final kbTo     = kb2Ctrl.text.trim().isEmpty ? '-1' : kb2Ctrl.text.trim();
                  final newRule = <String, String>{
                    'prio':    prioIdx,
                    'proto':   protoNum,
                    'src':     srcAddr,
                    'dst':     dstAddr,
                    'port1':   p1,
                    'port2':   p2,
                    'sport':   portType == 'src' || portType == 'srcordst' ? p1 : '',
                    'kb1':     kbFrom,
                    'kb2':     kbTo,
                    'rawDesc': descCtrl.text.trim(),
                    'desc':    descCtrl.text.trim(),
                    '_modified': '1',
                  };
                  final updated = List<Map<String, String>>.from(allRules);
                  if (isEdit && index != null) updated[index] = newRule;
                  else updated.add(newRule);
                  _saveRules(updated);
                },
                child: Text(isEdit ? 'Save' : 'Add', style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        }),
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

    final listData = rules.valueOrNull ?? [];
    if (listData.isEmpty && rules.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final displayList = rules.asData?.value ?? listData;
    return Stack(children: [
          displayList.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.rule_folder_outlined, size: 48, color: c.textMuted),
                const SizedBox(height: 12),
                Text('No QoS rules configured', style: TextStyle(color: c.textMuted)),
              ]))
            : ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: displayList.length,
                onReorder: (oldIdx, newIdx) {
                  if (newIdx > oldIdx) newIdx--;
                  final updated = List<Map<String,String>>.from(displayList);
                  final item = updated.removeAt(oldIdx);
                  updated.insert(newIdx, item);
                  _saveRules(updated);
                },
                itemBuilder: (_, i) {
                  final r     = displayList[i];
                  final prio  = r['prio'] ?? '0';
                  final color = prioColors[prio] ?? accent;
                  final itemKey = ValueKey('rule_${i}_${r['rawDesc'] ?? i}');
                  final portInfo = r['portDisplay']?.isNotEmpty == true && r['portDisplay'] != 'Any'
                      ? 'Port: ${r['portDisplay']}' : '';
                  final xferInfo = r['xferDisplay']?.isNotEmpty == true ? r['xferDisplay']! : '';
                  final subtitle = [r['proto'] ?? 'Any', if (portInfo.isNotEmpty) portInfo, if (xferInfo.isNotEmpty) xferInfo]
                      .join(' | ');
                  final className = r['className'] ?? '';

                  return AppCard(
                    key: itemKey,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      // Priority badge
                      Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10)),
                        child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Text('P$prio', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                          if (className.isNotEmpty)
                            Text(className, style: TextStyle(fontSize: 8, color: color.withOpacity(0.8)),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                      ),
                      const SizedBox(width: 10),
                      // Description + subtitle
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r['desc']!.isNotEmpty ? r['desc']! : 'Rule ${i + 1}',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary)),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(fontSize: 11, color: c.textMuted)),
                      ])),
                      // Edit, delete, drag handle
                      IconButton(
                        icon: Icon(Icons.edit_outlined, size: 18, color: accent),
                        onPressed: () => _showRuleDialog(context, displayList, existing: r, index: i),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.danger),
                        onPressed: () => _deleteRule(displayList, i, context),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 2),
                      ReorderableDragStartListener(
                        index: i,
                        child: Icon(Icons.drag_handle,
                          size: 20, color: Theme.of(context).extension<AppColors>()!.textMuted),
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
              onPressed: _saving ? null : () => _showRuleDialog(context, displayList),
              icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add, color: Colors.white),
              label: Text(_saving ? 'Saving...' : 'Add Rule',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ]);
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
              SizedBox(width: 48, child: Text('Proto',
                  style: TextStyle(fontSize: 10, color: c.textMuted, fontWeight: FontWeight.w600))),
              Expanded(flex: 3, child: Text('Source -> Destination',
                  style: TextStyle(fontSize: 10, color: c.textMuted, fontWeight: FontWeight.w600))),
              SizedBox(width: 70, child: Text('State',
                  style: TextStyle(fontSize: 10, color: c.textMuted, fontWeight: FontWeight.w600))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('${list.length} connections',
              style: TextStyle(fontSize: 10, color: accent, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: list.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: c.border),
              itemBuilder: (_, i) {
                final conn  = list[i];
                final isTcp = conn['proto'] == 'tcp';
                final color = isTcp ? accent : AppTheme.secondary;
                final state = conn['state'] ?? '';
                final stateColor = state == 'ESTABLISHED' ? AppTheme.success
                    : state.contains('WAIT') ? AppTheme.warning : c.textMuted;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    SizedBox(
                      width: 48,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(conn['proto']!.toUpperCase(),
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
                            textAlign: TextAlign.center),
                      ),
                    ),
                    Expanded(flex: 3, child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${conn['src']}:${conn['sport']}',
                            style: TextStyle(fontSize: 10, color: c.textPrimary),
                            overflow: TextOverflow.ellipsis),
                        Text('-> ${conn['dst']}:${conn['dport']}',
                            style: TextStyle(fontSize: 10, color: c.textSecondary),
                            overflow: TextOverflow.ellipsis),
                      ],
                    )),
                    SizedBox(width: 70, child: Text(
                      state.isNotEmpty ? state.replaceAll('_', ' ') : '-',
                      style: TextStyle(fontSize: 9, color: stateColor, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    )),
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

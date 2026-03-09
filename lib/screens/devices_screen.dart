import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/status_badge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/ssh_service.dart';
import '../models/models.dart';

// ── Port name helpers ──────────────────────────────────────────────────────
String _portName(int port) {
  const names = {
    80: 'HTTP', 443: 'HTTPS', 53: 'DNS', 22: 'SSH', 21: 'FTP',
    25: 'SMTP', 587: 'SMTP', 993: 'IMAP', 995: 'POP3',
    8080: 'HTTP-Alt', 8443: 'HTTPS-Alt',
    123: 'NTP', 853: 'DNS-TLS',
    5228: 'FCM', 5229: 'FCM', 3478: 'STUN', 3479: 'STUN',
  };
  return names[port] ?? port.toString();
}

Color _stateColor(String state) {
  if (state == 'ESTABLISHED') return AppTheme.success;
  if (state == 'TIME_WAIT') return AppTheme.warning;
  if (state == 'SYN_SENT') return Colors.blue;
  return AppTheme.textSecondary;
}

// ── Main Screen ─────────────────────────────────────────────────────────────
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});
  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  String _search = '';
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(devicesProvider);
    final filtered = all.where((d) {
      final ms = _search.isEmpty ||
        d.displayName.toLowerCase().contains(_search.toLowerCase()) ||
        d.ip.contains(_search) ||
        d.mac.toLowerCase().contains(_search.toLowerCase());
      final mf = _filter == 'all' ||
        (_filter == 'wifi' && d.isWireless) ||
        (_filter == 'ethernet' && !d.isWireless) ||
        (_filter == 'blocked' && d.isBlocked);
      return ms && mf;
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Devices', style: Theme.of(context).textTheme.titleLarge),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('${all.length} connected',
                style: Theme.of(context).textTheme.bodySmall)),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(100),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(children: [
                TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(
                    hintText: 'Search by name, IP, or MAC...',
                    prefixIcon: Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _FilterChip(label: 'All (${all.length})', value: 'all',
                      current: _filter, onTap: (v) => setState(() => _filter = v)),
                    _FilterChip(label: 'WiFi', value: 'wifi',
                      current: _filter, onTap: (v) => setState(() => _filter = v)),
                    _FilterChip(label: 'Ethernet', value: 'ethernet',
                      current: _filter, onTap: (v) => setState(() => _filter = v)),
                    _FilterChip(label: 'Blocked', value: 'blocked',
                      current: _filter, onTap: (v) => setState(() => _filter = v)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        filtered.isEmpty
          ? SliverFillRemaining(child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.devices_rounded, size: 48,
                  color: Theme.of(context).extension<AppColors>()!.textMuted),
                const SizedBox(height: 12),
                Text('No devices found',
                  style: TextStyle(
                    color: Theme.of(context).extension<AppColors>()!.textMuted)),
              ])))
          : SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (ctx, i) => _DeviceCard(device: filtered[i]),
                childCount: filtered.length,
              )),
            ),
      ]),
    );
  }
}

// ── Device Card ─────────────────────────────────────────────────────────────
class _DeviceCard extends ConsumerWidget {
  final ConnectedDevice device;
  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _DeviceDetailSheet(device: device),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: device.isBlocked
                ? AppTheme.danger.withOpacity(0.1)
                : accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              device.isWireless ? Icons.wifi_rounded : Icons.cable_rounded,
              color: device.isBlocked ? AppTheme.danger : accent, size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(device.displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis)),
                if (device.isBlocked)
                  StatusBadge(label: 'Blocked', color: AppTheme.danger),
              ]),
              const SizedBox(height: 2),
              if (device.hostname.isNotEmpty &&
                  device.hostname != device.displayName)
                Text(device.hostname,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: accent.withOpacity(0.8),
                    fontStyle: FontStyle.italic)),
              Row(children: [
                Icon(Icons.circle, size: 6,
                  color: Theme.of(context).extension<AppColors>()!.textSecondary),
                const SizedBox(width: 4),
                Text(device.ip,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).extension<AppColors>()!.textSecondary)),
                const SizedBox(width: 8),
                Expanded(child: Text(device.mac,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis)),
              ]),
            ],
          )),
          Icon(Icons.chevron_right_rounded, size: 20,
            color: Theme.of(context).extension<AppColors>()!.textMuted),
        ]),
      ),
    );
  }
}

// ── Device Detail Bottom Sheet ───────────────────────────────────────────────
class _DeviceDetailSheet extends ConsumerStatefulWidget {
  final ConnectedDevice device;
  const _DeviceDetailSheet({required this.device});
  @override
  ConsumerState<_DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends ConsumerState<_DeviceDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _conns = [];
  bool _loadingConns = true;
  bool _connError = false;
  Timer? _timer;

  int _dlLimit = 0, _ulLimit = 0;
  bool _bwLoading = false, _bwSaving = false;
  String? _bwMsg;
  final _dlCtrl = TextEditingController();
  final _ulCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadConns();
    _loadBw();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_tab.index == 0) _loadConns();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _timer?.cancel();
    _dlCtrl.dispose();
    _ulCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConns() async {
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    setState(() { _loadingConns = true; _connError = false; });
    try {
      final r = await ssh.getDeviceConnections(widget.device.ip);
      if (mounted) setState(() { _conns = r; _loadingConns = false; });
    } catch (_) {
      if (mounted) setState(() { _loadingConns = false; _connError = true; });
    }
  }

  Future<void> _loadBw() async {
    final ssh = ref.read(sshServiceProvider);
    setState(() => _bwLoading = true);
    try {
      final bw = await ssh.getDeviceBandwidth(widget.device.ip);
      if (mounted) {
        _dlLimit = bw['dl'] ?? 0;
        _ulLimit = bw['ul'] ?? 0;
        _dlCtrl.text = _dlLimit > 0 ? _dlLimit.toString() : '';
        _ulCtrl.text = _ulLimit > 0 ? _ulLimit.toString() : '';
        setState(() => _bwLoading = false);
      }
    } catch (_) { if (mounted) setState(() => _bwLoading = false); }
  }

  Future<void> _saveBw() async {
    final ssh = ref.read(sshServiceProvider);
    setState(() { _bwSaving = true; _bwMsg = null; });
    final dl = int.tryParse(_dlCtrl.text.trim()) ?? 0;
    final ul = int.tryParse(_ulCtrl.text.trim()) ?? 0;
    try {
      final ok = await ssh.setDeviceBandwidth(widget.device.ip, dl, ul);
      if (mounted) setState(() {
        _dlLimit = dl; _ulLimit = ul;
        _bwMsg = ok
          ? (dl == 0 && ul == 0 ? 'Limit removed!' : 'Saved! DL:${dl}kbps / UL:${ul}kbps')
          : 'Save failed.';
        _bwSaving = false;
      });
    } catch (e) {
      if (mounted) setState(() { _bwMsg = 'Error: $e'; _bwSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;

    return DraggableScrollableSheet(
      initialChildSize: 0.9, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: c.textMuted.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2)),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
            child: Row(children: [
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: widget.device.isBlocked
                    ? AppTheme.danger.withOpacity(0.12)
                    : accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  widget.device.isWireless
                    ? Icons.wifi_rounded : Icons.cable_rounded,
                  color: widget.device.isBlocked ? AppTheme.danger : accent,
                  size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.device.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis),
                  Text(widget.device.ip,
                    style: Theme.of(context).textTheme.bodySmall),
                  GestureDetector(
                    onTap: () => Clipboard.setData(
                      ClipboardData(text: widget.device.mac)),
                    child: Text(widget.device.mac,
                      style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: accent.withOpacity(0.7))),
                  ),
                ],
              )),
              // Block/Unblock icon button with confirmation
              Consumer(builder: (_, ref2, __) => IconButton(
                icon: Icon(
                  widget.device.isBlocked
                    ? Icons.lock_open_rounded : Icons.block_rounded,
                  color: widget.device.isBlocked
                    ? AppTheme.success : AppTheme.danger),
                tooltip: widget.device.isBlocked ? 'Unblock' : 'Block',
                onPressed: () => _confirmBlock(context, ref2),
              )),
              // Rename icon button
              Consumer(builder: (_, ref2, __) => IconButton(
                icon: Icon(Icons.edit_rounded, color: c.textMuted),
                tooltip: 'Rename',
                onPressed: () => _rename(context, ref2),
              )),
            ]),
          ),

          // Tabs
          TabBar(
            controller: _tab,
            indicatorColor: accent,
            labelColor: accent,
            unselectedLabelColor: c.textMuted,
            tabs: const [
              Tab(icon: Icon(Icons.router_rounded, size: 18), text: 'Connections'),
              Tab(icon: Icon(Icons.speed_rounded, size: 18), text: 'Bandwidth'),
            ],
          ),

          Expanded(child: TabBarView(
            controller: _tab,
            children: [
              _connsTab(c, accent, scroll),
              _bwTab(c, accent),
            ],
          )),
        ]),
      ),
    );
  }

  Widget _connsTab(AppColors c, Color accent, ScrollController scroll) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          Text('Active Connections',
            style: TextStyle(fontSize: 13, color: c.textSecondary,
              fontWeight: FontWeight.w500)),
          const Spacer(),
          if (!_loadingConns)
            Text('${_conns.length}',
              style: TextStyle(fontSize: 12, color: c.textMuted)),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.refresh_rounded, size: 18, color: accent),
            onPressed: _loadConns, padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ]),
      ),
      Expanded(child: (_loadingConns && _conns.isEmpty)
        ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
        : _connError
          ? _empty(Icons.error_outline_rounded,
              'Could not fetch connections.\nMake sure conntrack is available.', c)
          : _conns.isEmpty
            ? _empty(Icons.wifi_off_rounded,
                'No active connections.\nDevice may be idle or sleeping.', c)
            : ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                itemCount: _conns.length,
                itemBuilder: (_, i) => _ConnTile(conn: _conns[i], accent: accent, c: c),
              )),
    ],
  );

  Widget _bwTab(AppColors c, Color accent) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
    children: [
      // Current status
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface, borderRadius: BorderRadius.circular(12)),
        child: _bwLoading
          ? const SizedBox(height: 32,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Limit',
                    style: TextStyle(fontSize: 11, color: c.textMuted)),
                  const SizedBox(height: 4),
                  Text(
                    _dlLimit == 0 && _ulLimit == 0 ? 'Unlimited'
                      : 'DL: ${_fmt(_dlLimit)}  /  UL: ${_fmt(_ulLimit)}',
                    style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600,
                      color: _dlLimit == 0 && _ulLimit == 0
                        ? AppTheme.success : accent)),
                ],
              )),
              Icon(
                _dlLimit == 0 && _ulLimit == 0
                  ? Icons.all_inclusive_rounded : Icons.speed_rounded,
                color: _dlLimit == 0 && _ulLimit == 0
                  ? AppTheme.success : accent, size: 26),
            ]),
      ),
      const SizedBox(height: 20),

      Text('Set Limit', style: TextStyle(fontSize: 13,
        color: c.textSecondary, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text('0 = no limit. Values in Kbps (1000 Kbps = 1 Mbps)',
        style: TextStyle(fontSize: 12, color: c.textMuted)),
      const SizedBox(height: 14),

      _bwField('Download Limit (Kbps)', 'e.g. 5120 = 5 Mbps', _dlCtrl,
        Icons.download_rounded, c),
      const SizedBox(height: 10),
      _bwField('Upload Limit (Kbps)', 'e.g. 1024 = 1 Mbps', _ulCtrl,
        Icons.upload_rounded, c),
      const SizedBox(height: 12),

      // Quick presets
      Text('Quick presets:', style: TextStyle(fontSize: 12, color: c.textMuted)),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, children: [
        _preset('1 Mbps',  1024,  512,  accent),
        _preset('2 Mbps',  2048,  1024, accent),
        _preset('5 Mbps',  5120,  2048, accent),
        _preset('10 Mbps', 10240, 5120, accent),
        _preset('Unlimited', 0, 0, AppTheme.success),
      ]),
      const SizedBox(height: 16),

      if (_bwMsg != null)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (_bwMsg!.startsWith('Error') || _bwMsg!.contains('failed'))
              ? AppTheme.danger.withOpacity(0.1) : AppTheme.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (_bwMsg!.startsWith('Error') || _bwMsg!.contains('failed'))
                ? AppTheme.danger : AppTheme.success),
          ),
          child: Text(_bwMsg!, style: TextStyle(fontSize: 12,
            color: (_bwMsg!.startsWith('Error') || _bwMsg!.contains('failed'))
              ? AppTheme.danger : AppTheme.success)),
        ),

      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: _bwSaving
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save_rounded, color: Colors.white),
          label: Text(_bwSaving ? 'Saving...' : 'Apply Limit',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: accent),
          onPressed: _bwSaving ? null : _saveBw,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        'Note: Requires QoS to be enabled on the router.',
        style: TextStyle(fontSize: 11, color: c.textMuted),
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _bwField(String label, String hint, TextEditingController ctrl,
      IconData icon, AppColors c) => TextField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    style: const TextStyle(fontSize: 14),
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      labelStyle: TextStyle(color: c.textMuted, fontSize: 13),
      hintStyle: TextStyle(color: c.textMuted.withOpacity(0.5), fontSize: 12),
      prefixIcon: Icon(icon, size: 18),
      filled: true, fillColor: c.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );

  Widget _preset(String label, int dl, int ul, Color color) => GestureDetector(
    onTap: () => setState(() {
      _dlCtrl.text = dl > 0 ? dl.toString() : '';
      _ulCtrl.text = ul > 0 ? ul.toString() : '';
    }),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 12, color: color, fontWeight: FontWeight.w500)),
    ),
  );

  Widget _empty(IconData icon, String msg, AppColors c) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 40, color: c.textMuted),
      const SizedBox(height: 12),
      Text(msg, style: TextStyle(color: c.textMuted, fontSize: 13),
        textAlign: TextAlign.center),
    ]),
  );

  String _fmt(int kbps) {
    if (kbps == 0) return '0';
    if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(1)} Mbps';
    return '${kbps} Kbps';
  }

  void _confirmBlock(BuildContext context, WidgetRef ref) async {
    final isBlocked = widget.device.isBlocked;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isBlocked ? 'Unblock Device?' : 'Block Internet Access?'),
        content: Text(
          isBlocked
            ? 'Allow ${widget.device.displayName} to access the internet again?'
            : 'Block internet access for ${widget.device.displayName}?\n\n'
              'They will stay connected to WiFi but cannot reach the internet.',
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isBlocked ? AppTheme.success : AppTheme.danger),
              onPressed: () => Navigator.pop(context, true),
              child: Text(isBlocked ? 'Unblock' : 'Block Internet',
                style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w600)),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await ref.read(devicesProvider.notifier).toggleBlock(widget.device.mac);
      if (context.mounted) Navigator.pop(context);
    }
  }

  void _rename(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: widget.device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename Device'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Enter device name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Save')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await ref.read(devicesProvider.notifier).renameDevice(widget.device.mac, name);
    }
  }
}

// ── Connection Tile ─────────────────────────────────────────────────────────
class _ConnTile extends StatelessWidget {
  final Map<String, dynamic> conn;
  final Color accent;
  final AppColors c;
  const _ConnTile({required this.conn, required this.accent, required this.c});

  @override
  Widget build(BuildContext context) {
    final proto = conn['proto'] as String? ?? '?';
    final dst   = conn['dst']   as String? ?? '?';
    final dport = conn['dport'] as int?   ?? 0;
    final state = conn['state'] as String? ?? '';
    final rxB   = conn['rxBytes'] as int? ?? 0;
    final pname = _portName(dport);
    final known = pname != dport.toString();
    final stCol = _stateColor(state);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border.withOpacity(0.4)),
      ),
      child: Row(children: [
        // Proto badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: proto == 'TCP'
              ? accent.withOpacity(0.12)
              : AppTheme.warning.withOpacity(0.12),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(proto, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: proto == 'TCP' ? accent : AppTheme.warning)),
        ),
        const SizedBox(width: 10),

        // Destination info
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dst, style: TextStyle(
              fontSize: 13, color: c.textPrimary, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis),
            Row(children: [
              Text(known ? pname : ':$dport',
                style: TextStyle(fontSize: 11,
                  color: known ? accent : c.textMuted,
                  fontWeight: known ? FontWeight.w600 : FontWeight.w400)),
              if (rxB > 0) ...[
                Text('  |  ', style: TextStyle(color: c.textMuted, fontSize: 11)),
                Text(_fmtB(rxB), style: TextStyle(fontSize: 11, color: c.textMuted)),
              ],
            ]),
          ],
        )),

        // State badge
        if (state.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: stCol.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
            child: Text(
              state == 'ESTABLISHED' ? 'LIVE'
                : state == 'TIME_WAIT' ? 'WAIT' : state,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: stCol)),
          ),
      ]),
    );
  }

  String _fmtB(int b) {
    if (b > 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    if (b > 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '$b B';
  }
}

// ── Filter Chip ─────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label, value, current;
  final ValueChanged<String> onTap;
  const _FilterChip({required this.label, required this.value,
    required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent
            : Theme.of(context).extension<AppColors>()!.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : AppTheme.border),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? Colors.white : AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        )),
      ),
    );
  }
}

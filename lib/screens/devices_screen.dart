import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/ssh_service.dart';
import '../models/models.dart';

String _portName(int port) {
  const names = {80:'HTTP',443:'HTTPS',53:'DNS',22:'SSH',21:'FTP',25:'SMTP',
    587:'SMTP',993:'IMAP',995:'POP3',8080:'HTTP-Alt',8443:'HTTPS-Alt',
    123:'NTP',853:'DNS-TLS',5228:'FCM',5229:'FCM',3478:'STUN',3479:'STUN'};
  return names[port] ?? port.toString();
}

Color _stateColor(String state) {
  if (state == 'ESTABLISHED') return AppTheme.success;
  if (state == 'TIME_WAIT') return AppTheme.warning;
  if (state == 'SYN_SENT') return AppTheme.info;
  return AppTheme.darkTxtSec;
}

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
    final c   = Theme.of(context).extension<AppColors>()!;
    final filtered = all.where((d) {
      final ms = _search.isEmpty ||
        d.displayName.toLowerCase().contains(_search.toLowerCase()) ||
        d.ip.contains(_search) ||
        d.mac.toLowerCase().contains(_search.toLowerCase());
      final mf = _filter == 'all' ||
        (_filter == 'wifi' && d.isWireless) ||
        (_filter == 'wired' && !d.isWireless) ||
        (_filter == 'blocked' && d.isBlocked);
      return ms && mf;
    }).toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return Scaffold(
      backgroundColor: c.background,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          floating: true, snap: true,
          backgroundColor: c.surface,
          toolbarHeight: 56,
          title: Row(children: [
            Text('Devices', style: GoogleFonts.spaceGrotesk(
              fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${all.length}', style: GoogleFonts.jetBrainsMono(
                fontSize: 11, fontWeight: FontWeight.w700, color: c.accent)),
            ),
          ]),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(96),
            child: Column(children: [
              Divider(height: 1, color: c.border),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: GoogleFonts.spaceGrotesk(fontSize: 13, color: c.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search name, IP, MAC...',
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: c.textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: Row(children: [
                  _Chip('All', 'all', _filter, all.length, c, (v) => setState(() => _filter = v)),
                  const SizedBox(width: 6),
                  _Chip('WiFi', 'wifi', _filter, all.where((d) => d.isWireless).length, c, (v) => setState(() => _filter = v)),
                  const SizedBox(width: 6),
                  _Chip('Wired', 'wired', _filter, all.where((d) => !d.isWireless).length, c, (v) => setState(() => _filter = v)),
                  const SizedBox(width: 6),
                  _Chip('Blocked', 'blocked', _filter, all.where((d) => d.isBlocked).length, c, (v) => setState(() => _filter = v), color: AppTheme.danger),
                ]),
              ),
            ]),
          ),
        ),

        filtered.isEmpty
          ? SliverFillRemaining(child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.devices_rounded, size: 48, color: c.textMuted),
                const SizedBox(height: 12),
                Text('No devices', style: GoogleFonts.spaceGrotesk(
                  fontSize: 14, color: c.textMuted)),
              ],
            )))
          : SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 80),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => _DeviceTile(device: filtered[i], c: c),
                childCount: filtered.length,
              )),
            ),
      ]),
    );
  }
}

Widget _Chip(String label, String value, String current, int count, AppColors c, ValueChanged<String> onTap, {Color? color}) {
  final selected = value == current;
  final col = color ?? c.accent;
  return GestureDetector(
    onTap: () => onTap(value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? col.withOpacity(0.12) : c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? col.withOpacity(0.5) : c.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: GoogleFonts.spaceGrotesk(
          fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? col : c.textSecondary)),
        const SizedBox(width: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: selected ? col.withOpacity(0.18) : c.card2,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('$count', style: GoogleFonts.jetBrainsMono(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: selected ? col : c.textMuted)),
        ),
      ]),
    ),
  );
}

class _DeviceTile extends StatelessWidget {
  final ConnectedDevice device;
  final AppColors c;
  const _DeviceTile({required this.device, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: device.isBlocked ? AppTheme.danger.withOpacity(0.3) : c.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: device.isBlocked
              ? AppTheme.danger.withOpacity(0.10)
              : device.isWireless
                ? AppTheme.success.withOpacity(0.10)
                : AppTheme.info.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            device.isBlocked ? Icons.block_rounded
              : device.isWireless ? Icons.wifi_rounded : Icons.cable_rounded,
            size: 18,
            color: device.isBlocked ? AppTheme.danger
              : device.isWireless ? AppTheme.success : AppTheme.info,
          ),
        ),
        title: Row(children: [
          Expanded(child: Text(device.displayName,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: device.isBlocked ? AppTheme.danger : c.textPrimary),
            overflow: TextOverflow.ellipsis)),
          if (device.isBlocked)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.10),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('BLOCKED', style: GoogleFonts.spaceGrotesk(
                fontSize: 8, fontWeight: FontWeight.w800, color: AppTheme.danger, letterSpacing: 0.5)),
            ),
        ]),
        subtitle: Row(children: [
          Text(device.ip, style: GoogleFonts.jetBrainsMono(fontSize: 11, color: c.textMuted)),
          const SizedBox(width: 8),
          if (device.rssi.isNotEmpty)
            Text('${device.rssi} dBm', style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: c.textMuted)),
        ]),
        trailing: Icon(Icons.chevron_right_rounded, size: 18, color: c.textMuted),
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => _DeviceDetailScreen(device: device))),
      ),
    );
  }
}

// ── Device Detail ──────────────────────────────────────────────────────────────
class _DeviceDetailScreen extends ConsumerStatefulWidget {
  final ConnectedDevice device;
  const _DeviceDetailScreen({required this.device});
  @override
  ConsumerState<_DeviceDetailScreen> createState() => _DeviceDetailState();
}

class _DeviceDetailState extends ConsumerState<_DeviceDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _nameCtrl = TextEditingController();
  List<Map<String, dynamic>> _conns = [];
  bool _loadingConns = true;
  bool _connError = false;
  int _dlLimit = 0, _ulLimit = 0;
  bool _bwLoading = false, _bwSaving = false;
  final _dlCtrl = TextEditingController();
  final _ulCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _nameCtrl.text = widget.device.displayName;
    _loadConns();
    _loadBw();
    _tab.addListener(() { if (_tab.index == 0) _loadConns(); });
  }

  @override
  void dispose() { _tab.dispose(); _nameCtrl.dispose(); _dlCtrl.dispose(); _ulCtrl.dispose(); super.dispose(); }

  Future<void> _loadConns() async {
    final ssh = ref.read(sshServiceProvider);
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
    setState(() => _bwSaving = true);
    try {
      final dl = int.tryParse(_dlCtrl.text) ?? 0;
      final ul = int.tryParse(_ulCtrl.text) ?? 0;
      await ssh.setDeviceBandwidth(widget.device.ip, dl, ul);
      if (mounted) setState(() { _dlLimit = dl; _ulLimit = ul; _bwSaving = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bandwidth limit saved')));
    } catch (e) {
      if (mounted) setState(() => _bwSaving = false);
    }
  }

  Future<void> _toggleBlock() async {
    await ref.read(devicesProvider.notifier).toggleBlock(widget.device.mac);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _rename() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(devicesProvider.notifier).renameDevice(widget.device.mac, name);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Device renamed')));
  }

  String _fmt(int kbps) {
    if (kbps == 0) return 'Unlimited';
    if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(1)} Mbps';
    return '$kbps Kbps';
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Text(widget.device.displayName, style: GoogleFonts.spaceGrotesk(
          fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
        bottom: TabBar(
          controller: _tab,
          labelColor: c.accent,
          unselectedLabelColor: c.textMuted,
          indicatorColor: c.accent,
          indicatorWeight: 2,
          labelStyle: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w700),
          tabs: const [Tab(text: 'Connections'), Tab(text: 'Settings')],
        ),
        actions: [
          IconButton(
            icon: Icon(widget.device.isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
              color: widget.device.isBlocked ? AppTheme.success : AppTheme.danger),
            onPressed: _toggleBlock,
          ),
        ],
      ),
      body: TabBarView(controller: _tab, children: [
        _connsTab(c),
        _settingsTab(c),
      ]),
    );
  }

  Widget _connsTab(AppColors c) => Column(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: c.surface,
      child: Row(children: [
        Text('Active Connections', style: GoogleFonts.spaceGrotesk(
          fontSize: 12, fontWeight: FontWeight.w600, color: c.textSecondary)),
        if (!_loadingConns)
          Container(margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: c.card2, borderRadius: BorderRadius.circular(5)),
            child: Text('${_conns.length}', style: GoogleFonts.jetBrainsMono(
              fontSize: 10, color: c.accent))),
        const Spacer(),
        InkWell(onTap: _loadConns,
          child: Icon(Icons.refresh_rounded, size: 16, color: c.accent)),
      ]),
    ),
    Expanded(child: (_loadingConns && _conns.isEmpty)
      ? Center(child: CircularProgressIndicator(color: c.accent, strokeWidth: 2))
      : _connError
        ? Center(child: Text('Could not load connections', style: GoogleFonts.spaceGrotesk(color: c.textMuted)))
        : _conns.isEmpty
          ? Center(child: Text('No active connections', style: GoogleFonts.spaceGrotesk(color: c.textMuted)))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 32),
              itemCount: _conns.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: c.border),
              itemBuilder: (_, i) => _ConnRow(conn: _conns[i], c: c),
            )),
  ]);

  Widget _settingsTab(AppColors c) => ListView(
    padding: const EdgeInsets.all(14),
    children: [
      // Info card
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
        child: Column(children: [
          _InfoRow2('MAC', widget.device.mac, c),
          Divider(height: 14, color: c.border),
          _InfoRow2('IP', widget.device.ip, c),
          Divider(height: 14, color: c.border),
          _InfoRow2('Interface', widget.device.interface, c),
          if (widget.device.rssi.isNotEmpty) ...[
            Divider(height: 14, color: c.border),
            _InfoRow2('Signal', '${widget.device.rssi} dBm', c),
          ],
        ]),
      ),
      const SizedBox(height: 14),

      // Rename
      Text('NAME', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w700,
        color: c.textMuted, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: TextField(
          controller: _nameCtrl,
          style: GoogleFonts.spaceGrotesk(fontSize: 13, color: c.textPrimary),
          decoration: const InputDecoration(hintText: 'Device name'),
        )),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _rename,
          style: ElevatedButton.styleFrom(minimumSize: const Size(70, 44)),
          child: Text('Save', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: 14),

      // Bandwidth
      Text('BANDWIDTH LIMIT', style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w700,
        color: c.textMuted, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      if (_bwLoading)
        const Center(child: CircularProgressIndicator(strokeWidth: 2))
      else
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
          child: Column(children: [
            Row(children: [
              Text('Current: ', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: c.textMuted)),
              Text('DL ${_fmt(_dlLimit)}  UL ${_fmt(_ulLimit)}',
                style: GoogleFonts.jetBrainsMono(fontSize: 12, color: c.accent)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _dlCtrl, keyboardType: TextInputType.number,
                style: GoogleFonts.jetBrainsMono(fontSize: 13),
                decoration: const InputDecoration(labelText: 'DL Kbps (0=∞)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _ulCtrl, keyboardType: TextInputType.number,
                style: GoogleFonts.jetBrainsMono(fontSize: 13),
                decoration: const InputDecoration(labelText: 'UL Kbps (0=∞)'))),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _bwSaving ? null : _saveBw,
                child: _bwSaving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text('Apply Limit', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
    ],
  );
}

class _ConnRow extends StatelessWidget {
  final Map<String, dynamic> conn;
  final AppColors c;
  const _ConnRow({required this.conn, required this.c});

  @override
  Widget build(BuildContext context) {
    final proto = conn['proto'] ?? '';
    final state = conn['state'] ?? '';
    final src = conn['src'] ?? '';
    final dst = conn['dst'] ?? '';
    final dport = int.tryParse(conn['dport']?.toString() ?? '') ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: c.card2, borderRadius: BorderRadius.circular(4),
            border: Border.all(color: c.border),
          ),
          child: Text(proto.toUpperCase(), style: GoogleFonts.jetBrainsMono(
            fontSize: 9, fontWeight: FontWeight.w700, color: c.textSecondary)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$src → $dst', style: GoogleFonts.jetBrainsMono(
            fontSize: 10, color: c.textSecondary), overflow: TextOverflow.ellipsis),
          Text(_portName(dport), style: GoogleFonts.spaceGrotesk(
            fontSize: 10, color: c.textMuted)),
        ])),
        if (state.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _stateColor(state).withOpacity(0.10),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(state, style: GoogleFonts.spaceGrotesk(
              fontSize: 8, fontWeight: FontWeight.w700, color: _stateColor(state))),
          ),
      ]),
    );
  }
}

Widget _InfoRow2(String label, String value, AppColors c) => Row(children: [
  Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: c.textSecondary)),
  const Spacer(),
  GestureDetector(
    onLongPress: () => Clipboard.setData(ClipboardData(text: value)),
    child: Text(value, style: GoogleFonts.jetBrainsMono(
      fontSize: 12, fontWeight: FontWeight.w500, color: c.textPrimary)),
  ),
]);

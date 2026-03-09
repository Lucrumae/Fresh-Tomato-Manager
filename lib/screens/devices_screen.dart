import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});
  @override ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}
class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  String _q = ''; String _filter = 'all';

  @override Widget build(BuildContext context) {
    final all = ref.watch(devicesProvider);
    final v = Theme.of(context).extension<VC>()!;
    final filtered = all.where((d) {
      if (_q.isNotEmpty) {
        final q = _q.toLowerCase();
        if (!d.displayName.toLowerCase().contains(q) &&
            !d.ip.contains(q) && !d.mac.contains(q)) return false;
      }
      return _filter == 'all' || (_filter=='wifi' && d.isWireless) ||
        (_filter=='lan' && !d.isWireless) || (_filter=='blocked' && d.isBlocked);
    }).toList()..sort((a,b) => a.displayName.compareTo(b.displayName));

    return Scaffold(
      backgroundColor: v.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true, backgroundColor: v.dark ? V.d0 : V.l2, toolbarHeight: 52,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              color: v.dark ? V.d0 : V.l2,
              border: Border(bottom: BorderSide(color: v.wire)))),
          title: Row(children: [
            Text('NODES', style: GoogleFonts.outfit(fontSize: 14,
              fontWeight: FontWeight.w900, color: v.hi, letterSpacing: 1.5)),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: v.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6)),
              child: Text('${all.length}', style: GoogleFonts.dmMono(fontSize: 10,
                fontWeight: FontWeight.w700, color: v.accent))),
          ]),
          bottom: PreferredSize(preferredSize: const Size.fromHeight(90), child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: TextField(
              onChanged: (x) => setState(() => _q = x),
              style: GoogleFonts.dmMono(fontSize: 12, color: v.hi),
              decoration: InputDecoration(
                hintText: 'search name · ip · mac',
                isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 10),
                prefixIcon: Icon(Icons.search_rounded, size: 16, color: v.lo)),
            )),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
              child: Row(children: [
                _FC('ALL',     'all',     all.length,               null, v),
                const SizedBox(width: 6),
                _FC('WIFI',    'wifi',    all.where((d)=>d.isWireless).length,  V.ok, v),
                const SizedBox(width: 6),
                _FC('LAN',     'lan',     all.where((d)=>!d.isWireless).length, V.info, v),
                const SizedBox(width: 6),
                _FC('BLOCKED', 'blocked', all.where((d)=>d.isBlocked).length,   V.err, v),
              ]),
            ),
          ])),
        ),

        filtered.isEmpty
          ? SliverFillRemaining(child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.device_unknown_rounded, size: 48, color: v.lo),
                const SizedBox(height: 10),
                Text('no nodes found', style: GoogleFonts.dmMono(fontSize: 12, color: v.lo)),
              ])))
          : SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => _NodeTile(dev: filtered[i], v: v),
                childCount: filtered.length))),
      ]),
    );
  }

  Widget _FC(String lbl, String key, int n, Color? col, VC v) {
    final sel = _filter == key;
    final a = col ?? v.accent;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: AnimatedContainer(duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: sel ? a.withOpacity(0.08) : v.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? a.withOpacity(0.35) : v.wire)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(lbl, style: GoogleFonts.outfit(fontSize: 9,
            fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
            color: sel ? a : v.lo, letterSpacing: 0.6)),
          const SizedBox(width: 5),
          Text('$n', style: GoogleFonts.dmMono(fontSize: 9,
            color: sel ? a : v.lo)),
        ])),
    );
  }
}

class _NodeTile extends StatelessWidget {
  final ConnectedDevice dev; final VC v;
  const _NodeTile({required this.dev, required this.v});
  @override Widget build(BuildContext context) {
    final acl = dev.isBlocked ? V.err : dev.isWireless ? V.ok : V.info;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: v.panel, borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: acl, width: 2),
          top: BorderSide(color: v.wire), right: BorderSide(color: v.wire),
          bottom: BorderSide(color: v.wire))),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        leading: Container(width: 36, height: 36,
          decoration: BoxDecoration(color: acl.withOpacity(0.07),
            borderRadius: BorderRadius.circular(9)),
          child: Icon(dev.isBlocked ? Icons.block_rounded : dev.isWireless
            ? Icons.wifi_rounded : Icons.cable_rounded, size: 16, color: acl)),
        title: Row(children: [
          Expanded(child: Text(dev.displayName, style: GoogleFonts.outfit(fontSize: 13,
            fontWeight: FontWeight.w700, color: dev.isBlocked ? V.err : v.hi),
            overflow: TextOverflow.ellipsis)),
          if (dev.isBlocked) Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(color: V.err.withOpacity(0.08),
              borderRadius: BorderRadius.circular(4)),
            child: Text('BLOCKED', style: GoogleFonts.outfit(fontSize: 8,
              fontWeight: FontWeight.w800, color: V.err, letterSpacing: 0.5))),
        ]),
        subtitle: Text(dev.ip, style: GoogleFonts.dmMono(fontSize: 10, color: v.lo)),
        trailing: Icon(Icons.chevron_right_rounded, size: 15, color: v.lo),
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => _NodeDetail(dev: dev))),
      ),
    );
  }
}

// ── Node Detail ───────────────────────────────────────────────────────────────
class _NodeDetail extends ConsumerStatefulWidget {
  final ConnectedDevice dev;
  const _NodeDetail({required this.dev});
  @override ConsumerState<_NodeDetail> createState() => _NodeDetailState();
}
class _NodeDetailState extends ConsumerState<_NodeDetail> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _nameCtrl = TextEditingController();
  final _dlCtrl = TextEditingController(); final _ulCtrl = TextEditingController();
  List<Map<String,dynamic>> _conns = []; bool _loadingConns = true; bool _bwSaving = false;

  @override void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _nameCtrl.text = widget.dev.displayName;
    _loadConns(); _loadBw();
  }
  @override void dispose() { _tab.dispose(); _nameCtrl.dispose(); _dlCtrl.dispose(); _ulCtrl.dispose(); super.dispose(); }

  Future<void> _loadConns() async {
    final ssh = ref.read(sshServiceProvider);
    setState(() => _loadingConns = true);
    try { final r = await ssh.getDeviceConnections(widget.dev.ip);
      if (mounted) setState(() { _conns = r; _loadingConns = false; });
    } catch(_) { if (mounted) setState(() => _loadingConns = false); }
  }
  Future<void> _loadBw() async {
    final ssh = ref.read(sshServiceProvider);
    try {
      final bw = await ssh.getDeviceBandwidth(widget.dev.ip);
      if (mounted) setState(() {
        _dlCtrl.text = (bw['dl']??0)>0 ? '${bw['dl']}' : '';
        _ulCtrl.text = (bw['ul']??0)>0 ? '${bw['ul']}' : '';
      });
    } catch(_) {}
  }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Scaffold(
      backgroundColor: v.bg,
      appBar: AppBar(
        backgroundColor: v.dark ? V.d0 : V.l2,
        title: Text(widget.dev.displayName, style: GoogleFonts.outfit(fontSize: 14,
          fontWeight: FontWeight.w700, color: v.hi)),
        actions: [
          IconButton(
            icon: Icon(widget.dev.isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
              color: widget.dev.isBlocked ? V.ok : V.err, size: 20),
            onPressed: () async {
              await ref.read(devicesProvider.notifier).toggleBlock(widget.dev.mac);
              if (mounted) Navigator.pop(context);
            }),
        ],
        bottom: TabBar(controller: _tab,
          tabs: const [Tab(text: 'Connections'), Tab(text: 'Settings')]),
      ),
      body: TabBarView(controller: _tab, children: [
        // Connections tab
        Column(children: [
          Container(color: v.panel, padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Row(children: [
              Text('ACTIVE', style: GoogleFonts.outfit(fontSize: 10,
                fontWeight: FontWeight.w700, color: v.lo, letterSpacing: 1.3)),
              if (!_loadingConns) ...[const SizedBox(width: 8),
                Badge('${_conns.length}')],
              const Spacer(),
              GestureDetector(onTap: _loadConns,
                child: Icon(Icons.refresh_rounded, size: 16, color: v.accent)),
            ])),
          Divider(height: 1, color: v.wire),
          Expanded(child: _loadingConns && _conns.isEmpty
            ? Center(child: CircularProgressIndicator(color: v.accent, strokeWidth: 2))
            : _conns.isEmpty
              ? Center(child: Text('no connections', style: GoogleFonts.dmMono(fontSize: 11, color: v.lo)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  itemCount: _conns.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: v.wire),
                  itemBuilder: (_, i) {
                    final c = _conns[i];
                    final st = c['state'] ?? '';
                    Color sc() {
                      if (st == 'ESTABLISHED') return V.ok;
                      if (st == 'TIME_WAIT')   return V.warn;
                      return v.lo;
                    }
                    return Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: v.elevated,
                            borderRadius: BorderRadius.circular(4), border: Border.all(color: v.wire)),
                          child: Text('${c['proto']}', style: GoogleFonts.dmMono(fontSize: 9,
                            fontWeight: FontWeight.w700, color: v.mid))),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${c['dst']}', style: GoogleFonts.dmMono(fontSize: 10, color: v.mid),
                            overflow: TextOverflow.ellipsis),
                          Text(':${c['dport']}', style: GoogleFonts.dmMono(fontSize: 9, color: v.lo)),
                        ])),
                        if (st.isNotEmpty) Badge(st, color: sc()),
                      ]));
                  })),
        ]),
        // Settings tab
        ListView(padding: const EdgeInsets.all(14), children: [
          // Info block
          Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: v.panel, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: v.wire)),
            child: Column(children: [
              _InfoRow('MAC', widget.dev.mac, v),
              Divider(height: 12, color: v.wire),
              _InfoRow('IP', widget.dev.ip, v),
              Divider(height: 12, color: v.wire),
              _InfoRow('Interface', widget.dev.interface, v),
              if (widget.dev.rssi.isNotEmpty) ...[
                Divider(height: 12, color: v.wire),
                _InfoRow('Signal', '${widget.dev.rssi} dBm', v),
              ],
            ])),
          const SizedBox(height: 14),
          Text('RENAME', style: GoogleFonts.outfit(fontSize: 10,
            fontWeight: FontWeight.w700, color: v.lo, letterSpacing: 1.4)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _nameCtrl,
              style: GoogleFonts.dmMono(fontSize: 13),
              decoration: const InputDecoration(hintText: 'device label'))),
            const SizedBox(width: 8),
            SizedBox(width: 70, child: ElevatedButton(
              onPressed: () async {
                await ref.read(devicesProvider.notifier)
                  .renameDevice(widget.dev.mac, _nameCtrl.text.trim());
                if (mounted) ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Saved')));
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(70, 46)),
              child: Text('OK', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)))),
          ]),
          const SizedBox(height: 16),
          Text('BANDWIDTH LIMIT', style: GoogleFonts.outfit(fontSize: 10,
            fontWeight: FontWeight.w700, color: v.lo, letterSpacing: 1.4)),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: v.panel, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: v.wire)),
            child: Column(children: [
              Row(children: [
                Expanded(child: TextField(controller: _dlCtrl, keyboardType: TextInputType.number,
                  style: GoogleFonts.dmMono(fontSize: 13),
                  decoration: const InputDecoration(labelText: 'DL Kbps'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _ulCtrl, keyboardType: TextInputType.number,
                  style: GoogleFonts.dmMono(fontSize: 13),
                  decoration: const InputDecoration(labelText: 'UL Kbps'))),
              ]),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _bwSaving ? null : () async {
                  setState(() => _bwSaving = true);
                  await ref.read(sshServiceProvider).setDeviceBandwidth(
                    widget.dev.ip,
                    int.tryParse(_dlCtrl.text) ?? 0,
                    int.tryParse(_ulCtrl.text) ?? 0);
                  if (mounted) setState(() => _bwSaving = false);
                  if (mounted) ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Applied')));
                },
                child: _bwSaving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text('APPLY', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)))),
            ])),
        ]),
      ]),
    );
  }
}

Widget _InfoRow(String lbl, String val, VC v) => Row(children: [
  Text(lbl, style: GoogleFonts.outfit(fontSize: 11, color: v.mid)),
  const Spacer(),
  GestureDetector(
    onLongPress: () => Clipboard.setData(ClipboardData(text: val)),
    child: Text(val, style: GoogleFonts.dmMono(fontSize: 11,
      fontWeight: FontWeight.w500, color: v.hi))),
]);

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override Widget build(BuildContext context, WidgetRef ref) {
    final st  = ref.watch(routerStatusProvider);
    final bw  = ref.watch(bandwidthProvider);
    final dev = ref.watch(devicesProvider);
    final v   = Theme.of(context).extension<VC>()!;

    return Scaffold(
      backgroundColor: v.bg,
      body: CustomScrollView(slivers: [
        // ─── AppBar ───────────────────────────────────────────────────────
        SliverAppBar(
          pinned: true,
          backgroundColor: v.dark ? V.d0 : V.l2,
          toolbarHeight: 52,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              color: v.dark ? V.d0 : V.l2,
              border: Border(bottom: BorderSide(color: v.wire)),
            ),
          ),
          title: Row(children: [
            // status dot + model
            Dot(color: st.isOnline ? V.ok : V.err, size: 8),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('VOID', style: GoogleFonts.outfit(fontSize: 14,
                fontWeight: FontWeight.w900, color: v.hi, letterSpacing: 2)),
              Text(st.isOnline ? st.routerModel : 'DISCONNECTED',
                style: GoogleFonts.dmMono(fontSize: 9, color: v.mid),
                overflow: TextOverflow.ellipsis),
            ]),
          ]),
          actions: [
            // WAN IP quick-view
            Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: v.panel,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: v.wire),
              ),
              child: Text(st.wanIp, style: GoogleFonts.dmMono(fontSize: 11, color: v.mid)),
            ),
          ],
        ),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
          sliver: SliverList(delegate: SliverChildListDelegate([

            // ── ROW 1: CPU + RAM ─────────────────────────────────────────
            IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: _MetricTile(
                label: 'CPU', value: st.cpuUsage,
                percent: st.cpuPercent / 100,
                sub: st.cpuTempC > 0 ? st.cpuTemp : '—',
                v: v,
              )),
              const SizedBox(width: 8),
              Expanded(child: _MetricTile(
                label: 'RAM', value: st.ramUsage,
                percent: st.ramPercent / 100,
                sub: '/ ${st.ramTotal}',
                v: v,
              )),
            ])),
            const SizedBox(height: 8),

            // ── ROW 2: BW live ───────────────────────────────────────────
            _BandwidthTile(bw: bw, v: v),
            const SizedBox(height: 8),

            // ── ROW 3: Device counts ─────────────────────────────────────
            Row(children: [
              Expanded(child: _CountBox(
                n: dev.length, label: 'TOTAL',
                icon: Icons.devices_other_rounded, color: v.accent, v: v)),
              const SizedBox(width: 6),
              Expanded(child: _CountBox(
                n: dev.where((d) => d.isWireless).length, label: 'WIFI',
                icon: Icons.wifi_rounded, color: V.ok, v: v)),
              const SizedBox(width: 6),
              Expanded(child: _CountBox(
                n: dev.where((d) => !d.isWireless).length, label: 'LAN',
                icon: Icons.cable_rounded, color: V.info, v: v)),
              const SizedBox(width: 6),
              Expanded(child: _CountBox(
                n: dev.where((d) => d.isBlocked).length, label: 'BLOCK',
                icon: Icons.block_rounded, color: V.err, v: v)),
            ]),
            const SizedBox(height: 8),

            // ── ROW 4: Network overview ──────────────────────────────────
            _NetworkTile(st: st, v: v),
            const SizedBox(height: 8),

            // ── ROW 5: Ethernet ports ────────────────────────────────────
            _PortsTile(v: v),
            const SizedBox(height: 8),

            // ── ROW 6: Footer strip ──────────────────────────────────────
            _FooterStrip(st: st, v: v),

          ])),
        ),
      ]),
    );
  }
}

// ── CPU / RAM metric tile ─────────────────────────────────────────────────────
class _MetricTile extends StatelessWidget {
  final String label, value, sub;
  final double percent;
  final VC v;
  const _MetricTile({required this.label, required this.value,
    required this.percent, required this.sub, required this.v});

  Color _barColor(double p) => p > .8 ? V.err : p > .6 ? V.warn : V.ok;

  @override Widget build(BuildContext context) {
    final bar = _barColor(percent);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: v.panel,
        border: Border.all(color: v.wire),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: GoogleFonts.outfit(fontSize: 10,
            fontWeight: FontWeight.w700, color: v.lo, letterSpacing: 1.4)),
          const Spacer(),
          Text(sub, style: GoogleFonts.dmMono(fontSize: 10, color: v.mid)),
        ]),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.dmMono(fontSize: 26,
          fontWeight: FontWeight.w700, color: bar)),
        const SizedBox(height: 10),
        // Raw bar
        Stack(children: [
          Container(height: 3,
            decoration: BoxDecoration(color: v.wire2,
              borderRadius: BorderRadius.circular(2))),
          FractionallySizedBox(widthFactor: percent.clamp(0.0, 1.0),
            child: Container(height: 3,
              decoration: BoxDecoration(color: bar,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [BoxShadow(color: bar.withOpacity(0.4), blurRadius: 6)]))),
        ]),
      ]),
    );
  }
}

// ── Bandwidth tile ────────────────────────────────────────────────────────────
class _BandwidthTile extends StatelessWidget {
  final BandwidthStats bw; final VC v;
  const _BandwidthTile({required this.bw, required this.v});

  String _fmt(double k) =>
    k >= 1024 ? '${(k/1024).toStringAsFixed(2)} Mb/s' : '${k.toStringAsFixed(0)} Kb/s';

  @override Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: v.panel, border: Border.all(color: v.wire),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        // DOWN
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('↓', style: GoogleFonts.dmMono(fontSize: 11,
              color: v.accent, fontWeight: FontWeight.w700)),
            const SizedBox(width: 5),
            Text('DOWN', style: GoogleFonts.outfit(fontSize: 9,
              color: v.lo, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ]),
          const SizedBox(height: 4),
          Text(_fmt(bw.currentRx), style: GoogleFonts.dmMono(
            fontSize: 20, fontWeight: FontWeight.w700, color: v.accent)),
        ])),
        // divider
        Container(width: 1, height: 40, color: v.wire,
          margin: const EdgeInsets.symmetric(horizontal: 14)),
        // UP
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('↑', style: GoogleFonts.dmMono(fontSize: 11,
              color: V.warn, fontWeight: FontWeight.w700)),
            const SizedBox(width: 5),
            Text('UP', style: GoogleFonts.outfit(fontSize: 9,
              color: v.lo, fontWeight: FontWeight.w700, letterSpacing: 1)),
          ]),
          const SizedBox(height: 4),
          Text(_fmt(bw.currentTx), style: GoogleFonts.dmMono(
            fontSize: 20, fontWeight: FontWeight.w700, color: V.warn)),
        ])),
        // LIVE badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: V.ok.withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: V.ok.withOpacity(0.2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Dot(color: V.ok, size: 5),
            const SizedBox(width: 5),
            Text('LIVE', style: GoogleFonts.outfit(fontSize: 8,
              fontWeight: FontWeight.w800, color: V.ok, letterSpacing: 1)),
          ]),
        ),
      ]),
    );
  }
}

// ── Count box ─────────────────────────────────────────────────────────────────
class _CountBox extends StatelessWidget {
  final int n; final String label; final IconData icon;
  final Color color; final VC v;
  const _CountBox({required this.n, required this.label, required this.icon,
    required this.color, required this.v});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: v.panel, border: Border.all(color: v.wire),
      borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(height: 5),
      Text('$n', style: GoogleFonts.dmMono(fontSize: 20,
        fontWeight: FontWeight.w700, color: color)),
      Text(label, style: GoogleFonts.outfit(fontSize: 8,
        color: v.lo, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    ]),
  );
}

// ── Network tile ──────────────────────────────────────────────────────────────
class _NetworkTile extends StatelessWidget {
  final RouterStatus st; final VC v;
  const _NetworkTile({required this.st, required this.v});

  @override Widget build(BuildContext context) {
    return VCard(
      onTap: () => _showWifiSheet(context, st),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader('NETWORK', trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.edit_rounded, size: 11, color: v.lo),
          const SizedBox(width: 4),
          Text('edit', style: GoogleFonts.outfit(fontSize: 10,
            color: v.lo, fontWeight: FontWeight.w600)),
        ])),
        const SizedBox(height: 12),
        _NRow('WAN', st.wanIp, Icons.public_rounded, v),
        Divider(height: 12, color: v.wire),
        _NRow('LAN', st.lanIp, Icons.router_rounded, v),
        Divider(height: 12, color: v.wire),
        _WRow('2.4 GHz', st.wifiSsid, st.wifi24enabled, v),
        if (st.wifi5present) ...[
          Divider(height: 12, color: v.wire),
          _WRow('5 GHz', st.wifiSsid5, st.wifi5enabled, v),
        ],
      ]),
    );
  }
}

Widget _NRow(String l, String v2, IconData ic, VC v) => Row(children: [
  Icon(ic, size: 12, color: v.lo),
  const SizedBox(width: 8),
  Text(l, style: GoogleFonts.outfit(fontSize: 11, color: v.mid)),
  const Spacer(),
  Text(v2, style: GoogleFonts.dmMono(fontSize: 11,
    fontWeight: FontWeight.w500, color: v.hi)),
]);

Widget _WRow(String l, String ssid, bool on, VC v) => Row(children: [
  Icon(Icons.wifi_rounded, size: 12, color: v.lo),
  const SizedBox(width: 8),
  Text(l, style: GoogleFonts.outfit(fontSize: 11, color: v.mid)),
  const Spacer(),
  Dot(color: on ? V.ok : V.err, size: 6),
  const SizedBox(width: 6),
  Text(ssid.isEmpty ? '—' : ssid, style: GoogleFonts.dmMono(fontSize: 11,
    fontWeight: FontWeight.w500, color: on ? v.hi : V.err),
    overflow: TextOverflow.ellipsis),
]);

// ── Ethernet Ports ────────────────────────────────────────────────────────────
class _PortsTile extends ConsumerWidget {
  final VC v;
  const _PortsTile({required this.v});
  @override Widget build(BuildContext context, WidgetRef ref) {
    final ports = ref.watch(ethernetPortsProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: v.panel, border: Border.all(color: v.wire),
        borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('PORTS', style: GoogleFonts.outfit(fontSize: 10,
            fontWeight: FontWeight.w700, color: v.lo, letterSpacing: 1.4)),
          const Spacer(),
          if (ports.isNotEmpty) Text(
            '${ports.where((p) => p['up'] == true).length}/${ports.length}',
            style: GoogleFonts.dmMono(fontSize: 10, color: V.ok)),
        ]),
        const SizedBox(height: 12),
        ports.isEmpty
          ? Text('—', style: GoogleFonts.dmMono(fontSize: 12, color: v.lo))
          : Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ports.map((p) => _PortDot(port: p, v: v)).toList()),
      ]),
    );
  }
}

class _PortDot extends StatelessWidget {
  final Map<String, dynamic> port; final VC v;
  const _PortDot({required this.port, required this.v});
  @override Widget build(BuildContext context) {
    final lbl   = port['port'] as String;
    final up    = port['up']   as bool?;
    final spd   = port['speed'] as String;
    final isWan = lbl == 'WAN';
    final c = up == null ? v.lo : up ? (isWan ? V.info : V.ok) : V.err;
    return Column(children: [
      Container(width: 42, height: 30,
        decoration: BoxDecoration(
          color: up == true ? c.withOpacity(0.06) : v.elevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: up == true ? c.withOpacity(0.4) : v.wire, width: 1.5),
          boxShadow: up == true ? [BoxShadow(color: c.withOpacity(0.18), blurRadius: 8)] : null,
        ),
        child: Stack(alignment: Alignment.center, children: [
          Icon(isWan ? Icons.public_rounded : Icons.settings_ethernet_rounded,
            size: 14, color: up == true ? c : v.lo),
          Positioned(top: 3, right: 3, child: Dot(color: c, size: 4)),
        ]),
      ),
      const SizedBox(height: 4),
      Text(lbl, style: GoogleFonts.outfit(fontSize: 8, fontWeight: FontWeight.w700,
        color: isWan ? V.info : v.mid)),
      Text(up == null ? '?' : up ? (spd.isNotEmpty ? '${spd}M' : 'UP') : 'DN',
        style: GoogleFonts.dmMono(fontSize: 8, color: c)),
    ]);
  }
}

// ── Footer strip ──────────────────────────────────────────────────────────────
class _FooterStrip extends StatelessWidget {
  final RouterStatus st; final VC v;
  const _FooterStrip({required this.st, required this.v});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: v.panel, border: Border.all(color: v.wire),
      borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      _FChip(Icons.update_rounded, 'fw', st.firmware, v),
      Container(width: 1, height: 24, color: v.wire, margin: const EdgeInsets.symmetric(horizontal: 12)),
      _FChip(Icons.timer_outlined, 'up', st.uptime, v),
      Container(width: 1, height: 24, color: v.wire, margin: const EdgeInsets.symmetric(horizontal: 12)),
      _FChip(Icons.swap_horiz_rounded, 'wan', st.wanIface, v),
    ]),
  );
}

class _FChip extends StatelessWidget {
  final IconData ic; final String lbl, val; final VC v;
  const _FChip(this.ic, this.lbl, this.val, this.v);
  @override Widget build(BuildContext context) => Expanded(child: Row(children: [
    Icon(ic, size: 11, color: v.lo),
    const SizedBox(width: 5),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(lbl, style: GoogleFonts.outfit(fontSize: 8, color: v.lo,
        fontWeight: FontWeight.w700, letterSpacing: 1)),
      Text(val, style: GoogleFonts.dmMono(fontSize: 10, color: v.mid),
        overflow: TextOverflow.ellipsis),
    ])),
  ]));
}

// ── WiFi bottom sheet ─────────────────────────────────────────────────────────
void _showWifiSheet(BuildContext ctx, RouterStatus st) => showModalBottomSheet(
  context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
  builder: (_) => _WifiSheet(st: st));

class _WifiSheet extends ConsumerStatefulWidget {
  final RouterStatus st;
  const _WifiSheet({required this.st});
  @override ConsumerState<_WifiSheet> createState() => _WifiSheetState();
}
class _WifiSheetState extends ConsumerState<_WifiSheet> {
  bool _saving = false; String? _msg;
  late TextEditingController _s24, _p24, _c24, _s5, _p5, _c5;
  late bool _r24, _r5; late String _sec24, _sec5;

  @override void initState() {
    super.initState();
    _s24 = TextEditingController(text: widget.st.wifiSsid);
    _p24 = TextEditingController(); _c24 = TextEditingController();
    _r24 = widget.st.wifi24enabled; _sec24 = 'psk2';
    _s5 = TextEditingController(text: widget.st.wifiSsid5);
    _p5 = TextEditingController(); _c5 = TextEditingController();
    _r5 = widget.st.wifi5enabled; _sec5 = 'psk2';
    _load();
  }
  @override void dispose() {
    _s24.dispose(); _p24.dispose(); _c24.dispose();
    _s5.dispose(); _p5.dispose(); _c5.dispose(); super.dispose();
  }

  Future<void> _load() async {
    final ssh = ref.read(sshServiceProvider);
    try {
      final r = await ssh.run('nvram get wl0_wpa_psk; echo ---; nvram get wl0_channel; echo ---; nvram get wl0_security_mode; echo ---; nvram get wl1_wpa_psk; echo ---; nvram get wl1_channel; echo ---; nvram get wl1_security_mode');
      final p = r.split('---').map((s) => s.trim()).toList();
      String ms(String s) {
        if (s == 'wpa2_personal') return 'psk2'; if (s == 'wpa_personal') return 'psk';
        if (s == 'wpa_personal wpa2_personal') return 'psk psk2'; return s.isEmpty ? 'psk2' : s;
      }
      if (!mounted) return;
      setState(() {
        if (p.length > 0) _p24.text = p[0]; if (p.length > 1) _c24.text = p[1];
        if (p.length > 2) _sec24 = ms(p[2]); if (p.length > 3) _p5.text = p[3];
        if (p.length > 4) _c5.text = p[4]; if (p.length > 5) _sec5 = ms(p[5]);
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final ssh = ref.read(sshServiceProvider);
    setState(() { _saving = true; _msg = null; });
    try {
      String ns(String s) {
        if (s == 'psk2') return 'wpa2_personal'; if (s == 'psk') return 'wpa_personal';
        if (s == 'psk psk2') return 'wpa_personal wpa2_personal'; if (s == 'open') return 'disabled'; return s;
      }
      final cmds = ["nvram set wl0_ssid='${_s24.text}'", "nvram set wl0_radio=${_r24?1:0}",
        "nvram set wl0_security_mode='${ns(_sec24)}'", "nvram set wl0_crypto=aes",
        if (_p24.text.isNotEmpty) "nvram set wl0_wpa_psk='${_p24.text}'",
        if (_c24.text.isNotEmpty) "nvram set wl0_channel=${_c24.text}",
        if (widget.st.wifi5present) ...["nvram set wl1_ssid='${_s5.text}'",
          "nvram set wl1_radio=${_r5?1:0}", "nvram set wl1_security_mode='${ns(_sec5)}'",
          "nvram set wl1_crypto=aes",
          if (_p5.text.isNotEmpty) "nvram set wl1_wpa_psk='${_p5.text}'",
          if (_c5.text.isNotEmpty) "nvram set wl1_channel=${_c5.text}"],
        'nvram commit'];
      await ssh.run(cmds.join(' && '));
      ssh.run('(wlconf eth1 up; wlconf eth2 up; killall -HUP nas 2>/dev/null; service wireless restart>/dev/null 2>&1)&').catchError((_){});
      setState(() => _msg = '✓ Saved');
    } catch (e) { setState(() => _msg = '✗ $e'); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    const opts = ['open','psk','psk2','psk psk2'];
    final lbls = {'open':'Open','psk':'WPA','psk2':'WPA2','psk psk2':'WPA/WPA2'};
    return DraggableScrollableSheet(
      initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: v.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: v.wire)),
        child: Column(children: [
          Container(margin: const EdgeInsets.only(top: 8), width: 32, height: 4,
            decoration: BoxDecoration(color: v.wire2, borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
            Text('WIFI SETTINGS', style: GoogleFonts.outfit(fontSize: 13,
              fontWeight: FontWeight.w800, color: v.hi, letterSpacing: 1)),
            const Spacer(),
            _saving
              ? SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: v.accent))
              : TextButton(onPressed: _save,
                  child: Text('SAVE', style: GoogleFonts.outfit(fontSize: 12,
                    fontWeight: FontWeight.w800, color: v.accent))),
          ])),
          if (_msg != null) Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _msg!.startsWith('✓') ? V.ok.withOpacity(0.08) : V.err.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: (_msg!.startsWith('✓') ? V.ok : V.err).withOpacity(0.25))),
            child: Text(_msg!, style: GoogleFonts.dmMono(fontSize: 11,
              color: _msg!.startsWith('✓') ? V.ok : V.err))),
          Divider(height: 1, color: v.wire),
          Expanded(child: ListView(controller: sc, padding: const EdgeInsets.all(14), children: [
            _bandRow('2.4 GHz', _r24, (b) => setState(() => _r24 = b), v),
            const SizedBox(height: 10),
            _field('SSID', _s24), const SizedBox(height: 8),
            _field('Password', _p24, obs: true), const SizedBox(height: 8),
            _field('Channel', _c24, kb: TextInputType.number), const SizedBox(height: 8),
            _drop('Security', _sec24, opts, lbls, v, (x) => setState(() => _sec24 = x)),
            if (widget.st.wifi5present) ...[
              const SizedBox(height: 16),
              Divider(color: v.wire),
              const SizedBox(height: 12),
              _bandRow('5 GHz', _r5, (b) => setState(() => _r5 = b), v),
              const SizedBox(height: 10),
              _field('SSID', _s5), const SizedBox(height: 8),
              _field('Password', _p5, obs: true), const SizedBox(height: 8),
              _field('Channel', _c5, kb: TextInputType.number), const SizedBox(height: 8),
              _drop('Security', _sec5, opts, lbls, v, (x) => setState(() => _sec5 = x)),
            ],
          ])),
        ]),
      ),
    );
  }

  Widget _field(String l, TextEditingController c,
      {bool obs = false, TextInputType kb = TextInputType.text}) =>
    TextField(controller: c, obscureText: obs, keyboardType: kb,
      style: GoogleFonts.dmMono(fontSize: 13),
      decoration: InputDecoration(labelText: l));

  Widget _drop(String l, String val, List<String> opts, Map<String,String> lbls,
      VC v, ValueChanged<String> fn) =>
    DropdownButtonFormField<String>(
      value: opts.contains(val) ? val : opts[2],
      decoration: InputDecoration(labelText: l),
      dropdownColor: v.elevated,
      items: opts.map((o) => DropdownMenuItem(value: o, child:
        Text(lbls[o]??o, style: GoogleFonts.outfit(fontSize: 13)))).toList(),
      onChanged: (x) { if (x != null) fn(x); });

  Widget _bandRow(String lbl, bool on, ValueChanged<bool> fn, VC v) => Row(children: [
    Dot(color: on ? V.ok : V.err, size: 7),
    const SizedBox(width: 8),
    Text(lbl, style: GoogleFonts.outfit(fontSize: 13,
      fontWeight: FontWeight.w700, color: v.hi)),
    const Spacer(),
    Switch.adaptive(value: on, onChanged: fn, activeColor: v.accent),
  ]);
}

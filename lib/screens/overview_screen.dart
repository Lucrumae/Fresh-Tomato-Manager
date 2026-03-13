import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/ssh_service.dart';

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v      = Theme.of(context).extension<VC>()!;
    final status = ref.watch(routerStatusProvider);
    final bw     = ref.watch(bandwidthProvider);
    final devs   = ref.watch(devicesProvider);
    final ssh    = ref.watch(sshServiceProvider);

    return Scaffold(
      backgroundColor: v.bg,
      body: CustomScrollView(slivers:[
        SliverAppBar(
          backgroundColor: v.bg, surfaceTintColor:Colors.transparent,
          pinned:true, expandedHeight:0,
          title: Row(children:[
            Text('Tomato Manager', style:GoogleFonts.outfit(fontSize:16, fontWeight:FontWeight.w900, color:v.accent, letterSpacing:1)),
            const Spacer(),
            _ConnBadge(ssh:ssh, status:status),
            const SizedBox(width:12),
            GestureDetector(
              onTap: () => ref.read(routerStatusProvider.notifier).fetch(),
              child:Icon(Icons.refresh_rounded, color:v.lo, size:18)),
          ]),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16,8,16,100),
          child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[

            // ── Live metrics row (2 cards) ─────────────────────────────
            Row(children:[
              Expanded(child:_CpuTempTile(
                cpu:status.cpuPercent, temp:status.cpuTempC)),
              const SizedBox(width:10),
              Expanded(child:_MetricTile(
                label:'RAM', value:'${status.ramUsedMB}/${status.ramTotalMB}MB',
                progress:status.ramTotalMB>0?status.ramUsedMB/status.ramTotalMB:0,
                color:_ramColor(status.ramTotalMB>0?status.ramUsedMB/status.ramTotalMB*100:0))),
            ]),
            const SizedBox(height:10),

            // ── Bandwidth card (chart) ───────────────────────────────────
            VCard(padding:const EdgeInsets.all(14), child:Column(
              crossAxisAlignment:CrossAxisAlignment.start, children:[
                Row(children:[
                  Text('BANDWIDTH', style:GoogleFonts.outfit(fontSize:9, fontWeight:FontWeight.w800, color:v.mid, letterSpacing:1.5)),
                  const Spacer(),
                  _dot(v.accent), const SizedBox(width:4),
                  Text('DL', style:GoogleFonts.dmMono(fontSize:9, color:v.mid)),
                  const SizedBox(width:8),
                  _dot(V.info), const SizedBox(width:4),
                  Text('UL', style:GoogleFonts.dmMono(fontSize:9, color:v.mid)),
                ]),
                const SizedBox(height:10),
                if (bw.points.isNotEmpty)
                  SizedBox(height:60, child:_MiniChart(points:bw.points, dlColor:v.accent))
                else
                  SizedBox(height:60, child:Center(child:Text('No data yet', style:GoogleFonts.dmMono(fontSize:11, color:v.lo)))),
              ],
            )),
            const SizedBox(height:10),

            // ── Down / Up tiles ───────────────────────────────────────────
            Row(children:[
              Expanded(child:_BwTile(label:'DOWN', kbps:bw.currentRx, color:v.accent)),
              const SizedBox(width:10),
              Expanded(child:_BwTile(label:'UP',   kbps:bw.currentTx, color:V.info)),
            ]),
            const SizedBox(height:10),

            // ── STATUS section title ──────────────────────────────────────
            _SectionTitle(label: 'STATUS', v: v),
            const SizedBox(height: 6),

            // ── WAN / Router info ─────────────────────────────────────────
            VCard(padding:const EdgeInsets.all(14), child:Column(children:[
              _InfoRow('WAN IP',   status.wanIp.isEmpty?'—':status.wanIp),
              _divider(context),
              _InfoRow('LAN IP',   status.lanIp.isEmpty?'192.168.1.1':status.lanIp),
              _divider(context),
              _InfoRow('UPTIME',   _formatUptime(status.uptime)),
              _divider(context),
              _InfoRow('WAN IF',   status.wanIface.isEmpty?'usb0':status.wanIface),
              if (status.routerModel.isNotEmpty) ...[
                _divider(context),
                _InfoRow('MODEL', status.routerModel),
              ],
              if (status.firmware.isNotEmpty) ...[
                _divider(context),
                _InfoRow('FIRMWARE', status.firmware),
              ],
            ])),
            const SizedBox(height:10),

            // ── WIRELESS section title ───────────────────────────────────
            _SectionTitle(label: 'WIRELESS', v: v),
            const SizedBox(height: 6),

            // ── WiFi controls ─────────────────────────────────────────────
            VCard(padding:const EdgeInsets.all(14), child:Column(children:[
              _WifiRow(
                label:'2.4 GHz',
                ssid:status.wifiSsid.isEmpty?'—':status.wifiSsid,
                enabled:status.wifi24enabled,
                wifiTemp:status.wifiTemp24,
                onToggle:(v2) => _toggleWifi(context, ref, '2.4', v2),
              ),
              if (status.wifi5present) ...[
                _divider(context),
                _WifiRow(
                  label:'5 GHz',
                  ssid:status.wifiSsid5.isEmpty?'—':status.wifiSsid5,
                  enabled:status.wifi5enabled,
                  wifiTemp:status.wifiTemp5,
                  onToggle:(v2) => _toggleWifi(context, ref, '5', v2),
                ),
              ],
            ])),
            const SizedBox(height:10),

            // ── Devices summary ───────────────────────────────────────────
            VCard(padding:const EdgeInsets.all(14), child:Row(children:[
              Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                Text('NODES', style:GoogleFonts.outfit(fontSize:9, fontWeight:FontWeight.w800, color:v.mid, letterSpacing:1.5)),
                const SizedBox(height:4),
                Text('${devs.length}', style:GoogleFonts.outfit(fontSize:28, fontWeight:FontWeight.w900, color:v.hi)),
              ]),
              const SizedBox(width:20),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                _DevRow('WiFi',     devs.where((d)=>d.isWireless).length,     v),
                const SizedBox(height:4),
                _DevRow('Ethernet', devs.where((d)=>!d.isWireless).length,    v),
                const SizedBox(height:4),
                _DevRow('Blocked',  devs.where((d)=>d.isBlocked).length,      v, color:V.err),
              ])),
            ])),

          ]),
        )),
      ]),
    );
  }

  Widget _dot(Color c) => Container(width:6, height:6, decoration:BoxDecoration(color:c, shape:BoxShape.circle));
  Widget _divider(BuildContext ctx) {
    final v = Theme.of(ctx).extension<VC>()!;
    return Container(margin:const EdgeInsets.symmetric(vertical:8), height:0.5, color:v.wire);
  }

  Color _cpuColor(double p) => p>80?V.err:p>60?V.warn:V.ok;
  Color _ramColor(double p) => p>85?V.err:p>70?V.warn:V.info;

  String _formatUptime(String raw) {
    if (raw.isEmpty) return '—';
    if (raw.contains('up')) {
      final m = RegExp(r'up\s+(.+?),\s+load').firstMatch(raw);
      if (m!=null) return m.group(1)!.trim();
    }
    return raw.split(',').first.replaceAll('up','').trim();
  }

  Future<void> _toggleWifi(BuildContext ctx, WidgetRef ref, String band, bool enable) async {
    final ssh = ref.read(sshServiceProvider);
    final ok  = await ssh.toggleWifi(band, enable);
    if (ok) ref.read(routerStatusProvider.notifier).fetch();
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content:Text(ok?'WiFi ${band}GHz ${enable?"on":"off"}':'Failed to toggle WiFi',
          style:GoogleFonts.dmMono(fontSize:12)),
        backgroundColor:ok?V.ok:V.err));
    }
  }
}

// ── Section title ─────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String label;
  final VC v;
  const _SectionTitle({required this.label, required this.v});
  @override Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 4),
      child: Text(label,
        style: GoogleFonts.outfit(
          fontSize: 10, fontWeight: FontWeight.w800,
          color: v.mid, letterSpacing: 1.8)),
    );
  }
}

// ── Widgets ────────────────────────────────────────────────────────────────────
class _ConnBadge extends StatelessWidget {
  final SshService ssh; final dynamic status;
  const _ConnBadge({required this.ssh, required this.status});
  @override Widget build(BuildContext context) {
    final online = ssh.isConnected && status.isOnline;
    final color  = online ? V.ok : V.err;
    return Row(mainAxisSize:MainAxisSize.min, children:[
      Dot(color:color, size:6),
      const SizedBox(width:5),
      Text(online?'CONNECTED':'OFFLINE',
        style:GoogleFonts.outfit(fontSize:9, fontWeight:FontWeight.w800, color:color, letterSpacing:1)),
    ]);
  }
}

class _MetricTile extends StatelessWidget {
  final String label, value; final double progress; final Color color;
  const _MetricTile({required this.label, required this.value, required this.progress, required this.color});
  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return VCard(padding:const EdgeInsets.all(12), child:Column(
      crossAxisAlignment:CrossAxisAlignment.start, children:[
        Text(label, style:GoogleFonts.outfit(fontSize:9, fontWeight:FontWeight.w800, color:v.mid, letterSpacing:1.5)),
        const SizedBox(height:6),
        Text(value, style:GoogleFonts.dmMono(fontSize:18, fontWeight:FontWeight.w700, color:color)),
        const SizedBox(height:8),
        ClipRRect(borderRadius:BorderRadius.circular(2), child:LinearProgressIndicator(
          value:progress.clamp(0.0,1.0), minHeight:3, backgroundColor:v.wire,
          valueColor:AlwaysStoppedAnimation(color))),
      ]));
  }
}

// Combined CPU + Temp card
class _CpuTempTile extends StatelessWidget {
  final double cpu, temp;
  const _CpuTempTile({required this.cpu, required this.temp});
  @override Widget build(BuildContext context) {
    final v      = Theme.of(context).extension<VC>()!;
    final cpuClr = cpu>80?V.err:cpu>60?V.warn:V.ok;
    final tmpClr = temp>75?V.err:temp>60?V.warn:V.ok;
    return VCard(padding:const EdgeInsets.all(12), child:Column(
      crossAxisAlignment:CrossAxisAlignment.start, children:[
        // Header row: CPU label + Temp badge
        Row(crossAxisAlignment:CrossAxisAlignment.center, children:[
          Text('CPU', style:GoogleFonts.outfit(fontSize:9, fontWeight:FontWeight.w800, color:v.mid, letterSpacing:1.5)),
          const Spacer(),
          if (temp > 0) Container(
            padding:const EdgeInsets.symmetric(horizontal:6, vertical:2),
            decoration:BoxDecoration(
              color:tmpClr.withOpacity(0.15),
              borderRadius:BorderRadius.circular(6)),
            child:Row(mainAxisSize:MainAxisSize.min, children:[
              Icon(Icons.thermostat_rounded, size:10, color:tmpClr),
              const SizedBox(width:3),
              Text('${temp.round()}°', style:GoogleFonts.dmMono(fontSize:10, fontWeight:FontWeight.w700, color:tmpClr)),
            ]),
          ),
        ]),
        const SizedBox(height:6),
        Text('${cpu.round()}%', style:GoogleFonts.dmMono(fontSize:18, fontWeight:FontWeight.w700, color:cpuClr)),
        const SizedBox(height:8),
        ClipRRect(borderRadius:BorderRadius.circular(2), child:LinearProgressIndicator(
          value:(cpu/100).clamp(0.0,1.0), minHeight:3, backgroundColor:v.wire,
          valueColor:AlwaysStoppedAnimation(cpuClr))),
      ]));
  }
}

class _BwTile extends StatelessWidget {
  final String label; final double kbps; final Color color;
  const _BwTile({required this.label, required this.kbps, required this.color});
  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    String fmt; if (kbps>=1024) { fmt='${(kbps/1024).toStringAsFixed(1)} Mb/s'; }
    else { fmt='${kbps.round()} Kb/s'; }
    return VCard(padding:const EdgeInsets.symmetric(horizontal:12, vertical:10), child:Row(children:[
      Dot(color:color, size:6),
      const SizedBox(width:8),
      Text(label, style:GoogleFonts.outfit(fontSize:9, fontWeight:FontWeight.w800, color:v.mid, letterSpacing:1.5)),
      const Spacer(),
      Text(fmt, style:GoogleFonts.dmMono(fontSize:12, fontWeight:FontWeight.w700, color:color)),
    ]));
  }
}

class _InfoRow extends StatelessWidget {
  final String k, val; const _InfoRow(this.k, this.val);
  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Row(children:[
      Text(k, style:GoogleFonts.outfit(fontSize:10, fontWeight:FontWeight.w600, color:v.mid)),
      const Spacer(),
      Text(val, style:GoogleFonts.dmMono(fontSize:11, color:v.hi)),
    ]);
  }
}

Widget _DevRow(String label, int count, VC v, {Color? color}) => Row(children:[
  Text(label, style:GoogleFonts.dmMono(fontSize:10, color:v.mid)),
  const SizedBox(width:8),
  Text('$count', style:GoogleFonts.dmMono(fontSize:11, fontWeight:FontWeight.w700, color:color??v.hi)),
]);

class _WifiRow extends StatelessWidget {
  final String label, ssid;
  final bool enabled;
  final double wifiTemp;
  final ValueChanged<bool> onToggle;
  const _WifiRow({required this.label, required this.ssid, required this.enabled,
    this.wifiTemp = 0, required this.onToggle});
  @override Widget build(BuildContext context) {
    final v      = Theme.of(context).extension<VC>()!;
    final tmpClr = wifiTemp>70?V.err:wifiTemp>60?V.warn:v.mid;
    return Row(children:[
      Dot(color:enabled?V.ok:v.lo, size:6, glow:enabled),
      const SizedBox(width:10),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
        Row(children:[
          Text(label, style:GoogleFonts.outfit(fontSize:11, fontWeight:FontWeight.w700, color:v.hi)),
          if (wifiTemp > 0) ...[
            const SizedBox(width:8),
            Icon(Icons.thermostat_rounded, size:11, color:tmpClr),
            Text('${wifiTemp.round()}°', style:GoogleFonts.dmMono(fontSize:10, color:tmpClr)),
          ],
        ]),
        Text(ssid,  style:GoogleFonts.dmMono(fontSize:10, color:v.mid)),
      ])),
      Switch(value:enabled, onChanged:onToggle),
    ]);
  }
}

class _MiniChart extends StatelessWidget {
  final List<dynamic> points;
  final Color dlColor;
  const _MiniChart({required this.points, required this.dlColor});
  @override Widget build(BuildContext context) => CustomPaint(
    painter: _ChartPainter(points, dlColor), size:Size.infinite);
}

class _ChartPainter extends CustomPainter {
  final List<dynamic> points;
  final Color dlColor;
  const _ChartPainter(this.points, this.dlColor);
  @override void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxVal = points.fold(0.0, (a, b) =>
      max(a, max((b.rxKbps as double), (b.txKbps as double))));
    if (maxVal == 0) return;
    _drawLine(canvas, size, points.map((p)=>p.rxKbps as double).toList(), maxVal, dlColor);
    _drawLine(canvas, size, points.map((p)=>p.txKbps as double).toList(), maxVal, V.info);
  }
  void _drawLine(Canvas canvas, Size size, List<double> vals, double max, Color color) {
    if (vals.length < 2) return;
    final p = Paint()..color=color..strokeWidth=1.5..style=PaintingStyle.stroke
      ..strokeCap=StrokeCap.round..strokeJoin=StrokeJoin.round;
    final path = Path();
    for (int i=0;i<vals.length;i++) {
      final x = i/(vals.length-1)*size.width;
      final y = size.height-(vals[i]/max)*size.height;
      i==0?path.moveTo(x,y):path.lineTo(x,y);
    }
    canvas.drawPath(path, p);
  }
  @override bool shouldRepaint(_ChartPainter o) => o.points != points;
}

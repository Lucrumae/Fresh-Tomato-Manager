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
  String _filter = 'all'; // all | wifi | eth | blocked
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final v    = Theme.of(context).extension<VC>()!;
    final devs = ref.watch(devicesProvider);

    final filtered = devs.where((d) {
      if (_filter=='wifi'    && !d.isWireless) return false;
      if (_filter=='eth'     && d.isWireless)  return false;
      if (_filter=='blocked' && !d.isBlocked)  return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        return d.displayName.toLowerCase().contains(q) ||
               d.ip.contains(q) || d.mac.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: v.bg,
      appBar: AppBar(
        title: Text('DEVICES', style:GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w800, color:v.hi, letterSpacing:2)),
        actions:[
          Text('${devs.length}', style:GoogleFonts.dmMono(fontSize:12, color:v.accent, fontWeight:FontWeight.w700)),
          const SizedBox(width:16),
          GestureDetector(
            onTap: ()=> ref.read(devicesProvider.notifier).fetch(),
            child:Icon(Icons.refresh_rounded, color:v.lo, size:18)),
          const SizedBox(width:16),
        ],
      ),
      body: Column(children:[
        // Search
        Padding(padding:const EdgeInsets.fromLTRB(16,0,16,10), child:
          TextField(controller:_searchCtrl,
            onChanged:(s)=>setState(()=>_search=s),
            style:GoogleFonts.dmMono(fontSize:12, color:v.hi),
            decoration:InputDecoration(
              hintText:'Search name, IP, MAC…',
              prefixIcon:Icon(Icons.search_rounded, size:16, color:v.lo),
              suffixIcon:_search.isNotEmpty?GestureDetector(
                onTap:(){_searchCtrl.clear();setState(()=>_search='');},
                child:Icon(Icons.clear_rounded, size:16, color:v.lo)):null,
              isDense:true,
            ))),
        // Filter chips
        SizedBox(height:36, child:ListView(
          scrollDirection:Axis.horizontal, padding:const EdgeInsets.symmetric(horizontal:16),
          children:[
            _Chip('ALL',     'all',     devs.length,                               _filter, ()=>setState(()=>_filter='all'),     v),
            _Chip('WiFi',    'wifi',    devs.where((d)=>d.isWireless).length,      _filter, ()=>setState(()=>_filter='wifi'),    v),
            _Chip('Ethernet','eth',     devs.where((d)=>!d.isWireless).length,     _filter, ()=>setState(()=>_filter='eth'),     v),
            _Chip('Blocked', 'blocked', devs.where((d)=>d.isBlocked).length,       _filter, ()=>setState(()=>_filter='blocked'), v, danger:true),
          ])),
        const SizedBox(height:8),
        // List
        Expanded(child:filtered.isEmpty
          ? Center(child:Text(_search.isNotEmpty?'No results':'No devices',
              style:GoogleFonts.dmMono(fontSize:12, color:v.lo)))
          : ListView.separated(
              padding:const EdgeInsets.fromLTRB(16,0,16,100),
              itemCount:filtered.length,
              separatorBuilder:(_,__)=>const SizedBox(height:8),
              itemBuilder:(_,i)=>_DeviceCard(device:filtered[i]))),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label, key2; final int count; final String current;
  final VoidCallback onTap; final VC v; final bool danger;
  const _Chip(this.label, this.key2, this.count, this.current, this.onTap, this.v, {this.danger=false});
  @override Widget build(BuildContext context) {
    final sel = key2 == current;
    final c   = danger ? V.err : v.accent;
    return GestureDetector(onTap:onTap, child:AnimatedContainer(
      duration:const Duration(milliseconds:150),
      margin:const EdgeInsets.only(right:8),
      padding:const EdgeInsets.symmetric(horizontal:12, vertical:4),
      decoration:BoxDecoration(
        color: sel ? c.withOpacity(0.12) : Colors.transparent,
        borderRadius:BorderRadius.circular(20),
        border:Border.all(color: sel ? c : v.wire)),
      child:Text('$label  $count', style:GoogleFonts.outfit(
        fontSize:11, fontWeight:FontWeight.w700, color:sel?c:v.mid))));
  }
}

// ── Device card ─────────────────────────────────────────────────────────────
class _DeviceCard extends ConsumerWidget {
  final ConnectedDevice device;
  const _DeviceCard({required this.device});

  @override Widget build(BuildContext context, WidgetRef ref) {
    final v   = Theme.of(context).extension<VC>()!;
    final dev = device;

    return VCard(
      accentLeft: dev.isBlocked,
      bg: dev.isBlocked ? V.err.withOpacity(0.04) : null,
      child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
        Row(children:[
          // Interface icon
          Container(width:36, height:36, decoration:BoxDecoration(
            color: dev.isBlocked ? V.err.withOpacity(0.1) : v.accent.withOpacity(0.08),
            borderRadius:BorderRadius.circular(8)),
            child:Icon(
              dev.isWireless ? Icons.wifi_rounded : Icons.cable_rounded,
              size:18, color:dev.isBlocked?V.err:v.accent)),
          const SizedBox(width:12),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
            Text(dev.displayName,
              style:GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w700,
                color: dev.isBlocked?V.err:v.hi),
              overflow:TextOverflow.ellipsis),
            Text(dev.ip, style:GoogleFonts.dmMono(fontSize:11, color:v.mid)),
          ])),
          // Block toggle
          _BlockButton(device:dev),
        ]),
        const SizedBox(height:10),
        // Detail row
        Row(children:[
          _Tag(dev.mac.toUpperCase(), v),
          const SizedBox(width:6),
          if (dev.isWireless && dev.wifiBand.isNotEmpty)
            _BandTag(dev.wifiBand, v),
          if (dev.isWireless && dev.rssi.isNotEmpty) ...[
            const SizedBox(width:6),
            _Tag(dev.rssi, v),
          ],
          const Spacer(),
          GestureDetector(
            onTap:()=> _rename(context, ref, dev),
            child:Icon(Icons.edit_rounded, size:14, color:v.lo)),
          const SizedBox(width:12),
          GestureDetector(
            onTap:()=> _setBwLimit(context, ref, dev),
            child:Icon(Icons.speed_rounded, size:14, color:v.lo)),
          const SizedBox(width:12),
          GestureDetector(
            onTap:()=> HapticFeedback.lightImpact().then((_)=>
              Clipboard.setData(ClipboardData(text:dev.ip)).then((_){
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:Text('Copied ${dev.ip}', style:GoogleFonts.dmMono(fontSize:11)),
                  duration:const Duration(seconds:1)));
              })),
            child:Icon(Icons.copy_rounded, size:14, color:v.lo)),
        ]),
      ]),
    );
  }

  Future<void> _rename(BuildContext ctx, WidgetRef ref, ConnectedDevice dev) async {
    final ctrl = TextEditingController(text:dev.name);
    final res  = await showDialog<String>(context:ctx, builder:(ctx)=>AlertDialog(
      title:const Text('Rename Device'),
      content:TextField(controller:ctrl, autofocus:true,
        decoration:const InputDecoration(hintText:'Device name')),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx), child:const Text('Cancel')),
        TextButton(onPressed:()=>Navigator.pop(ctx, ctrl.text.trim()), child:const Text('Save')),
      ]));
    if (res!=null && res.isNotEmpty) {
      await ref.read(devicesProvider.notifier).renameDevice(dev.mac, res);
    }
  }

  Future<void> _setBwLimit(BuildContext ctx, WidgetRef ref, ConnectedDevice dev) async {
    final v = Theme.of(ctx).extension<VC>()!;
    final limits = await ref.read(sshServiceProvider).getBandwidthLimits();
    final existing = limits[dev.mac.toLowerCase()] ?? {'dl': 0, 'ul': 0};
    final dlCtrl = TextEditingController(text: existing['dl'] == 0 ? '' : '${existing['dl']}');
    final ulCtrl = TextEditingController(text: existing['ul'] == 0 ? '' : '${existing['ul']}');
    if (!ctx.mounted) return;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: v.panel,
        title: Text('Bandwidth Limit', style: GoogleFonts.outfit(color: v.hi, fontWeight: FontWeight.w700)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dev.displayName, style: GoogleFonts.dmMono(fontSize: 11, color: v.mid)),
          const SizedBox(height: 16),
          Text('DOWNLOAD LIMIT', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: v.mid, letterSpacing: 1.5)),
          const SizedBox(height: 6),
          TextField(controller: dlCtrl, keyboardType: TextInputType.number,
            style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
            decoration: const InputDecoration(isDense: true, hintText: '0 = unlimited', suffixText: 'kbps')),
          const SizedBox(height: 14),
          Text('UPLOAD LIMIT', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: v.mid, letterSpacing: 1.5)),
          const SizedBox(height: 6),
          TextField(controller: ulCtrl, keyboardType: TextInputType.number,
            style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
            decoration: const InputDecoration(isDense: true, hintText: '0 = unlimited', suffixText: 'kbps')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false),
            child: Text('CANCEL', style: GoogleFonts.outfit(color: v.mid))),
          TextButton(onPressed: () => Navigator.pop(dctx, true),
            child: Text('APPLY', style: GoogleFonts.outfit(color: V.ok, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true || !ctx.mounted) return;
    final dl = int.tryParse(dlCtrl.text.trim()) ?? 0;
    final ul = int.tryParse(ulCtrl.text.trim()) ?? 0;
    final result = await ref.read(sshServiceProvider).setBandwidthLimit(mac: dev.mac, dlKbps: dl, ulKbps: ul);
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(result ? 'Limit applied for ${dev.displayName}' : 'Failed to apply limit',
        style: GoogleFonts.dmMono(fontSize: 11)),
      backgroundColor: result ? V.ok : V.err));
  }
}

class _BlockButton extends ConsumerStatefulWidget {
  final ConnectedDevice device;
  const _BlockButton({required this.device});
  @override ConsumerState<_BlockButton> createState() => _BlockButtonState();
}

class _BlockButtonState extends ConsumerState<_BlockButton> {
  bool _loading = false;
  @override Widget build(BuildContext ctx) {
    final v       = Theme.of(ctx).extension<VC>()!;
    final blocked = widget.device.isBlocked;
    if (_loading) return SizedBox(width:24, height:24,
      child:CircularProgressIndicator(strokeWidth:2, color:blocked?V.err:v.accent));
    return GestureDetector(
      onTap: () async {
        setState(()=>_loading=true);
        final ok = await ref.read(devicesProvider.notifier).toggleBlock(widget.device.mac);
        if (mounted) setState(()=>_loading=false);
        if (!ok && ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content:Text('Block failed', style:GoogleFonts.dmMono(fontSize:11)),
            backgroundColor:V.err));
        }
      },
      child:Container(
        padding:const EdgeInsets.symmetric(horizontal:10, vertical:5),
        decoration:BoxDecoration(
          color: blocked?V.err.withOpacity(0.12):Colors.transparent,
          borderRadius:BorderRadius.circular(6),
          border:Border.all(color:blocked?V.err:v.wire)),
        child:Text(blocked?'BLOCKED':'ALLOWED',
          style:GoogleFonts.outfit(fontSize:9, fontWeight:FontWeight.w800,
            color:blocked?V.err:V.ok, letterSpacing:0.5))));
  }
}

Widget _Tag(String t, VC v) => Container(
  padding:const EdgeInsets.symmetric(horizontal:6, vertical:2),
  decoration:BoxDecoration(color:v.wire, borderRadius:BorderRadius.circular(4)),
  child:Text(t, style:GoogleFonts.dmMono(fontSize:9, color:v.mid)));

// WiFi band tag — color-coded: 2.4GHz=blue, 5GHz=green
Widget _BandTag(String band, VC v) {
  final is5 = band.contains('5');
  final color = is5 ? V.ok : V.info;
  return Container(
    padding:const EdgeInsets.symmetric(horizontal:6, vertical:2),
    decoration:BoxDecoration(
      color:color.withOpacity(0.12),
      borderRadius:BorderRadius.circular(4),
      border:Border.all(color:color.withOpacity(0.4), width:0.5)),
    child:Row(mainAxisSize:MainAxisSize.min, children:[
      Icon(Icons.wifi_rounded, size:9, color:color),
      const SizedBox(width:3),
      Text(band, style:GoogleFonts.dmMono(fontSize:9, color:color, fontWeight:FontWeight.w600)),
    ]));
}

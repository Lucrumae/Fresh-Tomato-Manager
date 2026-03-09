import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

// NETWORK screen = Port Forward + QoS in one place with tab switcher

class NetworkScreen extends ConsumerStatefulWidget {
  const NetworkScreen({super.key});
  @override ConsumerState<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends ConsumerState<NetworkScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override void initState() { super.initState(); _tab = TabController(length:2, vsync:this); }
  @override void dispose()   { _tab.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Scaffold(
      backgroundColor:v.bg,
      appBar:AppBar(
        title:Text('NETWORK', style:GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w800, color:v.hi, letterSpacing:2)),
        bottom:TabBar(controller:_tab, tabs:const [
          Tab(text:'PORT FORWARD'),
          Tab(text:'QoS RULES'),
        ])),
      body: TabBarView(controller:_tab, children:const [
        _PortForwardTab(),
        _QosTab(),
      ]),
    );
  }
}

// ── Port Forward ──────────────────────────────────────────────────────────────
class _PortForwardTab extends ConsumerWidget {
  const _PortForwardTab();
  @override Widget build(BuildContext context, WidgetRef ref) {
    final v     = Theme.of(context).extension<VC>()!;
    final rules = ref.watch(portForwardProvider);
    return Scaffold(
      backgroundColor:v.bg,
      floatingActionButton:FloatingActionButton(
        onPressed:()=>_addRule(context, ref),
        child:const Icon(Icons.add_rounded)),
      body:rules.isEmpty
        ? Center(child:Column(mainAxisSize:MainAxisSize.min, children:[
            Icon(Icons.router_rounded, color:v.lo, size:36),
            const SizedBox(height:12),
            Text('No port forward rules', style:GoogleFonts.dmMono(fontSize:12, color:v.lo))]))
        : ListView.separated(
            padding:const EdgeInsets.fromLTRB(16,16,16,100),
            itemCount:rules.length,
            separatorBuilder:(_,__)=>const SizedBox(height:8),
            itemBuilder:(_,i)=>_PfCard(rule:rules[i])));
  }

  Future<void> _addRule(BuildContext ctx, WidgetRef ref) async {
    final rule = await showDialog<PortForwardRule>(context:ctx, builder:(_)=>const _PfDialog());
    if (rule!=null) {
      ref.read(portForwardProvider.notifier).addRule(rule);
      await ref.read(portForwardProvider.notifier).saveAll();
    }
  }
}

class _PfCard extends ConsumerWidget {
  final PortForwardRule rule; const _PfCard({required this.rule});
  @override Widget build(BuildContext ctx, WidgetRef ref) {
    final v = Theme.of(ctx).extension<VC>()!;
    return VCard(accentLeft:rule.enabled, child:Row(children:[
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
        Text(rule.name.isNotEmpty?rule.name:'Rule ${rule.id}',
          style:GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w700, color:v.hi)),
        const SizedBox(height:4),
        Row(children:[
          VBadge(rule.protocol.toUpperCase(), color:v.accent),
          const SizedBox(width:6),
          Text(':${rule.externalPort} → ${rule.internalIp}:${rule.internalPort}',
            style:GoogleFonts.dmMono(fontSize:10, color:v.mid)),
        ]),
      ])),
      Switch(
        value:rule.enabled,
        onChanged:(_){ ref.read(portForwardProvider.notifier).toggleRule(rule.id); ref.read(portForwardProvider.notifier).saveAll(); }),
      GestureDetector(
        onTap:()async{
          ref.read(portForwardProvider.notifier).removeRule(rule.id);
          await ref.read(portForwardProvider.notifier).saveAll();},
        child:Padding(padding:const EdgeInsets.all(8), child:Icon(Icons.delete_outline_rounded, size:18, color:V.err))),
    ]));
  }
}

class _PfDialog extends StatefulWidget {
  const _PfDialog();
  @override State<_PfDialog> createState() => _PfDialogState();
}
class _PfDialogState extends State<_PfDialog> {
  final _name = TextEditingController();
  final _ext  = TextEditingController();
  final _int  = TextEditingController();
  final _ip   = TextEditingController();
  String _proto = 'tcp';
  @override void dispose() { _name.dispose(); _ext.dispose(); _int.dispose(); _ip.dispose(); super.dispose(); }
  @override Widget build(BuildContext ctx) => AlertDialog(
    title:const Text('Add Port Forward'),
    content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min, children:[
      TextField(controller:_name, decoration:const InputDecoration(labelText:'Name (optional)')),
      const SizedBox(height:10),
      TextField(controller:_ext,  decoration:const InputDecoration(labelText:'External port'), keyboardType:TextInputType.number),
      const SizedBox(height:10),
      TextField(controller:_ip,   decoration:const InputDecoration(labelText:'Internal IP'), keyboardType:TextInputType.numberWithOptions(decimal:true)),
      const SizedBox(height:10),
      TextField(controller:_int,  decoration:const InputDecoration(labelText:'Internal port'), keyboardType:TextInputType.number),
      const SizedBox(height:10),
      DropdownButtonFormField<String>(value:_proto, decoration:const InputDecoration(labelText:'Protocol'),
        items:['tcp','udp','tcp+udp'].map((p)=>DropdownMenuItem(value:p, child:Text(p.toUpperCase()))).toList(),
        onChanged:(p)=>setState(()=>_proto=p!)),
    ])),
    actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx), child:const Text('Cancel')),
      TextButton(onPressed:(){
        final ep = int.tryParse(_ext.text)??0;
        final ip2 = int.tryParse(_int.text)??ep;
        if (ep==0||_ip.text.isEmpty) return;
        Navigator.pop(ctx, PortForwardRule(
          id:DateTime.now().millisecondsSinceEpoch.toString(),
          name:_name.text.trim(), protocol:_proto,
          externalPort:ep, internalPort:ip2,
          internalIp:_ip.text.trim(), enabled:true));
      }, child:const Text('Add')),
    ]);
}

// ── QoS ───────────────────────────────────────────────────────────────────────
class _QosTab extends ConsumerStatefulWidget {
  const _QosTab();
  @override ConsumerState<_QosTab> createState() => _QosTabState();
}
class _QosTabState extends ConsumerState<_QosTab> {
  bool _saving = false;

  @override Widget build(BuildContext ctx) {
    final v     = Theme.of(ctx).extension<VC>()!;
    final rules = ref.watch(qosProvider);
    return Scaffold(
      backgroundColor:v.bg,
      body:rules.isEmpty
        ? Center(child:Text('No QoS rules', style:GoogleFonts.dmMono(fontSize:12, color:v.lo)))
        : ListView.separated(
            padding:const EdgeInsets.fromLTRB(16,16,16,100),
            itemCount:rules.length,
            separatorBuilder:(_,__)=>const SizedBox(height:8),
            itemBuilder:(_,i)=>_QosCard(rule:rules[i])));
  }
}

class _QosCard extends ConsumerWidget {
  final QosRule rule; const _QosCard({required this.rule});
  @override Widget build(BuildContext ctx, WidgetRef ref) {
    final v = Theme.of(ctx).extension<VC>()!;
    final dl = rule.downloadKbps; final ul = rule.uploadKbps;
    String fmt(int k) => k>=1024?'${(k/1024).toStringAsFixed(1)} Mb/s':'$k Kb/s';
    return VCard(accentLeft:rule.enabled, child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
      Row(children:[
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
          Text(rule.name.isNotEmpty?rule.name:rule.mac,
            style:GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w700, color:v.hi)),
          Text(rule.mac, style:GoogleFonts.dmMono(fontSize:10, color:v.mid)),
        ])),
        Switch(value:rule.enabled, onChanged:(_){/* TODO */}),
      ]),
      const SizedBox(height:8),
      Row(children:[
        Icon(Icons.arrow_downward_rounded, size:12, color:V.info),
        const SizedBox(width:4),
        Text(dl>0?fmt(dl):'unlimited', style:GoogleFonts.dmMono(fontSize:11, color:V.info)),
        const SizedBox(width:16),
        Icon(Icons.arrow_upward_rounded, size:12, color:V.ok),
        const SizedBox(width:4),
        Text(ul>0?fmt(ul):'unlimited', style:GoogleFonts.dmMono(fontSize:11, color:V.ok)),
        const Spacer(),
        VBadge('P${rule.priority}', color:V.warn),
      ]),
    ]));
  }
}

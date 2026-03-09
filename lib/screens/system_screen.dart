import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import 'setup_screen.dart';
import 'files_screen.dart';

// SYSTEM screen = Logs tab + Settings/Config tab

class SystemScreen extends ConsumerStatefulWidget {
  const SystemScreen({super.key});
  @override ConsumerState<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends ConsumerState<SystemScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override void initState() { super.initState(); _tab = TabController(length:2, vsync:this); }
  @override void dispose()   { _tab.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Scaffold(
      backgroundColor: v.bg,
      appBar: AppBar(
        title:Text('SYSTEM', style:GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w800, color:v.hi, letterSpacing:2)),
        bottom:TabBar(controller:_tab, tabs:const [
          Tab(text:'LOGS'),
          Tab(text:'CONFIG'),
        ])),
      body: TabBarView(controller:_tab, children:const [
        _LogsTab(),
        _ConfigTab(),
      ]),
    );
  }
}

// ── Logs tab ─────────────────────────────────────────────────────────────────
class _LogsTab extends ConsumerStatefulWidget {
  const _LogsTab();
  @override ConsumerState<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<_LogsTab> {
  String _filter = 'all';
  final _scroll  = ScrollController();
  bool  _follow  = true;

  @override void dispose() { _scroll.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final v    = Theme.of(context).extension<VC>()!;
    final logs = ref.watch(logsProvider);

    final filtered = logs.where((l) {
      if (_filter=='err')  return l.isError;
      if (_filter=='warn') return l.isWarning;
      if (_filter=='kern') return l.isKernel;
      if (_filter=='sys')  return l.isSyslog;
      return true;
    }).toList();

    return Column(children:[
      // Toolbar
      Container(color:v.bg, padding:const EdgeInsets.fromLTRB(16,8,16,8), child:Row(children:[
        _FilterBtn('ALL',  'all',  _filter, ()=>setState(()=>_filter='all'),  v),
        const SizedBox(width:6),
        _FilterBtn('ERR',  'err',  _filter, ()=>setState(()=>_filter='err'),  v, color:V.err),
        const SizedBox(width:6),
        _FilterBtn('WARN', 'warn', _filter, ()=>setState(()=>_filter='warn'), v, color:V.warn),
        const SizedBox(width:6),
        _FilterBtn('KERN', 'kern', _filter, ()=>setState(()=>_filter='kern'), v, color:V.info),
        const SizedBox(width:6),
        _FilterBtn('SYS',  'sys',  _filter, ()=>setState(()=>_filter='sys'),  v, color:V.ok),
        const Spacer(),
        GestureDetector(
          onTap:()=>setState(()=>_follow=!_follow),
          child:Row(children:[
            Icon(_follow?Icons.lock_rounded:Icons.lock_open_rounded, size:13, color:_follow?v.accent:v.lo),
            const SizedBox(width:4),
            Text(_follow?'FOLLOW':'PAUSED', style:GoogleFonts.outfit(fontSize:9, fontWeight:FontWeight.w700, color:_follow?v.accent:v.lo)),
          ])),
      ])),
      // Log lines
      Expanded(child:filtered.isEmpty
        ? Center(child:Text('No logs', style:GoogleFonts.dmMono(fontSize:12, color:v.lo)))
        : ListView.builder(
            controller:_scroll,
            padding:const EdgeInsets.fromLTRB(12,0,12,100),
            itemCount:filtered.length,
            itemBuilder:(_,i){
              final e = filtered[i];
              final c = e.isError?V.err:e.isWarning?V.warn:e.isKernel?V.info:v.mid;
              return Padding(
                padding:const EdgeInsets.symmetric(vertical:1.5),
                child:Row(crossAxisAlignment:CrossAxisAlignment.start, children:[
                  Container(width:2, margin:const EdgeInsets.only(right:8, top:2),
                    height:14, color:c),
                  Expanded(child:RichText(text:TextSpan(children:[
                    TextSpan(text:'${e.time} ', style:GoogleFonts.dmMono(fontSize:9, color:v.lo)),
                    TextSpan(text:'[${e.process}] ', style:GoogleFonts.dmMono(fontSize:9, color:v.mid)),
                    TextSpan(text:e.message, style:GoogleFonts.dmMono(fontSize:9, color:c)),
                  ]))),
                ]));
            })),
    ]);
  }
}

Widget _FilterBtn(String label, String key2, String cur, VoidCallback onTap, VC v, {Color? color}) {
  final sel = key2 == cur;
  final c   = color ?? v.accent;
  return GestureDetector(onTap:onTap, child:AnimatedContainer(
    duration:const Duration(milliseconds:120),
    padding:const EdgeInsets.symmetric(horizontal:10, vertical:4),
    decoration:BoxDecoration(
      color:sel?c.withOpacity(0.12):Colors.transparent,
      borderRadius:BorderRadius.circular(4),
      border:Border.all(color:sel?c:v.wire)),
    child:Text(label, style:GoogleFonts.outfit(fontSize:9, fontWeight:FontWeight.w800, color:sel?c:v.mid))));
}

// ── Config tab ────────────────────────────────────────────────────────────────
class _ConfigTab extends ConsumerStatefulWidget {
  const _ConfigTab();
  @override ConsumerState<_ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends ConsumerState<_ConfigTab> {
  bool _backupBusy=false, _restoreBusy=false, _resetBusy=false;

  @override Widget build(BuildContext context) {
    final v      = Theme.of(context).extension<VC>()!;
    final config = ref.watch(configProvider);
    final isDark = ref.watch(darkModeProvider);
    final accent = ref.watch(accentProvider);

    return ListView(
      padding:const EdgeInsets.fromLTRB(16,16,16,100),
      children:[

        // ── Connection info ───────────────────────────────────────────────
        _Section('CONNECTION', v),
        VCard(padding:const EdgeInsets.all(14), child:Row(children:[
          Container(width:36, height:36,
            decoration:BoxDecoration(color:v.accent.withOpacity(0.1), borderRadius:BorderRadius.circular(8)),
            child:Icon(Icons.terminal_rounded, size:18, color:v.accent)),
          const SizedBox(width:12),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
            Text(config?.host??'Not configured',
              style:GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w700, color:v.hi)),
            Text('${config?.username??'root'}  ·  SSH :${config?.sshPort??22}',
              style:GoogleFonts.dmMono(fontSize:10, color:v.mid)),
          ])),
          TextButton(
            onPressed:()=>Navigator.push(context, MaterialPageRoute(builder:(_)=>const SetupScreen())),
            child:const Text('CHANGE')),
        ])),
        const SizedBox(height:20),

        // ── Display ───────────────────────────────────────────────────────
        _Section('DISPLAY', v),
        VCard(padding:const EdgeInsets.all(14), child:Column(children:[
          Row(children:[
            Icon(isDark?Icons.wb_sunny_rounded:Icons.dark_mode_rounded, size:18, color:v.mid),
            const SizedBox(width:12),
            Expanded(child:Text(isDark?'Dark mode':'Light mode',
              style:GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w600, color:v.hi))),
            Switch(value:isDark, onChanged:(_)=>ref.read(darkModeProvider.notifier).toggle()),
          ]),
          Divider(color:v.wire, height:24),
          Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
            Text('ACCENT', style:GoogleFonts.outfit(fontSize:9, fontWeight:FontWeight.w800, color:v.mid, letterSpacing:1.5)),
            const SizedBox(height:12),
            Wrap(spacing:10, runSpacing:10, children:AccentColor.values.map((a){
              final sel = a == accent;
              return GestureDetector(
                onTap:()=>ref.read(accentProvider.notifier).set(a),
                child:AnimatedContainer(
                  duration:const Duration(milliseconds:200),
                  width:34, height:34,
                  decoration:BoxDecoration(color:a.primary, shape:BoxShape.circle,
                    border:Border.all(color:sel?Colors.white:Colors.transparent, width:2.5),
                    boxShadow:sel?[BoxShadow(color:a.primary.withOpacity(0.5), blurRadius:8, spreadRadius:2)]:null),
                  child:sel?const Icon(Icons.check_rounded, color:Colors.white, size:16):null));
            }).toList()),
          ]),
        ])),
        const SizedBox(height:20),

        // ── Router actions ────────────────────────────────────────────────
        _Section('ROUTER', v),
        VCard(padding:const EdgeInsets.all(14), child:Column(children:[
          _ActionRow(
            icon:Icons.restart_alt_rounded, color:V.warn,
            title:'Reboot Router', subtitle:'Graceful restart',
            busy:false,
            onTap:()=>_confirmReboot(context)),
        ])),
        const SizedBox(height:20),

        // ── Tools ────────────────────────────────────────────────────────
        _Section('TOOLS', v),
        VCard(padding:const EdgeInsets.all(14), child:Column(children:[
          _ActionRow(
            icon:Icons.folder_rounded, color:V.warn,
            title:'File Browser', subtitle:'Browse router filesystem',
            busy:false,
            onTap:()=>Navigator.push(context, MaterialPageRoute(builder:(_)=>const FilesScreenWrapper()))),
        ])),
        const SizedBox(height:20),

        // ── Backup & Restore ──────────────────────────────────────────────
        _Section('BACKUP', v),
        VCard(padding:const EdgeInsets.all(14), child:Column(children:[
          _ActionRow(
            icon:Icons.download_rounded, color:V.ok,
            title:'Export Config', subtitle:'Save nvram to file',
            busy:_backupBusy,
            onTap:_backup),
          Divider(color:v.wire, height:24),
          _ActionRow(
            icon:Icons.upload_rounded, color:V.info,
            title:'Import Config', subtitle:'Restore from file',
            busy:_restoreBusy,
            onTap:_restore),
          Divider(color:v.wire, height:24),
          _ActionRow(
            icon:Icons.delete_forever_rounded, color:V.err,
            title:'Factory Reset', subtitle:'Erase all nvram',
            busy:_resetBusy,
            onTap:()=>_factoryReset(context)),
        ])),
        const SizedBox(height:20),

        // ── App ────────────────────────────────────────────────────────────
        _Section('APP', v),
        VCard(padding:const EdgeInsets.all(14), child:_ActionRow(
          icon:Icons.logout_rounded, color:V.err,
          title:'Disconnect & Reset', subtitle:'Clear saved credentials',
          busy:false,
          onTap:()=>_disconnect(context))),
        const SizedBox(height:20),

        Center(child:Text('VOID  ·  FreshTomato Manager',
          style:GoogleFonts.outfit(fontSize:9, color:v.lo, letterSpacing:1))),
      ],
    );
  }

  Widget _Section(String t, VC v) => Padding(
    padding:const EdgeInsets.only(bottom:8),
    child:Text(t, style:GoogleFonts.outfit(fontSize:9, fontWeight:FontWeight.w800, color:v.lo, letterSpacing:2)));

  Future<void> _confirmReboot(BuildContext ctx) async {
    final ok = await showDialog<bool>(context:ctx, builder:(_)=>AlertDialog(
      title:const Text('Reboot Router'),
      content:const Text('The router will restart. You will be disconnected temporarily.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false), child:const Text('Cancel')),
        TextButton(onPressed:()=>Navigator.pop(ctx,true),  child:const Text('Reboot', style:TextStyle(color:V.warn))),
      ]));
    if (ok==true) {
      await ref.read(sshServiceProvider).run('reboot 2>/dev/null || true');
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content:Text('Rebooting…'), backgroundColor:V.warn));
    }
  }

  Future<void> _disconnect(BuildContext ctx) async {
    final ok = await showDialog<bool>(context:ctx, builder:(_)=>AlertDialog(
      title:const Text('Disconnect'),
      content:const Text('This will clear saved SSH credentials.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false), child:const Text('Cancel')),
        TextButton(onPressed:()=>Navigator.pop(ctx,true),  child:const Text('Disconnect', style:TextStyle(color:V.err))),
      ]));
    if (ok==true) {
      await ref.read(configProvider.notifier).clear();
      ref.read(sshServiceProvider).disconnect();
      if (ctx.mounted) Navigator.pushAndRemoveUntil(ctx,
        MaterialPageRoute(builder:(_)=>const SetupScreen()), (_)=>false);
    }
  }

  Future<void> _factoryReset(BuildContext ctx) async {
    final ok = await showDialog<bool>(context:ctx, builder:(_)=>AlertDialog(
      title:const Text('Factory Reset'),
      content:const Text('This will erase ALL router configuration. This cannot be undone.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false), child:const Text('Cancel')),
        TextButton(onPressed:()=>Navigator.pop(ctx,true),  child:const Text('RESET', style:TextStyle(color:V.err))),
      ]));
    if (ok==true) {
      setState(()=>_resetBusy=true);
      try {
        await ref.read(sshServiceProvider).run('nvram erase; reboot');
        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content:Text('Factory reset initiated'), backgroundColor:V.err));
      } finally { if (mounted) setState(()=>_resetBusy=false); }
    }
  }

  Future<void> _backup() async {
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    setState(()=>_backupBusy=true);
    try {
      await ssh.run('nvram show > /tmp/nvram_backup.cfg 2>/dev/null');
      final sz = (await ssh.run('wc -c < /tmp/nvram_backup.cfg 2>/dev/null||echo 0')).trim();
      if ((int.tryParse(sz.split(RegExp(r'\s+')).first)??0) < 10) throw Exception('Empty');
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port   = server.port;
      final ip     = await _localIp();
      if (ip==null) { await server.close(force:true); throw Exception('No local IP'); }
      final comp = Completer<List<int>>();
      server.listen((req) async {
        final b=<int>[]; await for(final c in req){b.addAll(c);}
        req.response.statusCode=200; await req.response.close();
        await server.close(force:true); comp.complete(b);
      });
      await ssh.run('curl -s -X POST --data-binary @/tmp/nvram_backup.cfg http://$ip:$port/ 2>/dev/null || wget -q -O /dev/null --post-file=/tmp/nvram_backup.cfg http://$ip:$port/ 2>/dev/null');
      final bytes = await comp.future.timeout(const Duration(seconds:30));
      if (bytes.isEmpty) throw Exception('Empty data');
      final dir  = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      final ts   = DateTime.now().toIso8601String().replaceAll(':','-').substring(0,19);
      final file = File('${dir.path}/tomato_$ts.cfg');
      await file.writeAsBytes(bytes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text('Saved: tomato_$ts.cfg  (${bytes.length} B)'),
        backgroundColor:V.ok));
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text('Backup failed: $e'), backgroundColor:V.err));
    } finally { if(mounted) setState(()=>_backupBusy=false); }
  }

  Future<void> _restore() async {
    final result = await FilePicker.platform.pickFiles(type:FileType.any);
    if (result==null||result.files.single.path==null) return;
    final ok = await showDialog<bool>(context:context, builder:(_)=>AlertDialog(
      title:const Text('Restore Config'),
      content:const Text('This will overwrite all router settings. Continue?'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(context,false), child:const Text('Cancel')),
        TextButton(onPressed:()=>Navigator.pop(context,true),  child:const Text('Restore', style:TextStyle(color:V.warn))),
      ]));
    if (ok!=true) return;
    setState(()=>_restoreBusy=true);
    try {
      final bytes = await File(result.files.single.path!).readAsBytes();
      final isText = bytes.isNotEmpty && bytes[0]>=32 && bytes[0]<127;
      final ssh = ref.read(sshServiceProvider);
      if (isText) {
        final lines = utf8.decode(bytes, allowMalformed:true).split('\n');
        final cmds  = <String>[];
        for (final ln in lines) {
          final t = ln.trim(); if (t.isEmpty) continue;
          final eq = t.indexOf('='); if (eq<1) continue;
          final k = t.substring(0,eq); final vl = t.substring(eq+1).replaceAll("'","'\\''");
          cmds.add("nvram set '$k'='$vl'");
        }
        for (var i=0; i<cmds.length; i+=20) {
          await ssh.run(cmds.sublist(i,(i+20).clamp(0,cmds.length)).join(' && '));
        }
        await ssh.run('nvram commit');
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Config restored — reboot to apply'), backgroundColor:V.ok));
    } catch(e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:Text('Restore failed: $e'), backgroundColor:V.err));
    } finally { if(mounted) setState(()=>_restoreBusy=false); }
  }

  Future<String?> _localIp() async {
    try {
      final ifaces = await NetworkInterface.list(type:InternetAddressType.IPv4);
      for (final i in ifaces) {
        if (i.name.startsWith('wlan')||i.name.startsWith('en')||i.name.startsWith('eth')) {
          return i.addresses.first.address;
        }
      }
      if (ifaces.isNotEmpty) return ifaces.first.addresses.first.address;
    } catch(_) {}
    return null;
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon; final Color color; final String title, subtitle;
  final bool busy; final VoidCallback onTap;
  const _ActionRow({required this.icon, required this.color, required this.title,
    required this.subtitle, required this.busy, required this.onTap});
  @override Widget build(BuildContext ctx) {
    final v = Theme.of(ctx).extension<VC>()!;
    return GestureDetector(
      behavior:HitTestBehavior.opaque,
      onTap:busy?null:onTap,
      child:Row(children:[
        Container(width:36, height:36,
          decoration:BoxDecoration(color:color.withOpacity(0.1), borderRadius:BorderRadius.circular(8)),
          child:busy
            ? Padding(padding:const EdgeInsets.all(8),
                child:CircularProgressIndicator(strokeWidth:2, color:color))
            : Icon(icon, size:18, color:color)),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
          Text(title,    style:GoogleFonts.outfit(fontSize:13, fontWeight:FontWeight.w600, color:v.hi)),
          Text(subtitle, style:GoogleFonts.dmMono(fontSize:10, color:v.mid)),
        ])),
        Icon(Icons.chevron_right_rounded, size:18, color:v.lo),
      ]));
  }
}

// ── stub exports so bandwidth_screen and files_screen stay importable ─────────
// These are pushed from SystemScreen config tab

// ── Wrappers so old screens work inside new nav ───────────────────────────────
class FilesScreenWrapper extends StatelessWidget {
  const FilesScreenWrapper({super.key});
  @override Widget build(BuildContext ctx) => const FilesScreen();
}

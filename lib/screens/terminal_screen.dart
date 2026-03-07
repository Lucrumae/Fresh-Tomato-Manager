import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';

// ─── ANSI Parser ──────────────────────────────────────────────────────────────
class _Span {
  final String text;
  final Color? fg, bg;
  final bool bold;
  const _Span(this.text, {this.fg, this.bg, this.bold = false});
}

List<_Span> _parseAnsi(String raw) {
  const base = [
    Color(0xFF1E1E2E), Color(0xFFCC3333), Color(0xFF44A744), Color(0xFFCDAA1A),
    Color(0xFF4F9EE8), Color(0xFFAA44AA), Color(0xFF44AAAA), Color(0xFFBBBBBB),
    Color(0xFF666666), Color(0xFFFF5555), Color(0xFF55FF55), Color(0xFFFFFF55),
    Color(0xFF6699FF), Color(0xFFFF55FF), Color(0xFF55FFFF), Color(0xFFFFFFFF),
  ];
  Color? fg, bg; bool bold = false;
  final out = <_Span>[];

  Color x256(int i) {
    if (i < 16) return base[i];
    if (i < 232) { final n=i-16; return Color.fromARGB(255,(n~/36)*51,((n~/6)%6)*51,(n%6)*51); }
    final v = 8+(i-232)*10; return Color.fromARGB(255,v,v,v);
  }

  void add(String t) {
    if (t.isEmpty) return;
    if (out.isNotEmpty && out.last.fg==fg && out.last.bg==bg && out.last.bold==bold)
      out[out.length-1] = _Span(out.last.text+t, fg:fg, bg:bg, bold:bold);
    else out.add(_Span(t, fg:fg, bg:bg, bold:bold));
  }

  final re = RegExp(r'\x1B\[([0-9;]*)m|([\s\S])');
  for (final m in re.allMatches(raw)) {
    if (m.group(1) != null) {
      final cs = m.group(1)!.split(';').map((s)=>int.tryParse(s)??0).toList();
      for (int i=0; i<cs.length; i++) {
        final c = cs[i];
        if (c==0) { fg=null; bg=null; bold=false; }
        else if (c==1) bold=true;
        else if (c==22) bold=false;
        else if (c>=30&&c<=37) fg=base[c-30+(bold?8:0)];
        else if (c==39) fg=null;
        else if (c>=40&&c<=47) bg=base[c-40];
        else if (c==49) bg=null;
        else if (c>=90&&c<=97) fg=base[c-82];
        else if (c>=100&&c<=107) bg=base[c-92];
        else if ((c==38||c==48)&&i+2<cs.length&&cs[i+1]==5) {
          final col=x256(cs[i+2].clamp(0,255));
          if(c==38) fg=col; else bg=col; i+=2;
        }
      }
    } else if (m.group(2)!=null) add(m.group(2)!);
  }
  return out;
}

class _Line {
  final String plain;
  final List<_Span> spans;
  final bool partial;
  _Line(this.plain, this.spans, {this.partial=false});
}

// ─── Terminal Screen ──────────────────────────────────────────────────────────
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});
  @override ConsumerState<TerminalScreen> createState() => _TS();
}

class _TS extends ConsumerState<TerminalScreen> with WidgetsBindingObserver {
  final _scroll = ScrollController();
  final _focus  = FocusNode();
  final _input  = TextEditingController();
  final _lines  = <_Line>[];
  SSHSession? _sess;
  bool _conn=false, _loading=false;
  bool _isDark=true; // updated each build
  StreamSubscription? _s1, _s2;
  String _buf='';
  final _hist=<String>[];
  int _hi=-1;
  bool _kb=false;

  // Colors ditentukan saat build berdasarkan theme

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focus.addListener((){if(mounted)setState((){});});
    _start();
  }

  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _s1?.cancel(); _s2?.cancel(); _sess?.close();
    _scroll.dispose(); _focus.dispose(); _input.dispose();
    super.dispose();
  }

  @override void didChangeMetrics() {
    final v = WidgetsBinding.instance.window.viewInsets.bottom > 150;
    if (v!=_kb && mounted) { setState(()=>_kb=v); if(v) _bot(); }
  }

  Future<void> _start() async {
    setState((){ _loading=true; _buf=''; });
    _addSys('Connecting...');
    try {
      final ssh = ref.read(sshServiceProvider);
      if (!ssh.isConnected || ssh.client==null) {
        _addSys('Not connected. Go back and reconnect.'); setState(()=>_loading=false); return;
      }
      _sess = await ssh.client!.shell(
        pty: SSHPtyConfig(width:200, height:50, type:'xterm-256color'));
      setState((){ _loading=false; _conn=true; });
      _s1 = _sess!.stdout.listen(_onData,
        onDone:(){ if(mounted){ _addSys('[Session closed]'); setState(()=>_conn=false); }});
      _s2 = _sess!.stderr.listen((d)=>_onData(d, err:true));
    } catch(e) { _addSys('Error: $e'); setState(()=>_loading=false); }
  }

  void _onData(Uint8List data, {bool err=false}) {
    var t = String.fromCharCodes(data)
      .replaceAll('\r\n','\n').replaceAll('\r','\n')
      .replaceAll(RegExp(r'\x1B\[[0-9;]*[ABCDHF]'),'')
      .replaceAll(RegExp(r'\x1B\[[0-9;]*[JK]'),'')
      .replaceAll(RegExp(r'\x1B\[[0-9;]*[hl]'),'')
      .replaceAll(RegExp(r'\x1B\][^\x07]*\x07'),'')
      .replaceAll(RegExp(r'\x1B\([AB]'),'');
    _buf+=t;
    final ps=_buf.split('\n'); _buf=ps.removeLast();
    for(final p in ps) _addAnsi(p, err:err);
    if(_buf.isNotEmpty){ _addAnsi(_buf, partial:true, err:err); _buf=''; }
  }

  void _addSys(String t) {
    if(!mounted) return;
    setState((){ _lines.add(_Line(t,[_Span(t,fg:AppTheme.terminal.withOpacity(0.6))]));
      if(_lines.length>2000) _lines.removeRange(0,_lines.length-2000); }); _bot();
  }

  void _addAnsi(String raw, {bool partial=false, bool err=false}) {
    if(!mounted) return;
    final plain=raw.replaceAll(RegExp(r'\x1B\[[0-9;]*m'),'');
    final spans=err?[_Span(plain,fg:const Color(0xFFF38BA8))]
      :(_parseAnsi(raw).isEmpty?[_Span(plain,fg:const Color(0xFFCDD6F4))]:_parseAnsi(raw));
    setState((){
      if(_lines.isNotEmpty&&_lines.last.partial){
        final p=_lines.last;
        _lines[_lines.length-1]=_Line(p.plain+plain,[...p.spans,...spans],partial:partial);
      } else _lines.add(_Line(plain,spans,partial:partial));
      if(_lines.length>2000) _lines.removeRange(0,_lines.length-2000);
    }); _bot();
  }

  void _send(String cmd) {
    if(!_conn||_sess==null) return;
    if(cmd.isNotEmpty&&(_hist.isEmpty||_hist.last!=cmd)){
      _hist.add(cmd); if(_hist.length>100) _hist.removeAt(0);
    }
    _hi=-1; _sess!.stdin.add(Uint8List.fromList('$cmd\n'.codeUnits));
    _input.clear(); _bot();
  }

  void _raw(List<int> b){ if(_conn) _sess?.stdin.add(Uint8List.fromList(b)); }

  void _bot() => WidgetsBinding.instance.addPostFrameCallback((_){
    if(_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent,
      duration:const Duration(milliseconds:80), curve:Curves.easeOut);
  });

  void _hUp(){ if(_hist.isEmpty)return; setState((){
    _hi=(_hi+1).clamp(0,_hist.length-1);
    _input.text=_hist[_hist.length-1-_hi];
    _input.selection=TextSelection.collapsed(offset:_input.text.length); }); }

  void _hDn(){ if(_hi<=0){setState((){_hi=-1;_input.clear();});return;} setState((){
    _hi--;
    _input.text=_hist[_hist.length-1-_hi];
    _input.selection=TextSelection.collapsed(offset:_input.text.length); }); }

  static const _quick=[
    ('top -bn1|head -25','top'),('free -m','free'),('df -h','df'),
    ('ip addr','ip'),('arp -a','arp'),('logread|tail -40','logs'),
    ('uptime','uptime'),('ps','ps'),('ls -la','ls'),
  ];

  @override
  Widget build(BuildContext context) {
    // Colors mengikuti tema yang dipilih
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _isDark = isDark;
    final bg  = isDark ? const Color(0xFF0B0F1A) : const Color(0xFFF0F4F8);
    final bar = isDark ? const Color(0xFF0F1622) : const Color(0xFFE2E8F0);
    final brd = isDark ? const Color(0xFF1A2535) : const Color(0xFFCBD5E0);
    final textColor = isDark ? const Color(0xFFCDD6F4) : const Color(0xFF1A202C);

    return Container(
      color: bg,
      child: Column(children:[

        // ── TOP BAR: Reconnect button ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal:12, vertical:6),
          color: bar,
          child: Row(children:[
            Container(width:8, height:8, decoration:BoxDecoration(
              color:_conn?AppTheme.terminal:Colors.redAccent,
              shape:BoxShape.circle)),
            const SizedBox(width:8),
            Text(_conn?'Connected':'Disconnected',
              style:GoogleFonts.jetBrainsMono(
                color:_conn?AppTheme.terminal:Colors.redAccent,
                fontSize:12, fontWeight:FontWeight.w500)),
            const Spacer(),
            // Reconnect button
            GestureDetector(
              onTap:(){
                _s1?.cancel(); _s2?.cancel(); _sess?.close();
                setState((){ _conn=false; _lines.clear(); });
                _start();
              },
              child:Container(
                padding:const EdgeInsets.symmetric(horizontal:12, vertical:5),
                decoration:BoxDecoration(
                  color:AppTheme.terminal.withOpacity(0.1),
                  border:Border.all(color:AppTheme.terminal.withOpacity(0.4)),
                  borderRadius:BorderRadius.circular(6)),
                child:Row(mainAxisSize:MainAxisSize.min, children:[
                  Icon(Icons.refresh_rounded, color:AppTheme.terminal, size:15),
                  const SizedBox(width:5),
                  Text('Reconnect',style:GoogleFonts.jetBrainsMono(
                    color:AppTheme.terminal, fontSize:12)),
                ]),
              ),
            ),
          ]),
        ),

        // ── OUTPUT AREA ──────────────────────────────────────────────────────
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:(){
              if(_focus.hasFocus) _focus.unfocus();
              else _focus.requestFocus();
            },
            child: Container(
              color:bg, width:double.infinity,
              child:_loading
                ? Center(child:Column(mainAxisSize:MainAxisSize.min, children:[
                    const SizedBox(width:18,height:18,
                      child:CircularProgressIndicator(color:AppTheme.terminal,strokeWidth:1.5)),
                    const SizedBox(height:10),
                    Text('Starting shell...',style:GoogleFonts.jetBrainsMono(
                      color:AppTheme.terminal,fontSize:12)),
                  ]))
                : ListView.builder(
                    controller:_scroll,
                    padding:const EdgeInsets.fromLTRB(10,6,10,4),
                    itemCount:_lines.length,
                    itemBuilder:(c,i)=>_buildLine(_lines[i]),
                  ),
            ),
          ),
        ),

        // ── KEYBOARD TOOLBAR (muncul di atas keyboard) ────────────────────
        if (_kb) ...[
          // Row 1 (atas): quick commands — top, free, df, dll
          Container(
            height:36,
            color:bar,
            child:ListView(
              scrollDirection:Axis.horizontal,
              padding:const EdgeInsets.symmetric(horizontal:6,vertical:5),
              children:_quick.map((q)=>_qBtn(q.$2,()=>_send(q.$1))).toList(),
            ),
          ),
          // Row 2 (bawah): ctrl keys + history + clear + restart
          Container(
            height:36,
            decoration:BoxDecoration(
              color:const Color(0xFF080C14),
              border:Border(top:BorderSide(color:_brd))),
            child:ListView(
              scrollDirection:Axis.horizontal,
              padding:const EdgeInsets.symmetric(horizontal:6,vertical:5),
              children:[
                _cBtn('↑',_hUp, col:Colors.white70),
                _cBtn('↓',_hDn, col:Colors.white70),
                _sep(),
                _cBtn('^C',()=>_raw([3])),
                _cBtn('^D',()=>_raw([4])),
                _cBtn('^Z',()=>_raw([26])),
                _cBtn('^L',()=>_raw([12])),
                _cBtn('^A',()=>_raw([1])),
                _cBtn('^E',()=>_raw([5])),
                _cBtn('^U',()=>_raw([21])),
                _cBtn('^W',()=>_raw([23])),
                _cBtn('^R',()=>_raw([18])),
                _cBtn('Tab',()=>_raw([9]), col:Colors.white54),
                _cBtn('Esc',()=>_raw([27]), col:Colors.white54),
                _sep(),
                _cBtn('Clear',()=>setState(()=>_lines.clear()), col:AppTheme.warning),
              ],
            ),
          ),
          // Input bar
          Container(
            color:_bar,
            padding:const EdgeInsets.fromLTRB(10,2,10,6),
            child:Row(children:[
              Text('# ',style:GoogleFonts.jetBrainsMono(
                color:AppTheme.terminal,fontSize:13,fontWeight:FontWeight.bold)),
              Expanded(child:TextField(
                controller:_input, focusNode:_focus, enabled:_conn,
                style:GoogleFonts.jetBrainsMono(color:Colors.white,fontSize:13),
                cursorColor:AppTheme.terminal,
                decoration:const InputDecoration(
                  isDense:true,border:InputBorder.none,
                  enabledBorder:InputBorder.none,focusedBorder:InputBorder.none,
                  filled:false,contentPadding:EdgeInsets.symmetric(vertical:8),
                  hintText:'command...',
                  hintStyle:TextStyle(color:isDark?const Color(0xFF2E3F55):const Color(0xFF8A9AB5),fontSize:13)),
                onSubmitted:_send, textInputAction:TextInputAction.send,
              )),
              GestureDetector(
                onTap:()=>_send(_input.text),
                child:const Padding(padding:EdgeInsets.all(6),
                  child:Icon(Icons.send_rounded,color:AppTheme.terminal,size:17))),
            ]),
          ),
        ],

        // ── BOTTOM BAR: status + quick cmds (saat keyboard tertutup) ─────
        if (!_kb)
          Container(
            height:36,
            decoration:BoxDecoration(color:bar,
              border:Border(top:BorderSide(color:brd))),
            child:Row(children:[
              GestureDetector(
                onTap:()=>_focus.requestFocus(),
                child:Container(
                  padding:const EdgeInsets.symmetric(horizontal:10),
                  child:Icon(Icons.keyboard_rounded,
                    color:AppTheme.terminal.withOpacity(0.6),size:16)),
              ),
              Expanded(child:ListView(
                scrollDirection:Axis.horizontal,
                padding:const EdgeInsets.symmetric(vertical:5),
                children:_quick.map((q)=>Padding(
                  padding:const EdgeInsets.only(right:5),
                  child:GestureDetector(
                    onTap:()=>_send(q.$1),
                    child:Container(
                      padding:const EdgeInsets.symmetric(horizontal:9,vertical:2),
                      decoration:BoxDecoration(
                        border:Border.all(color:AppTheme.terminal.withOpacity(0.25)),
                        borderRadius:BorderRadius.circular(4)),
                      child:Text(q.$2,style:GoogleFonts.jetBrainsMono(
                        color:AppTheme.terminal,fontSize:11)),
                    )),
                )).toList(),
              )),
            ]),
          ),

        // Hidden input so keyboard can be triggered
        SizedBox(height:0, child:Opacity(opacity:0, child:TextField(
          focusNode:_focus, controller:_input,
          onSubmitted:_send, textInputAction:TextInputAction.send,
        ))),
      ]),
    );
  }

  Widget _buildLine(_Line l) {
    if(l.spans.isEmpty) return const SizedBox(height:15);
    return RichText(text:TextSpan(children:l.spans.map((s)=>TextSpan(
      text:s.text,
      style:GoogleFonts.jetBrainsMono(
        fontSize:12, height:1.4,
        color:s.fg??(_isDark?const Color(0xFFCDD6F4):const Color(0xFF1A202C)),
        backgroundColor:s.bg,
        fontWeight:s.bold?FontWeight.bold:FontWeight.normal),
    )).toList()));
  }

  Widget _qBtn(String label, VoidCallback fn) =>
    GestureDetector(onTap:fn, child:Container(
      margin:const EdgeInsets.only(right:5),
      padding:const EdgeInsets.symmetric(horizontal:10,vertical:3),
      decoration:BoxDecoration(
        border:Border.all(color:AppTheme.terminal.withOpacity(0.3)),
        borderRadius:BorderRadius.circular(4)),
      child:Text(label,style:GoogleFonts.jetBrainsMono(
        color:AppTheme.terminal,fontSize:11))));

  Widget _cBtn(String label, VoidCallback fn, {Color? col}) =>
    GestureDetector(onTap:fn, child:Container(
      margin:const EdgeInsets.only(right:4),
      padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
      decoration:BoxDecoration(
        color:(col??AppTheme.terminal).withOpacity(0.08),
        border:Border.all(color:(col??AppTheme.terminal).withOpacity(0.3)),
        borderRadius:BorderRadius.circular(4)),
      child:Text(label,style:GoogleFonts.jetBrainsMono(
        color:col??AppTheme.terminal,fontSize:11,fontWeight:FontWeight.w500))));

  Widget _sep() {
    final isDark = _isDark;
    final brd = isDark ? const Color(0xFF1A2535) : const Color(0xFFCBD5E0);
    return Container(width:1, color:brd,
      margin:const EdgeInsets.symmetric(horizontal:4,vertical:5));
  }
}

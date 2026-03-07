import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';

//  ANSI Parser 
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
  final List<_Span> spans;
  final bool partial;
  _Line(this.spans, {this.partial=false});
}

//  Terminal Screen 
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});
  @override ConsumerState<TerminalScreen> createState() => _TS();
}

class _TS extends ConsumerState<TerminalScreen> {
  final _scroll  = ScrollController();
  final _focus   = FocusNode();
  final _input   = TextEditingController();
  final _lines   = <_Line>[];
  SSHSession? _sess;
  bool _conn=false, _loading=false;
  StreamSubscription? _s1, _s2;
  String _buf='';
  final _hist=<String>[];
  int _hi=-1;

  // Theme-reactive colors - updated each build()
  bool   _isDark = true;
  Color  _accent = const Color(0xFF00E5A0);
  Color  _bg     = const Color(0xFF0B0F1A);
  Color  _bar    = const Color(0xFF0F1622);
  Color  _brd    = const Color(0xFF1A2535);

  void _updateColors(BuildContext ctx) {
    _isDark = Theme.of(ctx).brightness == Brightness.dark;
    _accent = Theme.of(ctx).extension<AppColors>()?.accent ?? const Color(0xFF00E5A0);
    _bg  = _isDark ? const Color(0xFF0B0F1A) : const Color(0xFFF0F4F8);
    _bar = _isDark ? const Color(0xFF0F1622) : const Color(0xFFE2E8F0);
    _brd = _isDark ? const Color(0xFF1A2535) : const Color(0xFFCBD5E0);
  }

  @override void initState() { super.initState(); _start(); }

  @override void dispose() {
    _s1?.cancel(); _s2?.cancel(); _sess?.close();
    _scroll.dispose(); _focus.dispose(); _input.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() { _loading=true; _buf=''; _lines.clear(); });
    _addSys('Connecting...');
    try {
      final ssh = ref.read(sshServiceProvider);
      if (!ssh.isConnected || ssh.client==null) {
        _addSys('Not connected. Tap Reconnect.'); setState(()=>_loading=false); return;
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
    setState((){
      _lines.add(_Line([_Span(t, fg:_accent.withOpacity(0.6))]));
    }); _bot();
  }

  void _addAnsi(String raw, {bool partial=false, bool err=false}) {
    if(!mounted) return;
    final plain = raw.replaceAll(RegExp(r'\x1B\[[0-9;]*m'),'');
    final spans = err
      ? [_Span(plain, fg:const Color(0xFFF38BA8))]
      : (_parseAnsi(raw).isEmpty ? [_Span(plain, fg:const Color(0xFFCDD6F4))] : _parseAnsi(raw));
    setState((){
      if(_lines.isNotEmpty && _lines.last.partial){
        final p=_lines.last;
        _lines[_lines.length-1]=_Line([...p.spans,...spans], partial:partial);
      } else _lines.add(_Line(spans, partial:partial));
      if(_lines.length>2000) _lines.removeRange(0,_lines.length-2000);
    }); _bot();
  }

  void _send(String cmd) {
    if(!_conn||_sess==null) return;
    if(cmd.isNotEmpty&&(_hist.isEmpty||_hist.last!=cmd)){
      _hist.add(cmd); if(_hist.length>100) _hist.removeAt(0);
    }
    _hi=-1;
    _sess!.stdin.add(Uint8List.fromList('$cmd\n'.codeUnits));
    _input.clear();
    _focus.requestFocus();
    _bot();
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
    _updateColors(context);
    final textColor = _isDark ? const Color(0xFFCDD6F4) : const Color(0xFF1A202C);

    return SafeArea(
      child: Container(
        color: _bg,
        child: Column(children: [

          //  TOP BAR 
          Container(
            padding: const EdgeInsets.symmetric(horizontal:12, vertical:6),
            color: _bar,
            child: Row(children:[
              Container(width:8, height:8, decoration:BoxDecoration(
                color:_conn ? _accent : Colors.redAccent,
                shape:BoxShape.circle)),
              const SizedBox(width:8),
              Text(_conn ? 'Connected' : 'Disconnected',
                style:GoogleFonts.jetBrainsMono(
                  color:_conn ? _accent : Colors.redAccent,
                  fontSize:11, fontWeight:FontWeight.w500)),
              const Spacer(),
              GestureDetector(
                onTap:(){
                  _s1?.cancel(); _s2?.cancel(); _sess?.close();
                  setState((){ _conn=false; _lines.clear(); });
                  _start();
                },
                child:Container(
                  padding:const EdgeInsets.symmetric(horizontal:10, vertical:4),
                  decoration:BoxDecoration(
                    color:_accent.withOpacity(0.1),
                    border:Border.all(color:_accent.withOpacity(0.4)),
                    borderRadius:BorderRadius.circular(6)),
                  child:Row(mainAxisSize:MainAxisSize.min, children:[
                    Icon(Icons.refresh_rounded, color:_accent, size:14),
                    const SizedBox(width:4),
                    Text('Reconnect', style:GoogleFonts.jetBrainsMono(
                      color:_accent, fontSize:11)),
                  ]),
                ),
              ),
            ]),
          ),

          //  OUTPUT 
          Expanded(
            child: _loading
              ? Center(child:Column(mainAxisSize:MainAxisSize.min, children:[
                  SizedBox(width:18, height:18,
                    child:CircularProgressIndicator(color:_accent, strokeWidth:1.5)),
                  const SizedBox(height:10),
                  Text('Starting shell...', style:GoogleFonts.jetBrainsMono(
                    color:_accent, fontSize:11)),
                ]))
              : ListView.builder(
                  controller:_scroll,
                  padding:const EdgeInsets.fromLTRB(8,4,8,4),
                  itemCount:_lines.length,
                  itemBuilder:(c,i)=>_buildLine(_lines[i]),
                ),
          ),

          //  ALWAYS-VISIBLE TOOLBAR 
          Container(
            decoration:BoxDecoration(
              color:_bar,
              border:Border(top:BorderSide(color:_brd))),
            child:Column(mainAxisSize:MainAxisSize.min, children:[

              // Row 1: Quick commands
              SizedBox(height:34, child:ListView(
                scrollDirection:Axis.horizontal,
                padding:const EdgeInsets.symmetric(horizontal:6, vertical:5),
                children:_quick.map((q)=>_qBtn(q.$2, ()=>_send(q.$1))).toList(),
              )),

              Divider(height:1, color:_brd),

              // Row 2: Ctrl keys (lengkap)
              SizedBox(height:34, child:ListView(
                scrollDirection:Axis.horizontal,
                padding:const EdgeInsets.symmetric(horizontal:6, vertical:5),
                children:[
                  _cBtn('?', _hUp, col:Colors.white70),
                  _cBtn('?', _hDn, col:Colors.white70),
                  _sep(),
                  _cBtn('^C', ()=>_raw([3])),
                  _cBtn('^D', ()=>_raw([4])),
                  _cBtn('^Z', ()=>_raw([26])),
                  _cBtn('^X', ()=>_raw([24])),
                  _sep(),
                  _cBtn('^L', ()=>_raw([12])),
                  _cBtn('^S', ()=>_raw([19])),
                  _cBtn('^Q', ()=>_raw([17])),
                  _sep(),
                  _cBtn('^A', ()=>_raw([1])),
                  _cBtn('^E', ()=>_raw([5])),
                  _cBtn('Alt?', ()=>_raw([27,98]), col:Colors.white54),
                  _cBtn('Alt->', ()=>_raw([27,102]), col:Colors.white54),
                  _sep(),
                  _cBtn('^U', ()=>_raw([21])),
                  _cBtn('^K', ()=>_raw([11])),
                  _cBtn('^W', ()=>_raw([23])),
                  _cBtn('^Y', ()=>_raw([25])),
                  _sep(),
                  _cBtn('^R', ()=>_raw([18])),
                  _cBtn('^T', ()=>_raw([20])),
                  _cBtn('Tab', ()=>_raw([9]), col:Colors.white54),
                  _cBtn('Esc', ()=>_raw([27]), col:Colors.white54),
                  _cBtn('Del', ()=>_raw([127]), col:Colors.white54),
                  _sep(),
                  _cBtn('Clear', ()=>setState(()=>_lines.clear()), col:AppTheme.warning),
                ],
              )),

              Divider(height:1, color:_brd),

              // Row 3: Input - Enter key keeps keyboard open (like Termius)
              Container(
                color:_bar,
                padding:const EdgeInsets.fromLTRB(10,4,8,6),
                child:Row(children:[
                  Text('# ', style:GoogleFonts.jetBrainsMono(
                    color:_accent, fontSize:13, fontWeight:FontWeight.bold)),
                  Expanded(child:TextField(
                    controller:_input,
                    focusNode:_focus,
                    enabled:_conn,
                    style:GoogleFonts.jetBrainsMono(color:textColor, fontSize:13),
                    cursorColor:_accent,
                    textInputAction:TextInputAction.done,
                    keyboardType:TextInputType.text,
                    maxLines:1,
                    onSubmitted:(val) {
                      _send(val);
                      // Re-request focus immediately to keep keyboard open
                      Future.microtask(() => _focus.requestFocus());
                    },
                    decoration:InputDecoration(
                      isDense:true,
                      border:InputBorder.none,
                      enabledBorder:InputBorder.none,
                      focusedBorder:InputBorder.none,
                      filled:false,
                      contentPadding:const EdgeInsets.symmetric(vertical:6),
                      hintText:'command...',
                      hintStyle:TextStyle(
                        color:_isDark ? const Color(0xFF2E3F55) : const Color(0xFF8A9AB5),
                        fontSize:13)),
                  )),
                  // Send button (tap to execute)
                  GestureDetector(
                    onTap:() => _send(_input.text),
                    child:Container(
                      padding:const EdgeInsets.all(8),
                      decoration:BoxDecoration(
                        color:_accent.withOpacity(0.15),
                        borderRadius:BorderRadius.circular(8)),
                      child:Icon(Icons.keyboard_return_rounded,
                        color:_accent, size:18)),
                  ),
                ]),
              ),

            ]),
          ),

        ]),
      ),
    );
  }

  Widget _buildLine(_Line l) {
    if(l.spans.isEmpty) return const SizedBox(height:13);
    return RichText(
      text:TextSpan(children:l.spans.map((s)=>TextSpan(
        text:s.text,
        style:GoogleFonts.jetBrainsMono(
          fontSize:10.5, height:1.35,
          color:s.fg ?? (_isDark ? const Color(0xFFCDD6F4) : const Color(0xFF1A202C)),
          backgroundColor:s.bg,
          fontWeight:s.bold ? FontWeight.bold : FontWeight.normal),
      )).toList()),
    );
  }

  Widget _qBtn(String label, VoidCallback fn) =>
    GestureDetector(onTap:fn, child:Container(
      margin:const EdgeInsets.only(right:5),
      padding:const EdgeInsets.symmetric(horizontal:9, vertical:2),
      decoration:BoxDecoration(
        border:Border.all(color:_accent.withOpacity(0.3)),
        borderRadius:BorderRadius.circular(4)),
      child:Text(label, style:GoogleFonts.jetBrainsMono(
        color:_accent, fontSize:11))));

  Widget _cBtn(String label, VoidCallback fn, {Color? col}) =>
    GestureDetector(onTap:fn, child:Container(
      margin:const EdgeInsets.only(right:4),
      padding:const EdgeInsets.symmetric(horizontal:7, vertical:2),
      decoration:BoxDecoration(
        color:(col ?? _accent).withOpacity(0.08),
        border:Border.all(color:(col ?? _accent).withOpacity(0.3)),
        borderRadius:BorderRadius.circular(4)),
      child:Text(label, style:GoogleFonts.jetBrainsMono(
        color:col ?? _accent, fontSize:11, fontWeight:FontWeight.w500))));

  Widget _sep() => Container(
    width:1, color:_brd,
    margin:const EdgeInsets.symmetric(horizontal:4, vertical:4));
}

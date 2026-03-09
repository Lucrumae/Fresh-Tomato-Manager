import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});
  @override ConsumerState<LogsScreen> createState() => _LogsScreenState();
}
class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scroll = ScrollController();
  String _filter = 'all';
  String _q = '';
  bool _pinBottom = true;

  @override void initState() {
    super.initState();
    _scroll.addListener(() {
      final at = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
      if (_pinBottom != at) setState(() => _pinBottom = at);
    });
  }
  @override void dispose() { _scroll.dispose(); super.dispose(); }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override Widget build(BuildContext context) {
    final allLogs = ref.watch(logsProvider);
    final v = Theme.of(context).extension<VC>()!;

    final logs = allLogs.where((l) {
      if (_filter == 'err')    return l.isError;
      if (_filter == 'warn')   return l.isWarning;
      if (_filter == 'kernel') return l.isKernel;
      if (_q.isNotEmpty) return l.message.toLowerCase().contains(_q.toLowerCase())
        || l.process.toLowerCase().contains(_q.toLowerCase());
      return true;
    }).toList();

    if (_pinBottom && logs.isNotEmpty) _scrollDown();

    Color levelColor(LogEntry l) {
      if (l.isError)   return V.err;
      if (l.isWarning) return V.warn;
      if (l.isKernel)  return V.info;
      return v.lo;
    }

    return Scaffold(
      backgroundColor: v.dark ? V.d0 : V.l0,
      appBar: AppBar(
        backgroundColor: v.dark ? V.d0 : V.l2,
        title: Text('SYSLOG', style: GoogleFonts.outfit(fontSize: 14,
          fontWeight: FontWeight.w900, color: v.hi, letterSpacing: 1.5)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(80), child: Column(children: [
          Divider(height: 1, color: v.wire),
          Padding(padding: const EdgeInsets.fromLTRB(12, 7, 12, 0), child: TextField(
            onChanged: (x) => setState(() => _q = x),
            style: GoogleFonts.dmMono(fontSize: 12, color: v.hi),
            decoration: InputDecoration(hintText: 'filter log...',
              isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 9),
              prefixIcon: Icon(Icons.filter_alt_rounded, size: 15, color: v.lo)),
          )),
          SingleChildScrollView(scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 9),
            child: Row(children: [
              _FC('ALL',    'all',    v), const SizedBox(width:6),
              _FC('ERR',    'err',    v, color: V.err), const SizedBox(width:6),
              _FC('WARN',   'warn',   v, color: V.warn), const SizedBox(width:6),
              _FC('KERNEL', 'kernel', v, color: V.info),
            ])),
        ])),
      ),
      body: logs.isEmpty
        ? Center(child: Text('no entries', style: GoogleFonts.dmMono(fontSize: 11, color: v.lo)))
        : SelectionArea(child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 80),
            itemCount: logs.length,
            itemBuilder: (_, i) {
              final l = logs[i];
              final lc = levelColor(l);
              final ts = '${l.time.hour.toString().padLeft(2,'0')}:'
                '${l.time.minute.toString().padLeft(2,'0')}:'
                '${l.time.second.toString().padLeft(2,'0')}';
              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: v.wire.withOpacity(0.5)),
                    left: BorderSide(color: lc, width: 2)),
                  color: l.isError ? V.err.withOpacity(0.03) : Colors.transparent),
                padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // timestamp
                  SizedBox(width: 60, child: Text(ts,
                    style: GoogleFonts.dmMono(fontSize: 9, color: v.lo))),
                  const SizedBox(width: 6),
                  // process
                  SizedBox(width: 64, child: Text(l.process,
                    style: GoogleFonts.dmMono(fontSize: 9, color: lc),
                    overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  // message
                  Expanded(child: Text(l.message,
                    style: GoogleFonts.dmMono(fontSize: 10,
                      color: l.isError ? V.err : l.isWarning ? V.warn : v.mid),
                    softWrap: true)),
                ]),
              );
            })),
      floatingActionButton: !_pinBottom ? FloatingActionButton.small(
        onPressed: _scrollDown,
        child: const Icon(Icons.keyboard_arrow_down_rounded)) : null,
    );
  }

  Widget _FC(String lbl, String key, VC v, {Color? color}) {
    final sel = _filter == key;
    final a = color ?? v.accent;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: AnimatedContainer(duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: sel ? a.withOpacity(0.08) : v.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? a.withOpacity(0.35) : v.wire)),
        child: Text(lbl, style: GoogleFonts.outfit(fontSize: 9,
          fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
          color: sel ? a : v.lo, letterSpacing: 0.5))),
    );
  }
}

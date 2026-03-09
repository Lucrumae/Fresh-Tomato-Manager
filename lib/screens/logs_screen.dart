import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});
  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scroll = ScrollController();
  String _levelFilter  = 'all';
  String _sourceFilter = 'all';
  String _search = '';
  bool _userScrolledUp = false;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _userScrolledUp = _scroll.position.pixels < _scroll.position.maxScrollExtent - 80;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logsProvider);
    final c    = Theme.of(context).extension<AppColors>()!;

    if (logs.length != _lastCount) {
      _lastCount = logs.length;
      if (!_userScrolledUp) _jumpToBottom();
    }

    final filtered = logs.where((l) {
      final ms = _search.isEmpty ||
        l.message.toLowerCase().contains(_search.toLowerCase()) ||
        l.process.toLowerCase().contains(_search.toLowerCase());
      final ml = _levelFilter == 'all' ||
        (_levelFilter == 'error' && l.isError) ||
        (_levelFilter == 'warn'  && l.isWarning);
      final msc = _sourceFilter == 'all' ||
        (_sourceFilter == 'kernel' && l.isKernel) ||
        (_sourceFilter == 'system' && !l.isKernel);
      return ms && ml && msc;
    }).toList();

    final nKernel = logs.where((l) => l.isKernel).length;
    final nSystem = logs.where((l) => !l.isKernel).length;
    final nErrors = logs.where((l) => l.isError).length;
    final nWarns  = logs.where((l) => l.isWarning).length;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Row(children: [
          Text('Logs', style: GoogleFonts.spaceGrotesk(
            fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: c.accent.withOpacity(0.10), borderRadius: BorderRadius.circular(5)),
            child: Text('${logs.length}', style: GoogleFonts.jetBrainsMono(
              fontSize: 10, fontWeight: FontWeight.w700, color: c.accent)),
          ),
        ]),
        actions: [
          if (_userScrolledUp)
            IconButton(
              icon: Icon(Icons.arrow_downward_rounded, size: 18, color: c.accent),
              tooltip: 'Jump to latest',
              onPressed: () { setState(() => _userScrolledUp = false); _jumpToBottom(); },
            ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, size: 18, color: c.textMuted),
            onPressed: () => ref.read(logsProvider.notifier).fetch(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(108),
          child: Column(children: [
            Divider(height: 1, color: c.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: TextField(
                onChanged: (v) => setState(() { _search = v; if (!_userScrolledUp) _jumpToBottom(); }),
                style: GoogleFonts.spaceGrotesk(fontSize: 13, color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search logs...',
                  prefixIcon: Icon(Icons.search_rounded, size: 17, color: c.textMuted),
                  isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 7, 14, 10),
              child: Row(children: [
                _LogChip('All', 'all', _sourceFilter, logs.length, c, (v) { setState(() => _sourceFilter = v); _jumpToBottom(); }),
                const SizedBox(width: 5),
                _LogChip('System', 'system', _sourceFilter, nSystem, c, (v) { setState(() => _sourceFilter = v); _jumpToBottom(); }),
                const SizedBox(width: 5),
                _LogChip('Kernel', 'kernel', _sourceFilter, nKernel, c, (v) { setState(() => _sourceFilter = v); _jumpToBottom(); }, color: AppTheme.info),
                Container(margin: const EdgeInsets.symmetric(horizontal: 8), width: 1, height: 18, color: c.border),
                _LogChip('Errors', 'error', _levelFilter, nErrors, c, (v) { setState(() { _levelFilter = _levelFilter == v ? 'all' : v; }); }, color: AppTheme.danger),
                const SizedBox(width: 5),
                _LogChip('Warns', 'warn', _levelFilter, nWarns, c, (v) { setState(() { _levelFilter = _levelFilter == v ? 'all' : v; }); }, color: AppTheme.warning),
              ]),
            ),
          ]),
        ),
      ),
      body: logs.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: c.accent, strokeWidth: 2)),
            const SizedBox(height: 14),
            Text('Loading logs...', style: GoogleFonts.spaceGrotesk(fontSize: 13, color: c.textMuted)),
          ]))
        : filtered.isEmpty
          ? Center(child: Text('No logs match filter',
              style: GoogleFonts.spaceGrotesk(fontSize: 13, color: c.textMuted)))
          : Stack(children: [
              // Monospace log viewer
              Container(color: c.isDark ? const Color(0xFF060809) : const Color(0xFFF8FAFD),
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 64),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) => _LogRow(entry: filtered[i], c: c),
                )),
              // Bottom "latest" indicator
              Positioned(bottom: 12, left: 0, right: 0,
                child: Center(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.cardBg.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  child: Text('▼  ${filtered.length} entries · newest at bottom',
                    style: GoogleFonts.jetBrainsMono(fontSize: 9, color: c.textMuted)),
                ))),
            ]),
    );
  }
}

class _LogRow extends StatelessWidget {
  final LogEntry entry;
  final AppColors c;
  const _LogRow({required this.entry, required this.c});

  @override
  Widget build(BuildContext context) {
    Color lineColor;
    if (entry.isError) lineColor = AppTheme.danger;
    else if (entry.isWarning) lineColor = AppTheme.warning;
    else lineColor = c.isDark ? const Color(0xFF1E2535) : const Color(0xFFE2E6F0);

    final bg = entry.isError
      ? AppTheme.danger.withOpacity(0.05)
      : entry.isWarning
        ? AppTheme.warning.withOpacity(0.04)
        : Colors.transparent;

    return Container(
      color: bg,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Color strip
        Container(width: 2.5, color: lineColor, margin: const EdgeInsets.only(right: 10)),
        Expanded(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Timestamp
            Text(DateFormat('HH:mm:ss').format(entry.time),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10, color: c.textMuted, fontWeight: FontWeight.w400)),
            const SizedBox(width: 8),
            // Source badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: entry.isKernel ? AppTheme.info.withOpacity(0.10) : c.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(entry.isKernel ? 'K' : 'S',
                style: GoogleFonts.jetBrainsMono(fontSize: 9, fontWeight: FontWeight.w800,
                  color: entry.isKernel ? AppTheme.info : c.accent)),
            ),
            const SizedBox(width: 7),
            // Process + message
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.process, style: GoogleFonts.jetBrainsMono(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: entry.isError ? AppTheme.danger
                  : entry.isWarning ? AppTheme.warning : c.textSecondary)),
              const SizedBox(height: 1),
              Text(entry.message, style: GoogleFonts.jetBrainsMono(
                fontSize: 11, color: entry.isError ? AppTheme.danger.withOpacity(0.85)
                  : entry.isWarning ? AppTheme.warning.withOpacity(0.85) : c.textSecondary,
                height: 1.4)),
            ])),
          ]),
        )),
      ]),
    );
  }
}

Widget _LogChip(String label, String value, String current, int count, AppColors c,
    ValueChanged<String> onTap, {Color? color}) {
  final selected = value == current;
  final col = color ?? c.accent;
  return GestureDetector(
    onTap: () => onTap(value),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? col.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? col.withOpacity(0.4) : c.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: GoogleFonts.spaceGrotesk(
          fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? col : c.textSecondary)),
        const SizedBox(width: 4),
        Text('$count', style: GoogleFonts.jetBrainsMono(
          fontSize: 9, color: selected ? col : c.textMuted)),
      ]),
    ),
  );
}

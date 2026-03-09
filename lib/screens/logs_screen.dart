import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    ref.read(logsProvider.notifier).stopPolling();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    });
  }

  String _levelFilter  = 'all';  // all, error, warn
  String _sourceFilter = 'all';  // all, system, kernel
  String _search = '';
  bool _loading = false;
  bool _userScrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      final pos = _scrollCtrl.position;
      _userScrolled = pos.pixels < pos.maxScrollExtent - 50;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(logsProvider.notifier).startPolling();
      Future.delayed(const Duration(milliseconds: 800), _scrollToBottom);
    });
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    await ref.read(logsProvider.notifier).fetch();
    if (mounted) {
      setState(() => _loading = false);
      if (!_userScrolled) _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(logsProvider, (_, __) {
      if (!_userScrolled) _scrollToBottom();
    });
    final logs   = ref.watch(logsProvider);
    final c      = Theme.of(context).extension<AppColors>()!;
    final accent = c.accent;

    final filtered = logs.where((l) {
      final matchSearch = _search.isEmpty ||
        l.message.toLowerCase().contains(_search.toLowerCase()) ||
        l.process.toLowerCase().contains(_search.toLowerCase());
      final matchLevel = _levelFilter == 'all' ||
        (_levelFilter == 'error' && l.isError) ||
        (_levelFilter == 'warn'  && l.isWarning);
      final matchSource = _sourceFilter == 'all' ||
        (_sourceFilter == 'kernel' && l.isKernel) ||
        (_sourceFilter == 'system' && !l.isKernel);
      return matchSearch && matchLevel && matchSource;
    }).toList();

    final totalKernel = logs.where((l) => l.isKernel).length;
    final totalSystem  = logs.where((l) => !l.isKernel).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('System Logs', style: Theme.of(context).textTheme.titleLarge),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _fetch),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(116),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(children: [
              TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: const InputDecoration(
                  hintText: 'Search logs...',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _Chip(label: 'All',    count: logs.length,   value: 'all',    current: _sourceFilter, accent: accent,           c: c, onTap: (v) { setState(() { _sourceFilter = v; }); _scrollToBottom(); }),
                  _Chip(label: 'System', count: totalSystem,   value: 'system', current: _sourceFilter, accent: accent,           c: c, onTap: (v) { setState(() { _sourceFilter = v; }); _scrollToBottom(); }),
                  _Chip(label: 'Kernel', count: totalKernel,   value: 'kernel', current: _sourceFilter, accent: const Color(0xFF4F9EE8), c: c, onTap: (v) { setState(() { _sourceFilter = v; }); _scrollToBottom(); }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Container(width: 1, height: 20, color: c.border),
                  ),
                  _Chip(label: 'Errors',   value: 'error', current: _levelFilter, accent: AppTheme.danger,   c: c, onTap: (v) { setState(() { _levelFilter = _levelFilter == v ? 'all' : v; }); }),
                  _Chip(label: 'Warnings', value: 'warn',  current: _levelFilter, accent: AppTheme.warning,  c: c, onTap: (v) { setState(() { _levelFilter = _levelFilter == v ? 'all' : v; }); }),
                ]),
              ),
            ]),
          ),
        ),
      ),
      body: (_loading && ref.read(logsProvider).isEmpty)
        ? const Center(child: CircularProgressIndicator())
        : filtered.isEmpty
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.article_rounded, size: 48, color: c.textMuted),
                const SizedBox(height: 12),
                Text('No logs found', style: TextStyle(color: c.textMuted)),
              ],
            ))
          : ListView.separated(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: c.border),
              itemBuilder: (_, i) => _LogTile(entry: filtered[i]),
            ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final LogEntry entry;
  const _LogTile({required this.entry});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    Color levelColor;
    if (entry.isError)        levelColor = AppTheme.danger;
    else if (entry.isWarning) levelColor = AppTheme.warning;
    else                      levelColor = c.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 3, height: 42,
          margin: const EdgeInsets.only(right: 10, top: 1),
          decoration: BoxDecoration(
            color: levelColor, borderRadius: BorderRadius.circular(2)),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: entry.isKernel
                    ? const Color(0xFF4F9EE8).withOpacity(0.14)
                    : c.accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                entry.isKernel ? 'KERN' : 'SYS',
                style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  color: entry.isKernel ? const Color(0xFF4F9EE8) : c.accent,
                ),
              ),
            ),
            Expanded(child: Text(
              entry.process,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: entry.isError ? AppTheme.danger
                    : entry.isWarning ? AppTheme.warning
                    : c.textSecondary),
              overflow: TextOverflow.ellipsis,
            )),
            Text(
              DateFormat('HH:mm:ss').format(entry.time),
              style: TextStyle(fontSize: 11, color: c.textMuted),
            ),
          ]),
          const SizedBox(height: 3),
          Text(
            entry.message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: entry.isError ? AppTheme.danger.withOpacity(0.85)
                  : entry.isWarning ? AppTheme.warning.withOpacity(0.85)
                  : c.textSecondary,
            ),
          ),
        ])),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label, value, current;
  final int? count;
  final Color accent;
  final AppColors c;
  final ValueChanged<String> onTap;
  const _Chip({required this.label, required this.value, required this.current,
    required this.accent, required this.c, required this.onTap, this.count});
  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.15) : c.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? accent : c.border, width: selected ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? accent : c.textSecondary,
          )),
          if (count != null) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: selected ? accent.withOpacity(0.2) : c.border,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: selected ? accent : c.textMuted,
              )),
            ),
          ],
        ]),
      ),
    );
  }
}

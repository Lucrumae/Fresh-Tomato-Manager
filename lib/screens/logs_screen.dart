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
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }
  String _filter = 'all'; // all, error, warn
  String _search = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    await ref.read(logsProvider.notifier).fetch();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logsProvider);
    final filtered = logs.where((l) {
      final matchSearch = _search.isEmpty ||
        l.message.toLowerCase().contains(_search.toLowerCase()) ||
        l.process.toLowerCase().contains(_search.toLowerCase());
      final matchFilter = _filter == 'all' ||
        (_filter == 'error' && l.isError) ||
        (_filter == 'warn' && l.isWarning);
      return matchSearch && matchFilter;
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('System Logs', style: Theme.of(context).textTheme.titleLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetch,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
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
                  _Chip(label: 'All', value: 'all', current: _filter, onTap: (v) { setState(() => _filter = v); _scrollToBottom(); }),
                  _Chip(label: '🔴 Errors', value: 'error', current: _filter, onTap: (v) { setState(() => _filter = v); _scrollToBottom(); }),
                  _Chip(label: '🟡 Warnings', value: 'warn', current: _filter, onTap: (v) { setState(() => _filter = v); _scrollToBottom(); }),
                ]),
              ),
            ]),
          ),
        ),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : filtered.isEmpty
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.article_rounded, size: 48, color: Theme.of(context).extension<AppColors>()!.textMuted),
                const SizedBox(height: 12),
                Text('No logs found', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textMuted)),
              ],
            ))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
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
    Color levelColor = AppTheme.textMuted;
    if (entry.isError) levelColor = AppTheme.danger;
    else if (entry.isWarning) levelColor = AppTheme.warning;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Level indicator
          Container(
            width: 4, height: 40,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: levelColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(
                    entry.process,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: levelColor),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('HH:mm:ss').format(entry.time),
                    style: TextStyle(fontSize: 11, color: Theme.of(context).extension<AppColors>()!.textMuted),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(
                  entry.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: entry.isError ? AppTheme.danger.withOpacity(0.8) : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label, value, current;
  final ValueChanged<String> onTap;
  const _Chip({required this.label, required this.value, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final c2 = Theme.of(context).extension<AppColors>()!;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.15) : c2.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : c2.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? accent : c2.textSecondary,
        )),
      ),
    );
  }
}

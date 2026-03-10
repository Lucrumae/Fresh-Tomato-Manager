import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import 'setup_screen.dart';
import '../services/connection_keeper.dart';
import 'files_screen.dart';

// SYSTEM = LOGS | ROUTER | CONFIG
// ROUTER  = Export/Import Config, Reboot, Factory Reset, Firmware Upgrade
// CONFIG  = Connection/Session, Display, Disconnect

class SystemScreen extends ConsumerStatefulWidget {
  const SystemScreen({super.key});
  @override ConsumerState<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends ConsumerState<SystemScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); }
  @override void dispose()   { _tab.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Scaffold(
      backgroundColor: v.bg,
      appBar: AppBar(
        title: Text('SYSTEM', style: GoogleFonts.outfit(
          fontSize: 13, fontWeight: FontWeight.w800, color: v.hi, letterSpacing: 2)),
        bottom: TabBar(controller: _tab, tabs: const [
          Tab(text: 'LOGS'),
          Tab(text: 'ROUTER'),
          Tab(text: 'SETTINGS'),
        ]),
      ),
      body: TabBarView(controller: _tab, children: const [
        _LogsTab(),
        _RouterTab(),
        _ConfigTab(),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LOGS TAB
// ═══════════════════════════════════════════════════════════════════════════════
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
      if (_filter == 'err')  return l.isError;
      if (_filter == 'warn') return l.isWarning;
      if (_filter == 'kern') return l.isKernel;
      if (_filter == 'sys')  return l.isSyslog;
      return true;
    }).toList();

    // Auto-scroll to bottom when following
    if (_follow && _scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }

    return Column(children: [
      // Filter toolbar
      Container(
        color: v.bg,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          _Chip('ALL',  'all',  _filter, () => setState(() => _filter = 'all'),  v),
          const SizedBox(width: 5),
          _Chip('ERR',  'err',  _filter, () => setState(() => _filter = 'err'),  v, color: V.err),
          const SizedBox(width: 5),
          _Chip('WARN', 'warn', _filter, () => setState(() => _filter = 'warn'), v, color: V.warn),
          const SizedBox(width: 5),
          _Chip('KERN', 'kern', _filter, () => setState(() => _filter = 'kern'), v, color: V.info),
          const SizedBox(width: 5),
          _Chip('SYS',  'sys',  _filter, () => setState(() => _filter = 'sys'),  v, color: V.ok),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _follow = !_follow),
            child: Row(children: [
              Icon(_follow ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 13, color: _follow ? v.accent : v.lo),
              const SizedBox(width: 4),
              Text(_follow ? 'FOLLOW' : 'PAUSED',
                style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w700,
                  color: _follow ? v.accent : v.lo)),
            ]),
          ),
        ]),
      ),
      // Log lines
      Expanded(child: filtered.isEmpty
        ? Center(child: Text('No logs',
            style: GoogleFonts.dmMono(fontSize: 12, color: v.lo)))
        : ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 40),
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final e = filtered[i];
              final c = e.isError ? V.err
                : e.isWarning ? V.warn
                : e.isKernel  ? V.info
                : v.mid;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 2, height: 14, margin: const EdgeInsets.only(right: 8, top: 2), color: c),
                  Expanded(child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${e.time} ', style: GoogleFonts.dmMono(fontSize: 9, color: v.lo)),
                    TextSpan(text: '[${e.process}] ', style: GoogleFonts.dmMono(fontSize: 9, color: v.mid)),
                    TextSpan(text: e.message, style: GoogleFonts.dmMono(fontSize: 9, color: c)),
                  ]))),
                ]),
              );
            },
          ),
      ),
    ]);
  }
}

Widget _Chip(String label, String key, String cur, VoidCallback onTap, VC v, {Color? color}) {
  final sel = key == cur;
  final c   = color ?? v.accent;
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: sel ? c.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: sel ? c : v.wire)),
      child: Text(label, style: GoogleFonts.outfit(
        fontSize: 9, fontWeight: FontWeight.w800, color: sel ? c : v.mid)),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ROUTER TAB  — router management actions
// ═══════════════════════════════════════════════════════════════════════════════
class _RouterTab extends ConsumerStatefulWidget {
  const _RouterTab();
  @override ConsumerState<_RouterTab> createState() => _RouterTabState();
}

class _RouterTabState extends ConsumerState<_RouterTab> {
  bool _backupBusy  = false;
  bool _restoreBusy = false;
  bool _resetBusy   = false;
  bool _rebootBusy  = false;
  bool _fwBusy      = false;

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [

        // ── Config backup / restore ────────────────────────────────────
        _Sect('BACKUP & RESTORE', v),
        VCard(padding: const EdgeInsets.all(14), child: Column(children: [
          _Row(icon: Icons.download_rounded,     color: V.ok,
            title: 'Export Config',  sub: 'Save nvram settings to file',
            busy: _backupBusy, onTap: _backup),
          Divider(color: v.wire, height: 24),
          _Row(icon: Icons.upload_rounded,       color: V.info,
            title: 'Import Config',  sub: 'Restore settings from file',
            busy: _restoreBusy, onTap: _restore),
        ])),
        const SizedBox(height: 20),

        // ── Router control ────────────────────────────────────────────
        _Sect('ROUTER CONTROL', v),
        VCard(padding: const EdgeInsets.all(14), child: Column(children: [
          _Row(icon: Icons.restart_alt_rounded,  color: V.warn,
            title: 'Reboot',         sub: 'Graceful router restart',
            busy: _rebootBusy, onTap: () => _confirmReboot(context)),
          Divider(color: v.wire, height: 24),
          _Row(icon: Icons.system_update_rounded, color: V.info,
            title: 'Firmware Upgrade', sub: 'Flash new firmware (.trx / .bin)',
            busy: _fwBusy, onTap: () => _firmwareUpgrade(context)),
          Divider(color: v.wire, height: 24),
          _Row(icon: Icons.delete_forever_rounded, color: V.err,
            title: 'Factory Reset',  sub: 'Erase all nvram — cannot be undone',
            busy: _resetBusy, onTap: () => _factoryReset(context)),
        ])),
        const SizedBox(height: 20),

        // ── Tools ─────────────────────────────────────────────────────
        _Sect('TOOLS', v),
        VCard(padding: const EdgeInsets.all(14), child:
          _Row(icon: Icons.folder_rounded, color: V.warn,
            title: 'File Browser', sub: 'Browse router filesystem',
            busy: false,
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const FilesScreen())))),
      ],
    );
  }

  Widget _Sect(String t, VC v) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: GoogleFonts.outfit(
      fontSize: 9, fontWeight: FontWeight.w800, color: v.lo, letterSpacing: 2)));

  // ── Reboot ──────────────────────────────────────────────────────────────────
  Future<void> _confirmReboot(BuildContext ctx) async {
    final ok = await showDialog<bool>(context: ctx, builder: (_) => AlertDialog(
      title: const Text('Reboot Router'),
      content: const Text('The router will restart. You will be disconnected briefly.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Reboot', style: TextStyle(color: V.warn))),
      ]));
    if (ok != true || !ctx.mounted) return;
    setState(() => _rebootBusy = true);
    try {
      await ref.read(sshServiceProvider).run('reboot 2>/dev/null || true');
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Rebooting…'), backgroundColor: V.warn));
    } finally { if (mounted) setState(() => _rebootBusy = false); }
  }

  // ── Factory reset ───────────────────────────────────────────────────────────
  Future<void> _factoryReset(BuildContext ctx) async {
    final ok = await showDialog<bool>(context: ctx, builder: (_) => AlertDialog(
      title: const Text('Factory Reset'),
      content: const Text('This will erase ALL router configuration. Cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
          child: const Text('RESET', style: TextStyle(color: V.err))),
      ]));
    if (ok != true) return;
    setState(() => _resetBusy = true);
    try {
      await ref.read(sshServiceProvider).run('nvram erase; reboot');
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Factory reset initiated'), backgroundColor: V.err));
    } finally { if (mounted) setState(() => _resetBusy = false); }
  }

  // ── Firmware upgrade ────────────────────────────────────────────────────────
  Future<void> _firmwareUpgrade(BuildContext ctx) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final name = result.files.single.name;
    if (!name.endsWith('.trx') && !name.endsWith('.bin')) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Select a .trx or .bin file'), backgroundColor: V.err));
      return;
    }
    if (!ctx.mounted) return;
    final ok = await showDialog<bool>(context: ctx, builder: (_) => AlertDialog(
      title: const Text('Flash Firmware'),
      content: Text('Flash $name?\n\nThis will reboot the router. Do not disconnect power.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
          child: const Text('FLASH', style: TextStyle(color: V.err))),
      ]));
    if (ok != true) return;
    setState(() => _fwBusy = true);
    try {
      final ssh   = ref.read(sshServiceProvider);
      final bytes = await File(path).readAsBytes();
      // Upload to /tmp then flash
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port   = server.port;
      final ip     = await _localIp();
      if (ip == null) { await server.close(force: true); throw Exception('No local IP'); }
      // Serve file once
      server.listen((req) async {
        req.response.contentLength = bytes.length;
        req.response.add(bytes);
        await req.response.close();
        await server.close(force: true);
      });
      await ssh.run(
        'wget -q -O /tmp/firmware.trx http://$ip:$port/ 2>/dev/null; '
        'flash write /tmp/firmware.trx 2>/dev/null || '
        'mtd write /tmp/firmware.trx linux 2>/dev/null; '
        'reboot');
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Flashing… router will reboot'), backgroundColor: V.info));
    } catch (e) {
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('Firmware upgrade failed: $e'), backgroundColor: V.err));
    } finally { if (mounted) setState(() => _fwBusy = false); }
  }

  // ── Backup ──────────────────────────────────────────────────────────────────
  Future<void> _backup() async {
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) return;
    setState(() => _backupBusy = true);
    try {
      await ssh.run('nvram show > /tmp/nvram_backup.cfg 2>/dev/null');
      final sz = (await ssh.run('wc -c < /tmp/nvram_backup.cfg 2>/dev/null || echo 0')).trim();
      if ((int.tryParse(sz.split(RegExp(r'\s+')).first) ?? 0) < 10) throw Exception('Empty');
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port   = server.port;
      final ip     = await _localIp();
      if (ip == null) { await server.close(force: true); throw Exception('No local IP'); }
      final comp = Completer<List<int>>();
      server.listen((req) async {
        final b = <int>[];
        await for (final c in req) { b.addAll(c); }
        req.response.statusCode = 200;
        await req.response.close();
        await server.close(force: true);
        comp.complete(b);
      });
      await ssh.run(
        'curl -s -X POST --data-binary @/tmp/nvram_backup.cfg http://$ip:$port/ 2>/dev/null || '
        'wget -q -O /dev/null --post-file=/tmp/nvram_backup.cfg http://$ip:$port/ 2>/dev/null');
      final bytes = await comp.future.timeout(const Duration(seconds: 30));
      if (bytes.isEmpty) throw Exception('Empty data');
      final ts  = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      // Save to /storage/emulated/0/Download/Tomato Manager/Backup
      Directory saveDir;
      try {
        final dl = Directory('/storage/emulated/0/Download/Tomato Manager/Backup');
        if (!await dl.exists()) await dl.create(recursive: true);
        saveDir = dl;
      } catch (_) {
        saveDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      }
      final file = File('${saveDir.path}/tomato_$ts.cfg');
      await file.writeAsBytes(bytes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved to Download/Tomato Manager/Backup'),
        backgroundColor: V.ok));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Backup failed: $e'), backgroundColor: V.err));
    } finally { if (mounted) setState(() => _backupBusy = false); }
  }

  // ── Restore ─────────────────────────────────────────────────────────────────
  Future<void> _restore() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result == null || result.files.single.path == null) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Restore Config'),
      content: const Text('This will overwrite all router settings. Continue?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true),
          child: const Text('Restore', style: TextStyle(color: V.warn))),
      ]));
    if (ok != true) return;
    setState(() => _restoreBusy = true);
    try {
      final bytes = await File(result.files.single.path!).readAsBytes();
      final ssh   = ref.read(sshServiceProvider);
      final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
      final cmds  = <String>[];
      for (final ln in lines) {
        final t = ln.trim(); if (t.isEmpty) continue;
        final eq = t.indexOf('='); if (eq < 1) continue;
        final k  = t.substring(0, eq);
        final vl = t.substring(eq + 1).replaceAll("'", "'\\''");
        cmds.add("nvram set '$k'='$vl'");
      }
      for (var i = 0; i < cmds.length; i += 20) {
        await ssh.run(cmds.sublist(i, (i + 20).clamp(0, cmds.length)).join(' && '));
      }
      await ssh.run('nvram commit');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Config restored — reboot to apply'), backgroundColor: V.ok));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Restore failed: $e'), backgroundColor: V.err));
    } finally { if (mounted) setState(() => _restoreBusy = false); }
  }

  Future<String?> _localIp() async {
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final i in ifaces) {
        if (i.name.startsWith('wlan') || i.name.startsWith('en') || i.name.startsWith('eth')) {
          return i.addresses.first.address;
        }
      }
      if (ifaces.isNotEmpty) return ifaces.first.addresses.first.address;
    } catch (_) {}
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SETTINGS TAB  — Connection/Session · Display · Disconnect
// ═══════════════════════════════════════════════════════════════════════════════
class _ConfigTab extends ConsumerWidget {
  const _ConfigTab();

  @override Widget build(BuildContext ctx, WidgetRef ref) {
    final v      = ctx.extension<VC>()!;
    final config = ref.watch(configProvider);
    final isDark = ref.watch(darkModeProvider);
    final accent = ref.watch(accentProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [

        // ── Connection / Session ──────────────────────────────────────
        _Sect2('CONNECTION / SESSION', v),
        VCard(padding: const EdgeInsets.all(14), child: Column(children: [
          // Host info row
          Row(children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(color: v.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.terminal_rounded, size: 18, color: v.accent)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(config?.host ?? 'Not configured',
                style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: v.hi)),
              Text('${config?.username ?? 'root'}  ·  SSH :${config?.sshPort ?? 22}',
                style: GoogleFonts.dmMono(fontSize: 10, color: v.mid)),
            ])),
            TextButton(
              onPressed: () => Navigator.push(ctx,
                MaterialPageRoute(builder: (_) => const SetupScreen())),
              child: const Text('CHANGE')),
          ]),
          Divider(color: v.wire, height: 20),
          // Reconnect
          _Row(icon: Icons.refresh_rounded, color: V.info,
            title: 'Reconnect', sub: 'Re-establish SSH session',
            busy: false,
            onTap: () async {
              final cfg = ref.read(configProvider);
              if (cfg == null) return;
              ref.read(sshServiceProvider).disconnect();
              final err = await ref.read(sshServiceProvider).connect(cfg);
              if (err == null) {
                ref.read(routerStatusProvider.notifier).startPolling();
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Reconnected'), backgroundColor: V.ok));
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text('Failed: $err'), backgroundColor: V.err));
              }
            }),
        ])),
        const SizedBox(height: 20),

        // ── Display ───────────────────────────────────────────────────
        _Sect2('DISPLAY', v),
        VCard(padding: const EdgeInsets.all(14), child: Column(children: [
          Row(children: [
            Icon(isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded, size: 18, color: v.mid),
            const SizedBox(width: 12),
            Expanded(child: Text(isDark ? 'Dark mode' : 'Light mode',
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: v.hi))),
            Switch(value: isDark,
              onChanged: (_) => ref.read(darkModeProvider.notifier).toggle()),
          ]),
          Divider(color: v.wire, height: 20),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ACCENT COLOR',
              style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800,
                color: v.mid, letterSpacing: 1.5)),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10,
              children: AccentColor.values.map((a) {
                final sel = a == accent;
                return GestureDetector(
                  onTap: () => ref.read(accentProvider.notifier).set(a),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color:  a.primary,
                      shape:  BoxShape.circle,
                      border: Border.all(color: sel ? Colors.white : Colors.transparent, width: 2.5),
                      boxShadow: sel
                        ? [BoxShadow(color: a.primary.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)]
                        : null),
                    child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 16) : null),
                );
              }).toList()),
          ]),
        ])),
        const SizedBox(height: 20),

        // ── Disconnect ────────────────────────────────────────────────
        _Sect2('SESSION', v),
        VCard(padding: const EdgeInsets.all(14), child:
          _Row(icon: Icons.logout_rounded, color: V.err,
            title: 'Disconnect', sub: 'Clear saved credentials and sign out',
            busy: false,
            onTap: () => _disconnect(ctx, ref))),
        const SizedBox(height: 24),

        Center(child: Text('Tomato Manager',
          style: GoogleFonts.outfit(fontSize: 9, color: v.lo, letterSpacing: 1))),
      ],
    );
  }

  Widget _Sect2(String t, VC v) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: GoogleFonts.outfit(
      fontSize: 9, fontWeight: FontWeight.w800, color: v.lo, letterSpacing: 2)));

  Future<void> _disconnect(BuildContext ctx, WidgetRef ref) async {
    final ok = await showDialog<bool>(context: ctx, builder: (_) => AlertDialog(
      title: const Text('Disconnect'),
      content: const Text('Clear saved SSH credentials?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Disconnect', style: TextStyle(color: V.err))),
      ]));
    if (ok != true || !ctx.mounted) return;
    // Stop all pollers and background service before clearing
    ref.read(routerStatusProvider.notifier).stopPolling();
    ref.read(devicesProvider.notifier).stopPolling();
    ref.read(bandwidthProvider.notifier).stopPolling();
    try { ref.read(connectionKeeperProvider).stopAll(); } catch (_) {}
    await ref.read(configProvider.notifier).clear();
    await ref.read(sshServiceProvider).disconnect();
    if (ctx.mounted) Navigator.pushAndRemoveUntil(ctx,
      MaterialPageRoute(builder: (_) => const SetupScreen()), (_) => false);
  }
}

// ─── Shared _Row action widget ────────────────────────────────────────────────
class _Row extends StatelessWidget {
  final IconData icon; final Color color;
  final String title, sub;
  final bool busy;
  final VoidCallback onTap;
  const _Row({required this.icon, required this.color, required this.title,
    required this.sub, required this.busy, required this.onTap});

  @override Widget build(BuildContext ctx) {
    final v = Theme.of(ctx).extension<VC>()!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: busy
            ? Padding(padding: const EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2, color: color))
            : Icon(icon, size: 18, color: color)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.outfit(
            fontSize: 13, fontWeight: FontWeight.w600, color: v.hi)),
          Text(sub, style: GoogleFonts.dmMono(fontSize: 10, color: v.mid)),
        ])),
        Icon(Icons.chevron_right_rounded, size: 18, color: v.lo),
      ]),
    );
  }
}

// Extension helper
extension on BuildContext {
  T extension<T>() => Theme.of(this).extension<T>()!;
}

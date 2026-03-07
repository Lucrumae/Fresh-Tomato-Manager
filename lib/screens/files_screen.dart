import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dartssh2/dartssh2.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';

class _FsEntry {
  final String name, path, permissions, owner, modified;
  final bool isDir;
  final int size;
  const _FsEntry({
    required this.name, required this.path, required this.isDir,
    required this.size, required this.permissions,
    required this.owner, required this.modified,
  });
}

// ── Transfer progress ─────────────────────────────────────────────────────────
class _Transfer {
  final String name;
  final bool isUpload;
  double progress; // 0.0 - 1.0
  String? error;
  bool done;
  _Transfer({required this.name, required this.isUpload,
    this.progress = 0, this.error, this.done = false});
}

class FilesScreen extends ConsumerStatefulWidget {
  const FilesScreen({super.key});
  @override
  ConsumerState<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends ConsumerState<FilesScreen> {
  String _cwd = '/';
  List<_FsEntry> _entries = [];
  bool _loading = false;
  String? _error;
  final List<String> _history = ['/'];
  int _histIdx = 0;
  final List<_Transfer> _transfers = [];

  @override void initState() { super.initState(); _ls('/'); }

  // ── Theming ────────────────────────────────────────────────────────────────
  bool get _isDark => _brightness == Brightness.dark;
  Brightness _brightness = Brightness.dark;

  Color get _bg   => _isDark ? const Color(0xFF0B0F1A) : const Color(0xFFF8FAFC);
  Color get _bar  => _isDark ? const Color(0xFF0F1622) : const Color(0xFFE8EDF5);
  Color get _brd  => _isDark ? const Color(0xFF1A2535) : const Color(0xFFCBD5E0);

  // ── SSH helpers ────────────────────────────────────────────────────────────
  Future<String> _run(String cmd) async {
    final ssh = ref.read(sshServiceProvider);
    return ssh.run(cmd);
  }

  // ── List directory ─────────────────────────────────────────────────────────
  Future<void> _ls(String path) async {
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await _run('ls -la "$path" 2>&1');
      if (raw.startsWith('ls:') && raw.contains('No such')) {
        setState(() { _error = 'Cannot access: $path'; _loading = false; });
        return;
      }
      setState(() {
        _cwd = path;
        _entries = _parseLs(raw, path);
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<_FsEntry> _parseLs(String raw, String base) {
    final out = <_FsEntry>[];
    final re = RegExp(r'^([dlrwx\-]{10})\s+\d+\s+(\S+)\s+\S+\s+(\d+)\s+(\w+\s+\d+\s+[\d:]+)\s+(.+)$');
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('total')) continue;
      final m = re.firstMatch(t);
      if (m == null) continue;
      var name = m.group(5)!;
      if (name.contains(' -> ')) name = name.split(' -> ').first;
      if (name == '.' || name == '..') continue;
      final perms = m.group(1)!;
      final full = base == '/' ? '/$name' : '$base/$name';
      out.add(_FsEntry(
        name: name, path: full,
        isDir: perms.startsWith('d') || perms.startsWith('l'),
        size: int.tryParse(m.group(3)!) ?? 0,
        permissions: perms, owner: m.group(2)!,
        modified: m.group(4)!,
      ));
    }
    out.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  void _navigate(String path) {
    if (_histIdx < _history.length - 1) _history.removeRange(_histIdx + 1, _history.length);
    _history.add(path); _histIdx = _history.length - 1;
    _ls(path);
  }

  // ── Download ───────────────────────────────────────────────────────────────
  Future<void> _download(_FsEntry entry) async {
    // Request storage permission
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        final manageStatus = await Permission.manageExternalStorage.request();
        if (!manageStatus.isGranted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Izin storage diperlukan untuk download')));
          return;
        }
      }
    }

    final transfer = _Transfer(name: entry.name, isUpload: false);
    setState(() => _transfers.add(transfer));

    try {
      final ssh = ref.read(sshServiceProvider);
      if (ssh.client == null) throw Exception('Not connected');

      // Read file via SFTP
      final sftp = await ssh.client!.sftp();
      final remoteFile = await sftp.open(entry.path, mode: SftpFileOpenMode.read);
      final fileSize = entry.size > 0 ? entry.size : 1;

      // Save to downloads directory
      Directory saveDir;
      if (Platform.isAndroid) {
        saveDir = Directory('/storage/emulated/0/Download/TomatoManager');
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        saveDir = Directory('${docDir.path}/TomatoManager');
      }
      await saveDir.create(recursive: true);

      final localPath = '${saveDir.path}/${entry.name}';
      final localFile = File(localPath);
      final sink = localFile.openWrite();

      int received = 0;
      await for (final chunk in remoteFile.read()) {
        sink.add(chunk);
        received += chunk.length;
        setState(() => transfer.progress = (received / fileSize).clamp(0.0, 1.0));
      }
      await sink.close();
      await remoteFile.close();

      setState(() { transfer.done = true; transfer.progress = 1.0; });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ Disimpan ke: $localPath'),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ));
      }
    } catch (e) {
      setState(() { transfer.error = e.toString(); transfer.done = true; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download gagal: $e'),
          backgroundColor: AppTheme.danger));
    }

    // Remove transfer after 3s
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _transfers.remove(transfer));
  }

  // ── Upload ─────────────────────────────────────────────────────────────────
  Future<void> _upload() async {
    // Pick file
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final localPath = picked.path;
    if (localPath == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat mengakses file')));
      return;
    }

    final localFile = File(localPath);
    final fileSize = await localFile.length();
    final remotePath = _cwd == '/' ? '/${picked.name}' : '$_cwd/${picked.name}';

    final transfer = _Transfer(name: picked.name, isUpload: true);
    setState(() => _transfers.add(transfer));

    try {
      final ssh = ref.read(sshServiceProvider);
      if (ssh.client == null) throw Exception('Not connected');

      final sftp = await ssh.client!.sftp();
      final remoteFile = await sftp.open(remotePath,
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);

      int sent = 0;
      final stream = localFile.openRead();
      final writer = remoteFile.write();

      await for (final chunk in stream) {
        writer.add(Uint8List.fromList(chunk));
        sent += chunk.length;
        setState(() => transfer.progress = fileSize > 0
          ? (sent / fileSize).clamp(0.0, 1.0) : 0.5);
      }
      await writer.close();
      await remoteFile.close();

      setState(() { transfer.done = true; transfer.progress = 1.0; });
      _ls(_cwd); // refresh

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✓ ${picked.name} berhasil diupload')));
    } catch (e) {
      setState(() { transfer.error = e.toString(); transfer.done = true; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload gagal: $e'),
          backgroundColor: AppTheme.danger));
    }

    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _transfers.remove(transfer));
  }

  // ── File operations ────────────────────────────────────────────────────────
  Future<void> _showContent(_FsEntry entry) async {
    if (entry.size > 512 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File terlalu besar (>512KB)')));
      return;
    }
    setState(() => _loading = true);
    try {
      final content = await _run('cat "${entry.path}" 2>&1');
      setState(() => _loading = false);
      if (!mounted) return;
      _showContentSheet(entry.name, content);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _delete(_FsEntry entry) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: Text('Hapus ${entry.isDir ? "Folder" : "File"}?'),
      content: Text(entry.path),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
          child: const Text('Batal')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Hapus')),
      ],
    ));
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await _run(entry.isDir ? 'rm -rf "${entry.path}"' : 'rm -f "${entry.path}"');
      _ls(_cwd);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _rename(_FsEntry entry) async {
    final ctrl = TextEditingController(text: entry.name);
    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(controller: ctrl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Simpan')),
      ],
    ));
    if (name == null || name.isEmpty || name == entry.name) return;
    setState(() => _loading = true);
    final newPath = _cwd == '/' ? '/$name' : '$_cwd/$name';
    try {
      await _run('mv "${entry.path}" "$newPath"');
      _ls(_cwd);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _mkdir() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Buat Folder Baru'),
      content: TextField(controller: ctrl, autofocus: true,
        decoration: const InputDecoration(hintText: 'nama folder')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Buat')),
      ],
    ));
    if (name == null || name.isEmpty) return;
    setState(() => _loading = true);
    try {
      await _run('mkdir -p "${_cwd == '/' ? '/$name' : '$_cwd/$name'}"');
      _ls(_cwd);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showContentSheet(String title, String content) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: _bar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.4,
        builder: (_, sc) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16,12,8,8),
            child: Row(children: [
              Icon(Icons.insert_drive_file_rounded, color: AppTheme.terminal, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: GoogleFonts.jetBrainsMono(
                color: AppTheme.terminal, fontSize: 13))),
              IconButton(icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(_)),
            ]),
          ),
          Divider(height: 1, color: _brd),
          Expanded(child: SingleChildScrollView(
            controller: sc,
            padding: const EdgeInsets.all(12),
            child: SelectableText(content,
              style: GoogleFonts.jetBrainsMono(fontSize: 12, height: 1.5)),
          )),
        ]),
      ),
    );
  }

  String _fmtSize(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024*1024) return '${(b/1024).toStringAsFixed(1)}KB';
    return '${(b/(1024*1024)).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    _brightness = Theme.of(context).brightness;
    final textPrimary = _isDark ? const Color(0xFFE2E8F5) : const Color(0xFF1A202C);
    final textSub = _isDark ? const Color(0xFF6B7A99) : const Color(0xFF4A5568);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bar,
        elevation: 0,
        title: const Text('File Manager', style: TextStyle(fontSize: 16)),
        actions: [
          // Upload button
          IconButton(
            icon: const Icon(Icons.upload_rounded),
            tooltip: 'Upload file',
            onPressed: _upload,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _ls(_cwd),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            color: _bar,
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Row(children: [
              _navBtn(Icons.arrow_back_rounded,
                _histIdx > 0 ? _goBack : null),
              _navBtn(Icons.arrow_forward_rounded,
                _histIdx < _history.length-1 ? _goFwd : null),
              _navBtn(Icons.arrow_upward_rounded,
                _cwd != '/' ? _goUp : null),
              Expanded(
                child: GestureDetector(
                  onTap: _showGoTo,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal:10, vertical:6),
                    decoration: BoxDecoration(
                      color: _isDark ? const Color(0xFF060A11) : const Color(0xFFDDE3EE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _brd),
                    ),
                    child: Row(children: [
                      Icon(Icons.folder_rounded, color: AppTheme.terminal, size: 14),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_cwd,
                        style: GoogleFonts.jetBrainsMono(
                          color: textPrimary, fontSize: 12),
                        overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),

      // Transfer progress overlay
      body: Stack(children: [
        _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.terminal))
          : _error != null
            ? _buildError()
            : _entries.isEmpty
              ? _buildEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => Divider(height:1, color:_brd, indent:52),
                  itemBuilder: (ctx, i) => _EntryRow(
                    entry: _entries[i],
                    isDark: _isDark,
                    fmtSize: _fmtSize,
                    onTap: () => _entries[i].isDir
                      ? _navigate(_entries[i].path)
                      : _showContent(_entries[i]),
                    onDownload: _entries[i].isDir ? null : () => _download(_entries[i]),
                    onDelete: () => _delete(_entries[i]),
                    onRename: () => _rename(_entries[i]),
                  ),
                ),

        // Transfer progress cards
        if (_transfers.isNotEmpty)
          Positioned(
            bottom: 8, left: 12, right: 12,
            child: Column(mainAxisSize: MainAxisSize.min,
              children: _transfers.map((t) => _TransferCard(transfer: t)).toList()),
          ),
      ]),

      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: AppTheme.primary,
        onPressed: _mkdir,
        child: const Icon(Icons.create_new_folder_rounded, size: 20),
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback? onTap) => IconButton(
    icon: Icon(icon, size: 20),
    color: onTap != null ? Colors.white70 : Colors.white24,
    onPressed: onTap,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 36),
  );

  void _goBack()  { _histIdx--; _ls(_history[_histIdx]); }
  void _goFwd()   { _histIdx++; _ls(_history[_histIdx]); }
  void _goUp()    {
    final parts = _cwd.split('/');
    parts.removeLast();
    _navigate(parts.isEmpty || (parts.length==1 && parts[0].isEmpty) ? '/' : parts.join('/'));
  }

  void _showGoTo() async {
    final ctrl = TextEditingController(text: _cwd);
    final path = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Pergi ke Path'),
      content: TextField(controller: ctrl, autofocus: true,
        style: GoogleFonts.jetBrainsMono(fontSize: 13),
        decoration: const InputDecoration(hintText: '/tmp, /var, /etc...')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Pergi')),
      ],
    ));
    if (path != null && path.isNotEmpty) _navigate(path);
  }

  Widget _buildError() => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
      const SizedBox(height: 12),
      Text(_error!, textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54)),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: () => _ls(_cwd), child: const Text('Retry')),
    ]),
  ));

  Widget _buildEmpty() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.folder_open_rounded, color: Colors.white24, size: 48),
    const SizedBox(height: 12),
    Text('Folder kosong', style: TextStyle(color: Colors.white38)),
  ]));
}

// ── Entry Row ─────────────────────────────────────────────────────────────────
class _EntryRow extends StatelessWidget {
  final _FsEntry entry;
  final bool isDark;
  final String Function(int) fmtSize;
  final VoidCallback onTap, onDelete, onRename;
  final VoidCallback? onDownload;

  const _EntryRow({
    required this.entry, required this.isDark, required this.fmtSize,
    required this.onTap, required this.onDelete, required this.onRename,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final tileBg = isDark ? const Color(0xFF0B0F1A) : const Color(0xFFF8FAFC);
    final nameCol = isDark ? const Color(0xFFE2E8F5) : const Color(0xFF1A202C);
    final subCol  = isDark ? const Color(0xFF6B7A99) : const Color(0xFF718096);

    return Material(
      color: tileBg,
      child: InkWell(
        onTap: onTap,
        splashColor: AppTheme.terminal.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal:12, vertical:9),
          child: Row(children: [
            // Icon
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: entry.isDir
                  ? AppTheme.terminal.withOpacity(0.1)
                  : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                entry.isDir ? Icons.folder_rounded : _icon(entry.name),
                color: entry.isDir ? AppTheme.terminal : Colors.white38,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: TextStyle(
                  color: nameCol, fontSize: 13.5,
                  fontWeight: entry.isDir ? FontWeight.w500 : FontWeight.normal),
                  overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  Text(entry.permissions,
                    style: GoogleFonts.jetBrainsMono(fontSize: 10, color: subCol)),
                  const SizedBox(width: 8),
                  if (!entry.isDir) Text(fmtSize(entry.size),
                    style: TextStyle(fontSize: 11, color: subCol)),
                  if (!entry.isDir) const SizedBox(width: 8),
                  Expanded(child: Text(entry.modified,
                    style: TextStyle(fontSize: 11, color: subCol),
                    overflow: TextOverflow.ellipsis)),
                ]),
              ],
            )),
            // Download button (files only)
            if (onDownload != null)
              IconButton(
                icon: Icon(Icons.download_rounded,
                  color: AppTheme.primary.withOpacity(0.7), size: 20),
                tooltip: 'Download',
                onPressed: onDownload,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32),
              ),
            // More menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: Colors.white38, size: 18),
              color: isDark ? const Color(0xFF0F1622) : const Color(0xFFE8EDF5),
              onSelected: (v) {
                if (v=='download' && onDownload!=null) onDownload!();
                if (v=='rename') onRename();
                if (v=='delete') onDelete();
              },
              itemBuilder: (_) => [
                if (!entry.isDir)
                  const PopupMenuItem(value:'download',
                    child: Row(children:[
                      Icon(Icons.download_rounded, size:16, color:AppTheme.primary),
                      SizedBox(width:8), Text('Download'),
                    ])),
                const PopupMenuItem(value:'rename',
                  child: Row(children:[
                    Icon(Icons.drive_file_rename_outline, size:16, color:Colors.white54),
                    SizedBox(width:8), Text('Rename'),
                  ])),
                const PopupMenuItem(value:'delete',
                  child: Row(children:[
                    Icon(Icons.delete_outline_rounded, size:16, color:AppTheme.danger),
                    SizedBox(width:8), Text('Delete',
                      style:TextStyle(color:AppTheme.danger)),
                  ])),
              ],
            ),
          ]),
        ),
      ),
    ));
  }

  IconData _icon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'conf': case 'cfg': case 'ini': return Icons.settings_rounded;
      case 'sh': case 'bash': return Icons.terminal_rounded;
      case 'log': return Icons.article_rounded;
      case 'txt': case 'md': return Icons.description_rounded;
      case 'gz': case 'tar': case 'zip': return Icons.archive_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }
}

// ── Transfer Progress Card ────────────────────────────────────────────────────
class _TransferCard extends StatelessWidget {
  final _Transfer transfer;
  const _TransferCard({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final isErr = transfer.error != null;
    final color = isErr ? AppTheme.danger
      : transfer.done ? AppTheme.success : AppTheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1622),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(
            transfer.isUpload ? Icons.upload_rounded : Icons.download_rounded,
            color: color, size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(transfer.name,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            overflow: TextOverflow.ellipsis)),
          if (transfer.done)
            Icon(isErr ? Icons.error_rounded : Icons.check_circle_rounded,
              color: color, size: 16),
          if (!transfer.done)
            Text('${(transfer.progress * 100).toInt()}%',
              style: TextStyle(color: color, fontSize: 12)),
        ]),
        if (!transfer.done) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: transfer.progress,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 4,
            ),
          ),
        ],
        if (isErr) ...[
          const SizedBox(height: 4),
          Text(transfer.error!, style: const TextStyle(
            color: AppTheme.danger, fontSize: 11)),
        ],
      ]),
    );
  }
}

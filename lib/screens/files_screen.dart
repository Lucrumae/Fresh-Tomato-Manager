import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
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

//  Transfer progress 
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
  // Multi-select
  final Set<String> _selected = {};
  bool get _selectMode => _selected.isNotEmpty;

  @override void initState() { super.initState(); _ls('/'); }

  //  Theming 
  bool get _isDark => _brightness == Brightness.dark;
  Brightness _brightness = Brightness.dark;
  Color _accent = const Color(0xFF00E5A0);

  Color get _bg   => _isDark ? const Color(0xFF0B0F1A) : const Color(0xFFF8FAFC);
  Color get _bar  => _isDark ? const Color(0xFF0F1622) : const Color(0xFFE8EDF5);
  Color get _brd  => _isDark ? const Color(0xFF1A2535) : const Color(0xFFCBD5E0);

  //  SSH helpers 
  Future<String> _run(String cmd) async {
    final ssh = ref.read(sshServiceProvider);
    return ssh.run(cmd);
  }

  //  List directory 
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

  //  Download 
  Future<void> _download(_FsEntry entry) async {
    if (Platform.isAndroid) {
      if (!await _ensureStoragePermission()) return;
    }

    final transfer = _Transfer(name: entry.name, isUpload: false);
    setState(() { transfer.progress = -1; _transfers.add(transfer); });

    try {
      final ssh = ref.read(sshServiceProvider);
      if (ssh.client == null) throw Exception('Not connected');

      // Use SSH execute + cat - more reliable on embedded routers than SFTP
      setState(() => transfer.progress = -1); // indeterminate while reading

      Directory saveDir;
      if (Platform.isAndroid) {
        saveDir = Directory('/storage/emulated/0/Download/Tomato Manager');
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        saveDir = Directory('${docDir.path}/Tomato Manager');
      }
      await saveDir.create(recursive: true);

      final localPath = '${saveDir.path}/${entry.name}';
      final outFile = File(localPath);
      final raf = await outFile.open(mode: FileMode.write);
      int totalBytes = 0;
      final fileSize = entry.size > 0 ? entry.size : 0;

      // Jalankan cat via execute dan stream ke file
      final session = await ssh.client!.execute('cat "\${entry.path}"');

      // Drain stderr supaya tidak block stdout
      session.stderr.drain<void>().catchError((_) {});

      await for (final chunk in session.stdout) {
        if (chunk == null || chunk.isEmpty) continue;
        final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        await raf.writeFrom(bytes);
        totalBytes += bytes.length;
        if (fileSize > 0) {
          setState(() => transfer.progress =
            (totalBytes / fileSize).clamp(0.0, 0.99));
        } else {
          // Ukuran tidak diketahui - tampil indeterminate tapi update bytes
          setState(() => transfer.progress = -1);
        }
      }
      await raf.close();
      // Drain session - jangan tunggu terlalu lama
      await session.done.timeout(
        const Duration(seconds: 5), onTimeout: () {});

      if (totalBytes == 0) {
        await outFile.delete();
        throw Exception('File is empty or cannot be read');
      }

      setState(() { transfer.done = true; transfer.progress = 1.0; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(' Disimpan ke: $localPath'),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ));
      }
    } catch (e) {
      setState(() { transfer.error = e.toString(); transfer.done = true; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download gagal: $e'),
          backgroundColor: AppTheme.danger));
    }
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _transfers.remove(transfer));
  }

  //  Upload 
  Future<void> _upload() async {
    // Pick file
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final localPath = picked.path;
    if (localPath == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot access file')));
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

      final escapedPath = remotePath.replaceAll("'", "'\''");

      // Stream dari file langsung ke SSH stdin - tidak load ke RAM
      final session = await ssh.client!.execute(
        "dd of='$escapedPath' bs=65536"
      );

      // Baca file sebagai stream 64KB per chunk
      int sent = 0;
      await for (final chunk in localFile.openRead()) {
        session.stdin.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
        sent += chunk.length;
        setState(() => transfer.progress =
          (sent / fileSize).clamp(0.0, 0.99));
        await Future.delayed(Duration.zero);
      }
      await session.stdin.close();
      await session.done;

      setState(() { transfer.done = true; transfer.progress = 1.0; });
      _ls(_cwd);

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(' ${picked.name} berhasil diupload')));
    } catch (e) {
      setState(() { transfer.error = e.toString(); transfer.done = true; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload gagal: $e'),
          backgroundColor: AppTheme.danger));
    }

    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _transfers.remove(transfer));
  }

  //  File operations 
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
      title: Text('Delete ${entry.isDir ? "Folder" : "File"}?'),
      content: Text(entry.path),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete')),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Save')),
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
      title: const Text('New Folder'),
      content: TextField(controller: ctrl, autofocus: true,
        decoration: const InputDecoration(hintText: 'nama folder')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: const Text('Create')),
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

  /// Returns true if permission granted.
  /// Triggers system permission popup (Android/iOS native dialog).
  /// Only shows in-app dialog if PERMANENTLY denied (user must go to Settings).
  Future<bool> _ensureStoragePermission() async {
    final sdkInt = await _androidSdk();
    // Pick the right permission for the Android version
    final perm = sdkInt >= 33
        ? Permission.manageExternalStorage
        : Permission.storage;

    var status = await perm.status;
    if (status.isGranted) return true;

    // Directly request - this triggers the native OS permission popup
    status = await perm.request();
    if (status.isGranted) return true;

    // Only reach here if denied
    if (mounted) {
      if (status.isPermanentlyDenied) {
        // OS won't show popup anymore - guide user to App Settings
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Storage Permission Blocked'),
            content: const Text(
              'Storage permission was permanently denied. '
              'Please enable it in App Settings to upload/download files.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () { openAppSettings(); Navigator.pop(ctx); },
                child: const Text('Open Settings')),
            ],
          ),
        );
      }
    }
    return false;
  }

  Future<int> _androidSdk() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return info.version.sdkInt;
    } catch (_) { return 29; }
  }

  void _showContentSheet(String title, String content) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: _bar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false, initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.4,
        builder: (_, sc) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16,12,8,8),
            child: Row(children: [
              Icon(Icons.insert_drive_file_rounded, color: _accent, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: GoogleFonts.jetBrainsMono(
                color: _accent, fontSize: 13))),
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
    _accent = Theme.of(context).extension<AppColors>()?.accent ?? const Color(0xFF00E5A0);
    final textPrimary = _isDark ? const Color(0xFFE2E8F5) : const Color(0xFF1A202C);
    final textSub = _isDark ? const Color(0xFF6B7A99) : const Color(0xFF4A5568);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bar,
        elevation: 0,
        title: _selectMode
          ? Text('${_selected.length} selected', style: TextStyle(fontSize: 16, color: _accent))
          : const Text('File Manager', style: TextStyle(fontSize: 16)),
        leading: _selectMode
          ? IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _selected.clear()),
            )
          : null,
        actions: _selectMode ? [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            color: _accent,
            tooltip: 'Download selected',
            onPressed: _downloadSelected,
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded),
            color: _accent,
            tooltip: 'chmod selected',
            onPressed: _chmodSelected,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            color: AppTheme.danger,
            tooltip: 'Delete selected',
            onPressed: _deleteSelected,
          ),
        ] : [
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
                      Icon(Icons.folder_rounded, color: _accent, size: 14),
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
          ? Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
            ? _buildError()
            : _entries.isEmpty
              ? _buildEmpty()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => Divider(height:1, color:_brd, indent:52),
                  itemBuilder: (ctx, i) {
                    final e = _entries[i];
                    final isSelected = _selected.contains(e.path);
                    return _EntryRow(
                      entry: e,
                      isDark: _isDark,
                      fmtSize: _fmtSize,
                      isSelected: isSelected,
                      selectMode: _selectMode,
                      onTap: _selectMode
                        ? () => setState(() {
                            if (isSelected) _selected.remove(e.path);
                            else _selected.add(e.path);
                          })
                        : () => e.isDir ? _navigate(e.path) : _showContent(e),
                      onLongPress: () => setState(() {
                        if (!_selectMode) _selected.add(e.path);
                        else if (isSelected) _selected.remove(e.path);
                        else _selected.add(e.path);
                      }),
                      onDownload: e.isDir ? null : () => _download(e),
                      onDelete: () => _delete(e),
                      onRename: () => _rename(e),
                      onChmod: () => _chmod(e),
                    );
                  },
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
        backgroundColor: _accent,
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
  //  Chmod 
  Future<void> _chmod(_FsEntry entry) async {
    // Parse current octal from permissions string e.g. "drwxr-xr-x"
    String _toOctal(String p) {
      final chars = p.length >= 10 ? p.substring(1) : p;
      int octal = 0;
      const map = {'r':4,'w':2,'x':1,'-':0};
      for (int g=0; g<3; g++) {
        int v=0;
        for (int b=0; b<3; b++) {
          final ch = chars.length > g*3+b ? chars[g*3+b] : '-';
          v += map[ch] ?? 0;
        }
        octal = octal * 10 + v;
      }
      return octal.toString().padLeft(3,'0');
    }

    final current = _toOctal(entry.permissions);
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Permissions'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${entry.name}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Octal permission (e.g. 755)',
              hintText: '755',
            ),
            keyboardType: TextInputType.number,
            maxLength: 4,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Apply')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    try {
      await _run('chmod $result "${entry.path}"');
      _ls(_cwd);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('chmod failed: $e')));
    }
  }

  //  Download multiple selected 
  Future<void> _downloadSelected() async {
    final files = _entries.where((e) => _selected.contains(e.path) && !e.isDir).toList();
    if (files.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No files selected (folders cannot be downloaded)')));
      return;
    }
    setState(() => _selected.clear());
    for (final f in files) {
      await _download(f);
    }
  }

  //  Chmod multiple selected 
  Future<void> _chmodSelected() async {
    if (_selected.isEmpty) return;
    final ctrl = TextEditingController(text: '755');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change Permissions (${_selected.length} items)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Apply to all ${_selected.length} selected items',
            style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Octal permission (e.g. 755)',
              hintText: '755',
            ),
            keyboardType: TextInputType.number,
            maxLength: 4,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Apply')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty) return;
    try {
      for (final path in _selected) {
        await _run('chmod $result "$path"');
      }
      setState(() => _selected.clear());
      _ls(_cwd);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('chmod $result applied')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('chmod failed: $e')));
    }
  }

  //  Delete multiple selected 
  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Selected'),
        content: Text('Delete $count item(s)? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete')),
        ],
      ),
    ) ?? false;
    if (!ok) return;
    try {
      for (final path in _selected) {
        await _run('rm -rf "$path"');
      }
      setState(() => _selected.clear());
      _ls(_cwd);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')));
    }
  }

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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
    Text('Empty folder', style: TextStyle(color: Colors.white38)),
  ]));
}

//  Entry Row 
class _EntryRow extends StatelessWidget {
  final _FsEntry entry;
  final bool isDark, isSelected, selectMode;
  final String Function(int) fmtSize;
  final VoidCallback onTap, onDelete, onRename, onChmod;
  final VoidCallback? onDownload, onLongPress;

  const _EntryRow({
    required this.entry, required this.isDark, required this.fmtSize,
    required this.onTap, required this.onDelete, required this.onRename,
    required this.onChmod,
    this.onDownload, this.onLongPress,
    this.isSelected = false, this.selectMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final tileBg = isDark ? const Color(0xFF0B0F1A) : const Color(0xFFF8FAFC);
    final selBg  = isDark ? const Color(0xFF0F2030) : const Color(0xFFE8F4FF);
    final nameCol = isDark ? const Color(0xFFE2E8F5) : const Color(0xFF1A202C);
    final subCol  = isDark ? const Color(0xFF6B7A99) : const Color(0xFF718096);
    final _accent = Theme.of(context).extension<AppColors>()?.accent ?? const Color(0xFF00E5A0);

    return Material(
      color: isSelected ? selBg : tileBg,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: _accent.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal:12, vertical:9),
          child: Row(children: [
            // Checkbox (select mode) or folder icon
            if (selectMode)
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 24, height: 24,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: isSelected ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected ? _accent : subCol, width: 2),
                ),
                child: isSelected
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null,
              ),
            // Icon
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: entry.isDir
                  ? _accent.withOpacity(0.1)
                  : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                entry.isDir ? Icons.folder_rounded : _icon(entry.name),
                color: entry.isDir ? _accent : Colors.white38,
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
            if (!selectMode) ...[
              // Download button (files only)
              if (onDownload != null)
                IconButton(
                  icon: Icon(Icons.download_rounded, color: _accent.withOpacity(0.7), size: 20),
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
                  if (v=='chmod') onChmod();
                  if (v=='delete') onDelete();
                },
                itemBuilder: (_) => [
                  if (!entry.isDir)
                    PopupMenuItem(value:'download',
                      child: Row(children:[
                        Icon(Icons.download_rounded, size:16, color:_accent),
                        const SizedBox(width:8), const Text('Download'),
                      ])),
                  const PopupMenuItem(value:'rename',
                    child: Row(children:[
                      Icon(Icons.drive_file_rename_outline, size:16, color:Colors.white54),
                      SizedBox(width:8), Text('Rename'),
                    ])),
                  PopupMenuItem(value:'chmod',
                    child: Row(children:[
                      Icon(Icons.lock_outline_rounded, size:16, color:_accent),
                      const SizedBox(width:8), const Text('Permissions (chmod)'),
                    ])),
                  const PopupMenuItem(value:'delete',
                    child: Row(children:[
                      Icon(Icons.delete_outline_rounded, size:16, color:AppTheme.danger),
                      SizedBox(width:8), Text('Delete',
                        style:TextStyle(color:AppTheme.danger)),
                    ])),
                ],
              ),
            ],
          ]),
        ),
      ),
    );
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

//  Transfer Progress Card 
class _TransferCard extends StatelessWidget {
  final _Transfer transfer;
  const _TransferCard({required this.transfer});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary;
    final isErr = transfer.error != null;
    final color = isErr ? AppTheme.danger
      : transfer.done ? AppTheme.success : accent;
    final indeterminate = transfer.progress < 0;

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
            size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(transfer.name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis)),
          if (transfer.done)
            Icon(isErr ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              size: 16, color: color)
          else
            Text(
              indeterminate ? '...' : '${(transfer.progress * 100).toInt()}%',
              style: TextStyle(fontSize: 11, color: color)),
        ]),
        const SizedBox(height: 6),
        if (!transfer.done)
          indeterminate
            ? LinearProgressIndicator(color: color, backgroundColor: color.withOpacity(0.15))
            : LinearProgressIndicator(
                value: transfer.progress,
                color: color,
                backgroundColor: color.withOpacity(0.15),
              )
        else if (isErr)
          Text(transfer.error!, style: TextStyle(fontSize: 11, color: AppTheme.danger),
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

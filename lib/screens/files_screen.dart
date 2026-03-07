import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';

class _FsEntry {
  final String name, path, permissions, owner;
  final bool isDir;
  final int size;
  final String modified;
  const _FsEntry({required this.name, required this.path, required this.isDir,
    required this.size, required this.permissions, required this.owner,
    required this.modified});
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
  final _pathCtrl = TextEditingController();
  final List<String> _history = ['/'];
  int _histIdx = 0;

  @override
  void initState() {
    super.initState();
    _ls('/');
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _ls(String path) async {
    setState(() { _loading = true; _error = null; });
    try {
      final ssh = ref.read(sshServiceProvider);
      // Use ls -la to get full file listing
      final raw = await ssh.run(
        'ls -la "$path" 2>&1 || echo "ERROR: Cannot access $path"'
      );
      if (raw.startsWith('ERROR:')) {
        setState(() { _error = raw; _loading = false; });
        return;
      }
      final entries = _parseLs(raw, path);
      setState(() {
        _cwd = path;
        _entries = entries;
        _loading = false;
        _pathCtrl.text = path;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<_FsEntry> _parseLs(String raw, String basePath) {
    final entries = <_FsEntry>[];
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty || t.startsWith('total') || t.startsWith('ERROR')) continue;
      // Format: permissions links owner group size date name
      final re = RegExp(r'^([dlrwx\-]{10})\s+\d+\s+(\S+)\s+\S+\s+(\d+)\s+(\w+\s+\d+\s+[\d:]+)\s+(.+)$');
      final m = re.firstMatch(t);
      if (m == null) continue;
      final perms = m.group(1)!;
      final owner = m.group(2)!;
      final size  = int.tryParse(m.group(3)!) ?? 0;
      final mod   = m.group(4)!;
      var   name  = m.group(5)!;

      // Handle symlinks "name -> target"
      if (name.contains(' -> ')) name = name.split(' -> ').first;
      if (name == '.' || name == '..') continue;

      final isDir = perms.startsWith('d') || perms.startsWith('l');
      final full  = basePath == '/' ? '/$name' : '$basePath/$name';

      entries.add(_FsEntry(
        name: name, path: full, isDir: isDir,
        size: size, permissions: perms, owner: owner, modified: mod,
      ));
    }
    // Dirs first, then files, both sorted by name
    entries.sort((a, b) {
      if (a.isDir && !b.isDir) return -1;
      if (!a.isDir && b.isDir) return 1;
      return a.name.compareTo(b.name);
    });
    return entries;
  }

  void _navigate(String path) {
    if (_histIdx < _history.length - 1) {
      _history.removeRange(_histIdx + 1, _history.length);
    }
    _history.add(path);
    _histIdx = _history.length - 1;
    _ls(path);
  }

  void _goUp() {
    if (_cwd == '/') return;
    final parts = _cwd.split('/');
    parts.removeLast();
    _navigate(parts.isEmpty || (parts.length == 1 && parts[0].isEmpty) ? '/' : parts.join('/'));
  }

  void _goBack() {
    if (_histIdx <= 0) return;
    _histIdx--;
    _ls(_history[_histIdx]);
  }

  void _goForward() {
    if (_histIdx >= _history.length - 1) return;
    _histIdx++;
    _ls(_history[_histIdx]);
  }

  Future<void> _showFileContent(_FsEntry entry) async {
    setState(() => _loading = true);
    try {
      final ssh = ref.read(sshServiceProvider);
      final size = entry.size;
      if (size > 512 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File terlalu besar untuk ditampilkan (>512KB)')));
        setState(() => _loading = false);
        return;
      }
      final content = await ssh.run('cat "${entry.path}" 2>&1');
      setState(() => _loading = false);
      if (!mounted) return;
      _showContentDialog(entry.name, content);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _deleteEntry(_FsEntry entry) async {
    final ok = await showDialog<bool>(context: context, builder: (_) =>
      AlertDialog(
        title: Text('Hapus ${entry.isDir ? "Folder" : "File"}?'),
        content: Text(entry.path),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ));
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      final ssh = ref.read(sshServiceProvider);
      await ssh.run(entry.isDir
        ? 'rm -rf "${entry.path}"'
        : 'rm -f "${entry.path}"');
      _ls(_cwd);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _createDir() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (_) =>
      AlertDialog(
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
      final ssh = ref.read(sshServiceProvider);
      final path = _cwd == '/' ? '/$name' : '$_cwd/$name';
      await ssh.run('mkdir -p "$path"');
      _ls(_cwd);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _renameEntry(_FsEntry entry) async {
    final ctrl = TextEditingController(text: entry.name);
    final name = await showDialog<String>(context: context, builder: (_) =>
      AlertDialog(
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
    try {
      final ssh = ref.read(sshServiceProvider);
      final newPath = _cwd == '/' ? '/$name' : '$_cwd/$name';
      await ssh.run('mv "${entry.path}" "$newPath"');
      _ls(_cwd);
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showContentDialog(String title, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0F1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, sc) => Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16,12,12,12),
            child: Row(children: [
              const Icon(Icons.insert_drive_file_rounded,
                color: AppTheme.terminal, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(title,
                style: GoogleFonts.jetBrainsMono(
                  color: AppTheme.terminal, fontSize: 13,
                  fontWeight: FontWeight.w600))),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(_),
              ),
            ]),
          ),
          const Divider(color: Color(0xFF1F2D3D), height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: sc,
              padding: const EdgeInsets.all(12),
              child: SelectableText(content,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12, color: const Color(0xFFCDD6F4), height: 1.5)),
            ),
          ),
        ]),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024*1024) return '${(bytes/1024).toStringAsFixed(1)}KB';
    return '${(bytes/(1024*1024)).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        title: Text('File Manager',
          style: GoogleFonts.jetBrainsMono(fontSize: 15, fontWeight: FontWeight.w600)),
        // Path breadcrumb bar
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(children: [
              IconButton(
                icon: Icon(Icons.arrow_back_rounded,
                  color: _histIdx > 0 ? Colors.white70 : Colors.white24, size: 20),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth:32),
                onPressed: _histIdx > 0 ? _goBack : null,
              ),
              IconButton(
                icon: Icon(Icons.arrow_forward_rounded,
                  color: _histIdx < _history.length-1 ? Colors.white70 : Colors.white24, size: 20),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth:32),
                onPressed: _histIdx < _history.length-1 ? _goForward : null,
              ),
              IconButton(
                icon: Icon(Icons.arrow_upward_rounded,
                  color: _cwd != '/' ? Colors.white70 : Colors.white24, size: 20),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth:32),
                onPressed: _cwd != '/' ? _goUp : null,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _showGoToDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal:10, vertical:6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0F1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1F2D3D)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.folder_rounded,
                        color: AppTheme.terminal, size: 14),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_cwd,
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white70, fontSize: 12),
                        overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 20),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth:32),
                onPressed: () => _ls(_cwd),
              ),
            ]),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: AppTheme.primary,
        onPressed: _createDir,
        child: const Icon(Icons.create_new_folder_rounded, size: 20),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppTheme.terminal))
        : _error != null
          ? Center(child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54)),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: () => _ls(_cwd), child: const Text('Retry')),
              ]),
            ))
          : _entries.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.folder_open_rounded, color: Colors.white24, size: 48),
                const SizedBox(height: 12),
                Text('Folder kosong', style: TextStyle(color: Colors.white38)),
              ]))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: _entries.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1, color: Color(0xFF1A2234), indent: 52),
                itemBuilder: (ctx, i) => _EntryTile(
                  entry: _entries[i],
                  onTap: () => _entries[i].isDir
                    ? _navigate(_entries[i].path)
                    : _showFileContent(_entries[i]),
                  onDelete: () => _deleteEntry(_entries[i]),
                  onRename: () => _renameEntry(_entries[i]),
                  formatSize: _formatSize,
                ),
              ),
    );
  }

  void _showGoToDialog() async {
    final ctrl = TextEditingController(text: _cwd);
    final path = await showDialog<String>(context: context, builder: (_) =>
      AlertDialog(
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
}

class _EntryTile extends StatelessWidget {
  final _FsEntry entry;
  final VoidCallback onTap, onDelete, onRename;
  final String Function(int) formatSize;
  const _EntryTile({required this.entry, required this.onTap,
    required this.onDelete, required this.onRename, required this.formatSize});

  @override
  Widget build(BuildContext context) {
    final isDir = entry.isDir;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          // Icon
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isDir
                ? AppTheme.terminal.withOpacity(0.1)
                : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isDir ? Icons.folder_rounded : _fileIcon(entry.name),
              color: isDir ? AppTheme.terminal : Colors.white38,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name,
                style: TextStyle(
                  color: isDir ? Colors.white : Colors.white70,
                  fontSize: 13.5,
                  fontWeight: isDir ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(children: [
                Text(entry.permissions,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10.5, color: Colors.white30)),
                const SizedBox(width: 8),
                Text(entry.owner,
                  style: const TextStyle(fontSize: 11, color: Colors.white30)),
                if (!isDir) ...[
                  const SizedBox(width: 8),
                  Text(formatSize(entry.size),
                    style: const TextStyle(fontSize: 11, color: Colors.white38)),
                ],
                const SizedBox(width: 8),
                Text(entry.modified,
                  style: const TextStyle(fontSize: 11, color: Colors.white24)),
              ]),
            ],
          )),
          // More menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white24, size: 18),
            color: const Color(0xFF1A2234),
            onSelected: (v) {
              if (v == 'delete') onDelete();
              if (v == 'rename') onRename();
            },
            itemBuilder: (_) => [
              if (!entry.isDir)
                const PopupMenuItem(value:'view',
                  child: Row(children:[
                    Icon(Icons.visibility_rounded,size:16,color:Colors.white54),
                    SizedBox(width:8), Text('View',style:TextStyle(color:Colors.white70))
                  ])),
              const PopupMenuItem(value:'rename',
                child: Row(children:[
                  Icon(Icons.drive_file_rename_outline,size:16,color:Colors.white54),
                  SizedBox(width:8), Text('Rename',style:TextStyle(color:Colors.white70))
                ])),
              const PopupMenuItem(value:'delete',
                child: Row(children:[
                  Icon(Icons.delete_outline_rounded,size:16,color:AppTheme.danger),
                  SizedBox(width:8), Text('Delete',style:TextStyle(color:AppTheme.danger))
                ])),
            ],
          ),
        ]),
      ),
    );
  }

  IconData _fileIcon(String name) {
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

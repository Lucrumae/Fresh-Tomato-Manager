import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});
  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _inputCtrl   = TextEditingController();
  final _scrollCtrl  = ScrollController();
  final _focusNode   = FocusNode();
  final _lines       = <_TermLine>[];
  SSHSession? _session;
  bool _connecting = false;
  bool _connected  = false;
  String _prompt   = '# ';
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  String _buffer = '';

  @override
  void initState() {
    super.initState();
    _startShell();
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _session?.close();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _startShell() async {
    setState(() { _connecting = true; });
    _addLine('Connecting to SSH shell...', type: _LineType.system);

    try {
      final ssh = ref.read(sshServiceProvider);
      if (!ssh.isConnected) {
        _addLine('Not connected. Go back and reconnect.', type: _LineType.error);
        setState(() { _connecting = false; });
        return;
      }

      final client = ssh.client;
      if (client == null) {
        _addLine('SSH client not available.', type: _LineType.error);
        setState(() { _connecting = false; });
        return;
      }

      _session = await client.shell(
        pty: SSHPtyConfig(
          width: 80, height: 24,
          type: 'xterm-256color',
        ),
      );

      setState(() { _connecting = false; _connected = true; });
      _addLine('Connected! Type commands below.', type: _LineType.system);
      _addLine('', type: _LineType.system);

      // Stream stdout
      _stdoutSub = _session!.stdout.listen(
        (data) => _onData(data),
        onDone: () {
          if (mounted) {
            _addLine('\n[Session closed]', type: _LineType.system);
            setState(() => _connected = false);
          }
        },
      );

      // Stream stderr
      _stderrSub = _session!.stderr.listen(
        (data) => _onData(data, isError: true),
      );

    } catch (e) {
      _addLine('Error: $e', type: _LineType.error);
      setState(() { _connecting = false; });
    }
  }

  void _onData(Uint8List data, {bool isError = false}) {
    final text = String.fromCharCodes(data);
    // Strip ANSI escape codes
    final clean = text.replaceAll(RegExp(r'\x1B\[[0-9;]*[mGKHF]'), '')
                      .replaceAll(RegExp(r'\x1B\[[0-9;]*[ABCD]'), '')
                      .replaceAll(RegExp(r'\x1B\[?\d*[A-Za-z]'), '');

    _buffer += clean;

    // Split on newlines
    final parts = _buffer.split('\n');
    _buffer = parts.removeLast(); // keep incomplete line in buffer

    for (final part in parts) {
      if (part.trim().isNotEmpty || _lines.isNotEmpty) {
        _addLine(part, type: isError ? _LineType.error : _LineType.output);
      }
    }

    // Flush remaining buffer as partial line
    if (_buffer.isNotEmpty) {
      _addLine(_buffer, type: _LineType.output, partial: true);
      _buffer = '';
    }
  }

  void _addLine(String text, {required _LineType type, bool partial = false}) {
    if (!mounted) return;
    setState(() {
      // Replace last line if it was partial
      if (_lines.isNotEmpty && _lines.last.partial) {
        _lines.last = _TermLine(text: _lines.last.text + text, type: type, partial: partial);
      } else {
        // Split long output into multiple lines
        final parts = text.split('\n');
        for (int i = 0; i < parts.length; i++) {
          _lines.add(_TermLine(
            text: parts[i],
            type: type,
            partial: i == parts.length - 1 && partial,
          ));
        }
      }
      // Keep max 500 lines
      if (_lines.length > 500) _lines.removeRange(0, _lines.length - 500);
    });
    _scrollToBottom();
  }

  void _send(String cmd) {
    if (!_connected || _session == null) return;
    _addLine('$_prompt$cmd', type: _LineType.input);
    _session!.stdin.add(Uint8List.fromList('$cmd\n'.codeUnits));
    _inputCtrl.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Quick command buttons
  final _quickCmds = const [
    ('top -bn1', 'top'),
    ('free -m', 'free'),
    ('df -h', 'df'),
    ('ip a', 'ip a'),
    ('arp -a', 'arp'),
    ('logread | tail -20', 'logs'),
    ('uptime', 'uptime'),
    ('clear', 'clear'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.terminalBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(
            color: _connected ? AppTheme.terminal : Colors.red,
            shape: BoxShape.circle,
          )),
          const SizedBox(width: 8),
          Text('Terminal',
            style: GoogleFonts.jetBrainsMono(
              color: AppTheme.terminal, fontSize: 16, fontWeight: FontWeight.w600,
            )),
        ]),
        iconTheme: const IconThemeData(color: AppTheme.terminal),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.terminal),
            onPressed: () {
              setState(() { _lines.clear(); _connected = false; });
              _session?.close();
              _startShell();
            },
          ),
          IconButton(
            icon: const Icon(Icons.cleaning_services_rounded, color: AppTheme.terminal),
            onPressed: () => setState(() => _lines.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          // Terminal output
          Expanded(
            child: _connecting
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: AppTheme.terminal),
                  const SizedBox(height: 16),
                  Text('Starting shell...', style: GoogleFonts.jetBrainsMono(color: AppTheme.terminal)),
                ]))
              : SelectableRegion(
                  focusNode: FocusNode(),
                  selectionControls: materialTextSelectionControls,
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: _lines.length,
                    itemBuilder: (ctx, i) => _buildLine(_lines[i]),
                  ),
                ),
          ),

          // Quick commands
          Container(
            height: 36,
            color: const Color(0xFF161B22),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: _quickCmds.map((cmd) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => _send(cmd.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.terminal.withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(cmd.$2,
                      style: GoogleFonts.jetBrainsMono(
                        color: AppTheme.terminal, fontSize: 11,
                      )),
                  ),
                ),
              )).toList(),
            ),
          ),

          // Input bar
          Container(
            color: const Color(0xFF161B22),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(children: [
              Text(_prompt, style: GoogleFonts.jetBrainsMono(
                color: AppTheme.terminal, fontSize: 14, fontWeight: FontWeight.bold,
              )),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  focusNode: _focusNode,
                  autofocus: true,
                  enabled: _connected,
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.white, fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'enter command...',
                    hintStyle: TextStyle(color: Color(0xFF555A72), fontSize: 14),
                  ),
                  onSubmitted: _send,
                  textInputAction: TextInputAction.send,
                ),
              ),
              GestureDetector(
                onTap: () => _send(_inputCtrl.text),
                child: const Icon(Icons.send_rounded, color: AppTheme.terminal, size: 20),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(_TermLine line) {
    Color color;
    switch (line.type) {
      case _LineType.input:  color = Colors.white; break;
      case _LineType.output: color = const Color(0xFFCDD6F4); break;
      case _LineType.error:  color = const Color(0xFFF38BA8); break;
      case _LineType.system: color = AppTheme.terminal.withOpacity(0.7); break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        line.text,
        style: GoogleFonts.jetBrainsMono(fontSize: 13, color: color, height: 1.4),
      ),
    );
  }
}

enum _LineType { input, output, error, system }

class _TermLine {
  final String text;
  final _LineType type;
  final bool partial;
  const _TermLine({required this.text, required this.type, this.partial = false});
}

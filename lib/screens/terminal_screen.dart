import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode  = FocusNode();
  final _lines      = <_TermLine>[];
  SSHSession? _session;
  bool _connecting  = false;
  bool _connected   = false;
  StreamSubscription? _stdoutSub;
  String _buffer    = '';
  final _cmdHistory = <String>[];
  int _historyIdx   = -1;

  @override
  void initState() {
    super.initState();
    _startShell();
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _session?.close();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _startShell() async {
    setState(() { _connecting = true; _lines.clear(); });
    _addLine('Connecting to SSH shell...', type: _LineType.system);

    try {
      final ssh = ref.read(sshServiceProvider);
      if (!ssh.isConnected || ssh.client == null) {
        _addLine('Not connected. Go back and reconnect.', type: _LineType.error);
        setState(() => _connecting = false);
        return;
      }

      _session = await ssh.client!.shell(
        pty: SSHPtyConfig(width: 80, height: 24, type: 'xterm-256color'),
      );

      setState(() { _connecting = false; _connected = true; });

      _stdoutSub = _session!.stdout.listen((data) => _onData(data),
        onDone: () {
          if (mounted) {
            _addLine('[Session closed]', type: _LineType.system);
            setState(() => _connected = false);
          }
        },
      );
      _session!.stderr.listen((data) => _onData(data, isError: true));

    } catch (e) {
      _addLine('Error: $e', type: _LineType.error);
      setState(() => _connecting = false);
    }
  }

  void _onData(Uint8List data, {bool isError = false}) {
    var text = String.fromCharCodes(data);
    // Strip ANSI escape codes
    text = text.replaceAll(RegExp(r'\x1B\[[0-9;]*[mGKHFJABCDsuhl]'), '')
               .replaceAll(RegExp(r'\x1B\([AB]'), '')
               .replaceAll(RegExp(r'\r'), '');

    _buffer += text;
    final parts = _buffer.split('\n');
    _buffer = parts.removeLast();

    for (final part in parts) {
      _addLine(part, type: isError ? _LineType.error : _LineType.output);
    }
    if (_buffer.isNotEmpty) {
      _addLine(_buffer, type: _LineType.output, partial: true);
      _buffer = '';
    }
  }

  void _addLine(String text, {required _LineType type, bool partial = false}) {
    if (!mounted) return;
    setState(() {
      if (_lines.isNotEmpty && _lines.last.partial) {
        _lines[_lines.length - 1] = _TermLine(
          text: _lines.last.text + text, type: type, partial: partial);
      } else {
        for (final part in text.split('\n')) {
          _lines.add(_TermLine(text: part, type: type, partial: false));
        }
      }
      if (_lines.length > 500) _lines.removeRange(0, _lines.length - 500);
    });
    _scrollToBottom();
  }

  void _send(String cmd) {
    if (!_connected || _session == null || cmd.trim().isEmpty) return;
    if (_cmdHistory.isEmpty || _cmdHistory.last != cmd) {
      _cmdHistory.add(cmd);
      if (_cmdHistory.length > 50) _cmdHistory.removeAt(0);
    }
    _historyIdx = -1;
    _session!.stdin.add(Uint8List.fromList('$cmd\n'.codeUnits));
    _inputCtrl.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _historyUp() {
    if (_cmdHistory.isEmpty) return;
    setState(() {
      _historyIdx = (_historyIdx + 1).clamp(0, _cmdHistory.length - 1);
      _inputCtrl.text = _cmdHistory[_cmdHistory.length - 1 - _historyIdx];
      _inputCtrl.selection = TextSelection.collapsed(offset: _inputCtrl.text.length);
    });
  }

  void _historyDown() {
    if (_historyIdx <= 0) {
      setState(() { _historyIdx = -1; _inputCtrl.clear(); });
      return;
    }
    setState(() {
      _historyIdx--;
      _inputCtrl.text = _cmdHistory[_cmdHistory.length - 1 - _historyIdx];
      _inputCtrl.selection = TextSelection.collapsed(offset: _inputCtrl.text.length);
    });
  }

  static const _quickCmds = [
    ('top -bn1 | head -20', 'top'),
    ('free -m', 'free'),
    ('df -h', 'df'),
    ('ip addr', 'ip'),
    ('arp -a', 'arp'),
    ('logread | tail -30', 'logs'),
    ('uptime', 'uptime'),
    ('ls /tmp', 'ls'),
  ];

  @override
  Widget build(BuildContext context) {
    final termBg   = const Color(0xFF0D1117);
    final termBar  = const Color(0xFF161B22);
    final termBord = const Color(0xFF30363D);

    return Column(
      children: [
        // ── Header bar ────────────────────────────────────────────────────
        Container(
          color: termBar,
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: _connected ? AppTheme.terminal : Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text('Terminal',
              style: GoogleFonts.jetBrainsMono(
                color: AppTheme.terminal, fontSize: 14, fontWeight: FontWeight.w600,
              )),
            const Spacer(),
            // History up/down
            _headerBtn(Icons.arrow_upward_rounded, _historyUp),
            _headerBtn(Icons.arrow_downward_rounded, _historyDown),
            _headerBtn(Icons.refresh_rounded, () {
              _session?.close();
              _stdoutSub?.cancel();
              setState(() { _connected = false; });
              _startShell();
            }),
            _headerBtn(Icons.cleaning_services_rounded,
              () => setState(() => _lines.clear())),
          ]),
        ),

        // ── Terminal output ───────────────────────────────────────────────
        Expanded(
          child: Container(
            color: termBg,
            child: _connecting
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: AppTheme.terminal, strokeWidth: 2),
                  const SizedBox(height: 12),
                  Text('Starting shell...',
                    style: GoogleFonts.jetBrainsMono(color: AppTheme.terminal, fontSize: 13)),
                ]))
              : SelectableRegion(
                  focusNode: FocusNode(),
                  selectionControls: materialTextSelectionControls,
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    itemCount: _lines.length,
                    itemBuilder: (ctx, i) => _buildLine(_lines[i]),
                  ),
                ),
          ),
        ),

        // ── Quick commands scrollable ──────────────────────────────────────
        Container(
          height: 34,
          color: termBar,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            children: _quickCmds.map((cmd) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => _send(cmd.$1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.terminal.withOpacity(0.35)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(cmd.$2,
                    style: GoogleFonts.jetBrainsMono(
                      color: AppTheme.terminal, fontSize: 11)),
                ),
              ),
            )).toList(),
          ),
        ),

        // ── Input bar ─────────────────────────────────────────────────────
        Container(
          color: termBar,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: termBord),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            child: Row(children: [
              Text('# ', style: GoogleFonts.jetBrainsMono(
                color: AppTheme.terminal, fontSize: 14, fontWeight: FontWeight.bold)),
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  focusNode: _focusNode,
                  enabled: _connected,
                  style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true, border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false, contentPadding: EdgeInsets.zero,
                    hintText: 'enter command...',
                    hintStyle: TextStyle(color: Color(0xFF555A72), fontSize: 13),
                  ),
                  onSubmitted: _send,
                  textInputAction: TextInputAction.send,
                ),
              ),
              GestureDetector(
                onTap: () => _send(_inputCtrl.text),
                child: const Icon(Icons.send_rounded, color: AppTheme.terminal, size: 18),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _headerBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Icon(icon, color: AppTheme.terminal.withOpacity(0.7), size: 18),
    ),
  );

  Widget _buildLine(_TermLine line) {
    Color color;
    switch (line.type) {
      case _LineType.output: color = const Color(0xFFCDD6F4); break;
      case _LineType.error:  color = const Color(0xFFF38BA8); break;
      case _LineType.system: color = AppTheme.terminal.withOpacity(0.6); break;
    }
    return Text(line.text,
      style: GoogleFonts.jetBrainsMono(fontSize: 12.5, color: color, height: 1.5));
  }
}

enum _LineType { output, error, system }

class _TermLine {
  final String text;
  final _LineType type;
  final bool partial;
  const _TermLine({required this.text, required this.type, this.partial = false});
}

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

class _TerminalScreenState extends ConsumerState<TerminalScreen>
    with WidgetsBindingObserver {
  final _scrollCtrl  = ScrollController();
  final _focusNode   = FocusNode();
  final _inputCtrl   = TextEditingController();
  final _lines       = <_TermLine>[];
  SSHSession? _session;
  bool _connecting   = false;
  bool _connected    = false;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  String _buffer     = '';
  final _cmdHistory  = <String>[];
  int _historyIdx    = -1;
  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startShell();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _session?.close();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _inputCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final bottom = WidgetsBinding.instance.window.viewInsets.bottom;
    final visible = bottom > 100;
    if (visible != _keyboardVisible) {
      setState(() => _keyboardVisible = visible);
      if (visible) _scrollToBottom();
    }
  }

  Future<void> _startShell() async {
    setState(() { _connecting = true; });
    _addLine('Connecting...', type: _LineType.system);
    try {
      final ssh = ref.read(sshServiceProvider);
      if (!ssh.isConnected || ssh.client == null) {
        _addLine('Not connected. Go back and reconnect.', type: _LineType.error);
        setState(() => _connecting = false);
        return;
      }
      _session = await ssh.client!.shell(
        pty: SSHPtyConfig(width: 120, height: 40, type: 'xterm-256color'),
      );
      setState(() { _connecting = false; _connected = true; });

      _stdoutSub = _session!.stdout.listen(
        (data) => _onData(data),
        onDone: () {
          if (mounted) {
            _addLine('\n[Session closed]', type: _LineType.system);
            setState(() => _connected = false);
          }
        },
      );
      _stderrSub = _session!.stderr.listen((data) => _onData(data, isError: true));
    } catch (e) {
      _addLine('Error: $e', type: _LineType.error);
      setState(() => _connecting = false);
    }
  }

  void _onData(Uint8List data, {bool isError = false}) {
    var text = String.fromCharCodes(data);
    text = text
      .replaceAll(RegExp(r'\x1B\[[0-9;]*[mGKHFJABCDsuhlnr]'), '')
      .replaceAll(RegExp(r'\x1B\([AB]'), '')
      .replaceAll(RegExp(r'\x1B\][\s\S]*?\x07'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');

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
      if (_lines.length > 1000) _lines.removeRange(0, _lines.length - 1000);
    });
    _scrollToBottom();
  }

  void _send(String cmd) {
    if (!_connected || _session == null) return;
    if (cmd.isNotEmpty) {
      if (_cmdHistory.isEmpty || _cmdHistory.last != cmd) {
        _cmdHistory.add(cmd);
        if (_cmdHistory.length > 100) _cmdHistory.removeAt(0);
      }
    }
    _historyIdx = -1;
    _session!.stdin.add(Uint8List.fromList('$cmd\n'.codeUnits));
    _inputCtrl.clear();
    _scrollToBottom();
  }

  void _sendRaw(List<int> bytes) {
    if (!_connected || _session == null) return;
    _session!.stdin.add(Uint8List.fromList(bytes));
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
    ('top -bn1 | head -25', 'top'),
    ('free -m', 'free'),
    ('df -h', 'df'),
    ('ip addr', 'ip'),
    ('arp -a', 'arp'),
    ('logread | tail -40', 'logs'),
    ('uptime', 'uptime'),
    ('ps', 'ps'),
    ('ls -la', 'ls'),
    ('cat /proc/net/dev', 'netdev'),
  ];

  // Ctrl key combinations
  static const _ctrlKeys = [
    ('C', [3]),    // Ctrl+C
    ('D', [4]),    // Ctrl+D
    ('Z', [26]),   // Ctrl+Z
    ('L', [12]),   // Ctrl+L (clear)
    ('A', [1]),    // Ctrl+A (begin of line)
    ('E', [5]),    // Ctrl+E (end of line)
    ('U', [21]),   // Ctrl+U (clear line)
    ('W', [23]),   // Ctrl+W (delete word)
    ('R', [18]),   // Ctrl+R (history search)
  ];

  @override
  Widget build(BuildContext context) {
    const termBg  = Color(0xFF0D1117);
    const termBar = Color(0xFF161B22);
    const termBrd = Color(0xFF30363D);

    return GestureDetector(
      onTap: () {
        _focusNode.requestFocus();
      },
      child: Column(
        children: [
          // ── Output area (clean, no header) ──────────────────────────────
          Expanded(
            child: Container(
              color: termBg,
              child: _connecting
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                        color: AppTheme.terminal, strokeWidth: 1.5)),
                    const SizedBox(height: 10),
                    Text('Starting shell...',
                      style: GoogleFonts.jetBrainsMono(
                        color: AppTheme.terminal, fontSize: 11)),
                  ]))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
                    itemCount: _lines.length,
                    itemBuilder: (ctx, i) => _buildLine(_lines[i]),
                  ),
            ),
          ),

          // ── Toolbar: shows above keyboard when open ────────────────────
          Container(
            color: termBar,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // Ctrl keys row (shown when keyboard is visible)
                if (_keyboardVisible) ...[
                  Container(
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      border: Border(top: BorderSide(color: termBrd)),
                    ),
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      children: [
                        // History buttons
                        _ctrlBtn('↑', () => _historyUp(),
                          color: Colors.white70),
                        _ctrlBtn('↓', () => _historyDown(),
                          color: Colors.white70),
                        Container(width: 1, color: termBrd, margin:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 6)),
                        // Ctrl keys
                        ..._ctrlKeys.map((k) => _ctrlBtn(
                          'Ctrl+${k.$1}',
                          () => _sendRaw(k.$2),
                          color: AppTheme.terminal,
                        )),
                        Container(width: 1, color: termBrd, margin:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 6)),
                        // Special keys
                        _ctrlBtn('Tab',   () => _sendRaw([9]),  color: Colors.white54),
                        _ctrlBtn('Esc',   () => _sendRaw([27]), color: Colors.white54),
                        _ctrlBtn('Clear', () => setState(() => _lines.clear()),
                          color: AppTheme.warning),
                        _ctrlBtn('↺', () {
                          _session?.close();
                          _stdoutSub?.cancel();
                          setState(() { _connected = false; _lines.clear(); });
                          _startShell();
                        }, color: AppTheme.danger),
                      ],
                    ),
                  ),

                  // Input bar (only shown when keyboard is open)
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                    color: termBar,
                    child: Row(children: [
                      Text('# ', style: GoogleFonts.jetBrainsMono(
                        color: AppTheme.terminal, fontSize: 13,
                        fontWeight: FontWeight.bold)),
                      Expanded(
                        child: TextField(
                          controller: _inputCtrl,
                          focusNode: _focusNode,
                          enabled: _connected,
                          autofocus: false,
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true, border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.symmetric(vertical: 6),
                            hintText: 'command...',
                            hintStyle: TextStyle(
                              color: Color(0xFF555A72), fontSize: 13),
                          ),
                          onSubmitted: _send,
                          textInputAction: TextInputAction.send,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _send(_inputCtrl.text),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.send_rounded,
                            color: AppTheme.terminal, size: 17),
                        ),
                      ),
                    ]),
                  ),
                ],

                // Quick commands row + action buttons (always visible)
                Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: termBar,
                    border: Border(top: BorderSide(color: termBrd)),
                  ),
                  child: Row(children: [
                    // Status dot + toggle keyboard
                    GestureDetector(
                      onTap: () {
                        if (_focusNode.hasFocus) {
                          _focusNode.unfocus();
                        } else {
                          _focusNode.requestFocus();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 7, height: 7,
                            decoration: BoxDecoration(
                              color: _connected ? AppTheme.terminal : Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            _keyboardVisible
                              ? Icons.keyboard_hide_rounded
                              : Icons.keyboard_rounded,
                            color: AppTheme.terminal.withOpacity(0.7),
                            size: 16,
                          ),
                        ]),
                      ),
                    ),
                    // Scrollable quick cmds
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        children: _quickCmds.map((cmd) => Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: GestureDetector(
                            onTap: () => _send(cmd.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppTheme.terminal.withOpacity(0.3)),
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
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctrlBtn(String label, VoidCallback onTap, {Color? color}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: (color ?? AppTheme.terminal).withOpacity(0.1),
          border: Border.all(
            color: (color ?? AppTheme.terminal).withOpacity(0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: GoogleFonts.jetBrainsMono(
          color: color ?? AppTheme.terminal, fontSize: 11,
          fontWeight: FontWeight.w500)),
      ),
    );

  Widget _buildLine(_TermLine line) {
    Color color;
    switch (line.type) {
      case _LineType.output: color = const Color(0xFFCDD6F4); break;
      case _LineType.error:  color = const Color(0xFFF38BA8); break;
      case _LineType.system: color = AppTheme.terminal.withOpacity(0.5); break;
    }
    return Text(line.text,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 11.5, color: color, height: 1.45));
  }
}

enum _LineType { output, error, system }
class _TermLine {
  final String text;
  final _LineType type;
  final bool partial;
  const _TermLine({required this.text, required this.type, this.partial = false});
}

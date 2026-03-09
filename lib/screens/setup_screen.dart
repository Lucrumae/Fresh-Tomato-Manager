import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import 'main_shell.dart';

class SetupScreen extends ConsumerStatefulWidget {
  final bool reconnectFailed;
  const SetupScreen({super.key, this.reconnectFailed = false});
  @override ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _host = TextEditingController(text: '192.168.1.1');
  final _user = TextEditingController(text: 'root');
  final _pass = TextEditingController();
  final _port = TextEditingController(text: '22');
  bool _obs = true, _connecting = false, _remember = false;
  String? _error;

  static const _kRemember = 'remember_me';
  static const _kHost = 'saved_host'; static const _kUser = 'saved_user';
  static const _kPass = 'saved_pass'; static const _kPort = 'saved_port';

  @override void initState() {
    super.initState();
    _loadSaved();
    if (widget.reconnectFailed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Connection lost. Please reconnect.',
            style: GoogleFonts.dmMono(color: Colors.white, fontSize: 12)),
          backgroundColor: V.err,
          duration: const Duration(seconds: 5)));
      });
    }
  }

  Future<void> _loadSaved() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_kRemember) == true && mounted) {
      setState(() {
        _remember = true;
        _host.text = p.getString(_kHost) ?? '192.168.1.1';
        _user.text = p.getString(_kUser) ?? 'root';
        _pass.text = p.getString(_kPass) ?? '';
        _port.text = p.getString(_kPort) ?? '22';
      });
    }
  }

  Future<void> _connect() async {
    final host = _host.text.trim();
    final user = _user.text.trim();
    final pass = _pass.text;
    final port = int.tryParse(_port.text.trim()) ?? 22;
    if (host.isEmpty || user.isEmpty) {
      setState(() => _error = 'Host and username required');
      return;
    }
    setState(() { _connecting = true; _error = null; });
    final config = TomatoConfig(host: host, username: user, password: pass, sshPort: port);
    final ssh = ref.read(sshServiceProvider);
    final err = await ssh.connect(config);
    if (err != null) {
      if (mounted) setState(() { _error = err; _connecting = false; });
      return;
    }
    await ref.read(configProvider.notifier).save(config);
    if (_remember) {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kRemember, true);
      await p.setString(_kHost, host); await p.setString(_kUser, user);
      await p.setString(_kPass, pass); await p.setString(_kPort, '$port');
    } else {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kRemember, false);
    }
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()));
    }
  }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Scaffold(
      backgroundColor: v.dark ? V.d0 : V.l0,
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 40),

          // ── Logo block ─────────────────────────────────────────────────
          Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: v.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: v.accent.withOpacity(0.3))),
              child: Icon(Icons.router_rounded, color: v.accent, size: 22)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('VOID', style: GoogleFonts.outfit(fontSize: 28,
                fontWeight: FontWeight.w900, color: v.hi, letterSpacing: 2)),
              Text('Router Manager', style: GoogleFonts.dmMono(fontSize: 11, color: v.mid)),
            ]),
          ]),

          const SizedBox(height: 48),

          Text('CONNECT', style: GoogleFonts.outfit(fontSize: 10,
            fontWeight: FontWeight.w800, color: v.lo, letterSpacing: 1.8)),
          const SizedBox(height: 14),

          // ── Fields ─────────────────────────────────────────────────────
          TextField(controller: _host,
            style: GoogleFonts.dmMono(fontSize: 14, color: v.hi),
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Router IP',
              prefixIcon: Icon(Icons.router_rounded, size: 17))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _user,
              style: GoogleFonts.dmMono(fontSize: 14, color: v.hi),
              decoration: InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline_rounded, size: 17)))),
            const SizedBox(width: 10),
            SizedBox(width: 90, child: TextField(controller: _port,
              style: GoogleFonts.dmMono(fontSize: 14, color: v.hi),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _pass,
            obscureText: _obs,
            style: GoogleFonts.dmMono(fontSize: 14, color: v.hi),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline_rounded, size: 17),
              suffixIcon: IconButton(
                icon: Icon(_obs ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 17),
                onPressed: () => setState(() => _obs = !_obs)))),
          const SizedBox(height: 14),

          // Remember me
          GestureDetector(
            onTap: () => setState(() => _remember = !_remember),
            child: Row(children: [
              Checkbox(value: _remember, onChanged: (x) => setState(() => _remember = x ?? false)),
              Text('Remember credentials', style: GoogleFonts.outfit(fontSize: 13, color: v.mid)),
            ])),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: V.err.withOpacity(0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: V.err.withOpacity(0.25))),
              child: Row(children: [
                Icon(Icons.error_outline_rounded, size: 14, color: V.err),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: GoogleFonts.dmMono(
                  fontSize: 11, color: V.err))),
              ])),
          ],

          const SizedBox(height: 24),

          // Connect button
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: _connecting ? null : _connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: v.accent,
              foregroundColor: v.dark ? V.d0 : V.hi,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _connecting
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: v.dark ? V.d0 : V.hi))
              : Text('CONNECT', style: GoogleFonts.outfit(
                  fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1)))),

          const SizedBox(height: 32),

          // Feature list
          Text('FEATURES', style: GoogleFonts.outfit(fontSize: 9,
            fontWeight: FontWeight.w700, color: v.lo, letterSpacing: 1.8)),
          const SizedBox(height: 10),
          ...['Real-time CPU · RAM · Temperature',
              'Live bandwidth monitoring',
              'Connected device management',
              'WiFi & port forward config',
              'QoS rules · System logs',
              'SSH terminal · File manager',
          ].map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Dot(color: v.accent, size: 5),
              const SizedBox(width: 10),
              Text(f, style: GoogleFonts.dmMono(fontSize: 11, color: v.mid)),
            ]))),
        ]),
      )),
    );
  }
}

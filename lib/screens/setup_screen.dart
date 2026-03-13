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

class _SetupScreenState extends ConsumerState<SetupScreen>
    with TickerProviderStateMixin {

  final _host = TextEditingController(text: '192.168.1.1');
  final _user = TextEditingController(text: 'root');
  final _pass = TextEditingController();
  final _port = TextEditingController(text: '22');
  bool _obs = true, _connecting = false, _remember = false;
  String? _error;

  late final AnimationController _pulseCtrl;
  late final AnimationController _entryCtrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  static const _kRemember = 'remember_me';
  static const _kHost = 'saved_host'; static const _kUser = 'saved_user';
  static const _kPass = 'saved_pass'; static const _kPort = 'saved_port';

  @override void initState() {
    super.initState();
    _loadSaved();

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim  = CurvedAnimation(parent: _entryCtrl, curve: const Interval(0.0, 0.7, curve: Curves.easeOut));
    _slideAnim = Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(
      CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _entryCtrl.forward();

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

  @override void dispose() {
    _pulseCtrl.dispose();
    _entryCtrl.dispose();
    _host.dispose(); _user.dispose(); _pass.dispose(); _port.dispose();
    super.dispose();
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
      backgroundColor: V.d0,
      body: Stack(children: [
        // Ambient glow background
        Positioned.fill(child: AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => CustomPaint(
            painter: _GlowPainter(v.accent, _pulseAnim.value)),
        )),
        // Dot grid overlay
        Positioned.fill(child: CustomPaint(painter: _DotGridPainter())),
        // Main content
        SafeArea(child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 52),

                // Hero
                Center(child: Column(children: [
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: v.accent.withOpacity(0.25 * _pulseAnim.value),
                          blurRadius: 36, spreadRadius: 4)]),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: v.accent.withOpacity(0.18 + 0.14 * _pulseAnim.value),
                            width: 1.5),
                          color: V.d1),
                        padding: const EdgeInsets.all(14),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset('assets/icon/icon.png',
                            errorBuilder: (_, __, ___) =>
                              Icon(Icons.router_rounded, color: v.accent, size: 38)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('TOMATO MANAGER',
                    style: GoogleFonts.outfit(
                      fontSize: 20, fontWeight: FontWeight.w900,
                      color: V.hi, letterSpacing: 3.5)),
                  const SizedBox(height: 5),
                  Text('FreshTomato SSH Controller',
                    style: GoogleFonts.dmMono(fontSize: 11, color: V.mid)),
                ])),

                const SizedBox(height: 48),

                _SectionLabel('SSH CONNECTION'),
                const SizedBox(height: 12),

                _Field(controller: _host, label: 'Router IP',
                  icon: Icons.router_rounded, accent: v.accent,
                  keyboardType: TextInputType.url),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _Field(controller: _user, label: 'Username',
                    icon: Icons.person_outline_rounded, accent: v.accent)),
                  const SizedBox(width: 10),
                  SizedBox(width: 88, child: _Field(controller: _port, label: 'Port',
                    icon: null, accent: v.accent,
                    keyboardType: TextInputType.number, centerText: true)),
                ]),
                const SizedBox(height: 10),
                _Field(controller: _pass, label: 'Password',
                  icon: Icons.lock_outline_rounded, accent: v.accent,
                  obscure: _obs,
                  suffix: IconButton(
                    icon: Icon(_obs ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      size: 16, color: V.mid),
                    onPressed: () => setState(() => _obs = !_obs))),

                const SizedBox(height: 16),

                // Remember me — custom checkbox
                GestureDetector(
                  onTap: () => setState(() => _remember = !_remember),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 19, height: 19,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        color: _remember ? v.accent.withOpacity(0.15) : Colors.transparent,
                        border: Border.all(
                          color: _remember ? v.accent : V.wire, width: 1.5)),
                      child: _remember
                        ? Icon(Icons.check_rounded, size: 12, color: v.accent)
                        : null),
                    const SizedBox(width: 10),
                    Text('Remember credentials',
                      style: GoogleFonts.outfit(fontSize: 13, color: V.mid)),
                  ])),

                // Error
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: V.err.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: V.err.withOpacity(0.3))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: const EdgeInsets.only(top: 1),
                        child: Icon(Icons.error_outline_rounded, size: 14, color: V.err)),
                      const SizedBox(width: 9),
                      Expanded(child: Text(_error!,
                        style: GoogleFonts.dmMono(fontSize: 11, color: V.err, height: 1.5))),
                    ])),
                ],

                const SizedBox(height: 24),

                // Connect button
                _ConnectButton(
                  connecting: _connecting, accent: v.accent,
                  onTap: _connecting ? null : _connect),

                const SizedBox(height: 44),

                // Feature pills
                _SectionLabel('FEATURES'),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  'CPU & RAM', 'Temperature', 'Bandwidth',
                  'Devices', 'WiFi Config', 'Port Forward',
                  'QoS Rules', 'System Logs', 'Terminal',
                ].map((f) => _FeaturePill(f, accent: v.accent)).toList()),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        )),
      ]),
    );
  }
}

// ─── Painters ────────────────────────────────────────────────────────────────
class _GlowPainter extends CustomPainter {
  final Color accent; final double t;
  const _GlowPainter(this.accent, this.t);
  @override void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.1), 230,
      Paint()..shader = RadialGradient(colors: [
        accent.withOpacity(0.09 * t), Colors.transparent
      ]).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.15, size.height * 0.1), radius: 230)));
    canvas.drawCircle(
      Offset(size.width * 0.88, size.height * 0.72), 190,
      Paint()..shader = RadialGradient(colors: [
        accent.withOpacity(0.06 * t), Colors.transparent
      ]).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.88, size.height * 0.72), radius: 190)));
  }
  @override bool shouldRepaint(_GlowPainter old) => old.t != t;
}

class _DotGridPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF1C1C1C);
    const step = 28.0;
    for (double x = 0; x < size.width; x += step)
      for (double y = 0; y < size.height; y += step)
        canvas.drawCircle(Offset(x, y), 1.0, p);
  }
  @override bool shouldRepaint(_) => false;
}

// ─── Widgets ─────────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final Color accent;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final bool centerText;
  const _Field({required this.controller, required this.label,
    required this.icon, required this.accent, this.obscure = false,
    this.suffix, this.keyboardType, this.centerText = false});
  @override Widget build(BuildContext context) => TextField(
    controller: controller, obscureText: obscure,
    keyboardType: keyboardType,
    textAlign: centerText ? TextAlign.center : TextAlign.start,
    style: GoogleFonts.dmMono(fontSize: 14, color: V.hi),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, size: 16, color: V.mid) : null,
      suffixIcon: suffix,
      filled: true, fillColor: const Color(0xFF111111),
      labelStyle: GoogleFonts.outfit(fontSize: 12, color: V.mid),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: Color(0xFF2A2A2A))),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: accent, width: 1.5)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(11))));
}

class _ConnectButton extends StatelessWidget {
  final bool connecting;
  final Color accent;
  final VoidCallback? onTap;
  const _ConnectButton({required this.connecting, required this.accent, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: connecting ? accent.withOpacity(0.12) : accent,
        border: connecting ? Border.all(color: accent.withOpacity(0.4)) : null,
        boxShadow: connecting ? null : [
          BoxShadow(color: accent.withOpacity(0.28), blurRadius: 20, offset: const Offset(0, 6))]),
      child: Center(child: connecting
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
            const SizedBox(width: 12),
            Text('CONNECTING…', style: GoogleFonts.outfit(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: accent, letterSpacing: 1.5)),
          ])
        : Text('CONNECT', style: GoogleFonts.outfit(
            fontSize: 14, fontWeight: FontWeight.w900,
            color: V.d0, letterSpacing: 2.5)))));
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override Widget build(BuildContext context) => Row(children: [
    Text(text, style: GoogleFonts.outfit(
      fontSize: 9, fontWeight: FontWeight.w800, color: V.lo, letterSpacing: 2.0)),
    const SizedBox(width: 10),
    Expanded(child: Container(height: 1, color: V.wire)),
  ]);
}

class _FeaturePill extends StatelessWidget {
  final String text; final Color accent;
  const _FeaturePill(this.text, {required this.accent});
  @override Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: accent.withOpacity(0.06),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: accent.withOpacity(0.18))),
    child: Text(text, style: GoogleFonts.dmMono(fontSize: 10, color: V.mid)));
}

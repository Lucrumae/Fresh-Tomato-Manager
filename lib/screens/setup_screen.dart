import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    with SingleTickerProviderStateMixin {

  final _host = TextEditingController(text: '192.168.1.1');
  final _user = TextEditingController(text: 'root');
  final _pass = TextEditingController();
  final _port = TextEditingController(text: '22');

  bool _obs = true, _connecting = false, _remember = false;
  String? _error;

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;

  static const _kRemember = 'remember_me';
  static const _kHost = 'saved_host'; static const _kUser = 'saved_user';
  static const _kPass = 'saved_pass'; static const _kPort = 'saved_port';

  @override void initState() {
    super.initState();
    _loadSaved();

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _fade  = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.025), end: Offset.zero)
      .animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic));
    _fadeCtrl.forward();

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
    _fadeCtrl.dispose();
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
      setState(() => _error = 'Host and username are required');
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
    // Connect monitor session (bandwidth/CPU/logs/terminal) — non-blocking, best effort
    ref.read(monitorSshServiceProvider).connectIfNeeded(config).catchError((_) {});
    await ref.read(configProvider.notifier).save(config);
    final p = await SharedPreferences.getInstance();
    if (_remember) {
      await p.setBool(_kRemember, true);
      await p.setString(_kHost, host); await p.setString(_kUser, user);
      await p.setString(_kPass, pass); await p.setString(_kPort, '$port');
    } else {
      await p.setBool(_kRemember, false);
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()));
  }


  @override Widget build(BuildContext context) {
    final v     = Theme.of(context).extension<VC>()!;
    final isDark = v.dark;

    // Adaptive colors
    final bg      = isDark ? V.d0   : const Color(0xFFF5F5F5);
    final surface = isDark ? const Color(0xFF111111) : Colors.white;
    final border  = isDark ? V.wire : const Color(0xFFE8E8E8);
    final hiColor  = isDark ? V.hi   : const Color(0xFF111111);
    final midColor = isDark ? V.mid  : const Color(0xFF888888);
    final loColor  = isDark ? V.lo   : const Color(0xFFCCCCCC);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
        ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
        : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

                const SizedBox(height: 52),

                // ── Logo row ─────────────────────────────────────────────
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: v.accent,
                      borderRadius: BorderRadius.circular(11)),
                    child: Icon(Icons.router_rounded,
                      color: isDark ? V.d0 : Colors.white, size: 20)),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Tomato Manager',
                      style: GoogleFonts.outfit(
                        fontSize: 16, fontWeight: FontWeight.w800,
                        color: hiColor, letterSpacing: -0.2)),
                    Text('FreshTomato SSH Controller',
                      style: GoogleFonts.dmMono(fontSize: 10, color: midColor)),
                  ]),
                ]),

                const SizedBox(height: 44),

                // ── Headline ─────────────────────────────────────────────
                Text('Connect to\nyour router',
                  style: GoogleFonts.outfit(
                    fontSize: 34, fontWeight: FontWeight.w900,
                    color: hiColor, letterSpacing: -1.2, height: 1.08)),
                const SizedBox(height: 10),
                Text('Enter your SSH credentials below.',
                  style: GoogleFonts.outfit(fontSize: 14, color: midColor, height: 1.4)),

                const SizedBox(height: 32),

                // ── Form card ────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                    boxShadow: isDark ? null : [
                      BoxShadow(color: Colors.black.withOpacity(0.04),
                        blurRadius: 16, offset: const Offset(0, 4))]),
                  child: Column(children: [
                    _FormRow(label: 'IP Address', child: TextField(
                      controller: _host,
                      keyboardType: TextInputType.url,
                      style: GoogleFonts.dmMono(fontSize: 14, color: hiColor),
                      decoration: _fieldDeco(hint: '192.168.1.1', isDark: isDark))),
                    _Divider(color: border),
                    _FormRow(label: 'Username', child: TextField(
                      controller: _user,
                      style: GoogleFonts.dmMono(fontSize: 14, color: hiColor),
                      decoration: _fieldDeco(hint: 'root', isDark: isDark))),
                    _Divider(color: border),
                    _FormRow(label: 'Password', child: TextField(
                      controller: _pass,
                      obscureText: _obs,
                      style: GoogleFonts.dmMono(fontSize: 14, color: hiColor),
                      decoration: _fieldDeco(
                        hint: '••••••••',
                        isDark: isDark,
                        suffix: GestureDetector(
                          onTap: () => setState(() => _obs = !_obs),
                          child: Icon(
                            _obs ? Icons.visibility_outlined
                                 : Icons.visibility_off_outlined,
                            size: 16, color: midColor))))),
                    _Divider(color: border),
                    _FormRow(label: 'SSH Port', child: TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.dmMono(fontSize: 14, color: hiColor),
                      decoration: _fieldDeco(hint: '22', isDark: isDark))),
                  ]),
                ),

                const SizedBox(height: 16),

                // ── Remember me ───────────────────────────────────────────
                GestureDetector(
                  onTap: () => setState(() => _remember = !_remember),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: _remember ? v.accent : Colors.transparent,
                          border: Border.all(
                            color: _remember ? v.accent : loColor, width: 1.5)),
                        child: _remember
                          ? Icon(Icons.check_rounded, size: 13,
                              color: isDark ? V.d0 : Colors.white)
                          : null),
                      const SizedBox(width: 10),
                      Text('Remember me',
                        style: GoogleFonts.outfit(fontSize: 13, color: midColor)),
                    ]),
                  ),
                ),

                // ── Error ─────────────────────────────────────────────────
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: V.err.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: V.err.withOpacity(0.3))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.error_outline_rounded, size: 15, color: V.err),
                      const SizedBox(width: 9),
                      Expanded(child: Text(_error!,
                        style: GoogleFonts.dmMono(fontSize: 11, color: V.err, height: 1.5))),
                    ])),
                ],

                const SizedBox(height: 28),

                // ── Connect button ────────────────────────────────────────
                _ConnectButton(
                  connecting: _connecting,
                  accent: v.accent,
                  isDark: isDark,
                  onTap: _connecting ? null : _connect),

                const SizedBox(height: 44),

                // ── Status strip — shows what we connect to ───────────────
                _StatusStrip(isDark: isDark, midColor: midColor, loColor: loColor,
                  accent: v.accent, border: border, surface: surface),

                const SizedBox(height: 40),
              ]),
            ),
          ),
        )),
      ),
    );
  }

  InputDecoration _fieldDeco({
    required String hint, required bool isDark, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.dmMono(fontSize: 13,
        color: isDark ? V.lo : const Color(0xFFBBBBBB)),
      suffixIcon: suffix != null
        ? Padding(padding: const EdgeInsets.only(right: 4), child: suffix)
        : null,
      filled: true,
      fillColor: Colors.transparent,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    );
  }
}

// ── Form row ──────────────────────────────────────────────────────────────────
class _FormRow extends StatelessWidget {
  final String label; final Widget child;
  const _FormRow({required this.label, required this.child});
  @override Widget build(BuildContext context) {
    final v   = Theme.of(context).extension<VC>()!;
    final mid = v.dark ? V.mid : const Color(0xFF888888);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(children: [
        SizedBox(width: 88, child: Text(label,
          style: GoogleFonts.outfit(
            fontSize: 13, fontWeight: FontWeight.w600, color: mid))),
        Expanded(child: child),
      ]),
    );
  }
}

class _Divider extends StatelessWidget {
  final Color color;
  const _Divider({required this.color});
  @override Widget build(BuildContext context) =>
    Container(height: 1, color: color,
      margin: const EdgeInsets.symmetric(horizontal: 16));
}

// ── Connect button ─────────────────────────────────────────────────────────
class _ConnectButton extends StatelessWidget {
  final bool connecting;
  final Color accent;
  final bool isDark;
  final VoidCallback? onTap;
  const _ConnectButton({required this.connecting, required this.accent,
    required this.isDark, required this.onTap});

  @override Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: connecting ? accent.withOpacity(0.12) : accent,
          border: connecting ? Border.all(color: accent.withOpacity(0.35)) : null,
          boxShadow: connecting ? null : [
            BoxShadow(color: accent.withOpacity(0.28), blurRadius: 20,
              offset: const Offset(0, 6))]),
        child: Center(child: connecting
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
              const SizedBox(width: 12),
              Text('Connecting…', style: GoogleFonts.outfit(
                fontSize: 14, fontWeight: FontWeight.w600, color: accent)),
            ])
          : Text('Connect', style: GoogleFonts.outfit(
              fontSize: 15, fontWeight: FontWeight.w800,
              color: isDark ? V.d0 : Colors.white, letterSpacing: 0.2))),
      ),
    );
  }
}

// ── Status strip — feature capsules & SSH info ────────────────────────────────
class _StatusStrip extends StatelessWidget {
  final bool isDark;
  final Color midColor, loColor, accent, border, surface;
  const _StatusStrip({required this.isDark, required this.midColor,
    required this.loColor, required this.accent, required this.border,
    required this.surface});

  @override Widget build(BuildContext context) {
    final items = [
      (Icons.speed_rounded,         'Real-time stats'),
      (Icons.devices_rounded,       'Device manager'),
      (Icons.wifi_rounded,          'WiFi config'),
      (Icons.bar_chart_rounded,     'Bandwidth'),
      (Icons.article_outlined,      'System logs'),
      (Icons.shield_outlined,       'QoS & firewall'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Section divider
      Row(children: [
        Container(height: 1, width: 24, color: loColor),
        const SizedBox(width: 10),
        Text('WHAT YOU GET', style: GoogleFonts.outfit(
          fontSize: 9, fontWeight: FontWeight.w800,
          color: loColor, letterSpacing: 2.0)),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: loColor)),
      ]),
      const SizedBox(height: 16),

      // 2-column grid of features
      ...List.generate((items.length / 2).ceil(), (row) {
        final a = items[row * 2];
        final bIdx = row * 2 + 1;
        final b = bIdx < items.length ? items[bIdx] : null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(child: _FeatureItem(icon: a.$1, label: a.$2,
              accent: accent, surface: surface, border: border, midColor: midColor)),
            const SizedBox(width: 10),
            Expanded(child: b != null
              ? _FeatureItem(icon: b.$1, label: b.$2,
                  accent: accent, surface: surface, border: border, midColor: midColor)
              : const SizedBox()),
          ]),
        );
      }),

      const SizedBox(height: 16),

      // SSH badge
      Center(child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withOpacity(0.2))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline_rounded, size: 12, color: accent),
          const SizedBox(width: 7),
          Text('Encrypted SSH connection — no cloud, no tracking',
            style: GoogleFonts.dmMono(fontSize: 10, color: midColor)),
        ]),
      )),
    ]);
  }
}


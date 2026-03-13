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
  final _formKey = GlobalKey<FormState>();

  bool _obs = true, _connecting = false, _remember = false;
  String? _error;

  late final AnimationController _entryCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  static const _kRemember = 'remember_me';
  static const _kHost = 'saved_host'; static const _kUser = 'saved_user';
  static const _kPass = 'saved_pass'; static const _kPort = 'saved_port';

  @override void initState() {
    super.initState();
    _loadSaved();

    _entryCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fade  = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(
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
    await ref.read(configProvider.notifier).save(config);
    final p = await SharedPreferences.getInstance();
    if (_remember) {
      await p.setBool(_kRemember, true);
      await p.setString(_kHost, host); await p.setString(_kUser, user);
      await p.setString(_kPass, pass); await p.setString(_kPort, '$port');
    } else {
      await p.setBool(_kRemember, false);
    }
    if (mounted) Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()));
  }

  @override Widget build(BuildContext context) {
    final v     = Theme.of(context).extension<VC>()!;
    final isDark = v.dark;

    // Colors adapt to theme
    final bg      = isDark ? V.d0   : const Color(0xFFF7F7F7);
    final surface = isDark ? V.d1   : Colors.white;
    final border  = isDark ? V.wire : const Color(0xFFE5E5E5);
    final hi      = isDark ? V.hi   : const Color(0xFF111111);
    final mid     = isDark ? V.mid  : const Color(0xFF888888);
    final lo      = isDark ? V.lo   : const Color(0xFFCCCCCC);
    final inputBg = isDark ? V.d2   : Colors.white;

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
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 64),

                // ── Brand ────────────────────────────────────────────────
                Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: v.accent,
                      borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.router_rounded,
                      color: isDark ? V.d0 : Colors.white, size: 22)),
                  const SizedBox(width: 14),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Tomato Manager',
                      style: GoogleFonts.outfit(
                        fontSize: 18, fontWeight: FontWeight.w800,
                        color: hi, letterSpacing: -0.3)),
                    Text('FreshTomato SSH',
                      style: GoogleFonts.dmMono(fontSize: 11, color: mid)),
                  ]),
                ]),

                const SizedBox(height: 48),

                // ── Headline ─────────────────────────────────────────────
                Text('Sign in',
                  style: GoogleFonts.outfit(
                    fontSize: 32, fontWeight: FontWeight.w800,
                    color: hi, letterSpacing: -0.8, height: 1.1)),
                const SizedBox(height: 6),
                Text('Enter your router credentials to connect.',
                  style: GoogleFonts.outfit(fontSize: 14, color: mid, height: 1.4)),

                const SizedBox(height: 36),

                // ── Form card ────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border),
                    boxShadow: isDark ? null : [
                      BoxShadow(color: Colors.black.withOpacity(0.05),
                        blurRadius: 16, offset: const Offset(0, 4))]),
                  child: Column(children: [
                    _FormRow(
                      label: 'Router IP',
                      child: TextField(
                        controller: _host,
                        keyboardType: TextInputType.url,
                        style: GoogleFonts.dmMono(fontSize: 14, color: hi),
                        decoration: _inlineDeco('192.168.1.1', inputBg, hi)),
                    ),
                    _Divider(color: border),
                    _FormRow(
                      label: 'Username',
                      child: TextField(
                        controller: _user,
                        style: GoogleFonts.dmMono(fontSize: 14, color: hi),
                        decoration: _inlineDeco('root', inputBg, hi)),
                    ),
                    _Divider(color: border),
                    _FormRow(
                      label: 'Password',
                      child: TextField(
                        controller: _pass,
                        obscureText: _obs,
                        style: GoogleFonts.dmMono(fontSize: 14, color: hi),
                        decoration: _inlineDeco('••••••••', inputBg, hi,
                          suffix: GestureDetector(
                            onTap: () => setState(() => _obs = !_obs),
                            child: Icon(
                              _obs ? Icons.visibility_outlined
                                   : Icons.visibility_off_outlined,
                              size: 17, color: mid)))),
                    ),
                    _Divider(color: border),
                    _FormRow(
                      label: 'Port',
                      child: TextField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.dmMono(fontSize: 14, color: hi),
                        decoration: _inlineDeco('22', inputBg, hi)),
                    ),
                  ]),
                ),

                const SizedBox(height: 16),

                // ── Remember me ───────────────────────────────────────────
                GestureDetector(
                  onTap: () => setState(() => _remember = !_remember),
                  behavior: HitTestBehavior.opaque,
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: _remember ? v.accent : Colors.transparent,
                        border: Border.all(
                          color: _remember ? v.accent : lo, width: 1.5)),
                      child: _remember
                        ? Icon(Icons.check_rounded, size: 13,
                            color: isDark ? V.d0 : Colors.white)
                        : null),
                    const SizedBox(width: 10),
                    Text('Remember me',
                      style: GoogleFonts.outfit(fontSize: 13, color: mid)),
                  ]),
                ),

                // ── Error ─────────────────────────────────────────────────
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: V.err.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: V.err.withOpacity(0.25))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: const EdgeInsets.only(top: 1),
                        child: Icon(Icons.error_outline_rounded, size: 14, color: V.err)),
                      const SizedBox(width: 9),
                      Expanded(child: Text(_error!,
                        style: GoogleFonts.dmMono(fontSize: 11, color: V.err, height: 1.5))),
                    ])),
                ],

                const SizedBox(height: 28),

                // ── Connect button ────────────────────────────────────────
                SizedBox(width: double.infinity,
                  child: _connecting
                    // Loading state
                    ? Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: v.accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: v.accent.withOpacity(0.3))),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: v.accent)),
                          const SizedBox(width: 12),
                          Text('Connecting…',
                            style: GoogleFonts.outfit(
                              fontSize: 14, fontWeight: FontWeight.w600,
                              color: v.accent)),
                        ]))
                    // Normal state
                    : GestureDetector(
                        onTap: _connect,
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: v.accent,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(
                              color: v.accent.withOpacity(isDark ? 0.35 : 0.25),
                              blurRadius: 18, offset: const Offset(0, 6))]),
                          child: Center(child: Text('Connect',
                            style: GoogleFonts.outfit(
                              fontSize: 15, fontWeight: FontWeight.w700,
                              color: isDark ? V.d0 : Colors.white,
                              letterSpacing: 0.3)))))),

                const SizedBox(height: 48),

                // ── Footer ────────────────────────────────────────────────
                Center(child: Text('SSH · FreshTomato · Tomato by Shibby',
                  style: GoogleFonts.dmMono(fontSize: 10, color: lo))),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        )),
      ),
    );
  }

  InputDecoration _inlineDeco(String hint, Color bg, Color hi, {Widget? suffix}) =>
    InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.dmMono(fontSize: 13, color: const Color(0xFFBBBBBB)),
      suffixIcon: suffix != null ? Padding(
        padding: const EdgeInsets.only(right: 4), child: suffix) : null,
      filled: true,
      fillColor: bg,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
    );
}

// ── Form row (label left, input right) ───────────────────────────────────────
class _FormRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _FormRow({required this.label, required this.child});

  @override Widget build(BuildContext context) {
    final v    = Theme.of(context).extension<VC>()!;
    final mid  = v.dark ? V.mid : const Color(0xFF888888);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        SizedBox(width: 82,
          child: Text(label, style: GoogleFonts.outfit(
            fontSize: 13, fontWeight: FontWeight.w600, color: mid))),
        Expanded(child: child),
      ]),
    );
  }
}

// ── Thin divider ─────────────────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  final Color color;
  const _Divider({required this.color});
  @override Widget build(BuildContext context) =>
    Container(height: 1, color: color, margin: const EdgeInsets.symmetric(horizontal: 16));
}

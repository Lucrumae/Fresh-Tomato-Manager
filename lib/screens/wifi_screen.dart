import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

// ── Security helpers ──────────────────────────────────────────────────────────

String _parseSecurity(String akm, String authMode, String secMode) {
  final a = akm.trim().toLowerCase();
  final m = secMode.trim().toLowerCase();
  if (a == 'psk2')                      return 'wpa2-personal';
  if (a == 'psk')                       return 'wpa-personal';
  if (a == 'psk psk2' || a == 'psk2 psk') return 'wpa-wpa2';
  if (a == 'wpa2')                      return 'wpa2-enterprise';
  if (a == 'wpa')                       return 'wpa-enterprise';
  if (authMode.trim() == 'radius')      return 'radius';
  if (m.contains('wpa2_personal'))      return 'wpa2-personal';
  if (m.contains('wpa_personal'))       return 'wpa-personal';
  if (m.contains('wpa2'))               return 'wpa2-enterprise';
  if (m.contains('wpa'))                return 'wpa-enterprise';
  if (m.contains('wep'))                return 'wep';
  return 'disabled';
}

String _normCrypto(String raw) {
  final r = raw.toLowerCase().trim();
  if (r.contains('tkip') && r.contains('aes')) return 'tkip+aes';
  if (r == 'tkip') return 'tkip';
  return 'aes';
}

String _normNetMode(String raw) {
  final r = raw.trim().toLowerCase();
  // Tomato stores 'mixed' for what the UI calls 'Auto'
  if (r == 'mixed') return 'auto';
  const valid = ['auto','disabled','b-only','g-only','bg-mixed','n-only',
                 'a-only','ac-only','n/ac-mixed'];
  if (valid.contains(r)) return r;
  return 'auto';
}

String _normChanWidth24(String chanspec) {
  if (chanspec.endsWith('u') || chanspec.endsWith('l')) return '40';
  if (chanspec.contains('/80')) return '80';
  return '20';
}

String _normChanWidth5(String chanspec) {
  if (chanspec.contains('/80')) return '80';
  if (chanspec.contains('/40')) return '40';
  return '80';
}

// ── Local form state ──────────────────────────────────────────────────────────

class _BandForm {
  // Controllers
  final ssidCtrl = TextEditingController();
  final pwdCtrl  = TextEditingController();
  final pwrCtrl  = TextEditingController();

  // Dropdown/toggle state
  bool   enabled   = true;
  bool   broadcast = true;
  String wlMode    = 'ap';
  String netMode   = 'auto';
  String ch        = '0';
  String width     = '40';
  String sb        = 'upper';
  String sec       = 'wpa2-personal';
  String crypto    = 'aes';

  // UI state
  bool showPwd = false;
  bool saving  = false;

  void dispose() {
    ssidCtrl.dispose();
    pwdCtrl.dispose();
    pwrCtrl.dispose();
  }

  // Populate from RouterStatus
  void loadFrom24(RouterStatus s) {
    ssidCtrl.text = s.wifiSsid;
    pwdCtrl.text  = s.wifiPassword24;
    pwrCtrl.text  = s.wifiTxpower24.replaceAll(RegExp(r'[^0-9]'), '');
    enabled       = s.wifi24enabled;
    broadcast     = s.wifiBroadcast24 != '0';
    wlMode        = s.wifiMode24.isEmpty    ? 'ap'    : s.wifiMode24;
    netMode       = _normNetMode(s.wifiNetMode24);
    ch            = s.wifiChannel24.isEmpty ? '0'     : s.wifiChannel24;
    sec           = _parseSecurity(s.wifiAkm24, s.wifiAuthMode24, s.wifiSecurity24);
    crypto        = _normCrypto(s.wifiCrypto24);
    width         = _normChanWidth24(s.wifiChanspec24);
    sb            = s.wifiNctrlsb24.isEmpty ? 'upper' : s.wifiNctrlsb24;
  }

  void loadFrom5(RouterStatus s) {
    ssidCtrl.text = s.wifiSsid5;
    pwdCtrl.text  = s.wifiPassword5;
    pwrCtrl.text  = s.wifiTxpower5.replaceAll(RegExp(r'[^0-9]'), '');
    enabled       = s.wifi5enabled;
    broadcast     = s.wifiBroadcast5 != '0';
    wlMode        = s.wifiMode5.isEmpty    ? 'ap'    : s.wifiMode5;
    netMode       = _normNetMode(s.wifiNetMode5);
    ch            = s.wifiChannel5.isEmpty ? '36'    : s.wifiChannel5;
    sec           = _parseSecurity(s.wifiAkm5, s.wifiAuthMode5, s.wifiSecurity5);
    crypto        = _normCrypto(s.wifiCrypto5);
    width         = _normChanWidth5(s.wifiChanspec5);
    sb            = s.wifiNctrlsb5.isEmpty ? 'lower' : s.wifiNctrlsb5;
  }
}

// ── Main Screen ───────────────────────────────────────────────────────────────

class WifiScreen extends ConsumerStatefulWidget {
  const WifiScreen({super.key});
  @override ConsumerState<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends ConsumerState<WifiScreen> {
  final _b24 = _BandForm();
  final _b5  = _BandForm();

  bool _loaded   = false;   // has initial load happened?
  bool _loading  = false;   // currently fetching from router?
  bool _has5     = false;

  @override
  void initState() {
    super.initState();
    // Load once after first frame — stops polling while user edits
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialLoad());
  }

  @override
  void dispose() {
    _b24.dispose();
    _b5.dispose();
    super.dispose();
  }

  // ── Load / Refresh ──────────────────────────────────────────────────────────

  Future<void> _initialLoad() async {
    if (!mounted) return;
    setState(() { _loading = true; });

    // Stop periodic polling so it doesn't interfere with user edits
    ref.read(routerStatusProvider.notifier).stopPolling();

    // Do a single fresh fetch
    await ref.read(routerStatusProvider.notifier).fetch();

    if (mounted) {
      final s = ref.read(routerStatusProvider);
      _applyStatus(s);
      setState(() { _loading = false; _loaded = true; });
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() { _loading = true; });
    await ref.read(routerStatusProvider.notifier).fetch();
    if (mounted) {
      final s = ref.read(routerStatusProvider);
      _applyStatus(s);
      setState(() { _loading = false; });
    }
  }

  void _applyStatus(RouterStatus s) {
    _b24.loadFrom24(s);
    if (s.wifi5present) {
      _b5.loadFrom5(s);
      _has5 = true;
    }
  }

  // Re-start polling when leaving the screen
  @override
  void deactivate() {
    ref.read(routerStatusProvider.notifier).startPolling();
    super.deactivate();
  }

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> _save(bool is5) async {
    final ssh = ref.read(sshServiceProvider);
    final b   = is5 ? _b5 : _b24;
    setState(() { b.saving = true; });
    try {
      final ok = await ssh.saveWifiSettings(
        band:      is5 ? '5' : '2.4',
        ssid:      b.ssidCtrl.text.trim(),
        channel:   b.ch,
        security:  b.sec,
        crypto:    b.crypto,
        password:  b.pwdCtrl.text,
        txpower:   b.pwrCtrl.text.trim(),
        netMode:   b.netMode,
        wlMode:    b.wlMode,
        broadcast: b.broadcast ? '1' : '0',
        chanWidth: b.width,
        sideband:  b.sb,
      );
      if (ok) {
        // Single refresh after apply — don't re-enable continuous polling yet
        await _refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              '${is5 ? "5" : "2.4"} GHz applied — clients reconnecting…',
              style: GoogleFonts.dmMono(fontSize: 12)),
            backgroundColor: V.ok));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to save',
              style: GoogleFonts.dmMono(fontSize: 12)),
            backgroundColor: V.err));
        }
      }
    } finally {
      if (mounted) setState(() { b.saving = false; });
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;

    if (_loading && !_loaded) {
      return Scaffold(
        backgroundColor: v.bg,
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Loading WiFi settings…',
            style: GoogleFonts.dmMono(fontSize: 12, color: v.mid)),
        ])),
      );
    }

    return Scaffold(
      backgroundColor: v.bg,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            _BandCard(
              band: '2.4 GHz', is5: false, v: v, b: _b24,
              onChanged: () => setState(() {}),
              onSave: () => _save(false),
            ),
            const SizedBox(height: 16),
            if (_has5)
              _BandCard(
                band: '5 GHz', is5: true, v: v, b: _b5,
                onChanged: () => setState(() {}),
                onSave: () => _save(true),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Per-band card ─────────────────────────────────────────────────────────────

class _BandCard extends StatelessWidget {
  final String band;
  final bool is5;
  final VC v;
  final _BandForm b;
  final VoidCallback onChanged, onSave;

  const _BandCard({
    required this.band, required this.is5, required this.v, required this.b,
    required this.onChanged, required this.onSave,
  });

  // ── Option lists ─────────────────────────────────────────────────────────

  static const _wlModes = ['ap','apwds','sta','wet','wds','infra'];
  static const _wlLabels = {
    'ap':    'Access Point',
    'apwds': 'Access Point + WDS',
    'sta':   'Wireless Client',
    'wet':   'Wireless Ethernet Bridge',
    'wds':   'WDS',
    'infra': 'Media Bridge',
  };

  List<String> get _netModes => is5
    ? ['auto','disabled','a-only','n-only','n/ac-mixed','ac-only']
    : ['auto','disabled','b-only','g-only','bg-mixed','n-only'];

  static const _netLabels = {
    'auto':       'Auto',
    'disabled':   'Disabled',
    'b-only':     'B Only',
    'g-only':     'G Only',
    'bg-mixed':   'B/G Mixed',
    'n-only':     'N Only',
    'a-only':     'A Only',
    'n/ac-mixed': 'N/AC Mixed',
    'ac-only':    'AC Only',
  };

  static const _secModes = [
    'disabled',
    'wep',
    'wpa-personal',
    'wpa-enterprise',
    'wpa2-personal',
    'wpa2-enterprise',
    'wpa-wpa2',
    'wpa-wpa2-enterprise',
    'radius',
  ];

  static const _secLabels = {
    'disabled':           'Disabled',
    'wep':                'WEP (legacy)',
    'wpa-personal':       'WPA Personal (deprecated)',
    'wpa-enterprise':     'WPA Enterprise (deprecated)',
    'wpa2-personal':      'WPA2 Personal',
    'wpa2-enterprise':    'WPA2 Enterprise',
    'wpa-wpa2':           'WPA / WPA2 Personal (deprecated)',
    'wpa-wpa2-enterprise':'WPA / WPA2 Enterprise (deprecated)',
    'radius':             'Radius',
  };

  static const _cryptos   = ['aes', 'tkip', 'tkip+aes'];
  static const _cryptoLbl = {
    'aes':      'AES',
    'tkip':     'TKIP',
    'tkip+aes': 'TKIP / AES',
  };

  // 5GHz channels match Tomato web UI exactly
  List<String> get _channels => is5
    ? ['0','36','44','52','60','100','108','116','124','132','140',
       '149','157']
    : ['0','1','2','3','4','5','6','7','8','9','10','11','12','13'];

  List<String> get _widths => is5 ? ['20','40','80'] : ['20','40'];

  bool get _hasCrypto   => !['disabled','wep','radius'].contains(b.sec);
  bool get _hasPassword => !['disabled','radius'].contains(b.sec);
  bool get _showSideband => !is5 && b.width == '40';

  String _safe(String val, List<String> list) =>
    list.contains(val) ? val : list.first;

  // ── Build helpers ─────────────────────────────────────────────────────────

  Widget _label(String text, VC v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: GoogleFonts.outfit(
      fontSize: 9, fontWeight: FontWeight.w800,
      color: v.mid, letterSpacing: 1.5)),
  );

  Widget _dd(BuildContext ctx, String val, List<String> items,
      ValueChanged<String?> cb, {Map<String,String>? lbl, String sfx = ''}) {
    final vc = Theme.of(ctx).extension<VC>()!;
    return DropdownButtonFormField<String>(
      value: _safe(val, items),
      isExpanded: true,
      decoration: const InputDecoration(isDense: true),
      style: GoogleFonts.dmMono(fontSize: 12, color: vc.hi),
      items: items.map((i) => DropdownMenuItem(
        value: i,
        child: Text(lbl?[i] ?? '$i$sfx'),
      )).toList(),
      onChanged: b.enabled ? cb : null,
    );
  }

  @override
  Widget build(BuildContext ctx) {
    return VCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ─────────────────────────────────────────────────────────
        Row(children: [
          Dot(color: b.enabled ? V.ok : v.lo, size: 7, glow: b.enabled),
          const SizedBox(width: 10),
          Text(band, style: GoogleFonts.outfit(
            fontSize: 15, fontWeight: FontWeight.w800, color: v.hi)),
          const Spacer(),
          Switch(
            value: b.enabled,
            onChanged: (x) { b.enabled = x; onChanged(); },
          ),
        ]),
        Divider(color: v.wire, height: 20),

        // ── Wireless Mode ─────────────────────────────────────────────────
        _label('WIRELESS MODE', v),
        _dd(ctx, b.wlMode, _wlModes,
          (x) { b.wlMode = x!; onChanged(); }, lbl: _wlLabels),
        const SizedBox(height: 14),

        // ── Wireless Network Mode ─────────────────────────────────────────
        _label('WIRELESS NETWORK MODE', v),
        _dd(ctx, b.netMode, _netModes,
          (x) { b.netMode = x!; onChanged(); }, lbl: _netLabels),
        const SizedBox(height: 14),

        // ── SSID + Broadcast ──────────────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('SSID', v),
              TextField(
                controller: b.ssidCtrl,
                enabled: b.enabled,
                style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
                decoration: const InputDecoration(
                  isDense: true, hintText: 'Network name'),
              ),
            ]),
          ),
          const SizedBox(width: 16),
          Column(children: [
            _label('BROADCAST', v),
            Switch(
              value: b.broadcast,
              onChanged: b.enabled
                ? (x) { b.broadcast = x; onChanged(); }
                : null,
            ),
          ]),
        ]),
        const SizedBox(height: 14),

        // ── Channel + Channel Width ───────────────────────────────────────
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('CHANNEL', v),
              DropdownButtonFormField<String>(
                value: _safe(b.ch, _channels),
                isExpanded: true,
                decoration: const InputDecoration(isDense: true),
                style: GoogleFonts.dmMono(fontSize: 12,
                  color: Theme.of(ctx).extension<VC>()!.hi),
                items: _channels.map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c == '0' ? '0 (Auto)' : c),
                )).toList(),
                onChanged: b.enabled
                  ? (x) { b.ch = x!; onChanged(); }
                  : null,
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('CHANNEL WIDTH', v),
              _dd(ctx, b.width, _widths,
                (x) { b.width = x!; onChanged(); }, sfx: ' MHz'),
            ]),
          ),
        ]),
        const SizedBox(height: 14),

        // ── Control Sideband (2.4GHz + 40MHz only) ────────────────────────
        if (_showSideband) ...[
          _label('CONTROL SIDEBAND', v),
          _dd(ctx, b.sb, ['upper','lower'],
            (x) { b.sb = x!; onChanged(); },
            lbl: const {'upper': 'Upper', 'lower': 'Lower'}),
          const SizedBox(height: 14),
        ],

        // ── TX Power ──────────────────────────────────────────────────────
        _label('TX POWER (0 = Auto)', v),
        TextField(
          controller: b.pwrCtrl,
          enabled: b.enabled,
          style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            isDense: true, hintText: '0', suffixText: 'mW'),
        ),
        const SizedBox(height: 14),

        // ── Security ──────────────────────────────────────────────────────
        _label('SECURITY', v),
        _dd(ctx, b.sec, _secModes,
          (x) { b.sec = x!; onChanged(); }, lbl: _secLabels),
        const SizedBox(height: 14),

        // ── Encryption ────────────────────────────────────────────────────
        if (_hasCrypto) ...[
          _label('ENCRYPTION', v),
          _dd(ctx, b.crypto, _cryptos,
            (x) { b.crypto = x!; onChanged(); }, lbl: _cryptoLbl),
          const SizedBox(height: 14),
        ],

        // ── Shared Key ────────────────────────────────────────────────────
        if (_hasPassword) ...[
          _label('SHARED KEY', v),
          TextField(
            controller: b.pwdCtrl,
            enabled: b.enabled,
            obscureText: !b.showPwd,
            style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
            decoration: InputDecoration(
              isDense: true,
              hintText: '••••••••',
              suffixIcon: IconButton(
                icon: Icon(
                  b.showPwd
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                  size: 18, color: v.mid),
                onPressed: () {
                  b.showPwd = !b.showPwd;
                  onChanged();
                },
              ),
            ),
          ),
          const SizedBox(height: 18),
        ] else
          const SizedBox(height: 4),

        // ── Save button ───────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: b.enabled && !b.saving ? onSave : null,
            child: b.saving
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black))
              : Text('APPLY ${band.toUpperCase()}',
                  style: GoogleFonts.outfit(
                    fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '⚠  Changing SSID/channel will briefly disconnect all clients',
          style: GoogleFonts.dmMono(fontSize: 9, color: v.lo)),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

String _parseSecurity(String akm, String authMode, String secMode) {
  final a = akm.trim();
  final m = secMode.trim();
  // Check akm first — most reliable
  if (a == 'psk2')              return 'wpa2-personal';
  if (a == 'psk')               return 'wpa-personal';
  if (a == 'psk psk2' || a == 'psk2 psk') return 'wpa-wpa2';
  if (a == 'wpa2')              return 'wpa2-enterprise';
  if (a == 'wpa')               return 'wpa-enterprise';
  if (authMode == 'radius')     return 'radius';
  // Fallback to security_mode string
  if (m.contains('wpa2_personal'))  return 'wpa2-personal';
  if (m.contains('wpa_personal'))   return 'wpa-personal';
  if (m.contains('wpa2'))           return 'wpa2-enterprise';
  if (m.contains('wpa'))            return 'wpa-enterprise';
  if (m.contains('wep'))            return 'wep';
  return 'disabled';
}

String _normCrypto(String raw) {
  final r = raw.toLowerCase().trim();
  if (r.contains('tkip') && r.contains('aes')) return 'tkip+aes';
  if (r == 'tkip') return 'tkip';
  return 'aes';
}

// Convert wl0_net_mode → dropdown value
// Router stores: mixed/b-only/g-only/bg-mixed/n-only/disabled/a-only/ac-only
String _normNetMode(String raw) {
  final r = raw.trim().toLowerCase();
  const valid = ['auto','disabled','b-only','g-only','bg-mixed','n-only','a-only','n-only-5','ac-only','mixed'];
  if (valid.contains(r)) return r;
  if (r == 'mixed' || r == 'auto') return 'auto';
  return 'auto';
}

// ── State container passed down so StatefulWidget can hold it ─────────────────
class _WifiBandState {
  String ssid, ch, width, sb, sec, crypto, netMode, wlMode, txpwr, pwd;
  bool enabled, broadcast;
  _WifiBandState({
    this.ssid = '', this.ch = '0', this.width = '40', this.sb = 'upper',
    this.sec = 'wpa2-personal', this.crypto = 'aes', this.netMode = 'auto',
    this.wlMode = 'ap', this.txpwr = '', this.pwd = '',
    this.enabled = true, this.broadcast = true,
  });
}

// ── Main Screen ───────────────────────────────────────────────────────────────
class WifiScreen extends ConsumerStatefulWidget {
  const WifiScreen({super.key});
  @override ConsumerState<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends ConsumerState<WifiScreen> {
  // Controllers live here so they survive rebuilds
  final _ssid24c = TextEditingController();
  final _pwd24c  = TextEditingController();
  final _pwr24c  = TextEditingController();
  final _ssid5c  = TextEditingController();
  final _pwd5c   = TextEditingController();
  final _pwr5c   = TextEditingController();

  final _b24 = _WifiBandState();
  final _b5  = _WifiBandState(ch: '36', width: '80');

  bool _saving24 = false, _saving5 = false;
  bool _showPwd24 = false, _showPwd5 = false;

  // Track which RouterStatus we last synced from (by ssid as fingerprint)
  String _lastSynced24 = '', _lastSynced5 = '';

  @override void dispose() {
    _ssid24c.dispose(); _pwd24c.dispose(); _pwr24c.dispose();
    _ssid5c.dispose();  _pwd5c.dispose();  _pwr5c.dispose();
    super.dispose();
  }

  // Sync local state from RouterStatus — only when data actually changes
  void _sync(RouterStatus s) {
    // 2.4 GHz — sync when ssid OR password changes (means fresh data from router)
    final fp24 = '${s.wifiSsid}|${s.wifiAkm24}|${s.wifiChannel24}';
    if (fp24.isNotEmpty && fp24 != '||' && fp24 != _lastSynced24) {
      _lastSynced24 = fp24;
      _ssid24c.text = s.wifiSsid;
      _pwd24c.text  = s.wifiPassword24;
      _pwr24c.text  = s.wifiTxpower24.replaceAll(RegExp(r'[^0-9]'), '');
      _b24.enabled   = s.wifi24enabled;
      _b24.broadcast = s.wifiBroadcast24 != '0';
      _b24.ch        = s.wifiChannel24.isEmpty ? '0' : s.wifiChannel24;
      _b24.sec       = _parseSecurity(s.wifiAkm24, s.wifiAuthMode24, s.wifiSecurity24);
      _b24.crypto    = _normCrypto(s.wifiCrypto24);
      _b24.netMode   = _normNetMode(s.wifiNetMode24);
      _b24.wlMode    = s.wifiMode24.isEmpty ? 'ap' : s.wifiMode24;
      _b24.pwd       = s.wifiPassword24;
      // Channel width from nbw — but nctrlsb is the real sideband
      _b24.width  = s.wifiChanspec24.endsWith('u') || s.wifiChanspec24.endsWith('l') ? '40' :
                    s.wifiChanspec24.contains('/80') ? '80' : '20';
      _b24.sb     = s.wifiNctrlsb24.isEmpty ? 'upper' : s.wifiNctrlsb24;
    }

    // 5 GHz
    final fp5 = '${s.wifiSsid5}|${s.wifiAkm5}|${s.wifiChannel5}';
    if (fp5.isNotEmpty && fp5 != '||' && fp5 != _lastSynced5) {
      _lastSynced5 = fp5;
      _ssid5c.text  = s.wifiSsid5;
      _pwd5c.text   = s.wifiPassword5;
      _pwr5c.text   = s.wifiTxpower5.replaceAll(RegExp(r'[^0-9]'), '');
      _b5.enabled   = s.wifi5enabled;
      _b5.broadcast = s.wifiBroadcast5 != '0';
      _b5.ch        = s.wifiChannel5.isEmpty ? '36' : s.wifiChannel5;
      _b5.sec       = _parseSecurity(s.wifiAkm5, s.wifiAuthMode5, s.wifiSecurity5);
      _b5.crypto    = _normCrypto(s.wifiCrypto5);
      _b5.netMode   = _normNetMode(s.wifiNetMode5);
      _b5.wlMode    = s.wifiMode5.isEmpty ? 'ap' : s.wifiMode5;
      _b5.width     = s.wifiChanspec5.contains('/80') ? '80' :
                      s.wifiChanspec5.contains('/40') ? '40' : '80';
      _b5.sb        = s.wifiNctrlsb5.isEmpty ? 'lower' : s.wifiNctrlsb5;
    }
  }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    final s = ref.watch(routerStatusProvider);
    _sync(s); // non-destructive sync — only updates when router data changes

    return Scaffold(
      backgroundColor: v.bg,
      body: s.wifiSsid.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading WiFi settings…', style: GoogleFonts.dmMono(fontSize: 12, color: v.mid)),
          ]))
        : ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            _BandCard(
              band: '2.4 GHz', is5: false, v: v, b: _b24,
              ssidCtrl: _ssid24c, pwdCtrl: _pwd24c, pwrCtrl: _pwr24c,
              showPwd: _showPwd24, saving: _saving24,
              onChanged: () => setState(() {}),
              onShowPwd: () => setState(() => _showPwd24 = !_showPwd24),
              onSave: () => _save(false),
            ),
            const SizedBox(height: 16),
            if (s.wifi5present)
              _BandCard(
                band: '5 GHz', is5: true, v: v, b: _b5,
                ssidCtrl: _ssid5c, pwdCtrl: _pwd5c, pwrCtrl: _pwr5c,
                showPwd: _showPwd5, saving: _saving5,
                onChanged: () => setState(() {}),
                onShowPwd: () => setState(() => _showPwd5 = !_showPwd5),
                onSave: () => _save(true),
              ),
          ],
        ),
    );
  }

  Future<void> _save(bool is5) async {
    final ssh = ref.read(sshServiceProvider);
    final b   = is5 ? _b5 : _b24;
    final sc  = is5 ? _ssid5c : _ssid24c;
    final pc  = is5 ? _pwd5c  : _pwd24c;
    final pwc = is5 ? _pwr5c  : _pwr24c;
    setState(() { is5 ? _saving5 = true : _saving24 = true; });
    try {
      final ok = await ssh.saveWifiSettings(
        band:      is5 ? '5' : '2.4',
        ssid:      sc.text.trim(),
        channel:   b.ch,
        security:  b.sec,
        crypto:    b.crypto,
        password:  pc.text,
        txpower:   pwc.text.trim(),
        netMode:   b.netMode,
        wlMode:    b.wlMode,
        broadcast: b.broadcast ? '1' : '0',
        chanWidth: b.width,
        sideband:  b.sb,
      );
      if (ok) {
        // Force re-sync on next fetch
        if (is5) _lastSynced5 = ''; else _lastSynced24 = '';
        ref.read(routerStatusProvider.notifier).fetch();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${is5 ? "5" : "2.4"}GHz saved — reconnecting…',
            style: GoogleFonts.dmMono(fontSize: 12)),
          backgroundColor: V.ok));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save', style: GoogleFonts.dmMono(fontSize: 12)),
          backgroundColor: V.err));
      }
    } finally {
      if (mounted) setState(() { is5 ? _saving5 = false : _saving24 = false; });
    }
  }
}

// ── Per-band card ─────────────────────────────────────────────────────────────
class _BandCard extends StatelessWidget {
  final String band;
  final bool is5, showPwd, saving;
  final VC v;
  final _WifiBandState b;
  final TextEditingController ssidCtrl, pwdCtrl, pwrCtrl;
  final VoidCallback onChanged, onShowPwd, onSave;

  const _BandCard({
    required this.band, required this.is5, required this.v, required this.b,
    required this.ssidCtrl, required this.pwdCtrl, required this.pwrCtrl,
    required this.showPwd, required this.saving,
    required this.onChanged, required this.onShowPwd, required this.onSave,
  });

  // ── Option lists ─────────────────────────────────────────────────────────
  static const _wlModes  = ['ap','apwds','sta','wet','wds','infra'];
  static const _wlLabels = {
    'ap':'Access Point','apwds':'Access Point + WDS',
    'sta':'Wireless Client','wet':'Wireless Ethernet Bridge',
    'wds':'WDS','infra':'Media Bridge',
  };

  List<String> get _netModes => is5
    ? ['auto','disabled','a-only','n-only-5','ac-only','mixed']
    : ['auto','disabled','b-only','g-only','bg-mixed','n-only','mixed'];
  static const _netLabels = {
    'auto':'Auto','disabled':'Disabled',
    'b-only':'B Only','g-only':'G Only','bg-mixed':'B/G Mixed',
    'n-only':'N Only','n-only-5':'N Only','a-only':'A Only',
    'ac-only':'AC Only','mixed':'Auto',
  };

  static const _secModes = [
    'disabled','wep','wpa-personal','wpa-enterprise',
    'wpa2-personal','wpa2-enterprise','wpa-wpa2',
    'wpa-wpa2-enterprise','radius',
  ];
  static const _secLabels = {
    'disabled':'Disabled','wep':'WEP (legacy)',
    'wpa-personal':'WPA Personal (deprecated)',
    'wpa-enterprise':'WPA Enterprise (deprecated)',
    'wpa2-personal':'WPA2 Personal',
    'wpa2-enterprise':'WPA2 Enterprise',
    'wpa-wpa2':'WPA / WPA2 Personal (deprecated)',
    'wpa-wpa2-enterprise':'WPA / WPA2 Enterprise (deprecated)',
    'radius':'Radius',
  };

  static const _cryptos  = ['aes','tkip','tkip+aes'];
  static const _cryptoLbl = {'aes':'AES','tkip':'TKIP','tkip+aes':'TKIP / AES'};

  List<String> get _channels => is5
    ? ['0','36','40','44','48','52','56','60','64','100','104','108','112',
       '116','120','124','128','132','136','140','149','153','157','161','165']
    : ['0','1','2','3','4','5','6','7','8','9','10','11','12','13'];

  List<String> get _widths => is5 ? ['20','40','80'] : ['20','40'];

  bool get _hasCrypto   => !['disabled','wep','radius'].contains(b.sec);
  bool get _hasPassword => !['disabled','radius'].contains(b.sec);

  String _safe(String val, List<String> list) =>
    list.contains(val) ? val : list.first;

  // ── Build helpers ─────────────────────────────────────────────────────────
  Widget _label(String text, VC v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: GoogleFonts.outfit(
      fontSize: 9, fontWeight: FontWeight.w800, color: v.mid, letterSpacing: 1.5)),
  );

  Widget _dd(BuildContext ctx, String val, List<String> items,
      ValueChanged<String?> cb, {Map<String,String>? lbl, String sfx=''}) {
    final v = Theme.of(ctx).extension<VC>()!;
    return DropdownButtonFormField<String>(
      value: _safe(val, items),
      isExpanded: true,
      decoration: const InputDecoration(isDense: true),
      style: GoogleFonts.dmMono(fontSize: 12, color: v.hi),
      items: items.map((i) => DropdownMenuItem(value: i,
        child: Text(lbl?[i] ?? '$i$sfx'))).toList(),
      onChanged: b.enabled ? cb : null,
    );
  }

  @override Widget build(BuildContext ctx) {
    return VCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ──────────────────────────────────────────────────────────
        Row(children: [
          Dot(color: b.enabled ? V.ok : v.lo, size: 7, glow: b.enabled),
          const SizedBox(width: 10),
          Text(band, style: GoogleFonts.outfit(
            fontSize: 15, fontWeight: FontWeight.w800, color: v.hi)),
          const Spacer(),
          Switch(value: b.enabled, onChanged: (x) { b.enabled = x; onChanged(); }),
        ]),
        Divider(color: v.wire, height: 20),

        // ── Wireless Mode ────────────────────────────────────────────────────
        _label('WIRELESS MODE', v),
        _dd(ctx, b.wlMode, _wlModes,
          (x) { b.wlMode = x!; onChanged(); }, lbl: _wlLabels),
        const SizedBox(height: 14),

        // ── Wireless Network Mode ────────────────────────────────────────────
        _label('WIRELESS NETWORK MODE', v),
        _dd(ctx, b.netMode, _netModes,
          (x) { b.netMode = x!; onChanged(); }, lbl: _netLabels),
        const SizedBox(height: 14),

        // ── SSID + Broadcast ─────────────────────────────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('SSID', v),
            TextField(
              controller: ssidCtrl, enabled: b.enabled,
              style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
              decoration: const InputDecoration(isDense: true, hintText: 'Network name')),
          ])),
          const SizedBox(width: 16),
          Column(children: [
            _label('BROADCAST', v),
            Switch(
              value: b.broadcast,
              onChanged: b.enabled ? (x) { b.broadcast = x; onChanged(); } : null),
          ]),
        ]),
        const SizedBox(height: 14),

        // ── Channel + Channel Width ──────────────────────────────────────────
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('CHANNEL', v),
            DropdownButtonFormField<String>(
              value: _safe(b.ch, _channels),
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              style: GoogleFonts.dmMono(fontSize: 12, color: v.hi),
              items: _channels.map((c) => DropdownMenuItem(value: c,
                child: Text(c == '0' ? '0 (Auto)' : c))).toList(),
              onChanged: b.enabled ? (x) { b.ch = x!; onChanged(); } : null,
            ),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('CHANNEL WIDTH', v),
            _dd(ctx, b.width, _widths,
              (x) { b.width = x!; onChanged(); }, sfx: ' MHz'),
          ])),
        ]),
        const SizedBox(height: 14),

        // ── Control Sideband (2.4GHz + 40MHz only) ──────────────────────────
        if (!is5 && b.width == '40') ...[
          _label('CONTROL SIDEBAND', v),
          _dd(ctx, b.sb, ['upper','lower'],
            (x) { b.sb = x!; onChanged(); },
            lbl: {'upper':'Upper','lower':'Lower'}),
          const SizedBox(height: 14),
        ],

        // ── TX Power ─────────────────────────────────────────────────────────
        _label('TX POWER (0 = Auto)', v),
        TextField(
          controller: pwrCtrl, enabled: b.enabled,
          style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(isDense: true, hintText: '0', suffixText: 'mW')),
        const SizedBox(height: 14),

        // ── Security ─────────────────────────────────────────────────────────
        _label('SECURITY', v),
        _dd(ctx, b.sec, _secModes,
          (x) { b.sec = x!; onChanged(); }, lbl: _secLabels),
        const SizedBox(height: 14),

        // ── Encryption ───────────────────────────────────────────────────────
        if (_hasCrypto) ...[
          _label('ENCRYPTION', v),
          _dd(ctx, b.crypto, _cryptos,
            (x) { b.crypto = x!; onChanged(); }, lbl: _cryptoLbl),
          const SizedBox(height: 14),
        ],

        // ── Shared Key ───────────────────────────────────────────────────────
        if (_hasPassword) ...[
          _label('SHARED KEY', v),
          TextField(
            controller: pwdCtrl, enabled: b.enabled,
            obscureText: !showPwd,
            style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
            decoration: InputDecoration(
              isDense: true, hintText: '••••••••',
              suffixIcon: IconButton(
                icon: Icon(showPwd
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
                  size: 18, color: v.mid),
                onPressed: onShowPwd,
              ),
            ),
          ),
          const SizedBox(height: 18),
        ] else
          const SizedBox(height: 4),

        // ── Save button ──────────────────────────────────────────────────────
        SizedBox(width: double.infinity,
          child: ElevatedButton(
            onPressed: b.enabled && !saving ? onSave : null,
            child: saving
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : Text('APPLY ${band.toUpperCase()}',
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 8),
        Text('⚠  Changing SSID/channel will briefly disconnect all clients',
          style: GoogleFonts.dmMono(fontSize: 9, color: v.lo)),
      ]),
    );
  }
}

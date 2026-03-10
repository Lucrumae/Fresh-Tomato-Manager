import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

String _parseSecurityMode(String akm, String authMode, String secMode) {
  final a = akm.toLowerCase().trim();
  final m = secMode.toLowerCase().trim();
  if (m.contains('wpa2_personal') || m.contains('wpa2 personal') || a == 'psk2') return 'wpa2-personal';
  if (a.contains('psk2') && a.contains('psk'))  return 'wpa-wpa2';
  if (m.contains('wpa_personal') || a == 'psk') return 'wpa-personal';
  if (m.contains('wpa2_enterprise') || a == 'wpa2') return 'wpa2-enterprise';
  if (m.contains('wpa_enterprise') || a == 'wpa')   return 'wpa-enterprise';
  if (m == 'radius' || authMode == 'radius')         return 'radius';
  if (m.contains('wep'))                             return 'wep';
  return 'disabled';
}

Map<String, String> _parseChanspec(String chanspec) {
  if (chanspec.endsWith('u'))          return {'width': '40', 'sideband': 'upper'};
  if (chanspec.endsWith('l'))          return {'width': '40', 'sideband': 'lower'};
  if (chanspec.contains('/80'))        return {'width': '80', 'sideband': 'upper'};
  if (chanspec.contains('/40'))        return {'width': '40', 'sideband': 'upper'};
  return {'width': '20', 'sideband': 'upper'};
}

class WifiScreen extends ConsumerStatefulWidget {
  const WifiScreen({super.key});
  @override ConsumerState<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends ConsumerState<WifiScreen> {
  bool _saving24 = false, _saving5 = false;

  final _ssid24 = TextEditingController();
  final _pwd24  = TextEditingController();
  final _pwr24  = TextEditingController();
  String _sec24 = 'wpa2-personal', _crypto24 = 'aes';
  String _netmode24 = 'auto', _wlmode24 = 'ap';
  String _ch24 = '0', _width24 = '40', _sb24 = 'upper';
  bool _broadcast24 = true, _en24 = true, _showPwd24 = false;

  final _ssid5 = TextEditingController();
  final _pwd5  = TextEditingController();
  final _pwr5  = TextEditingController();
  String _sec5 = 'wpa2-personal', _crypto5 = 'aes';
  String _netmode5 = 'auto', _wlmode5 = 'ap';
  String _ch5 = '36', _width5 = '80', _sb5 = 'upper';
  bool _broadcast5 = true, _en5 = true, _showPwd5 = false;

  bool _populated = false;

  @override void dispose() {
    _ssid24.dispose(); _pwd24.dispose(); _pwr24.dispose();
    _ssid5.dispose();  _pwd5.dispose();  _pwr5.dispose();
    super.dispose();
  }

  String _normCrypto(String raw) {
    final r = raw.toLowerCase().trim();
    if (r.contains('tkip') && r.contains('aes')) return 'tkip+aes';
    if (r.contains('tkip')) return 'tkip';
    return 'aes';
  }

  void _populate(RouterStatus s) {
    if (_populated) return;
    if (s.wifiSsid.isEmpty && s.wifiAkm24.isEmpty) return;

    _ssid24.text = s.wifiSsid;
    _en24        = s.wifi24enabled;
    _ch24        = s.wifiChannel24.isEmpty ? '0' : s.wifiChannel24;
    _broadcast24 = s.wifiBroadcast24 != '0';
    _netmode24   = s.wifiNetMode24.isEmpty ? 'auto' : s.wifiNetMode24;
    _wlmode24    = s.wifiMode24.isEmpty ? 'ap' : s.wifiMode24;
    _pwr24.text  = s.wifiTxpower24.replaceAll(RegExp(r'[^0-9]'), '');
    _sec24       = _parseSecurityMode(s.wifiAkm24, s.wifiAuthMode24, s.wifiSecurity24);
    _crypto24    = _normCrypto(s.wifiCrypto24);
    _pwd24.text  = s.wifiPassword24;
    final cs24   = _parseChanspec(s.wifiChanspec24);
    _width24     = cs24['width']!;
    _sb24        = cs24['sideband']!;

    _ssid5.text  = s.wifiSsid5;
    _en5         = s.wifi5enabled;
    _ch5         = s.wifiChannel5.isEmpty ? '36' : s.wifiChannel5;
    _broadcast5  = s.wifiBroadcast5 != '0';
    _netmode5    = s.wifiNetMode5.isEmpty ? 'auto' : s.wifiNetMode5;
    _wlmode5     = s.wifiMode5.isEmpty ? 'ap' : s.wifiMode5;
    _pwr5.text   = s.wifiTxpower5.replaceAll(RegExp(r'[^0-9]'), '');
    _sec5        = _parseSecurityMode(s.wifiAkm5, s.wifiAuthMode5, s.wifiSecurity5);
    _crypto5     = _normCrypto(s.wifiCrypto5);
    _pwd5.text   = s.wifiPassword5;
    final cs5    = _parseChanspec(s.wifiChanspec5);
    _width5      = cs5['width']!;
    _sb5         = cs5['sideband']!;

    _populated = true;
  }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    final s = ref.watch(routerStatusProvider);
    _populate(s);
    return Scaffold(
      backgroundColor: v.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _BandCard(
            band: '2.4 GHz', is5: false, v: v, enabled: _en24, broadcast: _broadcast24,
            ssidCtrl: _ssid24, pwdCtrl: _pwd24, pwrCtrl: _pwr24,
            ch: _ch24, width: _width24, sb: _sb24, sec: _sec24, crypto: _crypto24,
            netMode: _netmode24, wlMode: _wlmode24, showPwd: _showPwd24, saving: _saving24,
            onToggle: (x) => setState(() => _en24 = x),
            onBroadcast: (x) => setState(() => _broadcast24 = x),
            onCh: (x) => setState(() => _ch24 = x),
            onWidth: (x) => setState(() => _width24 = x),
            onSb: (x) => setState(() => _sb24 = x),
            onSec: (x) => setState(() => _sec24 = x),
            onCrypto: (x) => setState(() => _crypto24 = x),
            onNetMode: (x) => setState(() => _netmode24 = x),
            onWlMode: (x) => setState(() => _wlmode24 = x),
            onShowPwd: () => setState(() => _showPwd24 = !_showPwd24),
            onSave: () => _save(false),
          ),
          const SizedBox(height: 16),
          if (s.wifi5present)
            _BandCard(
              band: '5 GHz', is5: true, v: v, enabled: _en5, broadcast: _broadcast5,
              ssidCtrl: _ssid5, pwdCtrl: _pwd5, pwrCtrl: _pwr5,
              ch: _ch5, width: _width5, sb: _sb5, sec: _sec5, crypto: _crypto5,
              netMode: _netmode5, wlMode: _wlmode5, showPwd: _showPwd5, saving: _saving5,
              onToggle: (x) => setState(() => _en5 = x),
              onBroadcast: (x) => setState(() => _broadcast5 = x),
              onCh: (x) => setState(() => _ch5 = x),
              onWidth: (x) => setState(() => _width5 = x),
              onSb: (x) => setState(() => _sb5 = x),
              onSec: (x) => setState(() => _sec5 = x),
              onCrypto: (x) => setState(() => _crypto5 = x),
              onNetMode: (x) => setState(() => _netmode5 = x),
              onWlMode: (x) => setState(() => _wlmode5 = x),
              onShowPwd: () => setState(() => _showPwd5 = !_showPwd5),
              onSave: () => _save(true),
            ),
        ],
      ),
    );
  }

  Future<void> _save(bool is5) async {
    final ssh = ref.read(sshServiceProvider);
    setState(() { if (is5) _saving5 = true; else _saving24 = true; });
    try {
      final ok = await ssh.saveWifiSettings(
        band: is5 ? '5' : '2.4',
        ssid: is5 ? _ssid5.text.trim() : _ssid24.text.trim(),
        channel: is5 ? _ch5 : _ch24,
        security: is5 ? _sec5 : _sec24,
        crypto: is5 ? _crypto5 : _crypto24,
        password: is5 ? _pwd5.text : _pwd24.text,
        txpower: is5 ? _pwr5.text.trim() : _pwr24.text.trim(),
        netMode: is5 ? _netmode5 : _netmode24,
        wlMode: is5 ? _wlmode5 : _wlmode24,
        broadcast: is5 ? (_broadcast5 ? '1' : '0') : (_broadcast24 ? '1' : '0'),
        chanWidth: is5 ? _width5 : _width24,
        sideband: is5 ? _sb5 : _sb24,
      );
      if (ok) {
        _populated = false;
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
      if (mounted) setState(() { if (is5) _saving5 = false; else _saving24 = false; });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _BandCard extends StatelessWidget {
  final String band; final bool is5, enabled, broadcast, showPwd, saving; final VC v;
  final TextEditingController ssidCtrl, pwdCtrl, pwrCtrl;
  final String ch, width, sb, sec, crypto, netMode, wlMode;
  final ValueChanged<bool> onToggle, onBroadcast;
  final ValueChanged<String> onCh, onWidth, onSb, onSec, onCrypto, onNetMode, onWlMode;
  final VoidCallback onShowPwd, onSave;

  const _BandCard({
    required this.band, required this.is5, required this.v,
    required this.enabled, required this.broadcast,
    required this.ssidCtrl, required this.pwdCtrl, required this.pwrCtrl,
    required this.ch, required this.width, required this.sb,
    required this.sec, required this.crypto, required this.netMode, required this.wlMode,
    required this.showPwd, required this.saving,
    required this.onToggle, required this.onBroadcast,
    required this.onCh, required this.onWidth, required this.onSb,
    required this.onSec, required this.onCrypto, required this.onNetMode, required this.onWlMode,
    required this.onShowPwd, required this.onSave,
  });

  static const _wlModes = ['ap','apwds','sta','wet','wds','infra'];
  static const _wlModeLabels = {
    'ap': 'Access Point', 'apwds': 'Access Point + WDS',
    'sta': 'Wireless Client', 'wet': 'Wireless Ethernet Bridge',
    'wds': 'WDS', 'infra': 'Media Bridge',
  };
  List<String> get _netModes => is5
    ? ['auto','a-only','n-only','ac-only']
    : ['auto','b-only','g-only','bg-mixed','n-only'];
  static const _netModeLabels = {
    'auto': 'Auto', 'b-only': 'B Only', 'g-only': 'G Only',
    'bg-mixed': 'B/G Mixed', 'n-only': 'N Only',
    'a-only': 'A Only', 'ac-only': 'AC Only',
  };
  static const _secModes = ['disabled','wep','wpa-personal','wpa-enterprise','wpa2-personal','wpa2-enterprise','wpa-wpa2','wpa-wpa2-enterprise','radius'];
  static const _secLabels = {
    'disabled': 'Disabled', 'wep': 'WEP (legacy)',
    'wpa-personal': 'WPA Personal (deprecated)',
    'wpa-enterprise': 'WPA Enterprise (deprecated)',
    'wpa2-personal': 'WPA2 Personal',
    'wpa2-enterprise': 'WPA2 Enterprise',
    'wpa-wpa2': 'WPA / WPA2 Personal (deprecated)',
    'wpa-wpa2-enterprise': 'WPA / WPA2 Enterprise (deprecated)',
    'radius': 'Radius',
  };
  static const _cryptos = ['aes','tkip','tkip+aes'];
  static const _cryptoLabels = {'aes': 'AES', 'tkip': 'TKIP', 'tkip+aes': 'TKIP / AES'};

  List<String> get _channels => is5
    ? ['0','36','40','44','48','52','56','60','64','100','104','108','112','116','120','124','128','132','136','140','149','153','157','161','165']
    : ['0','1','2','3','4','5','6','7','8','9','10','11','12','13'];

  List<String> get _widths => is5 ? ['20','40','80'] : ['20','40'];

  bool get _needsCrypto => sec != 'disabled' && sec != 'wep' && sec != 'radius';
  bool get _needsPassword => sec != 'disabled' && sec != 'radius';

  String _safe(String val, List<String> list) => list.contains(val) ? val : list.first;

  Widget _lbl(String text) => Text(text, style: GoogleFonts.outfit(
    fontSize: 9, fontWeight: FontWeight.w800, color: v.mid, letterSpacing: 1.5));

  Widget _dd<T>(String value, List<String> items, ValueChanged<String?> cb,
      {Map<String, String>? labels, String suffix = ''}) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: const InputDecoration(isDense: true),
      style: GoogleFonts.dmMono(fontSize: 12, color: v.hi),
      items: items.map((i) => DropdownMenuItem(value: i,
        child: Text(labels?[i] ?? '$i$suffix'))).toList(),
      onChanged: enabled ? cb : null,
    );
  }

  @override Widget build(BuildContext ctx) {
    return VCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Dot(color: enabled ? V.ok : v.lo, size: 7, glow: enabled),
          const SizedBox(width: 10),
          Text(band, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: v.hi)),
          const Spacer(),
          Switch(value: enabled, onChanged: onToggle),
        ]),
        Divider(color: v.wire, height: 20),

        _lbl('WIRELESS MODE'),
        const SizedBox(height: 6),
        _dd(wlMode.isEmpty ? 'ap' : _safe(wlMode, _wlModes), _wlModes, (x) => onWlMode(x!), labels: _wlModeLabels),
        const SizedBox(height: 14),

        _lbl('WIRELESS NETWORK MODE'),
        const SizedBox(height: 6),
        _dd(_safe(netMode.isEmpty ? 'auto' : netMode, _netModes), _netModes, (x) => onNetMode(x!), labels: _netModeLabels),
        const SizedBox(height: 14),

        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl('SSID'),
            const SizedBox(height: 6),
            TextField(controller: ssidCtrl, enabled: enabled,
              style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
              decoration: const InputDecoration(hintText: 'Network name', isDense: true)),
          ])),
          const SizedBox(width: 16),
          Column(children: [
            _lbl('BROADCAST'),
            Switch(value: broadcast, onChanged: enabled ? onBroadcast : null),
          ]),
        ]),
        const SizedBox(height: 14),

        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl('CHANNEL'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _safe(ch, _channels),
              isExpanded: true,
              decoration: const InputDecoration(isDense: true),
              style: GoogleFonts.dmMono(fontSize: 12, color: v.hi),
              items: _channels.map((c) => DropdownMenuItem(value: c,
                child: Text(c == '0' ? '0 (Auto)' : c))).toList(),
              onChanged: enabled ? (x) => onCh(x!) : null,
            ),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl('CHANNEL WIDTH'),
            const SizedBox(height: 6),
            _dd(_safe(width, _widths), _widths, (x) => onWidth(x!), suffix: ' MHz'),
          ])),
        ]),
        const SizedBox(height: 14),

        if (!is5 && width == '40') ...[
          _lbl('CONTROL SIDEBAND'),
          const SizedBox(height: 6),
          _dd(_safe(sb, ['upper','lower']), ['upper','lower'], (x) => onSb(x!),
            labels: {'upper': 'Upper', 'lower': 'Lower'}),
          const SizedBox(height: 14),
        ],

        _lbl('TX POWER (0 = Auto)'),
        const SizedBox(height: 6),
        TextField(controller: pwrCtrl, enabled: enabled,
          style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '0', isDense: true, suffixText: 'mW')),
        const SizedBox(height: 14),

        _lbl('SECURITY'),
        const SizedBox(height: 6),
        _dd(_safe(sec, _secModes), _secModes, (x) => onSec(x!), labels: _secLabels),
        const SizedBox(height: 14),

        if (_needsCrypto) ...[
          _lbl('ENCRYPTION'),
          const SizedBox(height: 6),
          _dd(_safe(crypto, _cryptos), _cryptos, (x) => onCrypto(x!), labels: _cryptoLabels),
          const SizedBox(height: 14),
        ],

        if (_needsPassword) ...[
          _lbl('SHARED KEY'),
          const SizedBox(height: 6),
          TextField(
            controller: pwdCtrl, enabled: enabled, obscureText: !showPwd,
            style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
            decoration: InputDecoration(
              isDense: true, hintText: '••••••••',
              suffixIcon: IconButton(
                icon: Icon(showPwd ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 18, color: v.mid),
                onPressed: onShowPwd,
              ),
            ),
          ),
          const SizedBox(height: 18),
        ] else
          const SizedBox(height: 4),

        SizedBox(width: double.infinity,
          child: ElevatedButton(
            onPressed: enabled && !saving ? onSave : null,
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

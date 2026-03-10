import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';

class WifiScreen extends ConsumerStatefulWidget {
  const WifiScreen({super.key});
  @override ConsumerState<WifiScreen> createState() => _WifiScreenState();
}

class _WifiScreenState extends ConsumerState<WifiScreen> {
  bool _saving24 = false;
  bool _saving5  = false;

  // 2.4 GHz controllers
  final _ssid24  = TextEditingController();
  final _ch24    = TextEditingController();
  final _pwr24   = TextEditingController();
  String _sec24  = 'wpa2-personal';
  bool _en24     = true;

  // 5 GHz controllers
  final _ssid5   = TextEditingController();
  final _ch5     = TextEditingController();
  final _pwr5    = TextEditingController();
  String _sec5   = 'wpa2-personal';
  bool _en5      = true;

  bool _populated = false;

  @override void initState() {
    super.initState();
    // Populate after first frame so providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() { _populated = false; });
    });
  }

  @override void dispose() {
    _ssid24.dispose(); _ch24.dispose(); _pwr24.dispose();
    _ssid5.dispose();  _ch5.dispose();  _pwr5.dispose();
    super.dispose();
  }

  void _populate() {
    if (_populated) return;
    final s = ref.read(routerStatusProvider);
    _ssid24.text = s.wifiSsid;
    _ssid5.text  = s.wifiSsid5;
    _ch24.text   = s.wifiChannel24;
    _ch5.text    = s.wifiChannel5;
    _en24        = s.wifi24enabled;
    _en5         = s.wifi5enabled;
    // Parse security mode
    final rawSec24 = s.wifiSecurity24.toLowerCase();
    if (rawSec24.contains('wpa2')) _sec24 = 'wpa2-personal';
    else if (rawSec24.contains('wpa')) _sec24 = 'wpa-personal';
    else if (rawSec24.isEmpty || rawSec24 == 'open' || rawSec24 == 'disabled') _sec24 = 'disabled';
    final rawSec5 = s.wifiSecurity5.toLowerCase();
    if (rawSec5.contains('wpa2')) _sec5 = 'wpa2-personal';
    else if (rawSec5.contains('wpa')) _sec5 = 'wpa-personal';
    else if (rawSec5.isEmpty || rawSec5 == 'open' || rawSec5 == 'disabled') _sec5 = 'disabled';
    // Parse txpower — strip "mW" suffix
    _pwr24.text = s.wifiTxpower24.replaceAll(RegExp(r'[^0-9]'), '');
    _pwr5.text  = s.wifiTxpower5.replaceAll(RegExp(r'[^0-9]'), '');
    _populated = true;
  }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    final s = ref.watch(routerStatusProvider);
    _populate();

    return Scaffold(
      backgroundColor: v.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [

          // ── 2.4 GHz ──────────────────────────────────────────────────────
          _BandCard(
            band: '2.4 GHz', iface: 'eth1',
            enabled: _en24,
            ssidCtrl: _ssid24, chCtrl: _ch24, pwrCtrl: _pwr24,
            security: _sec24, saving: _saving24,
            channels: _ch24List,
            onToggle: (val) async {
              setState(() => _en24 = val);
              final ok = await ref.read(sshServiceProvider).toggleWifi('2.4', val);
              if (ok) ref.read(routerStatusProvider.notifier).fetch();
            },
            onSecChange: (val) => setState(() => _sec24 = val!),
            onSave: () => _save('2.4'),
          ),
          const SizedBox(height: 16),

          // ── 5 GHz ─────────────────────────────────────────────────────────
          if (s.wifi5present)
            _BandCard(
              band: '5 GHz', iface: 'eth2',
              enabled: _en5,
              ssidCtrl: _ssid5, chCtrl: _ch5, pwrCtrl: _pwr5,
              security: _sec5, saving: _saving5,
              channels: _ch5List,
              onToggle: (val) async {
                setState(() => _en5 = val);
                final ok = await ref.read(sshServiceProvider).toggleWifi('5', val);
                if (ok) ref.read(routerStatusProvider.notifier).fetch();
              },
              onSecChange: (val) => setState(() => _sec5 = val!),
              onSave: () => _save('5'),
            ),
        ],
      ),
    );
  }

  Future<void> _save(String band) async {
    final ssh = ref.read(sshServiceProvider);
    final is5 = band == '5';
    setState(() { if (is5) _saving5 = true; else _saving24 = true; });
    try {
      final ok = await ssh.saveWifiSettings(
        band:     band,
        ssid:     is5 ? _ssid5.text.trim()  : _ssid24.text.trim(),
        channel:  is5 ? _ch5.text.trim()    : _ch24.text.trim(),
        security: is5 ? _sec5               : _sec24,
        txpower:  is5 ? _pwr5.text.trim()   : _pwr24.text.trim(),
      );
      if (ok) {
        ref.read(routerStatusProvider.notifier).fetch();
        _populated = false; // refresh from router
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${band}GHz settings saved — reconnecting clients…',
            style: GoogleFonts.dmMono(fontSize: 11)),
          backgroundColor: V.ok));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to save', style: GoogleFonts.dmMono(fontSize: 11)),
          backgroundColor: V.err));
      }
    } finally {
      if (mounted) setState(() { if (is5) _saving5 = false; else _saving24 = false; });
    }
  }

  static const _ch24List = ['0 (Auto)', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13'];
  static const _ch5List  = ['0 (Auto)', '36', '40', '44', '48', '52', '56', '60', '64',
    '100', '104', '108', '112', '116', '120', '124', '128', '132', '136', '140',
    '149', '153', '157', '161', '165'];
}

// ── Per-band settings card ────────────────────────────────────────────────────
class _BandCard extends StatelessWidget {
  final String band, iface, security;
  final bool enabled, saving;
  final TextEditingController ssidCtrl, chCtrl, pwrCtrl;
  final List<String> channels;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String?> onSecChange;
  final VoidCallback onSave;

  const _BandCard({
    required this.band, required this.iface, required this.enabled,
    required this.ssidCtrl, required this.chCtrl, required this.pwrCtrl,
    required this.security, required this.saving, required this.channels,
    required this.onToggle, required this.onSecChange, required this.onSave,
  });

  @override Widget build(BuildContext ctx) {
    final v = Theme.of(ctx).extension<VC>()!;
    return VCard(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with toggle
        Row(children: [
          Dot(color: enabled ? V.ok : v.lo, size: 7, glow: enabled),
          const SizedBox(width: 10),
          Text(band, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: v.hi)),
          const Spacer(),
          Switch(value: enabled, onChanged: onToggle),
        ]),
        Divider(color: v.wire, height: 20),

        // SSID
        Text('SSID', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: v.mid, letterSpacing: 1.5)),
        const SizedBox(height: 6),
        TextField(controller: ssidCtrl, enabled: enabled,
          style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
          decoration: const InputDecoration(hintText: 'Network name', isDense: true)),
        const SizedBox(height: 14),

        // Channel + Security row
        Row(children: [
          // Channel dropdown
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('CHANNEL', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: v.mid, letterSpacing: 1.5)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _resolveChannel(chCtrl.text, channels),
              decoration: const InputDecoration(isDense: true),
              isExpanded: true,
              style: GoogleFonts.dmMono(fontSize: 12, color: v.hi),
              items: channels.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: enabled ? (val) {
                if (val != null) {
                  chCtrl.text = val.split(' ').first; // strip "(Auto)"
                }
              } : null,
            ),
          ])),
          const SizedBox(width: 12),
          // TX Power
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TX POWER', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: v.mid, letterSpacing: 1.5)),
            const SizedBox(height: 6),
            TextField(controller: pwrCtrl, enabled: enabled,
              style: GoogleFonts.dmMono(fontSize: 13, color: v.hi),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'mW', isDense: true, suffixText: 'mW')),
          ])),
        ]),
        const SizedBox(height: 14),

        // Security
        Text('SECURITY', style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.w800, color: v.mid, letterSpacing: 1.5)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: security,
          decoration: const InputDecoration(isDense: true),
          style: GoogleFonts.dmMono(fontSize: 12, color: v.hi),
          items: const [
            DropdownMenuItem(value: 'disabled',      child: Text('Open (no security)')),
            DropdownMenuItem(value: 'wpa-personal',  child: Text('WPA Personal')),
            DropdownMenuItem(value: 'wpa2-personal', child: Text('WPA2 Personal')),
          ],
          onChanged: enabled ? onSecChange : null,
        ),
        const SizedBox(height: 18),

        // Save button
        SizedBox(width: double.infinity,
          child: ElevatedButton(
            onPressed: enabled && !saving ? onSave : null,
            child: saving
              ? SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: V.d0))
              : Text('APPLY ${band.toUpperCase()}',
                  style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800))),
        ),

        // Warning
        const SizedBox(height: 8),
        Text('⚠  Changing SSID/channel will briefly disconnect all clients',
          style: GoogleFonts.dmMono(fontSize: 9, color: v.lo)),
      ],
    ));
  }

  String _resolveChannel(String current, List<String> list) {
    final clean = current.trim();
    if (clean.isEmpty || clean == '0') return list.first;
    for (final item in list) {
      if (item == clean || item.startsWith('$clean ')) return item;
    }
    return list.first;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status    = ref.watch(routerStatusProvider);
    final bandwidth = ref.watch(bandwidthProvider);
    final devices   = ref.watch(devicesProvider);
    final c         = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: c.background,
      body: CustomScrollView(
        slivers: [
          // ── Header ────────────────────────────────────────────────────────
          SliverAppBar(
            floating: true, snap: true,
            backgroundColor: c.surface,
            toolbarHeight: 60,
            title: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: c.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.accent.withOpacity(0.3)),
                ),
                child: Icon(Icons.router_rounded, size: 17, color: c.accent),
              ),
              const SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dashboard',
                  style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                Text(status.routerModel,
                  style: GoogleFonts.spaceGrotesk(fontSize: 10, color: c.textMuted)),
              ]),
            ]),
            actions: [
              // Online badge
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: status.isOnline
                    ? AppTheme.success.withOpacity(0.10)
                    : AppTheme.danger.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: status.isOnline
                      ? AppTheme.success.withOpacity(0.3)
                      : AppTheme.danger.withOpacity(0.3)),
                ),
                child: Row(children: [
                  StatusDot(
                    color: status.isOnline ? AppTheme.success : AppTheme.danger,
                    size: 6),
                  const SizedBox(width: 5),
                  Text(
                    status.isOnline ? 'Online' : 'Offline',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: status.isOnline ? AppTheme.success : AppTheme.danger)),
                ]),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(height: 1, color: c.border),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(delegate: SliverChildListDelegate([

              // ── CPU + RAM row ──────────────────────────────────────────────
              Row(children: [
                Expanded(child: _ResourceCard(
                  label: 'CPU',
                  value: status.cpuUsage,
                  percent: status.cpuPercent / 100,
                  icon: Icons.memory_rounded,
                  sub: status.cpuTempC > 0 ? status.cpuTemp : null,
                  subColor: status.cpuTempC >= 70 ? AppTheme.danger
                    : status.cpuTempC >= 50 ? AppTheme.warning : AppTheme.success,
                )),
                const SizedBox(width: 10),
                Expanded(child: _ResourceCard(
                  label: 'RAM',
                  value: status.ramUsage,
                  sub: '/ ${status.ramTotal}',
                  percent: status.ramPercent / 100,
                  icon: Icons.developer_board_rounded,
                )),
              ]),
              const SizedBox(height: 10),

              // ── Bandwidth live card ────────────────────────────────────────
              _BandwidthLiveCard(bandwidth: bandwidth, c: c),
              const SizedBox(height: 10),

              // ── 3 quick stat tiles ─────────────────────────────────────────
              Row(children: [
                Expanded(child: _MiniStatTile(
                  icon: Icons.devices_rounded,
                  value: '${devices.length}',
                  label: 'Devices',
                  color: AppTheme.info,
                )),
                const SizedBox(width: 10),
                Expanded(child: _MiniStatTile(
                  icon: Icons.block_rounded,
                  value: '${devices.where((d) => d.isBlocked).length}',
                  label: 'Blocked',
                  color: AppTheme.danger,
                )),
                const SizedBox(width: 10),
                Expanded(child: _MiniStatTile(
                  icon: Icons.wifi_rounded,
                  value: '${devices.where((d) => d.isWireless).length}',
                  label: 'WiFi',
                  color: AppTheme.success,
                )),
              ]),
              const SizedBox(height: 10),

              // ── Network info card ──────────────────────────────────────────
              _NetworkCard(status: status, c: c),
              const SizedBox(height: 10),

              // ── Ethernet ports ─────────────────────────────────────────────
              const _EthernetPortCard(),
              const SizedBox(height: 10),

              // ── Firmware strip ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.info.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.system_update_rounded, size: 16, color: AppTheme.info),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Firmware', style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, fontWeight: FontWeight.w600, color: c.textMuted)),
                    Text(status.firmware, style: GoogleFonts.jetBrainsMono(
                      fontSize: 12, fontWeight: FontWeight.w500, color: c.textSecondary)),
                  ]),
                  const Spacer(),
                  Text('Uptime', style: GoogleFonts.spaceGrotesk(
                    fontSize: 11, color: c.textMuted)),
                  const SizedBox(width: 8),
                  Text(status.uptime, style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary)),
                ]),
              ),
              const SizedBox(height: 80),
            ])),
          ),
        ],
      ),
    );
  }
}

// ── Resource Card (CPU/RAM) ────────────────────────────────────────────────────
class _ResourceCard extends StatelessWidget {
  final String label, value;
  final String? sub;
  final Color? subColor;
  final double percent;
  final IconData icon;

  const _ResourceCard({
    required this.label, required this.value, required this.percent,
    required this.icon, this.sub, this.subColor,
  });

  Color _barColor(double p) {
    if (p > 0.80) return AppTheme.danger;
    if (p > 0.60) return AppTheme.warning;
    return AppTheme.success;
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    final barColor = _barColor(percent);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: c.textMuted),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.spaceGrotesk(
            fontSize: 11, fontWeight: FontWeight.w600, color: c.textMuted, letterSpacing: 0.5)),
          const Spacer(),
          if (sub != null)
            Row(children: [
              if (subColor != null)
                Icon(Icons.thermostat_rounded, size: 11, color: subColor),
              Text(sub!, style: GoogleFonts.jetBrainsMono(
                fontSize: 10, color: subColor ?? c.textMuted, fontWeight: FontWeight.w600)),
            ]),
        ]),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.jetBrainsMono(
          fontSize: 22, fontWeight: FontWeight.w700, color: c.textPrimary)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: percent.clamp(0.0, 1.0),
            backgroundColor: c.border,
            valueColor: AlwaysStoppedAnimation(barColor),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 4),
        Text('${(percent * 100).toStringAsFixed(1)}%',
          style: GoogleFonts.jetBrainsMono(fontSize: 9, color: barColor, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Bandwidth Live Card ────────────────────────────────────────────────────────
class _BandwidthLiveCard extends StatelessWidget {
  final BandwidthStats bandwidth;
  final AppColors c;
  const _BandwidthLiveCard({required this.bandwidth, required this.c});

  String _fmt(double kbps) {
    if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(2)} Mbps';
    return '${kbps.toStringAsFixed(0)} Kbps';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(children: [
        Row(children: [
          Text('Bandwidth', style: GoogleFonts.spaceGrotesk(
            fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.10),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(children: [
              StatusDot(color: AppTheme.success, size: 5),
              const SizedBox(width: 4),
              Text('LIVE', style: GoogleFonts.spaceGrotesk(
                fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.success, letterSpacing: 1)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _BwTile(
            direction: '↓ DOWN',
            value: _fmt(bandwidth.currentRx),
            color: c.accent,
          )),
          Container(width: 1, height: 40, color: c.border),
          Expanded(child: _BwTile(
            direction: '↑ UP',
            value: _fmt(bandwidth.currentTx),
            color: AppTheme.warning,
          )),
        ]),
      ]),
    );
  }
}

class _BwTile extends StatelessWidget {
  final String direction, value;
  final Color color;
  const _BwTile({required this.direction, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(direction, style: GoogleFonts.spaceGrotesk(
        fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.5)),
      const SizedBox(height: 4),
      Text(value, style: GoogleFonts.jetBrainsMono(
        fontSize: 18, fontWeight: FontWeight.w700, color: color)),
    ]),
  );
}

// ── Mini Stat Tile ─────────────────────────────────────────────────────────────
class _MiniStatTile extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color color;
  const _MiniStatTile({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(height: 8),
        Text(value, style: GoogleFonts.jetBrainsMono(
          fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label, style: GoogleFonts.spaceGrotesk(
          fontSize: 10, color: c.textMuted)),
      ]),
    );
  }
}

// ── Network Info Card ──────────────────────────────────────────────────────────
class _NetworkCard extends StatelessWidget {
  final RouterStatus status;
  final AppColors c;
  const _NetworkCard({required this.status, required this.c});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => _showWifiSettings(context, status),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Network', style: GoogleFonts.spaceGrotesk(
            fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const Spacer(),
          Icon(Icons.edit_rounded, size: 13, color: c.accent.withOpacity(0.6)),
        ]),
        const SizedBox(height: 14),
        _NetRow(label: 'WAN', value: status.wanIp, icon: Icons.language_rounded, c: c),
        Divider(height: 16, color: c.border),
        _NetRow(label: 'LAN', value: status.lanIp, icon: Icons.home_rounded, c: c),
        Divider(height: 16, color: c.border),
        _WifiStatusRow(label: '2.4 GHz', ssid: status.wifiSsid, enabled: status.wifi24enabled, c: c),
        if (status.wifi5present) ...[
          Divider(height: 16, color: c.border),
          _WifiStatusRow(label: '5 GHz', ssid: status.wifiSsid5, enabled: status.wifi5enabled, c: c),
        ],
      ]),
    );
  }
}

class _NetRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final AppColors c;
  const _NetRow({required this.label, required this.value, required this.icon, required this.c});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 14, color: c.textMuted),
    const SizedBox(width: 8),
    Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: c.textSecondary)),
    const Spacer(),
    Text(value, style: GoogleFonts.jetBrainsMono(
      fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary)),
  ]);
}

class _WifiStatusRow extends StatelessWidget {
  final String label, ssid;
  final bool enabled;
  final AppColors c;
  const _WifiStatusRow({required this.label, required this.ssid, required this.enabled, required this.c});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(Icons.wifi_rounded, size: 14, color: c.textMuted),
    const SizedBox(width: 8),
    Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: c.textSecondary)),
    const Spacer(),
    StatusDot(color: enabled ? AppTheme.success : AppTheme.danger, size: 6),
    const SizedBox(width: 6),
    Text(ssid.isEmpty ? '—' : ssid, style: GoogleFonts.spaceGrotesk(
      fontSize: 12, fontWeight: FontWeight.w600,
      color: enabled ? c.textPrimary : AppTheme.danger)),
  ]);
}

void _showWifiSettings(BuildContext context, RouterStatus status) {
  showModalBottomSheet(
    context: context, isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _WifiSheet(status: status),
  );
}

// ── WiFi Settings Sheet ────────────────────────────────────────────────────────
class _WifiSheet extends ConsumerStatefulWidget {
  final RouterStatus status;
  const _WifiSheet({required this.status});
  @override
  ConsumerState<_WifiSheet> createState() => _WifiSheetState();
}

class _WifiSheetState extends ConsumerState<_WifiSheet> {
  bool _saving = false;
  String? _msg;
  late TextEditingController _ssid24, _pass24, _ch24;
  late bool _radio24;
  late String _sec24;
  late TextEditingController _ssid5, _pass5, _ch5;
  late bool _radio5;
  late String _sec5;

  @override
  void initState() {
    super.initState();
    _ssid24 = TextEditingController(text: widget.status.wifiSsid);
    _pass24 = TextEditingController();
    _ch24   = TextEditingController();
    _radio24 = widget.status.wifi24enabled;
    _sec24 = 'psk2';
    _ssid5 = TextEditingController(text: widget.status.wifiSsid5);
    _pass5 = TextEditingController();
    _ch5   = TextEditingController();
    _radio5 = widget.status.wifi5enabled;
    _sec5 = 'psk2';
    _loadDetails();
  }

  @override
  void dispose() {
    _ssid24.dispose(); _pass24.dispose(); _ch24.dispose();
    _ssid5.dispose();  _pass5.dispose();  _ch5.dispose();
    super.dispose();
  }

  Future<void> _loadDetails() async {
    final ssh = ref.read(sshServiceProvider);
    try {
      final r = await ssh.run(
        'nvram get wl0_wpa_psk; echo "---";'
        'nvram get wl0_channel; echo "---";'
        'nvram get wl0_security_mode; echo "---";'
        'nvram get wl1_wpa_psk; echo "---";'
        'nvram get wl1_channel; echo "---";'
        'nvram get wl1_security_mode'
      );
      final parts = r.split('---').map((s) => s.trim()).toList();
      String mapSec(String s) {
        if (s == 'wpa2_personal') return 'psk2';
        if (s == 'wpa_personal')  return 'psk';
        if (s == 'wpa2_enterprise') return 'wpa2';
        if (s == 'wpa_enterprise')  return 'wpa';
        if (s == 'wpa_personal wpa2_personal') return 'psk psk2';
        return s.isEmpty ? 'psk2' : s;
      }
      if (mounted) setState(() {
        if (parts.length > 0) _pass24.text = parts[0];
        if (parts.length > 1) _ch24.text   = parts[1];
        if (parts.length > 2) _sec24       = mapSec(parts[2]);
        if (parts.length > 3) _pass5.text  = parts[3];
        if (parts.length > 4) _ch5.text    = parts[4];
        if (parts.length > 5) _sec5        = mapSec(parts[5]);
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final ssh = ref.read(sshServiceProvider);
    setState(() { _saving = true; _msg = null; });
    try {
      String toNvramSec(String s) {
        if (s == 'psk2') return 'wpa2_personal';
        if (s == 'psk')  return 'wpa_personal';
        if (s == 'wpa2') return 'wpa2_enterprise';
        if (s == 'wpa')  return 'wpa_enterprise';
        if (s == 'psk psk2') return 'wpa_personal wpa2_personal';
        if (s == 'open') return 'disabled';
        return s;
      }
      final cmds = <String>[
        "nvram set wl0_ssid='${_ssid24.text}'",
        "nvram set wl0_radio=${_radio24 ? 1 : 0}",
        "nvram set wl0_security_mode='${toNvramSec(_sec24)}'",
        "nvram set wl0_crypto='aes'",
        if (_pass24.text.isNotEmpty) "nvram set wl0_wpa_psk='${_pass24.text}'",
        if (_ch24.text.isNotEmpty)   "nvram set wl0_channel='${_ch24.text}'",
      ];
      if (widget.status.wifi5present) {
        cmds.addAll([
          "nvram set wl1_ssid='${_ssid5.text}'",
          "nvram set wl1_radio=${_radio5 ? 1 : 0}",
          "nvram set wl1_security_mode='${toNvramSec(_sec5)}'",
          "nvram set wl1_crypto='aes'",
          if (_pass5.text.isNotEmpty) "nvram set wl1_wpa_psk='${_pass5.text}'",
          if (_ch5.text.isNotEmpty)   "nvram set wl1_channel='${_ch5.text}'",
        ]);
      }
      cmds.add('nvram commit');
      await ssh.run(cmds.join(' && '));
      ssh.run('(wlconf eth1 up; wlconf eth2 up; killall -HUP eapd 2>/dev/null; killall -HUP nas 2>/dev/null; service wireless restart > /dev/null 2>&1) &').catchError((_){});
      setState(() => _msg = 'Saved! Applying WiFi settings...');
    } catch (e) {
      setState(() => _msg = 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    const secOpts = ['open', 'psk', 'psk2', 'psk psk2', 'wpa', 'wpa2'];
    final secLabels = {'open': 'Open', 'psk': 'WPA', 'psk2': 'WPA2',
      'psk psk2': 'WPA/WPA2', 'wpa': 'WPA Ent.', 'wpa2': 'WPA2 Ent.'};

    return DraggableScrollableSheet(
      initialChildSize: 0.85, minChildSize: 0.5, maxChildSize: 0.95,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: c.border),
        ),
        child: Column(children: [
          Container(margin: const EdgeInsets.only(top: 10), width: 36, height: 4,
            decoration: BoxDecoration(color: c.border2, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
            child: Row(children: [
              Icon(Icons.wifi_rounded, color: c.accent, size: 18),
              const SizedBox(width: 8),
              Text('WiFi Settings', style: GoogleFonts.spaceGrotesk(
                fontSize: 15, fontWeight: FontWeight.w700, color: c.textPrimary)),
              const Spacer(),
              _saving
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent))
                : TextButton(
                    onPressed: _save,
                    child: Text('Save', style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700, color: c.accent))),
            ]),
          ),
          if (_msg != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _msg!.startsWith('Error') ? AppTheme.danger.withOpacity(0.10) : AppTheme.success.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _msg!.startsWith('Error') ? AppTheme.danger.withOpacity(0.3) : AppTheme.success.withOpacity(0.3)),
              ),
              child: Text(_msg!, style: GoogleFonts.spaceGrotesk(fontSize: 12,
                color: _msg!.startsWith('Error') ? AppTheme.danger : AppTheme.success)),
            ),
          Expanded(child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              _BandHeader(band: '2.4 GHz', enabled: widget.status.wifi24enabled,
                radioVal: _radio24, onChanged: (v) => setState(() => _radio24 = v), c: c),
              const SizedBox(height: 10),
              _tf('SSID', _ssid24), const SizedBox(height: 8),
              _tf('Password', _pass24, obscure: true), const SizedBox(height: 8),
              _tf('Channel (0=auto)', _ch24, keyboard: TextInputType.number), const SizedBox(height: 8),
              _dd('Security', _sec24, secOpts, secLabels, (v) => setState(() => _sec24 = v)),
              if (widget.status.wifi5present) ...[
                const SizedBox(height: 20),
                _BandHeader(band: '5 GHz', enabled: widget.status.wifi5enabled,
                  radioVal: _radio5, onChanged: (v) => setState(() => _radio5 = v), c: c),
                const SizedBox(height: 10),
                _tf('SSID', _ssid5), const SizedBox(height: 8),
                _tf('Password', _pass5, obscure: true), const SizedBox(height: 8),
                _tf('Channel (0=auto)', _ch5, keyboard: TextInputType.number), const SizedBox(height: 8),
                _dd('Security', _sec5, secOpts, secLabels, (v) => setState(() => _sec5 = v)),
              ],
            ],
          )),
        ]),
      ),
    );
  }

  Widget _tf(String label, TextEditingController ctrl, {bool obscure = false, TextInputType keyboard = TextInputType.text}) =>
    TextField(controller: ctrl, obscureText: obscure, keyboardType: keyboard,
      style: GoogleFonts.jetBrainsMono(fontSize: 13),
      decoration: InputDecoration(labelText: label));

  Widget _dd(String label, String val, List<String> opts, Map<String, String> labels, ValueChanged<String> onChange) {
    final c = Theme.of(context).extension<AppColors>()!;
    return DropdownButtonFormField<String>(
      value: opts.contains(val) ? val : opts[2],
      decoration: InputDecoration(labelText: label),
      dropdownColor: c.cardBg,
      items: opts.map((o) => DropdownMenuItem(value: o, child: Text(labels[o] ?? o,
        style: GoogleFonts.spaceGrotesk(fontSize: 13)))).toList(),
      onChanged: (v) { if (v != null) onChange(v); },
    );
  }
}

class _BandHeader extends StatelessWidget {
  final String band;
  final bool enabled, radioVal;
  final ValueChanged<bool> onChanged;
  final AppColors c;
  const _BandHeader({required this.band, required this.enabled, required this.radioVal, required this.onChanged, required this.c});

  @override
  Widget build(BuildContext context) => Row(children: [
    StatusDot(color: enabled ? AppTheme.success : AppTheme.danger, size: 7),
    const SizedBox(width: 8),
    Text('WiFi $band', style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary)),
    const Spacer(),
    Text(radioVal ? 'On' : 'Off', style: GoogleFonts.spaceGrotesk(fontSize: 11,
      color: radioVal ? AppTheme.success : AppTheme.danger, fontWeight: FontWeight.w600)),
    const SizedBox(width: 6),
    Switch.adaptive(value: radioVal, onChanged: onChanged, activeColor: c.accent),
  ]);
}

// ── Ethernet Port Card ─────────────────────────────────────────────────────────
class _EthernetPortCard extends ConsumerWidget {
  const _EthernetPortCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portList = ref.watch(ethernetPortsProvider);
    final c = Theme.of(context).extension<AppColors>()!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.settings_ethernet_rounded, size: 14, color: c.textMuted),
          const SizedBox(width: 7),
          Text('Ports', style: GoogleFonts.spaceGrotesk(
            fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const Spacer(),
          if (portList.isNotEmpty)
            Text('${portList.where((p) => p['up'] == true).length}/${portList.length} up',
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppTheme.success)),
        ]),
        const SizedBox(height: 12),
        portList.isEmpty
          ? Text('Detecting ports...', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: c.textMuted))
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: portList.map((p) => _PortDot(port: p, c: c)).toList(),
            ),
      ]),
    );
  }
}

class _PortDot extends StatelessWidget {
  final Map<String, dynamic> port;
  final AppColors c;
  const _PortDot({required this.port, required this.c});

  @override
  Widget build(BuildContext context) {
    final label = port['port'] as String;
    final up    = port['up'] as bool?;
    final speed = port['speed'] as String;
    final isWan = label == 'WAN';
    final ledColor = up == null ? c.textMuted
      : up ? (isWan ? AppTheme.info : AppTheme.success) : AppTheme.danger;

    return Column(children: [
      Container(
        width: 40, height: 32,
        decoration: BoxDecoration(
          color: up == true
            ? (isWan ? AppTheme.info.withOpacity(0.10) : AppTheme.success.withOpacity(0.08))
            : c.card2,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: up == true
              ? (isWan ? AppTheme.info.withOpacity(0.4) : AppTheme.success.withOpacity(0.3))
              : c.border,
            width: 1.5,
          ),
        ),
        child: Stack(alignment: Alignment.center, children: [
          Icon(isWan ? Icons.language_rounded : Icons.settings_ethernet_rounded,
            size: 15, color: up == true ? ledColor : c.textMuted),
          Positioned(top: 3, right: 3,
            child: StatusDot(color: ledColor, size: 5, glow: up == true)),
        ]),
      ),
      const SizedBox(height: 5),
      Text(label, style: GoogleFonts.spaceGrotesk(
        fontSize: 9, fontWeight: FontWeight.w700,
        color: isWan ? AppTheme.info : c.textSecondary)),
      Text(up == null ? '?' : up ? (speed.isNotEmpty ? '${speed}M' : 'Up') : 'Down',
        style: GoogleFonts.jetBrainsMono(fontSize: 8, color: ledColor)),
    ]);
  }
}

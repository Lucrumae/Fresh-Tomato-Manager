import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(routerStatusProvider);
    final bandwidth = ref.watch(bandwidthProvider);
    final devices = ref.watch(devicesProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            floating: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dashboard', style: Theme.of(context).textTheme.titleLarge),
                Text(status.routerModel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: status.isOnline
                    ? AppTheme.success.withOpacity(0.1)
                    : AppTheme.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                        color: status.isOnline ? AppTheme.success : AppTheme.danger,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      status.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: status.isOnline ? AppTheme.success : AppTheme.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(delegate: SliverChildListDelegate([

              //  Status cards row 
              Builder(builder: (bCtx) {
                final acc = Theme.of(bCtx).extension<AppColors>()?.accent;
                return Row(children: [
                  Expanded(child: _StatCard(
                    label: 'CPU',
                    value: status.cpuUsage,
                    sublabel: status.cpuTempC > 0 ? status.cpuTemp : null,
                    sublabelColor: status.cpuTempC >= 70 ? AppTheme.danger
                      : status.cpuTempC >= 50 ? AppTheme.warning : AppTheme.success,
                    percent: status.cpuPercent / 100,
                    color: _percentColor(status.cpuPercent, acc),
                    icon: Icons.memory_rounded,
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(
                    label: 'RAM',
                    value: status.ramUsage,
                    sublabel: '/ ${status.ramTotal}',
                    percent: status.ramPercent / 100,
                    color: _percentColor(status.ramPercent, acc),
                    icon: Icons.storage_rounded,
                  )),
                ]);
              }),
              const SizedBox(height: 12),

              //  Bandwidth quick view 
              _BandwidthCard(bandwidth: bandwidth)
                ,
              const SizedBox(height: 12),

              //  Network info - tap to open WiFi settings 
              AppCard(
                onTap: () => _showWifiSettings(context, ref, status, accent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('Network', style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      Icon(Icons.settings_rounded, size: 14, color: accent.withOpacity(0.5)),
                    ]),
                    const SizedBox(height: 14),
                    _InfoRow(icon: Icons.language_rounded, label: 'WAN IP', value: status.wanIp),
                    const SizedBox(height: 10),
                    _InfoRow(icon: Icons.home_rounded, label: 'LAN IP', value: status.lanIp),
                    const SizedBox(height: 10),
                    // WiFi 2.4GHz row with LED
                    _WifiRow(
                      label: 'WiFi 2.4GHz',
                      ssid: status.wifiSsid,
                      enabled: status.wifi24enabled,
                      accent: accent,
                    ),
                    // WiFi 5GHz row - only if present
                    if (status.wifi5present) ...[
                      const SizedBox(height: 10),
                      _WifiRow(
                        label: 'WiFi 5GHz',
                        ssid: status.wifiSsid5,
                        enabled: status.wifi5enabled,
                        accent: accent,
                      ),
                    ],
                    const SizedBox(height: 10),
                    _InfoRow(icon: Icons.schedule_rounded, label: 'Uptime', value: status.uptime),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              //  Quick stats 
              Row(children: [
                Expanded(child: _QuickStat(
                  icon: Icons.devices_rounded,
                  value: '${devices.length}',
                  label: 'Devices',
                  color: AppTheme.primary,
                )),
                const SizedBox(width: 12),
                Expanded(child: _QuickStat(
                  icon: Icons.block_rounded,
                  value: '${devices.where((d) => d.isBlocked).length}',
                  label: 'Blocked',
                  color: AppTheme.danger,
                )),
                const SizedBox(width: 12),
                Expanded(child: _QuickStat(
                  icon: Icons.wifi_rounded,
                  value: '${devices.where((d) => d.isWireless).length}',
                  label: 'WiFi',
                  color: AppTheme.success,
                )),
              ]),
              const SizedBox(height: 12),

              //  Firmware 
              AppCard(
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.system_update_rounded, color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Firmware', style: Theme.of(context).textTheme.titleSmall),
                        Text(status.firmware, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    )),
                  ],
                ),
              ),

              const SizedBox(height: 80),
            ])),
          ),
        ],
      ),
    );
  }

  Color _percentColor(double p, [Color? accent]) {
    if (p > 80) return AppTheme.danger;
    if (p > 60) return AppTheme.warning;
    return accent ?? AppTheme.success;
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final String? sublabel;
  final Color? sublabelColor;
  final double percent;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label, required this.value, this.sublabel,
    this.sublabelColor,
    required this.percent, required this.color, required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: Theme.of(context).extension<AppColors>()!.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              if (sublabel != null)
                Row(children: [
                  if (sublabelColor != null)
                    Icon(Icons.thermostat_rounded, size: 12, color: sublabelColor),
                  Text(sublabel!,
                    style: sublabelColor != null
                      ? TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sublabelColor)
                      : Theme.of(context).textTheme.bodySmall),
                ]),
            ],
          ),
          const SizedBox(height: 10),
          _AnimatedBar(percent: percent.clamp(0.0, 1.0), color: color),
        ],
      ),
    );
  }
}

class _BandwidthCard extends StatelessWidget {
  final BandwidthStats bandwidth;
  const _BandwidthCard({required this.bandwidth});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Bandwidth', style: Theme.of(context).textTheme.titleSmall),
              Text('Live', style: TextStyle(
                fontSize: 11, color: AppTheme.success, fontWeight: FontWeight.w600,
              )),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _BwStat(
              label: 'Down Download',
              value: _fmt(bandwidth.currentRx),
              color: Theme.of(context).extension<AppColors>()?.accent ?? AppTheme.primary,
            )),
            Expanded(child: _BwStat(
              label: 'Up Upload',
              value: _fmt(bandwidth.currentTx),
              color: AppTheme.secondary,
            )),
          ]),
        ],
      ),
    );
  }

  String _fmt(double kbps) {
    if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(1)} Mbps';
    return '${kbps.toStringAsFixed(0)} Kbps';
  }
}

class _BwStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _BwStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w700, color: color,
      )),
    ],
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: Theme.of(context).extension<AppColors>()!.textMuted),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      Text(value, style: Theme.of(context).textTheme.labelLarge),
    ],
  );
}

// Smooth animated progress bar - properly tracks value changes
class _AnimatedBar extends StatefulWidget {
  final double percent;
  final Color color;
  const _AnimatedBar({required this.percent, required this.color});
  @override
  State<_AnimatedBar> createState() => _AnimatedBarState();
}

class _AnimatedBarState extends State<_AnimatedBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  double _prev = 0;

  @override
  void initState() {
    super.initState();
    _prev = widget.percent;
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _anim = Tween(begin: widget.percent, end: widget.percent).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_AnimatedBar old) {
    super.didUpdateWidget(old);
    if ((widget.percent - _prev).abs() > 0.001) {
      _anim = Tween(begin: _prev, end: widget.percent).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
      _ctrl.forward(from: 0);
      _prev = widget.percent;
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _anim.value,
            backgroundColor: AppTheme.border,
            valueColor: AlwaysStoppedAnimation(widget.color),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text('${(_anim.value * 100).toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 11, color: widget.color,
              fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

class _QuickStat extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color color;
  const _QuickStat({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

// WiFi row with LED indicator
class _WifiRow extends StatelessWidget {
  final String label;
  final String ssid;
  final bool enabled;
  final Color accent;
  const _WifiRow({required this.label, required this.ssid,
    required this.enabled, required this.accent});

  @override
  Widget build(BuildContext context) {
    final ledColor = enabled ? AppTheme.success : AppTheme.danger;
    return Row(children: [
      Icon(Icons.wifi_rounded, size: 16, color: accent),
      const SizedBox(width: 10),
      Expanded(child: Text(label,
        style: Theme.of(context).textTheme.bodySmall)),
      // LED dot
      Container(
        width: 8, height: 8,
        decoration: BoxDecoration(
          color: ledColor,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: ledColor.withOpacity(0.6),
            blurRadius: 4, spreadRadius: 1)],
        ),
      ),
      const SizedBox(width: 6),
      Text(ssid.isEmpty ? '-' : ssid,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: enabled
            ? Theme.of(context).extension<AppColors>()!.textPrimary
            : AppTheme.danger,
          fontWeight: FontWeight.w500,
        )),
    ]);
  }
}

// WiFi settings dialog
void _showWifiSettings(
    BuildContext context, WidgetRef ref, RouterStatus status, Color accent) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _WifiSettingsSheet(status: status, accent: accent),
  );
}

class _WifiSettingsSheet extends ConsumerStatefulWidget {
  final RouterStatus status;
  final Color accent;
  const _WifiSettingsSheet({required this.status, required this.accent});
  @override
  ConsumerState<_WifiSettingsSheet> createState() => _WifiSettingsSheetState();
}

class _WifiSettingsSheetState extends ConsumerState<_WifiSettingsSheet> {
  bool _saving = false;
  String? _msg;

  // 2.4GHz controllers
  late TextEditingController _ssid24;
  late TextEditingController _pass24;
  late TextEditingController _ch24;
  late bool _radio24;
  late String _sec24;

  // 5GHz controllers
  late TextEditingController _ssid5;
  late TextEditingController _pass5;
  late TextEditingController _ch5;
  late bool _radio5;
  late String _sec5;

  @override
  void initState() {
    super.initState();
    _ssid24  = TextEditingController(text: widget.status.wifiSsid);
    _pass24  = TextEditingController();
    _ch24    = TextEditingController();
    _radio24 = widget.status.wifi24enabled;
    _sec24   = 'psk2';

    _ssid5  = TextEditingController(text: widget.status.wifiSsid5);
    _pass5  = TextEditingController();
    _ch5    = TextEditingController();
    _radio5 = widget.status.wifi5enabled;
    _sec5   = 'psk2';

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
      if (mounted) setState(() {
        if (parts.length > 0) _pass24.text = parts[0];
        if (parts.length > 1) _ch24.text   = parts[1];
        if (parts.length > 2) _sec24       = parts[2].isEmpty ? 'psk2' : parts[2];
        if (parts.length > 3) _pass5.text  = parts[3];
        if (parts.length > 4) _ch5.text    = parts[4];
        if (parts.length > 5) _sec5        = parts[5].isEmpty ? 'psk2' : parts[5];
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final ssh = ref.read(sshServiceProvider);
    setState(() { _saving = true; _msg = null; });
    try {
      final cmds = <String>[
        "nvram set wl0_ssid='${_ssid24.text}'",
        "nvram set wl0_radio=${_radio24 ? 1 : 0}",
        "nvram set wl0_security_mode='$_sec24'",
        if (_pass24.text.isNotEmpty) "nvram set wl0_wpa_psk='${_pass24.text}'",
        if (_ch24.text.isNotEmpty)   "nvram set wl0_channel='${_ch24.text}'",
      ];
      if (widget.status.wifi5present) {
        cmds.addAll([
          "nvram set wl1_ssid='${_ssid5.text}'",
          "nvram set wl1_radio=${_radio5 ? 1 : 0}",
          "nvram set wl1_security_mode='$_sec5'",
          if (_pass5.text.isNotEmpty) "nvram set wl1_wpa_psk='${_pass5.text}'",
          if (_ch5.text.isNotEmpty)   "nvram set wl1_channel='${_ch5.text}'",
        ]);
      }
      cmds.add('nvram commit');
      await ssh.run(cmds.join(' && '));
      // Restart wireless
      ssh.run('(service wireless restart > /dev/null 2>&1 &)').catchError((_){});
      setState(() => _msg = 'Saved! Applying WiFi settings...');
      // Refresh status
      await Future.delayed(const Duration(seconds: 2));
      ref.invalidate(routerStatusProvider);
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
    final secLabels = {
      'open': 'Open (No Password)',
      'psk':  'WPA Personal',
      'psk2': 'WPA2 Personal',
      'psk psk2': 'WPA/WPA2 Mixed',
      'wpa':  'WPA Enterprise',
      'wpa2': 'WPA2 Enterprise',
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: c.textMuted.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(children: [
              Icon(Icons.wifi_rounded, color: widget.accent, size: 20),
              const SizedBox(width: 8),
              Text('WiFi Settings',
                style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              _saving
                ? const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(
                    onPressed: _save,
                    child: Text('Save',
                      style: TextStyle(color: widget.accent))),
            ]),
          ),
          if (_msg != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _msg!.startsWith('Error')
                  ? AppTheme.danger.withOpacity(0.12)
                  : AppTheme.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _msg!.startsWith('Error')
                  ? AppTheme.danger : AppTheme.success),
              ),
              child: Text(_msg!, style: TextStyle(fontSize: 12,
                color: _msg!.startsWith('Error') ? AppTheme.danger : AppTheme.success)),
            ),
          Expanded(child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              // --- 2.4GHz ---
              _sectionHeader(context, '2.4 GHz', _radio24,
                widget.status.wifi24enabled, (v) => setState(() => _radio24 = v)),
              const SizedBox(height: 8),
              _field(context, 'SSID', _ssid24, c),
              const SizedBox(height: 8),
              _field(context, 'Password', _pass24, c, obscure: true),
              const SizedBox(height: 8),
              _field(context, 'Channel (0=auto)', _ch24, c,
                keyboard: TextInputType.number),
              const SizedBox(height: 8),
              _dropdown(context, 'Security', _sec24, secOpts, secLabels, c,
                (v) => setState(() => _sec24 = v)),

              if (widget.status.wifi5present) ...[

                const SizedBox(height: 20),
                // --- 5GHz ---
                _sectionHeader(context, '5 GHz', _radio5,
                  widget.status.wifi5enabled, (v) => setState(() => _radio5 = v)),
                const SizedBox(height: 8),
                _field(context, 'SSID', _ssid5, c),
                const SizedBox(height: 8),
                _field(context, 'Password', _pass5, c, obscure: true),
                const SizedBox(height: 8),
                _field(context, 'Channel (0=auto)', _ch5, c,
                  keyboard: TextInputType.number),
                const SizedBox(height: 8),
                _dropdown(context, 'Security', _sec5, secOpts, secLabels, c,
                  (v) => setState(() => _sec5 = v)),
              ],
            ],
          )),
        ]),
      ),
    );
  }

  Widget _sectionHeader(BuildContext ctx, String band, bool radioVal,
      bool currentState, ValueChanged<bool> onChanged) {
    final ledColor = currentState ? AppTheme.success : AppTheme.danger;
    return Row(children: [
      Container(width: 8, height: 8,
        decoration: BoxDecoration(color: ledColor, shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: ledColor.withOpacity(0.6),
            blurRadius: 4, spreadRadius: 1)])),
      const SizedBox(width: 8),
      Text('WiFi $band',
        style: Theme.of(ctx).textTheme.titleSmall),
      const Spacer(),
      Text(radioVal ? 'Enabled' : 'Disabled',
        style: TextStyle(fontSize: 12,
          color: radioVal ? AppTheme.success : AppTheme.danger)),
      const SizedBox(width: 8),
      Switch(
        value: radioVal,
        onChanged: onChanged,
        activeColor: widget.accent,
      ),
    ]);
  }

  Widget _field(BuildContext ctx, String label, TextEditingController ctrl,
      AppColors c, {bool obscure = false,
      TextInputType keyboard = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboard,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: c.textMuted, fontSize: 13),
        filled: true,
        fillColor: c.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _dropdown(BuildContext ctx, String label, String value,
      List<String> opts, Map<String, String> labels,
      AppColors c, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      value: opts.contains(value) ? value : opts[2],
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: c.textMuted, fontSize: 13),
        filled: true,
        fillColor: c.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12),
      ),
      items: opts.map((o) => DropdownMenuItem(
        value: o,
        child: Text(labels[o] ?? o, style: const TextStyle(fontSize: 13)),
      )).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }
}

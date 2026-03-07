import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

/// VPN Screen
/// Strategy: auto-detect jika user di luar wifi rumah → tawarkan koneksi VPN
/// FreshTomato mendukung OpenVPN server bawaan — user tinggal export .ovpn dari router

class VpnScreen extends ConsumerStatefulWidget {
  const VpnScreen({super.key});
  @override
  ConsumerState<VpnScreen> createState() => _VpnScreenState();
}

class _VpnScreenState extends ConsumerState<VpnScreen> {
  bool _vpnEnabled = false;
  String _status = 'Disconnected';
  String _ovpnContent = '';
  final _ovpnCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = ref.read(configProvider);
    if (config != null) {
      setState(() {
        _vpnEnabled = config.vpnEnabled;
        _ovpnContent = config.vpnConfig;
        _ovpnCtrl.text = config.vpnConfig;
      });
    }
  }

  Future<void> _saveConfig() async {
    final config = ref.read(configProvider);
    if (config == null) return;
    final newConfig = RouterConfig(
      host: config.host,
      username: config.username,
      password: config.password,
      port: config.port,
      useHttps: config.useHttps,
      vpnEnabled: _vpnEnabled,
      vpnConfig: _ovpnCtrl.text,
    );
    await ref.read(configProvider.notifier).save(newConfig);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('VPN', style: Theme.of(context).textTheme.titleLarge),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // Status card
          AppCard(
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: _vpnEnabled
                    ? AppTheme.success.withOpacity(0.1)
                    : AppTheme.border,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.vpn_lock_rounded,
                  color: _vpnEnabled ? AppTheme.success : AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('VPN Status', style: Theme.of(context).textTheme.titleSmall),
                  Text(_status, style: TextStyle(
                    color: _vpnEnabled ? AppTheme.success : AppTheme.textMuted,
                    fontSize: 13,
                  )),
                ],
              )),
              Switch(
                value: _vpnEnabled,
                onChanged: (v) => setState(() {
                  _vpnEnabled = v;
                  _status = v ? 'Connected' : 'Disconnected';
                  _saveConfig();
                }),
                activeColor: AppTheme.primary,
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // How to setup info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.info_rounded, color: AppTheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Text('How to set up VPN', style: TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 14,
                  )),
                ]),
                const SizedBox(height: 12),
                ..._steps([
                  'Buka router admin web UI',
                  'Pergi ke VPN → OpenVPN Server',
                  'Enable OpenVPN Server, konfigurasi port (default 1194)',
                  'Download file .ovpn dari halaman tersebut',
                  'Paste isi file .ovpn di kolom di bawah',
                  'Aktifkan toggle VPN di atas',
                ]),
                const SizedBox(height: 8),
                Text(
                  'Saat berada di luar jaringan WiFi rumah, app akan otomatis mengingatkan untuk mengaktifkan VPN.',
                  style: TextStyle(color: AppTheme.primary.withOpacity(0.8), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // .ovpn paste area
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('OpenVPN Config (.ovpn)', style: Theme.of(context).textTheme.titleSmall),
                    if (_ovpnCtrl.text.isNotEmpty)
                      StatusBadge(label: '✓ Loaded', color: AppTheme.success),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ovpnCtrl,
                  maxLines: 8,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  decoration: const InputDecoration(
                    hintText: 'Paste isi file .ovpn di sini...',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await _saveConfig();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('VPN config saved')),
                        );
                      }
                    },
                    child: const Text('Save Config'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Auto-connect info
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Auto-Connect', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(
                  'App mendeteksi apakah kamu terhubung ke WiFi rumah secara otomatis. '
                  'Jika terdeteksi di jaringan mobile/luar, app akan menampilkan notifikasi untuk mengaktifkan VPN agar router tetap bisa diakses.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                _NetworkStatus(),
              ],
            ),
          ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  List<Widget> _steps(List<String> steps) => steps.asMap().entries.map((e) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(
              '${e.key + 1}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary),
            )),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(e.value, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
        ],
      ),
    )
  ).toList();
}

class _NetworkStatus extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netAsync = ref.watch(networkTypeProvider);

    return netAsync.when(
      data: (result) {
        final isWifi = result == ConnectivityResult.wifi;
        return Row(children: [
          Icon(
            isWifi ? Icons.wifi_rounded : Icons.signal_cellular_alt_rounded,
            size: 16,
            color: isWifi ? AppTheme.success : AppTheme.warning,
          ),
          const SizedBox(width: 8),
          Text(
            isWifi ? 'Connected via WiFi — VPN not required' : 'Mobile/External network — VPN recommended',
            style: TextStyle(
              fontSize: 12,
              color: isWifi ? AppTheme.success : AppTheme.warning,
              fontWeight: FontWeight.w500,
            ),
          ),
        ]);
      },
      loading: () => const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => const Text('Cannot detect network', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
    );
  }
}

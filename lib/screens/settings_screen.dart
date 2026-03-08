import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import 'setup_screen.dart';
import 'qos_screen.dart';
import 'port_forward_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _backupBusy   = false;
  bool _restoreBusy  = false;
  bool _resetBusy    = false;
  String? _statusMsg;
  bool _statusIsError = false;

  void _showStatus(String msg, {bool error = false}) {
    setState(() { _statusMsg = msg; _statusIsError = error; });
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _statusMsg = null);
    });
  }

  //  Backup 
  Future<void> _backup() async {
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) { _showStatus('Not connected', error: true); return; }
    setState(() => _backupBusy = true);
    try {
      // Ask router for config backup (same as web UI Administration > Backup)
      // FreshTomato stores config in nvram; export via 'nvram show' or cfg backup
      // The web backup downloads /tmp/tomato.cfg - trigger generation first
      await ssh.run('nvram save /tmp/tomato.cfg 2>/dev/null || true');
      final cfgB64 = await ssh.run(
        'base64 /tmp/tomato.cfg 2>/dev/null || nvram show | base64');

      // Decode base64
      final bytes = _decodeBase64Loose(cfgB64.trim());

      // Save to Downloads/TomatoManager/Backup/
      final savePath = await _resolveDownloadPath('Backup');
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
      final file = File('$savePath/tomato_$ts.cfg');
      await file.writeAsBytes(bytes);
      _showStatus('Saved to ${file.path}');
    } catch (e) {
      _showStatus('Backup failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  //  Restore 
  Future<void> _restore() async {
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) { _showStatus('Not connected', error: true); return; }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Select .cfg backup file',
    );
    if (result == null || result.files.single.path == null) return;

    final confirm = await _confirm(
      'Restore Configuration',
      'This will overwrite router settings and reboot. Continue?',
      confirmColor: AppTheme.warning,
      confirmLabel: 'Restore',
    );
    if (confirm != true) return;

    setState(() => _restoreBusy = true);
    try {
      final fileBytes = await File(result.files.single.path!).readAsBytes();
      // Upload via base64 to avoid binary SSH issues
      final b64 = _encodeBase64(fileBytes);
      // Write in chunks to avoid command length limits
      await ssh.run('rm -f /tmp/restore.cfg.b64');
      const chunkSize = 2000;
      for (var i = 0; i < b64.length; i += chunkSize) {
        final chunk = b64.substring(i, i + chunkSize > b64.length ? b64.length : i + chunkSize);
        final op = i == 0 ? '>' : '>>';
        await ssh.run("echo '$chunk' $op /tmp/restore.cfg.b64");
      }
      // Decode and restore
      await ssh.run('base64 -d /tmp/restore.cfg.b64 > /tmp/tomato.cfg');
      await ssh.run('nvram restore /tmp/tomato.cfg 2>/dev/null || true');
      await ssh.run('nvram commit');
      // Reboot after restore
      ssh.run('reboot').catchError((_) {});
      _showStatus('Restored! Router is rebooting...');
    } catch (e) {
      _showStatus('Restore failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _restoreBusy = false);
    }
  }

  //  NVRAM Reset 
  Future<void> _nvramReset() async {
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) { _showStatus('Not connected', error: true); return; }

    final confirm = await _confirm(
      'Reset NVRAM',
      'This will erase ALL router settings and restore factory defaults. The router will reboot. This cannot be undone.',
      confirmColor: AppTheme.danger,
      confirmLabel: 'Reset',
    );
    if (confirm != true) return;

    // Double confirm for destructive action
    final confirm2 = await _confirm(
      'Are you sure?',
      'NVRAM reset is irreversible. All custom settings will be lost.',
      confirmColor: AppTheme.danger,
      confirmLabel: 'Yes, Reset',
    );
    if (confirm2 != true) return;

    setState(() => _resetBusy = true);
    try {
      await ssh.run('mtd-erase2 nvram 2>/dev/null || nvram erase');
      ssh.run('reboot').catchError((_) {});
      _showStatus('NVRAM erased. Router is rebooting...');
    } catch (e) {
      _showStatus('Reset failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  Future<bool?> _confirm(String title, String msg, {
    required Color confirmColor, required String confirmLabel}) =>
    showDialog<bool>(context: context, builder: (_) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(title),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel, style: const TextStyle(color: Colors.white)),
        ),
      ],
    ));

  Future<String> _resolveDownloadPath(String sub) async {
    // Android: /storage/emulated/0/Download/TomatoManager/<sub>
    // iOS: app Documents directory
    String base;
    if (Platform.isAndroid) {
      if (await Permission.storage.request().isGranted ||
          await Permission.manageExternalStorage.request().isGranted) {
        base = '/storage/emulated/0/Download/TomatoManager/$sub';
      } else {
        final dir = await getApplicationDocumentsDirectory();
        base = '${dir.path}/TomatoManager/$sub';
      }
    } else {
      final dir = await getApplicationDocumentsDirectory();
      base = '${dir.path}/TomatoManager/$sub';
    }
    await Directory(base).create(recursive: true);
    return base;
  }

  List<int> _decodeBase64Loose(String s) {
    // Handle line breaks in base64
    final clean = s.replaceAll(RegExp(r'\s'), '');
    // Pad to multiple of 4
    final padded = clean + '=' * ((4 - clean.length % 4) % 4);
    // Dart base64 decode
    final b64 = padded;
    final result = <int>[];
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    for (var i = 0; i < b64.length - 3; i += 4) {
      final a = chars.indexOf(b64[i]);
      final bv = chars.indexOf(b64[i+1]);
      final cv = b64[i+2] == '=' ? 0 : chars.indexOf(b64[i+2]);
      final dv = b64[i+3] == '=' ? 0 : chars.indexOf(b64[i+3]);
      if (a < 0 || bv < 0) continue;
      result.add((a << 2) | (bv >> 4));
      if (b64[i+2] != '=') result.add(((bv & 0xf) << 4) | (cv >> 2));
      if (b64[i+3] != '=') result.add(((cv & 0x3) << 6) | dv);
    }
    return result;
  }

  String _encodeBase64(List<int> bytes) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final sb = StringBuffer();
    for (var i = 0; i < bytes.length; i += 3) {
      final b0 = bytes[i];
      final b1 = i+1 < bytes.length ? bytes[i+1] : 0;
      final b2 = i+2 < bytes.length ? bytes[i+2] : 0;
      sb.write(chars[b0 >> 2]);
      sb.write(chars[((b0 & 3) << 4) | (b1 >> 4)]);
      sb.write(i+1 < bytes.length ? chars[((b1 & 0xf) << 2) | (b2 >> 6)] : '=');
      sb.write(i+2 < bytes.length ? chars[b2 & 0x3f] : '=');
    }
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l      = AppL10n.of(context);
    final config = ref.watch(configProvider);
    final isDark = ref.watch(darkModeProvider);
    final accent = ref.watch(accentProvider);
    final c      = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.settings, style: Theme.of(context).textTheme.titleLarge),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // Status message
          if (_statusMsg != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _statusIsError
                  ? AppTheme.danger.withOpacity(0.15)
                  : AppTheme.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _statusIsError ? AppTheme.danger : AppTheme.success),
              ),
              child: Row(children: [
                Icon(_statusIsError ? Icons.error_outline : Icons.check_circle_outline,
                  size: 16, color: _statusIsError ? AppTheme.danger : AppTheme.success),
                const SizedBox(width: 8),
                Expanded(child: Text(_statusMsg!, style: TextStyle(fontSize: 12,
                  color: _statusIsError ? AppTheme.danger : AppTheme.success))),
              ]),
            ),

          //  Connection 
          AppCard(
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withOpacity(isDark ? 0.15 : 1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.terminal_rounded, color: AppTheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(config?.host ?? '-', style: Theme.of(context).textTheme.titleSmall),
                  Text('${config?.username ?? 'root'}  | SSH :${config?.sshPort ?? 22}',
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              TextButton(
                onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SetupScreen())),
                child: Text(l.btnChange),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          //  Display 
          _label(context, l.display),
          const SizedBox(height: 8),
          AppCard(
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
                  color: AppTheme.secondary, size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.darkMode, style: Theme.of(context).textTheme.titleSmall),
                  Text(isDark ? l.darkModeOn : l.darkModeOff,
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              Switch(
                value: isDark,
                activeColor: AppTheme.primary,
                onChanged: (_) => ref.read(darkModeProvider.notifier).toggle(),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: accent.main.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.palette_rounded, color: accent.main, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Accent Color', style: Theme.of(context).textTheme.titleSmall),
                      Text('Active: ${accent.label}',
                        style: Theme.of(context).textTheme.bodySmall),
                    ],
                  )),
                ]),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10, runSpacing: 10,
                  children: AccentColor.values.map((a) {
                    final selected = a == accent;
                    return GestureDetector(
                      onTap: () => ref.read(accentProvider.notifier).set(a),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: a.main,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: selected ? [
                            BoxShadow(color: a.main.withOpacity(0.5),
                              blurRadius: 8, spreadRadius: 2)
                          ] : null,
                        ),
                        child: selected
                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                          : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          //  Network 
          _label(context, l.network),
          const SizedBox(height: 8),
          _tile(context, l,
            icon: Icons.speed_rounded, color: AppTheme.secondary,
            title: l.qosRules, subtitle: l.qosSubtitle,
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const QosScreen())),
          ),
          const SizedBox(height: 8),
          _tile(context, l,
            icon: Icons.lan_rounded, color: AppTheme.success,
            title: l.portForward, subtitle: l.portForwardSubtitle,
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PortForwardScreen())),
          ),

          const SizedBox(height: 20),

          //  Router 
          _label(context, 'Router'),
          const SizedBox(height: 8),
          _tile(context, l,
            icon: Icons.restart_alt_rounded, color: AppTheme.warning,
            title: l.rebootRouter, subtitle: l.rebootSubtitle,
            onTap: () => _confirmReboot(context, ref, l),
          ),

          const SizedBox(height: 20),

          //  Configuration 
          _label(context, 'Configuration'),
          const SizedBox(height: 8),

          // Backup
          AppCard(
            onTap: _backupBusy ? null : _backup,
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _backupBusy
                  ? const Padding(padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded, color: AppTheme.success, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Backup Configuration',
                    style: Theme.of(context).textTheme.titleSmall),
                  Text('Download .cfg to Downloads/TomatoManager/Backup',
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ]),
          ),
          const SizedBox(height: 8),

          // Restore
          AppCard(
            onTap: _restoreBusy ? null : _restore,
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.secondary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _restoreBusy
                  ? const Padding(padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file_rounded, color: AppTheme.secondary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Restore Configuration',
                    style: Theme.of(context).textTheme.titleSmall),
                  Text('Upload .cfg backup file to router',
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ]),
          ),
          const SizedBox(height: 8),

          // NVRAM Reset
          AppCard(
            onTap: _resetBusy ? null : _nvramReset,
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _resetBusy
                  ? const Padding(padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.danger))
                  : const Icon(Icons.delete_forever_rounded, color: AppTheme.danger, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Reset NVRAM', style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(color: AppTheme.danger)),
                  Text('Erase all settings and restore factory defaults',
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              Icon(Icons.chevron_right_rounded, color: c.textMuted),
            ]),
          ),

          const SizedBox(height: 20),

          //  App 
          _label(context, 'App'),
          const SizedBox(height: 8),
          _tile(context, l,
            icon: Icons.logout_rounded, color: AppTheme.danger,
            title: l.btnDisconnect, subtitle: l.disconnectMessage,
            onTap: () => _confirmDisconnect(context, ref, l),
          ),

          const SizedBox(height: 32),
          Center(child: Text('Tomato Manager v1.0.0',
            style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String text) =>
    Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).extension<AppColors>()!.textMuted,
      fontWeight: FontWeight.w600, letterSpacing: 0.5,
    ));

  Widget _tile(BuildContext context, AppL10n l, {
    required IconData icon, required Color color,
    required String title, required String subtitle,
    required VoidCallback onTap,
  }) => AppCard(
    onTap: onTap,
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      )),
      Icon(Icons.chevron_right_rounded,
        color: Theme.of(context).extension<AppColors>()!.textMuted),
    ]),
  );

  void _confirmReboot(BuildContext context, WidgetRef ref, AppL10n l) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: Text(l.rebootConfirm),
      content: Text(l.rebootMessage),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.btnCancel)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warning),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.btnReboot),
        ),
      ],
    ));
    if (ok == true) {
      await ref.read(sshServiceProvider).reboot();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.rebootSent)));
    }
  }

  void _confirmDisconnect(BuildContext context, WidgetRef ref, AppL10n l) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: Text(l.disconnectConfirm),
      content: Text(l.disconnectMessage),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.btnCancel)),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
          onPressed: () => Navigator.pop(context, true),
          child: Text(l.btnDisconnect),
        ),
      ],
    ));
    if (ok == true) {
      ref.read(routerStatusProvider.notifier).stopPolling();
      ref.read(devicesProvider.notifier).stopPolling();
      ref.read(bandwidthProvider.notifier).stopPolling();
      await ref.read(sshServiceProvider).disconnect();
      await ref.read(configProvider.notifier).clear();
      if (context.mounted) Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SetupScreen()), (_) => false,
      );
    }
  }
}

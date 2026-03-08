import 'dart:io';
import 'dart:async';
import 'dart:convert';
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
  bool _firmwareBusy = false;

  //  Backup 
  Future<void> _backup() async {
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected to router'),
        backgroundColor: AppTheme.danger));
      return;
    }
    setState(() => _backupBusy = true);
    try {
      // Tulis nvram ke file di router dulu
      await ssh.run('nvram show > /tmp/nvram_backup.cfg 2>/dev/null');
      final sizeStr = (await ssh.run(
        'wc -c < /tmp/nvram_backup.cfg 2>/dev/null || echo 0')).trim();
      final size = int.tryParse(sizeStr.split(RegExp(r'\s+')).first) ?? 0;
      if (size < 10) throw Exception('nvram show returned empty output');

      // HP buka HTTP server, router curl/wget upload file ke HP
      final httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port = httpServer.port;
      final localIp = await _getLocalIp();
      if (localIp == null) {
        await httpServer.close(force: true);
        throw Exception('Cannot determine local IP address');
      }

      // Terima file dari router
      final completer = Completer<List<int>>();
      httpServer.listen((req) async {
        final bytes = <int>[];
        await for (final chunk in req) { bytes.addAll(chunk); }
        req.response.statusCode = 200;
        await req.response.close();
        await httpServer.close(force: true);
        completer.complete(bytes);
      });

      // Router POST file backup ke HP via curl/wget
      await ssh.run(
        'curl -s -X POST --data-binary @/tmp/nvram_backup.cfg '
        'http://$localIp:$port/backup 2>/dev/null || '
        'wget -q -O /dev/null --post-file=/tmp/nvram_backup.cfg '
        'http://$localIp:$port/backup 2>/dev/null'
      );

      final bytes = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          httpServer.close(force: true);
          throw Exception('Backup transfer timeout');
        },
      );

      if (bytes.isEmpty) throw Exception('Received empty backup data');

      // Simpan ke Downloads/TomatoManager/Backup/
      final savePath = await _resolveDownloadPath('Backup');
      final ts = DateTime.now().toIso8601String()
          .replaceAll(':', '-').substring(0, 19);
      final file = File('$savePath/tomato_$ts.cfg');
      await file.writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saved: tomato_$ts.cfg  (${bytes.length} bytes)'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Backup failed: $e'),
          backgroundColor: AppTheme.danger,
          duration: const Duration(seconds: 4),
        ));
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }
  //  Restore 
  Future<void> _restore() async {
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected to router'),
        backgroundColor: AppTheme.danger)); return; }

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
      // Baca file backup sebagai bytes dulu untuk deteksi format
      final fileBytes = await File(result.files.single.path!).readAsBytes();

      // Deteksi format dari bytes:
      // - Text (nvram show): byte pertama adalah ASCII printable
      // - Binary (web UI cfg): dimulai dengan magic bytes non-ASCII
      final firstByte = fileBytes.isNotEmpty ? fileBytes[0] : 0;
      final isText = firstByte >= 32 && firstByte < 127 &&
          String.fromCharCodes(fileBytes.take(20))
              .contains(RegExp(r'^[a-zA-Z0-9_]'));

      final lines = isText
          ? utf8.decode(fileBytes, allowMalformed: true).split('\n')
          : <String>[];

      int restored = 0;
      if (isText) {
        // Format text (nvram show) - set tiap key satu per satu
        // Kirim dalam batch 10 key per command untuk efisiensi
        final cmds = <String>[];
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final eqIdx = trimmed.indexOf('=');
          if (eqIdx < 1) continue;
          final key = trimmed.substring(0, eqIdx);
          final val = trimmed.substring(eqIdx + 1);
          // Skip read-only / hardware keys
          if (key.startsWith('wl') && key.contains('_hwaddr')) continue;
          if (key == 'et0macaddr' || key == 'il0macaddr') continue;
          final escapedVal = val.replaceAll("'", "'\''");
          cmds.add("nvram set '$key'='$escapedVal'");
          restored++;
        }
        // Kirim 20 set per SSH call
        const batch = 20;
        for (var i = 0; i < cmds.length; i += batch) {
          final end = (i + batch) > cmds.length ? cmds.length : (i + batch);
          final batchCmd = cmds.sublist(i, end).join(' && ');
          await ssh.run(batchCmd);
        }
        await ssh.run('nvram commit');
      } else {
        // Format binary - upload dan pakai nvram restore
        final b64 = base64Encode(fileBytes);
        await ssh.run('rm -f /tmp/restore.cfg.b64');
        const chunkSize = 2000;
        for (var i = 0; i < b64.length; i += chunkSize) {
          final end = (i + chunkSize) > b64.length ? b64.length : (i + chunkSize);
          final chunk = b64.substring(i, end);
          final op = i == 0 ? '>' : '>>';
          await ssh.run("printf '%s' '$chunk' $op /tmp/restore.cfg.b64");
        }
        await ssh.run('base64 -d /tmp/restore.cfg.b64 > /tmp/tomato.cfg');
        await ssh.run('nvram restore /tmp/tomato.cfg');
        await ssh.run('nvram commit');
        restored = -1;
      }

      // nvram commit dulu baru reboot (sama seperti manual)
      ssh.run('nvram commit && reboot').catchError((_) {});
      if (mounted) {
        final msg = restored > 0
            ? 'Restored $restored keys! Router is rebooting...'
            : 'Configuration restored! Router is rebooting...';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 5),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: AppTheme.danger,
          duration: const Duration(seconds: 4),
        ));
      }
    } finally {
      if (mounted) setState(() => _restoreBusy = false);
    }
  }

  //  NVRAM Reset 
  Future<void> _nvramReset() async {
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected to router'),
        backgroundColor: AppTheme.danger)); return; }

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('NVRAM erased! Router is rebooting to factory defaults...'),
          backgroundColor: AppTheme.warning,
          duration: Duration(seconds: 5),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Reset failed: $e'),
          backgroundColor: AppTheme.danger,
          duration: const Duration(seconds: 4),
        ));
      }
    } finally {
      if (mounted) setState(() => _resetBusy = false);
    }
  }

  Future<String?> _getLocalIp() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      // Prefer wlan interface (connected to router via WiFi)
      for (final iface in ifaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('wlan') || name.contains('wifi') || name.contains('en')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) return addr.address;
          }
        }
      }
      // Fallback: first non-loopback IPv4
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  // -- Firmware Upgrade --
  Future<void> _upgradeFirmware() async {
    final ssh = ref.read(sshServiceProvider);
    if (!ssh.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Not connected to router'),
        backgroundColor: AppTheme.danger));
      return;
    }

    // Pick firmware file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Select firmware file (.trx, .bin, .img)',
    );
    if (result == null || result.files.single.path == null) return;

    final fwPath = result.files.single.path!;
    final fwName = result.files.single.name;
    final fwSize = result.files.single.size;
    final fwExt = fwName.toLowerCase().endsWith('.bin') ? 'bin' : 'trx';
    final fwTmp = '/tmp/upgrade.$fwExt';

    // Warn and confirm
    final sizeMB = (fwSize / 1024 / 1024).toStringAsFixed(1);
    final confirmMsg = 'File: $fwName ($sizeMB MB)\n\n'
        'This will:\n1. Force-unmount JFFS if mounted\n'
        '2. Reset NVRAM\n3. Flash the firmware\n'
        '4. Reboot router\n\nDo NOT disconnect during flash. Continue?';
    final ok = await _confirm(
      'Upgrade Firmware',
      confirmMsg,
      confirmColor: AppTheme.danger,
      confirmLabel: 'Flash Now',
    );
    if (ok != true) return;

    setState(() => _firmwareBusy = true);
    _showProgress('Preparing firmware upload...');

    try {
      // Step 1: Unmount JFFS if mounted
      _showProgress('Step 1/4: Checking JFFS...');
      final jffsCheck = await ssh.run('mount | grep jffs 2>/dev/null || echo ""');
      if (jffsCheck.trim().isNotEmpty) {
        await ssh.run('umount -f /jffs 2>/dev/null || true');
        await ssh.run('umount -l /jffs 2>/dev/null || true');
      }

      // Step 2: Reset NVRAM
      _showProgress('Step 2/4: Resetting NVRAM...');
      await ssh.run('nvram erase 2>/dev/null || mtd-erase2 nvram 2>/dev/null || true');

      // Step 3: Upload via HTTP server (router wget dari HP)
      _showProgress('Step 3/4: Starting HTTP server...');
      final fileBytes = await File(fwPath).readAsBytes();
      final totalBytes = fileBytes.length;

      // HP buka HTTP server, router wget download langsung
      final httpServer = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port = httpServer.port;
      final localIp = await _getLocalIp();
      if (localIp == null) {
        await httpServer.close(force: true);
        throw Exception('Cannot determine local IP address');
      }

      // Serve file sekali lalu tutup
      var served = false;
      httpServer.listen((req) async {
        if (served) { req.response.statusCode = 410; req.response.close(); return; }
        served = true;
        req.response.headers.contentType =
          ContentType('application', 'octet-stream');
        req.response.contentLength = totalBytes;
        req.response.add(fileBytes);
        await req.response.flush();
        await req.response.close();
      });

      final mb = (totalBytes / 1024 / 1024).toStringAsFixed(1);
      _showProgress('Step 3/4: Router downloading $mb MB...');

      // Router download dari HP
      await ssh.run('rm -f $fwTmp');
      final dlResult = await ssh.run(
        'wget -q --timeout=120 -O $fwTmp http://$localIp:$port/fw 2>&1 || '
        'curl -s --max-time 120 -o $fwTmp http://$localIp:$port/fw 2>&1'
      );
      await httpServer.close(force: true);

      // Verify ukuran file
      final uploadedSize = int.tryParse(
        (await ssh.run('wc -c < $fwTmp 2>/dev/null || echo 0')).trim()) ?? 0;
      if (uploadedSize < totalBytes - 1024) {
        throw Exception(
          'Upload gagal: $uploadedSize / $totalBytes bytes. $dlResult');
      }

      // Step 4: Flash firmware then erase nvram and reboot
      _showProgress('Step 4/4: Flashing... DO NOT DISCONNECT!');
      ssh.run(
        '(mtd-write2 $fwTmp linux || '
        'mtd write $fwTmp linux || '
        'write $fwTmp linux) && nvram erase && reboot'
      ).catchError((_) {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Firmware flashing started! Router will reboot when done. '
              'Wait 2-3 minutes before reconnecting.'),
          backgroundColor: AppTheme.warning,
          duration: Duration(seconds: 10),
        ));
        setState(() => _progressMsg = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Firmware upgrade failed: $e'),
          backgroundColor: AppTheme.danger,
          duration: const Duration(seconds: 5),
        ));
        setState(() => _progressMsg = null);
      }
    } finally {
      if (mounted) setState(() => _firmwareBusy = false);
    }
  }

  String? _progressMsg;
  void _showProgress(String msg) {
    if (mounted) setState(() => _progressMsg = msg);
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

          const SizedBox(height: 8),

          // Firmware Upgrade
          AppCard(
            onTap: _firmwareBusy ? null : _upgradeFirmware,
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _firmwareBusy
                  ? const Padding(padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2,
                        color: Color(0xFF7C3AED)))
                  : const Icon(Icons.system_update_rounded,
                      color: Color(0xFF7C3AED), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Upgrade Firmware',
                    style: Theme.of(context).textTheme.titleSmall),
                  Text('Flash .trx/.bin firmware file to router',
                    style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),

          // Progress banner firmware - dekat tombol upgrade
          if (_progressMsg != null)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.warning.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.warning),
              ),
              child: Row(children: [
                const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2,
                    color: AppTheme.warning)),
                const SizedBox(width: 10),
                Expanded(child: Text(_progressMsg!,
                  style: const TextStyle(fontSize: 13, color: AppTheme.warning))),
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

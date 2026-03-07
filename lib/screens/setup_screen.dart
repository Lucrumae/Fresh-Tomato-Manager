import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import 'main_shell.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _hostCtrl = TextEditingController(text: '192.168.1.1');
  final _userCtrl = TextEditingController(text: 'root');
  final _passCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  bool _obscure = true;
  bool _connecting = false;
  String? _error;
  int _step = 0;

  @override
  void dispose() {
    _hostCtrl.dispose(); _userCtrl.dispose();
    _passCtrl.dispose(); _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_hostCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'Isi semua field terlebih dahulu');
      return;
    }
    setState(() { _connecting = true; _error = null; });

    final config = TomatoConfig(
      host: _hostCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
      sshPort: int.tryParse(_portCtrl.text.trim()) ?? 22,
    );

    final ssh = ref.read(sshServiceProvider);
    final error = await ssh.connect(config);
    if (!mounted) return;

    if (error == null) {
      await ref.read(configProvider.notifier).save(config);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    } else {
      setState(() { _error = error; _connecting = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _step == 0 ? _buildWelcome() : _buildForm(),
      ),
    );
  }

  Widget _buildWelcome() {
    final l = AppL10n.of(context);
    final isDark = ref.watch(darkModeProvider);
    final c = Theme.of(context).extension<AppColors>()!;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dark mode toggle top right
          Align(
            alignment: Alignment.topRight,
            child: GestureDetector(
              onTap: () => ref.read(darkModeProvider.notifier).toggle(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: c.cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: c.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
                    size: 16,
                    color: isDark ? AppTheme.warning : AppTheme.secondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isDark ? 'Light' : 'Dark',
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? AppTheme.warning : AppTheme.secondary,
                    ),
                  ),
                ]),
              ),
            ),
          ),

          const Spacer(),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withOpacity(isDark ? 0.15 : 1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.router_rounded, size: 36, color: AppTheme.primary),
          ).animate().fadeIn().slideY(begin: 0.2),
          const SizedBox(height: 24),
          Text(l.appTitle,
            style: Theme.of(context).textTheme.displayLarge,
          ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.2),
          const SizedBox(height: 12),
          Text(l.appSubtitle,
            style: Theme.of(context).textTheme.bodyLarge,
          ).animate(delay: 200.ms).fadeIn(),
          const Spacer(),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _pill('📊 ${l.dashboard}'), _pill('📱 ${l.devices}'),
            _pill('📈 ${l.bandwidth}'), _pill('🚫 ${l.blockDevice}'),
            _pill('⚡ ${l.qosRules}'), _pill('🔌 ${l.portForward}'),
            _pill('📋 ${l.logs}'), _pill('🖥️ ${l.terminal}'),
          ]).animate(delay: 300.ms).fadeIn(),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _step = 1),
              child: Text(l.btnStart),
            ),
          ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.2),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _pill(String label) {
    final c = Theme.of(context).extension<AppColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.cardBg, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _buildForm() {
    final l = AppL10n.of(context);
    final isDark = ref.watch(darkModeProvider);
    final c = Theme.of(context).extension<AppColors>()!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => setState(() => _step = 0),
                child: Icon(Icons.arrow_back_rounded, color: c.textPrimary),
              ),
              // Dark mode toggle on form page too
              GestureDetector(
                onTap: () => ref.read(darkModeProvider.notifier).toggle(),
                child: Icon(
                  isDark ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
                  color: isDark ? AppTheme.warning : AppTheme.secondary,
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(l.connectTitle, style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 8),
          Text(l.connectSubtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 32),

          Text(l.fieldIp, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _hostCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: '192.168.1.1',
              prefixIcon: Icon(Icons.router_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          Text(l.fieldPort, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _portCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '22',
              prefixIcon: Icon(Icons.terminal_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          Text(l.fieldUsername, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(
              hintText: 'root',
              prefixIcon: Icon(Icons.person_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          Text(l.fieldPassword, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_rounded, size: 20),
              suffixIcon: GestureDetector(
                onTap: () => setState(() => _obscure = !_obscure),
                child: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Tips box (no VPN mention)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withOpacity(isDark ? 0.15 : 1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.info_rounded, color: AppTheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Text(l.tipsTitle, style: const TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
                const SizedBox(height: 8),
                Text(l.tipsContent,
                  style: TextStyle(color: AppTheme.primary.withOpacity(0.8), fontSize: 13)),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.danger.withOpacity(0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_rounded, color: AppTheme.danger, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!,
                    style: const TextStyle(color: AppTheme.danger, fontSize: 13))),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _connecting ? null : _connect,
              child: _connecting
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(height: 18, width: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    const SizedBox(width: 12),
                    const Text('Connecting via SSH...'),
                  ])
                : Text(l.btnConnect),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

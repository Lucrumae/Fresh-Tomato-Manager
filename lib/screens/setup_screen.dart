import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
  final _hostCtrl    = TextEditingController(text: '192.168.1.1');
  final _userCtrl    = TextEditingController(text: 'root');
  final _passCtrl    = TextEditingController();
  final _portCtrl    = TextEditingController(text: '22');
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
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: _step == 0 ? _buildWelcome() : _buildForm(),
      ),
    );
  }

  Widget _buildWelcome() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.router_rounded, size: 36, color: AppTheme.primary),
          ).animate().fadeIn().slideY(begin: 0.2),
          const SizedBox(height: 24),
          Text('Tomato\nManager',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(height: 1.1),
          ).animate(delay: 100.ms).fadeIn().slideY(begin: 0.2),
          const SizedBox(height: 16),
          Text(
            'Kelola FreshTomato router dari mana saja via SSH.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.textSecondary),
          ).animate(delay: 200.ms).fadeIn(),
          const Spacer(),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _pill('📊 Dashboard'), _pill('📱 Devices'),
            _pill('📈 Bandwidth'), _pill('🚫 Block devices'),
            _pill('⚡ QoS'), _pill('🔌 Port Forward'),
            _pill('📋 Logs'), _pill('🔐 SSH'),
          ]).animate(delay: 300.ms).fadeIn(),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('Mulai'),
            ),
          ).animate(delay: 400.ms).fadeIn().slideY(begin: 0.2),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _pill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.cardBg, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppTheme.border),
    ),
    child: Text(label, style: const TextStyle(fontSize: 13)),
  );

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() => _step = 0),
            child: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 32),
          Text('Connect via SSH', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 8),
          Text('Pastikan SSH aktif di router: Administration → Admin Access → SSH',
            style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 32),

          _label('Router IP Address'),
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

          _label('SSH Port'),
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

          _label('Username'),
          const SizedBox(height: 8),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(
              hintText: 'root',
              prefixIcon: Icon(Icons.person_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          _label('Password'),
          const SizedBox(height: 8),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: 'SSH password',
              prefixIcon: const Icon(Icons.lock_rounded, size: 20),
              suffixIcon: GestureDetector(
                onTap: () => setState(() => _obscure = !_obscure),
                child: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Info box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.info_rounded, color: AppTheme.primary, size: 16),
                  const SizedBox(width: 8),
                  Text('Tips', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
                const SizedBox(height: 8),
                Text('• Username FreshTomato biasanya: root\n'
                     '• Password = password admin router\n'
                     '• Dari luar jaringan: aktifkan VPN dulu',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.primary),
                ),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.danger),
                  )),
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
                : const Text('Connect'),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text, style: Theme.of(context).textTheme.labelLarge);
}

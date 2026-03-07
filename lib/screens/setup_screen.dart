import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/router_api.dart';
import 'main_shell.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _hostCtrl = TextEditingController(text: '192.168.1.1');
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '80');
  bool _obscure = true;
  bool _testing = false;
  String? _error;
  int _step = 0; // 0=welcome, 1=form

  @override
  void dispose() {
    _hostCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() { _testing = true; _error = null; });

    final config = TomatoConfig(
      host: _hostCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
      port: int.tryParse(_portCtrl.text) ?? 80,
    );

    final api = ref.read(apiServiceProvider);
    api.configure(config);

    String? errorMsg;
    try {
      errorMsg = await api.testConnection().timeout(
        const Duration(seconds: 12),
        onTimeout: () => 'Timeout setelah 12 detik. Pastikan IP benar dan HP terhubung ke WiFi router.',
      );
    } catch (e) {
      errorMsg = e.toString().replaceAll('Exception: ', '');
    }

    if (!mounted) return;

    if (errorMsg == null) {
      await ref.read(configProvider.notifier).save(config);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainShell()),
      );
    } else {
      setState(() {
        _error = errorMsg;
        _testing = false;
      });
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
          // Logo / icon
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
            'Monitor and manage your FreshTomato router from anywhere.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.textSecondary),
          ).animate(delay: 200.ms).fadeIn(),
          const Spacer(),
          // Feature pills
          Wrap(spacing: 8, runSpacing: 8, children: [
            _pill('📊 Dashboard'),
            _pill('📱 Devices'),
            _pill('📈 Bandwidth'),
            _pill('🔔 Notifications'),
            _pill('🔒 Block devices'),
            _pill('🌐 VPN support'),
          ]).animate(delay: 300.ms).fadeIn(),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('Get Started'),
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
      color: AppTheme.cardBg,
      borderRadius: BorderRadius.circular(20),
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
          Text('Connect Router', style: Theme.of(context).textTheme.displayMedium),
          const SizedBox(height: 8),
          Text('Enter your router\'s address and credentials',
            style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 32),

          // Router IP
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

          // Port
          _label('Port'),
          const SizedBox(height: 8),
          TextField(
            controller: _portCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '80',
              prefixIcon: Icon(Icons.lan_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          // Username
          _label('Username'),
          const SizedBox(height: 8),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(
              hintText: 'admin',
              prefixIcon: Icon(Icons.person_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          // Password
          _label('Password'),
          const SizedBox(height: 8),
          TextField(
            controller: _passCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: 'Enter password',
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
            child: Row(
              children: [
                const Icon(Icons.info_rounded, color: AppTheme.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'When outside your home network, connect via VPN first, then use your router\'s LAN IP.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.primary),
                )),
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
              onPressed: _testing ? null : _connect,
              child: _testing
                ? const SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(text,
    style: Theme.of(context).textTheme.labelLarge,
  );
}

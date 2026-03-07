import 'package:flutter/material.dart';
import '../widgets/status_badge.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class QosScreen extends ConsumerStatefulWidget {
  const QosScreen({super.key});
  @override
  ConsumerState<QosScreen> createState() => _QosScreenState();
}

class _QosScreenState extends ConsumerState<QosScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() => _loading = true);
      await ref.read(qosProvider.notifier).fetch();
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(qosProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('QoS Rules', style: Theme.of(context).textTheme.titleLarge),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showRuleDialog(context, ref),
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : rules.isEmpty
          ? _empty()
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _QosTile(rule: rules[i]),
            ),
    );
  }

  Widget _empty() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.speed_rounded, size: 48, color: Theme.of(context).extension<AppColors>()!.textMuted),
      const SizedBox(height: 12),
      Text('No QoS rules yet', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textMuted)),
      const SizedBox(height: 8),
      Text('Tap + to add a bandwidth limit', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textMuted, fontSize: 13)),
    ]),
  );

  void _showRuleDialog(BuildContext context, WidgetRef ref, [QosRule? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final macCtrl = TextEditingController(text: existing?.mac ?? '');
    final dlCtrl = TextEditingController(text: existing?.downloadKbps.toString() ?? '0');
    final ulCtrl = TextEditingController(text: existing?.uploadKbps.toString() ?? '0');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24,
          MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(existing == null ? 'New QoS Rule' : 'Edit Rule',
              style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Device Name')),
            const SizedBox(height: 12),
            TextField(controller: macCtrl, decoration: const InputDecoration(labelText: 'MAC Address', hintText: 'AA:BB:CC:DD:EE:FF')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(
                controller: dlCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Download (Kbps)', hintText: '0 = unlimited'),
              )),
              const SizedBox(width: 12),
              Expanded(child: TextField(
                controller: ulCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Upload (Kbps)', hintText: '0 = unlimited'),
              )),
            ]),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final rule = QosRule(
                    id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameCtrl.text,
                    mac: macCtrl.text,
                    downloadKbps: int.tryParse(dlCtrl.text) ?? 0,
                    uploadKbps: int.tryParse(ulCtrl.text) ?? 0,
                    enabled: true,
                  );
                  Navigator.pop(context);
                  await ref.read(qosProvider.notifier).saveRule(rule);
                },
                child: const Text('Save Rule'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QosTile extends ConsumerWidget {
  final QosRule rule;
  const _QosTile({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dlLabel = rule.downloadKbps == 0 ? 'Unlimited' : '${rule.downloadKbps} Kbps';
    final ulLabel = rule.uploadKbps == 0 ? 'Unlimited' : '${rule.uploadKbps} Kbps';

    return AppCard(
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppTheme.secondary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.speed_rounded, color: AppTheme.secondary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(rule.name.isNotEmpty ? rule.name : rule.mac,
              style: Theme.of(context).textTheme.titleSmall),
            Text('↓ $dlLabel  ·  ↑ $ulLabel',
              style: Theme.of(context).textTheme.bodySmall),
          ],
        )),
        StatusBadge(
          label: rule.enabled ? 'Active' : 'Off',
          color: rule.enabled ? AppTheme.success : AppTheme.textMuted,
        ),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class PortForwardScreen extends ConsumerStatefulWidget {
  const PortForwardScreen({super.key});
  @override
  ConsumerState<PortForwardScreen> createState() => _PortForwardScreenState();
}

class _PortForwardScreenState extends ConsumerState<PortForwardScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() => _loading = true);
      await ref.read(portForwardProvider.notifier).fetch();
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(portForwardProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text('Port Forwarding', style: Theme.of(context).textTheme.titleLarge),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(portForwardProvider.notifier).saveAll();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Port forwarding rules saved')),
                );
              }
            },
            child: const Text('Save All'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(context, ref),
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : rules.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.lan_rounded, size: 48, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text('No port forwarding rules', style: TextStyle(color: AppTheme.textMuted)),
            ]))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _PFTile(rule: rules[i]),
            ),
    );
  }

  void _showDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final extCtrl = TextEditingController();
    final intCtrl = TextEditingController();
    final ipCtrl = TextEditingController();
    String proto = 'tcp';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModalState) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24,
          MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('New Port Forward Rule', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Rule Name')),
          const SizedBox(height: 12),
          // Protocol selector
          Row(children: ['tcp', 'udp', 'both'].map((p) => Expanded(
            child: GestureDetector(
              onTap: () => setModalState(() => proto = p),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: proto == p ? AppTheme.primary : AppTheme.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: proto == p ? AppTheme.primary : AppTheme.border),
                ),
                child: Text(p.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: proto == p ? Colors.white : AppTheme.textSecondary,
                    fontWeight: FontWeight.w600, fontSize: 13,
                  ),
                ),
              ),
            ),
          )).toList()),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: extCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'External Port'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: intCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Internal Port'))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: ipCtrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Internal IP', hintText: '192.168.1.x')),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () {
              ref.read(portForwardProvider.notifier).addRule(PortForwardRule(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text,
                protocol: proto,
                externalPort: int.tryParse(extCtrl.text) ?? 0,
                internalPort: int.tryParse(intCtrl.text) ?? 0,
                internalIp: ipCtrl.text,
                enabled: true,
              ));
              Navigator.pop(context);
            },
            child: const Text('Add Rule'),
          )),
        ]),
      )),
    );
  }
}

class _PFTile extends ConsumerWidget {
  final PortForwardRule rule;
  const _PFTile({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppCard(
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.lan_rounded, color: AppTheme.success, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(rule.name.isNotEmpty ? rule.name : 'Port ${rule.externalPort}',
            style: Theme.of(context).textTheme.titleSmall),
          Text(
            '${rule.protocol.toUpperCase()} :${rule.externalPort} → ${rule.internalIp}:${rule.internalPort}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      )),
      Switch(
        value: rule.enabled,
        onChanged: (_) => ref.read(portForwardProvider.notifier).toggleRule(rule.id),
        activeColor: AppTheme.primary,
      ),
      IconButton(
        icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
        onPressed: () => ref.read(portForwardProvider.notifier).removeRule(rule.id),
      ),
    ]),
  );
}

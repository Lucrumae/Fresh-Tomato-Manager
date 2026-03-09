import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class PortForwardScreen extends ConsumerWidget {
  const PortForwardScreen({super.key});

  @override Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(portForwardProvider);
    final v = Theme.of(context).extension<VC>()!;
    return Scaffold(
      backgroundColor: v.bg,
      appBar: AppBar(
        backgroundColor: v.dark ? V.d0 : V.l2,
        title: Text('PORT FORWARD', style: GoogleFonts.outfit(fontSize: 13,
          fontWeight: FontWeight.w900, letterSpacing: 1.2, color: v.hi)),
        actions: [
          if (rules.isNotEmpty) TextButton(
            onPressed: () async {
              await ref.read(portForwardProvider.notifier).saveAll();
              if (context.mounted) ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Saved & applied')));
            },
            child: Text('SAVE', style: GoogleFonts.outfit(fontSize: 12,
              fontWeight: FontWeight.w800, color: v.accent))),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context, ref, v),
        child: const Icon(Icons.add_rounded)),
      body: rules.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.alt_route_rounded, size: 48, color: v.lo),
            const SizedBox(height: 10),
            Text('no rules', style: GoogleFonts.dmMono(fontSize: 11, color: v.lo)),
          ]))
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
            itemCount: rules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 7),
            itemBuilder: (_, i) => _RuleTile(rule: rules[i], ref: ref, v: v)),
    );
  }

  void _showForm(BuildContext ctx, WidgetRef ref, VC v, [PortForwardRule? existing]) {
    showModalBottomSheet(context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _RuleForm(existing: existing, ref: ref));
  }
}

class _RuleTile extends StatelessWidget {
  final PortForwardRule rule; final WidgetRef ref; final VC v;
  const _RuleTile({required this.rule, required this.ref, required this.v});
  @override Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: v.panel, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: v.wire)),
    child: Row(children: [
      // enable toggle
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Switch.adaptive(value: rule.enabled,
          onChanged: (_) => ref.read(portForwardProvider.notifier).toggleRule(rule.id),
          activeColor: v.accent)),
      // info
      Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child:
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rule.name.isEmpty ? 'Rule' : rule.name, style: GoogleFonts.outfit(fontSize: 13,
            fontWeight: FontWeight.w700, color: rule.enabled ? v.hi : v.lo)),
          const SizedBox(height: 3),
          Row(children: [
            Badge(rule.protocol.toUpperCase(), color: v.accent),
            const SizedBox(width: 6),
            Text(':${rule.externalPort} → ${rule.internalIp}:${rule.internalPort}',
              style: GoogleFonts.dmMono(fontSize: 10, color: v.mid)),
          ]),
        ]))),
      // delete
      IconButton(icon: Icon(Icons.close_rounded, size: 16, color: v.lo),
        onPressed: () => ref.read(portForwardProvider.notifier).removeRule(rule.id)),
    ]),
  );
}

class _RuleForm extends ConsumerStatefulWidget {
  final PortForwardRule? existing;
  final WidgetRef ref;
  const _RuleForm({this.existing, required this.ref});
  @override ConsumerState<_RuleForm> createState() => _RuleFormState();
}
class _RuleFormState extends ConsumerState<_RuleForm> {
  final _name  = TextEditingController();
  final _extP  = TextEditingController();
  final _intP  = TextEditingController();
  final _intIp = TextEditingController();
  String _proto = 'both';

  @override void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name; _extP.text = '${e.externalPort}';
      _intP.text = '${e.internalPort}'; _intIp.text = e.internalIp;
      _proto = e.protocol;
    }
  }
  @override void dispose() { _name.dispose(); _extP.dispose(); _intP.dispose(); _intIp.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        decoration: BoxDecoration(color: v.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: v.wire)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 32, height: 4, margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: v.wire2, borderRadius: BorderRadius.circular(2))),
          Text('ADD RULE', style: GoogleFonts.outfit(fontSize: 13,
            fontWeight: FontWeight.w800, color: v.hi, letterSpacing: 1)),
          const SizedBox(height: 14),
          TextField(controller: _name, style: GoogleFonts.dmMono(fontSize: 13),
            decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _extP, keyboardType: TextInputType.number,
              style: GoogleFonts.dmMono(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Ext Port'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: _intP, keyboardType: TextInputType.number,
              style: GoogleFonts.dmMono(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Int Port'))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _intIp, keyboardType: TextInputType.number,
            style: GoogleFonts.dmMono(fontSize: 13),
            decoration: const InputDecoration(labelText: 'Internal IP')),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _proto, dropdownColor: v.elevated,
            decoration: const InputDecoration(labelText: 'Protocol'),
            items: ['tcp','udp','both'].map((p) => DropdownMenuItem(value: p,
              child: Text(p.toUpperCase(), style: GoogleFonts.outfit(fontSize: 13)))).toList(),
            onChanged: (x) { if (x != null) setState(() => _proto = x); }),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () {
              if (_intIp.text.isEmpty || _extP.text.isEmpty) return;
              final rule = PortForwardRule(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: _name.text, protocol: _proto,
                externalPort: int.tryParse(_extP.text) ?? 0,
                internalPort: int.tryParse(_intP.text) ?? 0,
                internalIp: _intIp.text, enabled: true);
              ref.read(portForwardProvider.notifier).addRule(rule);
              Navigator.pop(context);
            },
            child: Text('ADD', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)))),
        ]),
      ),
    );
  }
}

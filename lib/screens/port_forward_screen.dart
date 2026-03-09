import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class PortForwardScreen extends ConsumerWidget {
  const PortForwardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(portForwardProvider);
    final c     = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Row(children: [
          Text('Port Forward', style: GoogleFonts.spaceGrotesk(
            fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: c.accent.withOpacity(0.10), borderRadius: BorderRadius.circular(5)),
            child: Text('${rules.length}', style: GoogleFonts.jetBrainsMono(
              fontSize: 10, fontWeight: FontWeight.w700, color: c.accent)),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(portForwardProvider.notifier).saveAll();
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Port forward rules saved')));
            },
            child: Text('Save All', style: GoogleFonts.spaceGrotesk(
              fontSize: 12, fontWeight: FontWeight.w700, color: c.accent)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showDialog(context, ref, c),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text('Add Rule', style: GoogleFonts.spaceGrotesk(
          fontSize: 12, fontWeight: FontWeight.w700)),
      ),
      body: (rules.isEmpty)
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.lan_rounded, size: 48, color: c.textMuted),
            const SizedBox(height: 12),
            Text('No port forward rules', style: GoogleFonts.spaceGrotesk(fontSize: 14, color: c.textMuted)),
          ]))
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
            itemCount: rules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _PfTile(rule: rules[i], ref: ref, c: c),
          ),
    );
  }
}

void _showDialog(BuildContext context, WidgetRef ref, AppColors c, [PortForwardRule? existing]) {
  final nameCtrl  = TextEditingController(text: existing?.name ?? '');
  final ipCtrl    = TextEditingController(text: existing?.internalIp ?? '');
  final extCtrl   = TextEditingController(text: existing?.externalPort.toString() ?? '');
  final intCtrl   = TextEditingController(text: existing?.internalPort.toString() ?? '');
  String proto    = existing?.protocol ?? 'tcp';

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setSt) => AlertDialog(
      backgroundColor: c.cardBg,
      title: Text(existing == null ? 'Add Port Forward' : 'Edit Rule',
        style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _f('Name', nameCtrl), const SizedBox(height: 10),
        _f('Internal IP', ipCtrl, hint: '192.168.1.x'), const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _f('Ext. Port', extCtrl, keyboard: TextInputType.number)),
          const SizedBox(width: 8),
          Expanded(child: _f('Int. Port', intCtrl, keyboard: TextInputType.number)),
        ]),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: proto,
          decoration: const InputDecoration(labelText: 'Protocol'),
          dropdownColor: c.cardBg,
          items: ['tcp', 'udp', 'both'].map((p) => DropdownMenuItem(
            value: p, child: Text(p.toUpperCase(),
              style: GoogleFonts.jetBrainsMono(fontSize: 13)))).toList(),
          onChanged: (v) { if (v != null) setSt(() => proto = v); },
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
          child: Text('Cancel', style: GoogleFonts.spaceGrotesk(color: c.textMuted))),
        ElevatedButton(
          onPressed: () {
            final rule = PortForwardRule(
              id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
              name: nameCtrl.text, protocol: proto,
              externalPort: int.tryParse(extCtrl.text) ?? 0,
              internalPort: int.tryParse(intCtrl.text) ?? 0,
              internalIp: ipCtrl.text, enabled: existing?.enabled ?? true,
            );
            if (existing == null) ref.read(portForwardProvider.notifier).addRule(rule);
            Navigator.pop(ctx);
          },
          style: ElevatedButton.styleFrom(minimumSize: const Size(80, 38)),
          child: Text('Save', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        ),
      ],
    )),
  );
}

Widget _f(String label, TextEditingController ctrl, {String? hint, TextInputType keyboard = TextInputType.text}) =>
  TextField(controller: ctrl, keyboardType: keyboard,
    style: GoogleFonts.jetBrainsMono(fontSize: 13),
    decoration: InputDecoration(labelText: label, hintText: hint));

class _PfTile extends StatelessWidget {
  final PortForwardRule rule;
  final WidgetRef ref;
  final AppColors c;
  const _PfTile({required this.rule, required this.ref, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: rule.enabled ? c.border : c.border.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppTheme.info.withOpacity(0.08), borderRadius: BorderRadius.circular(9)),
          child: Icon(Icons.swap_horiz_rounded, size: 17, color: AppTheme.info),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rule.name.isEmpty ? '${rule.protocol.toUpperCase()} :${rule.externalPort}' : rule.name,
            style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w600,
              color: rule.enabled ? c.textPrimary : c.textMuted)),
          const SizedBox(height: 2),
          Row(children: [
            Text('${rule.protocol.toUpperCase()}', style: GoogleFonts.jetBrainsMono(
              fontSize: 9, color: AppTheme.info, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Text(':${rule.externalPort} → ${rule.internalIp}:${rule.internalPort}',
              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: c.textSecondary)),
          ]),
        ])),
        Switch.adaptive(
          value: rule.enabled,
          onChanged: (_) => ref.read(portForwardProvider.notifier).toggleRule(rule.id),
          activeColor: c.accent,
        ),
        IconButton(
          icon: Icon(Icons.delete_rounded, size: 16, color: AppTheme.danger.withOpacity(0.5)),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          onPressed: () => ref.read(portForwardProvider.notifier).removeRule(rule.id),
        ),
      ]),
    );
  }
}

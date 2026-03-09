import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class QosScreen extends ConsumerWidget {
  const QosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules  = ref.watch(qosProvider);
    final c      = Theme.of(context).extension<AppColors>()!;
    final accent = c.accent;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.surface,
        title: Row(children: [
          Text('QoS Rules', style: GoogleFonts.spaceGrotesk(
            fontSize: 17, fontWeight: FontWeight.w700, color: c.textPrimary)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10), borderRadius: BorderRadius.circular(5)),
            child: Text('${rules.length}', style: GoogleFonts.jetBrainsMono(
              fontSize: 10, fontWeight: FontWeight.w700, color: accent)),
          ),
        ]),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, size: 18, color: c.textMuted),
            onPressed: () => ref.read(qosProvider.notifier).fetch(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRuleDialog(context, ref, c),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text('Add Rule', style: GoogleFonts.spaceGrotesk(
          fontSize: 12, fontWeight: FontWeight.w700)),
      ),
      body: rules.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.speed_rounded, size: 48, color: c.textMuted),
            const SizedBox(height: 12),
            Text('No QoS rules', style: GoogleFonts.spaceGrotesk(fontSize: 14, color: c.textMuted)),
            const SizedBox(height: 6),
            Text('Tap + to add bandwidth limits per device',
              style: GoogleFonts.spaceGrotesk(fontSize: 11, color: c.textMuted)),
          ]))
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 80),
            itemCount: rules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _RuleTile(rule: rules[i], c: c),
          ),
    );
  }
}

void _showRuleDialog(BuildContext context, WidgetRef ref, AppColors c, [QosRule? existing]) {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final macCtrl  = TextEditingController(text: existing?.mac  ?? '');
  final dlCtrl   = TextEditingController(text: existing?.downloadKbps != 0 ? existing?.downloadKbps.toString() : '');
  final ulCtrl   = TextEditingController(text: existing?.uploadKbps   != 0 ? existing?.uploadKbps.toString()   : '');
  bool saving = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) => AlertDialog(
        backgroundColor: c.cardBg,
        title: Text(existing == null ? 'Add QoS Rule' : 'Edit Rule',
          style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _f('Device Name', nameCtrl), const SizedBox(height: 10),
          _f('MAC Address', macCtrl, hint: 'xx:xx:xx:xx:xx:xx'), const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _f('DL Kbps', dlCtrl, keyboard: TextInputType.number, hint: '0=∞')),
            const SizedBox(width: 8),
            Expanded(child: _f('UL Kbps', ulCtrl, keyboard: TextInputType.number, hint: '0=∞')),
          ]),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.spaceGrotesk(color: c.textMuted))),
          ElevatedButton(
            onPressed: saving ? null : () async {
              setSt(() => saving = true);
              final rule = QosRule(
                id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text,
                mac:  macCtrl.text,
                downloadKbps: int.tryParse(dlCtrl.text) ?? 0,
                uploadKbps:   int.tryParse(ulCtrl.text) ?? 0,
                enabled: existing?.enabled ?? true,
              );
              await ref.read(qosProvider.notifier).saveRule(rule);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(minimumSize: const Size(80, 38)),
            child: saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : Text('Save', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    ),
  );
}

Widget _f(String label, TextEditingController ctrl, {String? hint, TextInputType keyboard = TextInputType.text}) =>
  TextField(
    controller: ctrl, keyboardType: keyboard,
    style: GoogleFonts.jetBrainsMono(fontSize: 13),
    decoration: InputDecoration(labelText: label, hintText: hint),
  );

class _RuleTile extends StatelessWidget {
  final QosRule rule;
  final AppColors c;
  const _RuleTile({required this.rule, required this.c});

  String _fmt(int kbps) {
    if (kbps == 0) return '∞';
    if (kbps >= 1024) return '${(kbps / 1024).toStringAsFixed(1)}M';
    return '${kbps}K';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: rule.enabled ? c.border : c.border.withOpacity(0.4)),
        opacity: rule.enabled ? 1.0 : 0.6,
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: c.accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(Icons.speed_rounded, size: 17, color: c.accent),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rule.name.isEmpty ? rule.mac : rule.name,
            style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w600, color: c.textPrimary)),
          Text(rule.mac, style: GoogleFonts.jetBrainsMono(fontSize: 10, color: c.textMuted)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(children: [
            Text('↓', style: TextStyle(color: c.accent, fontSize: 10)),
            const SizedBox(width: 2),
            Text(_fmt(rule.downloadKbps), style: GoogleFonts.jetBrainsMono(
              fontSize: 11, fontWeight: FontWeight.w700, color: c.accent)),
          ]),
          Row(children: [
            Text('↑', style: TextStyle(color: AppTheme.warning, fontSize: 10)),
            const SizedBox(width: 2),
            Text(_fmt(rule.uploadKbps), style: GoogleFonts.jetBrainsMono(
              fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.warning)),
          ]),
        ]),
      ]),
    );
  }
}

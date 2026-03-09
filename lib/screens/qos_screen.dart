import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class QosScreen extends ConsumerWidget {
  const QosScreen({super.key});

  String _kbps(int k) => k == 0 ? '∞' : k >= 1024 ? '${(k/1024).toStringAsFixed(1)}M' : '${k}K';

  @override Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(qosProvider);
    final v = Theme.of(context).extension<VC>()!;
    return Scaffold(
      backgroundColor: v.bg,
      appBar: AppBar(
        backgroundColor: v.dark ? V.d0 : V.l2,
        title: Text('QOS', style: GoogleFonts.outfit(fontSize: 14,
          fontWeight: FontWeight.w900, color: v.hi, letterSpacing: 1.5)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(context, ref),
        child: const Icon(Icons.add_rounded)),
      body: rules.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.speed_rounded, size: 48, color: v.lo),
            const SizedBox(height: 10),
            Text('no qos rules', style: GoogleFonts.dmMono(fontSize: 11, color: v.lo)),
          ]))
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
            itemCount: rules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 7),
            itemBuilder: (_, i) {
              final r = rules[i];
              return Container(
                decoration: BoxDecoration(
                  color: v.panel, borderRadius: BorderRadius.circular(12),
                  border: Border(
                    left: BorderSide(color: r.enabled ? v.accent : v.wire, width: 2),
                    top: BorderSide(color: v.wire), right: BorderSide(color: v.wire),
                    bottom: BorderSide(color: v.wire))),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.name, style: GoogleFonts.outfit(fontSize: 13,
                      fontWeight: FontWeight.w700, color: r.enabled ? v.hi : v.lo)),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text('${r.mac}', style: GoogleFonts.dmMono(fontSize: 9, color: v.lo)),
                      const Spacer(),
                      Icon(Icons.arrow_downward_rounded, size: 10, color: v.accent),
                      const SizedBox(width: 2),
                      Text(_kbps(r.downloadKbps), style: GoogleFonts.dmMono(fontSize: 10, color: v.accent)),
                      const SizedBox(width: 10),
                      Icon(Icons.arrow_upward_rounded, size: 10, color: V.warn),
                      const SizedBox(width: 2),
                      Text(_kbps(r.uploadKbps), style: GoogleFonts.dmMono(fontSize: 10, color: V.warn)),
                    ]),
                  ])),
                  const SizedBox(width: 8),
                  Switch.adaptive(value: r.enabled,
                    onChanged: (_) async {
                      final updated = QosRule(id:r.id, name:r.name, mac:r.mac,
                        downloadKbps:r.downloadKbps, uploadKbps:r.uploadKbps,
                        priority:r.priority, enabled:!r.enabled);
                      await ref.read(qosProvider.notifier).saveRule(updated);
                    }, activeColor: v.accent),
                ]),
              );
            }),
    );
  }

  void _showForm(BuildContext ctx, WidgetRef ref) {
    final v = Theme.of(ctx).extension<VC>()!;
    final nameC = TextEditingController();
    final macC  = TextEditingController();
    final dlC   = TextEditingController();
    final ulC   = TextEditingController();
    showModalBottomSheet(context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          decoration: BoxDecoration(color: v.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: v.wire)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 32, height: 4, margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: v.wire2, borderRadius: BorderRadius.circular(2))),
            Text('ADD QOS RULE', style: GoogleFonts.outfit(fontSize: 13,
              fontWeight: FontWeight.w800, color: v.hi, letterSpacing: 1)),
            const SizedBox(height: 14),
            TextField(controller: nameC, style: GoogleFonts.dmMono(fontSize: 13),
              decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(controller: macC, style: GoogleFonts.dmMono(fontSize: 13),
              decoration: const InputDecoration(labelText: 'MAC Address (leave blank for all)')),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: dlC, keyboardType: TextInputType.number,
                style: GoogleFonts.dmMono(fontSize: 13),
                decoration: const InputDecoration(labelText: 'DL Kbps (0=∞)'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: ulC, keyboardType: TextInputType.number,
                style: GoogleFonts.dmMono(fontSize: 13),
                decoration: const InputDecoration(labelText: 'UL Kbps (0=∞)'))),
            ]),
            const SizedBox(height: 14),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () {
                if (nameC.text.isEmpty) return;
                final rule = QosRule(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameC.text, mac: macC.text,
                  downloadKbps: int.tryParse(dlC.text) ?? 0,
                  uploadKbps: int.tryParse(ulC.text) ?? 0,
                  enabled: true);
                ref.read(qosProvider.notifier).saveRule(rule);
                Navigator.pop(ctx);
              },
              child: Text('ADD', style: GoogleFonts.outfit(fontWeight: FontWeight.w800)))),
          ]),
        ),
      ));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';
import 'bandwidth_screen.dart';

// NETWORK = Bandwidth | QoS | Port Forward (3 tabs)

class NetworkScreen extends ConsumerStatefulWidget {
  const NetworkScreen({super.key});
  @override ConsumerState<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends ConsumerState<NetworkScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }
  @override void dispose() { _tab.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final v = Theme.of(context).extension<VC>()!;
    return Scaffold(
      backgroundColor: v.bg,
      appBar: AppBar(
        title: Text('NETWORK',
          style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800,
            color: v.hi, letterSpacing: 2)),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'BANDWIDTH'),
            Tab(text: 'QoS'),
            Tab(text: 'PORT FORWARD'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _BandwidthTab(),
          _QosTab(),
          _PortForwardTab(),
        ],
      ),
    );
  }
}

// ── Bandwidth tab ─────────────────────────────────────────────────────────────
class _BandwidthTab extends StatelessWidget {
  const _BandwidthTab();
  @override Widget build(BuildContext context) =>
    const BandwidthScreen(initialShowQos: false);
}

// ── QoS tab — uses BandwidthScreen QoS view ─────────────────────────────────
class _QosTab extends StatelessWidget {
  const _QosTab();
  @override Widget build(BuildContext context) =>
    const BandwidthScreen(initialShowQos: true);
}

// ── Port Forward tab ───────────────────────────────────────────────────────────
class _PortForwardTab extends ConsumerWidget {
  const _PortForwardTab();

  @override Widget build(BuildContext context, WidgetRef ref) {
    final v     = Theme.of(context).extension<VC>()!;
    final rules = ref.watch(portForwardProvider);

    return Scaffold(
      backgroundColor: v.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addRule(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: rules.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.router_rounded, color: v.lo, size: 36),
            const SizedBox(height: 12),
            Text('No port forward rules',
              style: GoogleFonts.dmMono(fontSize: 12, color: v.lo)),
          ]))
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: rules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _PfCard(rule: rules[i]),
          ),
    );
  }

  Future<void> _addRule(BuildContext ctx, WidgetRef ref) async {
    final rule = await showDialog<PortForwardRule>(
      context: ctx, builder: (_) => const _PfDialog());
    if (rule != null) {
      ref.read(portForwardProvider.notifier).addRule(rule);
      await ref.read(portForwardProvider.notifier).saveAll();
    }
  }
}

class _PfCard extends ConsumerWidget {
  final PortForwardRule rule;
  const _PfCard({required this.rule});

  @override Widget build(BuildContext ctx, WidgetRef ref) {
    final v = Theme.of(ctx).extension<VC>()!;
    return VCard(
      accentLeft: rule.enabled,
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rule.name.isNotEmpty ? rule.name : 'Rule ${rule.id}',
            style: GoogleFonts.outfit(fontSize: 13,
              fontWeight: FontWeight.w700, color: v.hi),
            overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [
            VBadge(rule.protocol.toUpperCase(), color: v.accent),
            const SizedBox(width: 6),
            Text(':${rule.externalPort} → ${rule.internalIp}:${rule.internalPort}',
              style: GoogleFonts.dmMono(fontSize: 10, color: v.mid)),
          ]),
        ])),
        Switch(
          value: rule.enabled,
          onChanged: (_) {
            ref.read(portForwardProvider.notifier).toggleRule(rule.id);
            ref.read(portForwardProvider.notifier).saveAll();
          },
        ),
        GestureDetector(
          onTap: () async {
            ref.read(portForwardProvider.notifier).removeRule(rule.id);
            await ref.read(portForwardProvider.notifier).saveAll();
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.delete_outline_rounded, size: 18, color: V.err)),
        ),
      ]),
    );
  }
}

class _PfDialog extends StatefulWidget {
  const _PfDialog();
  @override State<_PfDialog> createState() => _PfDialogState();
}

class _PfDialogState extends State<_PfDialog> {
  final _name  = TextEditingController();
  final _ext   = TextEditingController();
  final _intP  = TextEditingController();
  final _ip    = TextEditingController();
  String _proto = 'tcp';

  @override void dispose() {
    _name.dispose(); _ext.dispose(); _intP.dispose(); _ip.dispose();
    super.dispose();
  }

  @override Widget build(BuildContext ctx) => AlertDialog(
    title: const Text('Add Port Forward'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(controller: _name,
        decoration: const InputDecoration(labelText: 'Name (optional)')),
      const SizedBox(height: 10),
      TextField(controller: _ext,
        decoration: const InputDecoration(labelText: 'External port'),
        keyboardType: TextInputType.number),
      const SizedBox(height: 10),
      TextField(controller: _ip,
        decoration: const InputDecoration(labelText: 'Internal IP'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: 10),
      TextField(controller: _intP,
        decoration: const InputDecoration(labelText: 'Internal port'),
        keyboardType: TextInputType.number),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _proto,
        decoration: const InputDecoration(labelText: 'Protocol'),
        items: ['tcp', 'udp', 'tcp+udp']
          .map((p) => DropdownMenuItem(value: p, child: Text(p.toUpperCase())))
          .toList(),
        onChanged: (p) => setState(() => _proto = p!),
      ),
    ])),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel')),
      TextButton(
        onPressed: () {
          final ep  = int.tryParse(_ext.text) ?? 0;
          final ip2 = int.tryParse(_intP.text) ?? ep;
          if (ep == 0 || _ip.text.isEmpty) return;
          Navigator.pop(ctx, PortForwardRule(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: _name.text.trim(), protocol: _proto,
            externalPort: ep, internalPort: ip2,
            internalIp: _ip.text.trim(), enabled: true));
        },
        child: const Text('Add')),
    ],
  );
}

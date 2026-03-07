import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../models/models.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});
  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  String _search = '';
  String _filter = 'all'; // all, wifi, ethernet, blocked

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(devicesProvider);

    final filtered = all.where((d) {
      final matchSearch = _search.isEmpty ||
        d.displayName.toLowerCase().contains(_search.toLowerCase()) ||
        d.ip.contains(_search) ||
        d.mac.toLowerCase().contains(_search.toLowerCase());

      final matchFilter = _filter == 'all' ||
        (_filter == 'wifi' && d.isWireless) ||
        (_filter == 'ethernet' && !d.isWireless) ||
        (_filter == 'blocked' && d.isBlocked);

      return matchSearch && matchFilter;
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Text('Devices', style: Theme.of(context).textTheme.titleLarge),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: Text(
                  '${all.length} connected',
                  style: Theme.of(context).textTheme.bodySmall,
                )),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(100),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    // Search bar
                    TextField(
                      onChanged: (v) => setState(() => _search = v),
                      decoration: const InputDecoration(
                        hintText: 'Search by name, IP, or MAC...',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Filter chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(label: 'All (${all.length})', value: 'all', current: _filter, onTap: (v) => setState(() => _filter = v)),
                          _FilterChip(label: 'WiFi', value: 'wifi', current: _filter, onTap: (v) => setState(() => _filter = v)),
                          _FilterChip(label: 'Ethernet', value: 'ethernet', current: _filter, onTap: (v) => setState(() => _filter = v)),
                          _FilterChip(label: '🚫 Blocked', value: 'blocked', current: _filter, onTap: (v) => setState(() => _filter = v)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          filtered.isEmpty
            ? SliverFillRemaining(child: _empty())
            : SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _DeviceCard(device: filtered[i]),
                    childCount: filtered.length,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.devices_rounded, size: 48, color: Theme.of(context).extension<AppColors>()!.textMuted),
        const SizedBox(height: 12),
        Text('No devices found', style: TextStyle(color: Theme.of(context).extension<AppColors>()!.textMuted)),
      ],
    ),
  );
}

class _DeviceCard extends ConsumerWidget {
  final ConnectedDevice device;
  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(
          children: [
            // Device icon
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: device.isBlocked
                  ? AppTheme.danger.withOpacity(0.1)
                  : AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                device.isWireless ? Icons.wifi_rounded : Icons.cable_rounded,
                color: device.isBlocked ? AppTheme.danger : AppTheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Device info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(
                      device.displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    )),
                    if (device.isBlocked)
                      StatusBadge(label: 'Blocked', color: AppTheme.danger),
                  ]),
                  const SizedBox(height: 3),
                  Text(device.ip,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).extension<AppColors>()!.textSecondary,
                    ),
                  ),
                  Text(device.mac,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),

            // Actions
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Theme.of(context).extension<AppColors>()!.textMuted),
              onSelected: (action) => _onAction(context, ref, action),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(
                  value: 'block',
                  child: Text(device.isBlocked ? 'Unblock' : 'Block Internet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onAction(BuildContext context, WidgetRef ref, String action) async {
    if (action == 'rename') {
      final ctrl = TextEditingController(text: device.name);
      final name = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Rename Device'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'Enter device name'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (name != null && name.isNotEmpty) {
        await ref.read(devicesProvider.notifier).renameDevice(device.mac, name);
      }
    } else if (action == 'block') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(device.isBlocked ? 'Unblock Device' : 'Block Internet Access'),
          content: Text(device.isBlocked
            ? 'Allow ${device.displayName} to access the internet?'
            : 'Block internet access for ${device.displayName}? They will stay connected to WiFi but cannot reach the internet.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: device.isBlocked ? AppTheme.success : AppTheme.danger,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(device.isBlocked ? 'Unblock' : 'Block'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await ref.read(devicesProvider.notifier).toggleBlock(device.mac);
      }
    }
  }
}

class _FilterChip extends StatelessWidget {
  final String label, value, current;
  final ValueChanged<String> onTap;
  const _FilterChip({required this.label, required this.value, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.border),
        ),
        child: Text(label, style: TextStyle(
          color: selected ? Colors.white : AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        )),
      ),
    );
  }
}

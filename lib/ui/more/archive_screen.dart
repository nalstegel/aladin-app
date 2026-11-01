import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/order_phases.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../orders/archive_actions.dart';
import '../orders/order_detail_screen.dart';
import '../widgets/common.dart';

/// Archive: old orders that were handed back in practice but never completed
/// in the app. They are not deleted — just kept out of the tabs, counters and
/// statistics. An order archived by mistake comes back with "Vrni iz arhiva".
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final all = state.archivedOrders;
    final query = _search.text.trim();

    // Same search as on the Naročila page: order or item ID, name without
    // diacritics, phone by digits, address.
    final list = query.isEmpty
        ? all
        : all.where((o) => matchesSearch(o, state.itemsOf(o.id), query)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Arhiv')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SearchField(
              controller: _search,
              hint: 'Išči po ID-ju, imenu ali telefonu',
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: all.isEmpty
                ? const EmptyState(
                    icon: Icons.archive_outlined,
                    title: 'Arhiv je prazen',
                    message:
                        'Naročila, ki jih v podrobnostih premakneš v arhiv, '
                        'se pokažejo tukaj.',
                  )
                : list.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    title: 'Ni zadetkov',
                    message: 'Iskanje zajame samo naročila v arhivu.',
                  )
                : Column(
                    children: [
                      UnitCaption(Fmt.orders(list.length)),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: list.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => _ArchivedTile(order: list[i]),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ArchivedTile extends ConsumerWidget {
  const _ArchivedTile({required this.order});

  final WorkOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final pieces = state.itemsOf(order.id).length;
    final details = [
      if (order.customerPhone.isNotEmpty) Fmt.phone(order.customerPhone),
      Fmt.pieces(pieces),
      Fmt.money(state.orderTotal(order.id)),
    ].join(' · ');

    return AppCard(
      accent: AppColors.border,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                order.number,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusChip(
                label: order.channel.label,
                color: AppColors.forChannel(order.channel),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            details,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Arhivirano ${Fmt.date(order.archivedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => restoreFromArchive(
                  context,
                  ref.read(repositoryProvider.notifier),
                  order,
                ),
                icon: const Icon(Icons.unarchive_outlined, size: 18),
                label: const Text('Vrni iz arhiva'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

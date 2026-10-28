import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../rugs/quick_finish_sheet.dart';
import '../rugs/rug_detail_screen.dart';
import '../widgets/common.dart';

/// Vsi kosi v enem statusu — delovni seznam ob stroju.
///
/// Do njega se pride z bližnjic pod skenerjem: delavec vidi, kaj ga v tem
/// koraku še čaka, tudi če etikete nima pri roki.
class WorkListScreen extends ConsumerWidget {
  const WorkListScreen({super.key, required this.status});

  final RugStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final color = AppColors.forRug(status);

    // Kose zaključenih naročil izpustimo — sicer bi se seznam "Vrnjeno" z
    // vsakim zaključenim naročilom nezadržno daljšal.
    final items = state.items.where((i) {
      if (i.status != status) return false;
      final order = state.order(i.orderId);
      return order != null &&
          (order.status.isOpen || status == RugStatus.returned);
    }).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(status.label),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: items.isEmpty
          ? EmptyState(
              icon: AppIcons.forRug(status),
              title: 'Nič ni v koraku "${status.label}"',
              message: 'Ko kos doseže ta korak, se pojavi tukaj.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final item = items[i];
                final order = state.order(item.orderId);
                return AppCard(
                  accent: color,
                  // Iz Sušenja gre tap naravnost v hitri obračun (v3 spec
                  // §3) — ne v podrobnosti kosa kot za ostale korake.
                  onTap: status == RugStatus.drying
                      ? () => QuickFinishSheet.show(context, item)
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RugDetailScreen(itemId: item.id),
                            ),
                          ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.id,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                order?.customerName ?? '—',
                                item.label.toLowerCase(),
                                if (item.lastChangeAt != null)
                                  Fmt.relative(item.lastChangeAt!),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.chevron_right,
                          size: 20, color: AppColors.textMuted),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

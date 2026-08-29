import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../widgets/common.dart';

/// Promet in števci. Vse je izračunano iz naročil — nič se ne vodi posebej,
/// zato se ne more razhajati.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final counts = ref.watch(productionCountsProvider);

    final completed =
        state.orders.where((o) => o.status == OrderStatus.completed).toList();
    final open = state.orders.where((o) => o.status.isOpen).toList();

    final revenue =
        completed.fold<double>(0, (s, o) => s + state.orderTotal(o.id));
    final openValue =
        open.fold<double>(0, (s, o) => s + state.orderTotal(o.id));

    final now = DateTime.now();
    final thisMonth = completed.where((o) {
      final d = o.completedAt;
      return d != null && d.year == now.year && d.month == now.month;
    }).toList();
    final monthRevenue =
        thisMonth.fold<double>(0, (s, o) => s + state.orderTotal(o.id));

    final m2Total = completed.fold<double>(0, (s, o) => s + state.orderM2(o.id));
    final avg = completed.isEmpty ? 0.0 : revenue / completed.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Statistika in promet')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SectionHeader('Promet'),
          AppCard(
            child: Column(
              children: [
                DetailRow('Zaključena naročila', Fmt.money(revenue),
                    strong: true),
                const Divider(height: 18),
                DetailRow('Ta mesec (${thisMonth.length})',
                    Fmt.money(monthRevenue)),
                DetailRow('Povprečno naročilo', Fmt.money(avg)),
                DetailRow('V teku (še ni obračunano)', Fmt.money(openValue)),
              ],
            ),
          ),
          const SectionHeader('Naročila'),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${open.length}',
                  label: 'aktivnih',
                  color: AppColors.primary,
                  icon: Icons.receipt_long_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: '${completed.length}',
                  label: 'zaključenih',
                  color: AppColors.ready,
                  icon: Icons.check_circle_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${state.customers.length}',
                  label: 'strank',
                  color: AppColors.awaitingPickup,
                  icon: Icons.people_alt_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: Fmt.m2(m2Total),
                  label: 'opranih skupaj',
                  color: AppColors.drying,
                  icon: Icons.texture,
                ),
              ),
            ],
          ),
          const SectionHeader('V obratu zdaj'),
          AppCard(
            child: Column(
              children: [
                for (final s in RugStatus.values)
                  if (s != RugStatus.returned)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.forRug(s),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.label,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          Text(
                            '${counts[s] ?? 0}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
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

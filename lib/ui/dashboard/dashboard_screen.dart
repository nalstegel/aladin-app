import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../orders/order_card.dart';
import '../widgets/common.dart';

/// Nadzorna plošča za današnji dan — nadomešča list, kamor se je do zdaj
/// pisalo, kdo je za prevzem in kdo za vračilo.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final pickups = ref.watch(todayPickupsProvider);
    final deliveries = ref.watch(todayDeliveriesProvider);
    final collections = ref.watch(awaitingCollectionProvider);
    final counts = ref.watch(productionCountsProvider);
    final overdue = ref.watch(overdueOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(Fmt.dayHeader(DateTime.now())),
            Text(
              user == null ? '' : 'Prijavljen: ${user.name}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const SectionHeader('V obratu'),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${counts[RugStatus.awaitingWash] ?? 0}',
                  label: 'Čaka na pranje',
                  color: AppColors.awaitingWash,
                  icon: Icons.water_drop_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: '${counts[RugStatus.drying] ?? 0}',
                  label: 'Sušenje',
                  color: AppColors.drying,
                  icon: Icons.air,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${counts[RugStatus.finishing] ?? 0}',
                  label: 'Mere in cena',
                  color: AppColors.finishing,
                  icon: Icons.straighten,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: '${counts[RugStatus.ready] ?? 0}',
                  label: 'READY',
                  color: AppColors.ready,
                  icon: Icons.check_circle,
                ),
              ),
            ],
          ),
          if (overdue.isNotEmpty) ...[
            const SectionHeader('Zamuda'),
            for (final o in overdue) ...[
              OrderCard(o, showChannel: true),
              const SizedBox(height: 8),
            ],
          ],
          _group(
            'Danes za prevzem',
            'Gremo po preproge k stranki.',
            pickups,
            Icons.local_shipping_outlined,
            'Danes ni prevzemov.',
          ),
          _group(
            'Danes za vračilo',
            'Preproge peljemo nazaj.',
            deliveries,
            Icons.home_outlined,
            'Danes ni vračil.',
          ),
          _group(
            'Čaka na prevzem v obratu',
            'Stranka pride sama.',
            collections,
            Icons.storefront_outlined,
            'Nič ne čaka na prevzem.',
          ),
        ],
      ),
    );
  }

  Widget _group(
    String title,
    String subtitle,
    List<WorkOrder> orders,
    IconData icon,
    String empty,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          subtitle: subtitle,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${orders.length}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        if (orders.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Icon(icon, size: 24, color: AppColors.border),
                const SizedBox(height: 6),
                Text(
                  empty,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          )
        else
          for (final o in orders) ...[
            OrderCard(o),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

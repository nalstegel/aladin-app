import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../notifications/notifications_screen.dart';
import '../orders/order_card.dart';
import '../orders/return_flow_screen.dart';
import '../scanner/work_list_screen.dart';
import '../widgets/common.dart';

/// Nadzorna plošča za današnji dan — nadomešča list, kamor se je do zdaj
/// pisalo, kdo je za prevzem in kdo za vračilo.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _pickupsKey = GlobalKey();
  final _deliveriesKey = GlobalKey();
  final _overdueKey = GlobalKey();
  final _collectionsKey = GlobalKey();

  Future<void> _scrollTo(GlobalKey key) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pickups = ref.watch(todayPickupsProvider);
    final deliveries = ref.watch(todayDeliveriesProvider);
    final collections = ref.watch(awaitingCollectionProvider);
    final counts = ref.watch(productionCountsProvider);
    final overdue = ref.watch(overdueOrdersProvider);
    final unread = ref.watch(unreadAlertCountProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            PageHeader(
              'Danes',
              subtitle: Fmt.dayHeader(DateTime.now()),
              trailing: _bell(unread),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _tiles(pickups, deliveries, collections, counts, overdue),
            ),
            _section(
              key: _pickupsKey,
              title: 'Danes za prevzem',
              subtitle: 'Gremo po preproge k stranki.',
              orders: pickups,
              icon: Icons.local_shipping_outlined,
              empty: 'Danes ni prevzemov.',
              actionFor: (o) => OrderCardAction(
                label: 'Prevzemi',
                onPressed: () => _pickUp(o),
              ),
            ),
            _section(
              key: _deliveriesKey,
              title: 'Danes za vračilo',
              subtitle: 'Preproge peljemo nazaj.',
              orders: deliveries,
              icon: Icons.home_outlined,
              empty: 'Danes ni vračil.',
              actionFor: (o) => OrderCardAction(
                label: 'Vrni',
                onPressed: () => _startReturn(o),
              ),
            ),
            _section(
              key: _overdueKey,
              title: 'Zamude',
              subtitle: 'Rok je potekel, naročilo pa še ni zaključeno.',
              orders: overdue,
              icon: Icons.check_circle_outline,
              empty: 'Ni zamud.',
            ),
            _section(
              key: _collectionsKey,
              title: 'Čaka na prevzem v obratu',
              subtitle: 'Stranka pride sama.',
              orders: collections,
              icon: Icons.storefront_outlined,
              empty: 'Nič ne čaka na prevzem.',
              actionFor: (o) => OrderCardAction(
                label: 'Vrni',
                onPressed: () => _startReturn(o),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bell(int unread) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_none, size: 26),
          tooltip: 'Obvestila',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          ),
        ),
        if (unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 18),
              child: Text(
                unread > 9 ? '9+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Pet ploščic v dveh vrstah. Peta ("Mere in cena") je tu zato, ker so
  /// bližnjice pod skenerjem namenoma brez nje — sicer do čakalne vrste za
  /// merjenje ne bi vodilo nič.
  Widget _tiles(
    List<WorkOrder> pickups,
    List<WorkOrder> deliveries,
    List<WorkOrder> collections,
    Map<RugStatus, int> counts,
    List<WorkOrder> overdue,
  ) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _tile('${pickups.length}', 'Prevzem',
                  Icons.local_shipping_outlined, AppColors.awaitingWash,
                  () => _scrollTo(_pickupsKey)),
              _tile('${deliveries.length}', 'Vračilo', Icons.home_outlined,
                  AppColors.ready, () => _scrollTo(_deliveriesKey)),
              _tile('${counts[RugStatus.drying] ?? 0}', 'Sušenje', Icons.air,
                  AppColors.drying, () => _openList(RugStatus.drying)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              _tile('${counts[RugStatus.finishing] ?? 0}', 'Mere in cena',
                  Icons.straighten, AppColors.finishing,
                  () => _openList(RugStatus.finishing)),
              _tile('${overdue.length}', 'Zamude',
                  Icons.warning_amber_rounded, AppColors.danger,
                  () => _scrollTo(_overdueKey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(
    String value,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({
    required GlobalKey key,
    required String title,
    required String subtitle,
    required List<WorkOrder> orders,
    required IconData icon,
    required String empty,
    OrderCardAction Function(WorkOrder)? actionFor,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
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
              OrderCard(o, action: actionFor?.call(o)),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  void _openList(RugStatus status) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WorkListScreen(status: status)),
      );

  /// Prevzem je en dotik — kosi gredo iz "V prevzemu" na "Na pranju".
  void _pickUp(WorkOrder order) {
    ref.read(repositoryProvider.notifier).markOrderPickedUp(order.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${order.number} prevzeto pri stranki.')),
    );
  }

  /// Vračilo NIKOLI ni en dotik: postopek zahteva skeniranje vseh kosov in
  /// podpis stranke. Gumb zato samo odpre ta postopek.
  void _startReturn(WorkOrder order) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReturnFlowScreen(orderId: order.id)),
      );
}

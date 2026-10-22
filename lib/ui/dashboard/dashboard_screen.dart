import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/navigation.dart';
import '../../data/order_phases.dart';
import '../../data/providers.dart';
import '../../models/order.dart';
import '../notifications/notifications_screen.dart';
import '../orders/ready_lists.dart';
import '../orders/return_flow_screen.dart';
import '../widgets/common.dart';
import 'quick_order_card.dart';

/// Najdaljši seznam v enem bloku na Home — več ni "kratek Home". Preostalo
/// odpre ustrezen zavihek.
const _maxRowsPerBlock = 5;

/// Nadzorna plošča za današnji dan (V8 §1): Hiter vnos naročila je edino
/// glavno mesto za ustvarjanje naročil, pod njim pa so kratki zaprti bloki,
/// ki kažejo samo števec in se razprejo na klik. Brez dolgih seznamov.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  /// Razprti bloki — privzeto so vsi zaprti.
  final _open = <String>{};

  void _toggle(String id) =>
      setState(() => _open.contains(id) ? _open.remove(id) : _open.add(id));

  @override
  Widget build(BuildContext context) {
    final pickups = ref.watch(todayPickupsProvider);
    final deliveries = ref.watch(todayDeliveriesProvider);
    final state = ref.watch(repositoryProvider);
    final counts = phaseCounts(state);
    final action = ref.watch(actionNeededProvider);
    final unread = ref.watch(unreadAlertCountProvider);

    final workshopTotal =
        (counts[OrderPhase.washing] ?? 0) + (counts[OrderPhase.drying] ?? 0);

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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: QuickOrderCard(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _Accordion(
                    title: 'Prevzemi danes',
                    icon: Icons.local_shipping_outlined,
                    color: AppColors.awaitingWash,
                    count: pickups.length,
                    open: _open.contains('pickups'),
                    onToggle: () => _toggle('pickups'),
                    child: _orderRows(
                      orders: pickups,
                      empty: 'Danes ni prevzemov.',
                      overflowPhase: OrderPhase.intake,
                      subtitle: (o) => [
                        Fmt.timeRange(o.pickupAt, o.pickupWindowEnd),
                        if (o.customerAddress.isNotEmpty) o.customerAddress,
                      ].join(' · '),
                      actionLabel: 'Prevzemi',
                      onAction: (o) => startPickup(context, o),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Accordion(
                    title: 'Vračila danes',
                    icon: Icons.home_outlined,
                    color: AppColors.ready,
                    count: deliveries.length,
                    open: _open.contains('returns'),
                    onToggle: () => _toggle('returns'),
                    child: _orderRows(
                      orders: deliveries,
                      empty: 'Danes ni vračil.',
                      overflowPhase: OrderPhase.deliveries,
                      subtitle: (o) => [
                        if (o.deliveryAt != null) Fmt.time(o.deliveryAt),
                        if (o.customerAddress.isNotEmpty) o.customerAddress,
                      ].join(' · '),
                      actionLabel: 'Vrni',
                      // Vračilo NIKOLI ni en dotik: skeniranje vseh kosov in
                      // podpis stranke sta bistvo — gumb samo odpre postopek.
                      onAction: (o) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReturnFlowScreen(orderId: o.id),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Accordion(
                    title: 'Delavnica',
                    icon: Icons.local_laundry_service_outlined,
                    color: AppColors.drying,
                    count: workshopTotal,
                    open: _open.contains('workshop'),
                    onToggle: () => _toggle('workshop'),
                    child: Column(
                      children: [
                        for (final p in [
                          OrderPhase.washing,
                          OrderPhase.drying,
                          OrderPhase.ready,
                          OrderPhase.deliveries,
                        ])
                          _LinkRow(
                            label: p.label,
                            value: counts[p] ?? 0,
                            onTap: () => openOrdersPhase(ref, p),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _Accordion(
                    title: 'Potrebna akcija',
                    icon: Icons.flag_outlined,
                    color: action.pickupLate.isEmpty
                        ? AppColors.awaitingWash
                        : AppColors.danger,
                    count: action.total,
                    open: _open.contains('action'),
                    onToggle: () => _toggle('action'),
                    child: action.total == 0
                        ? const _EmptyLine('Vse je v redu.')
                        : Column(
                            children: [
                              if (action.pickupLate.isNotEmpty)
                                _LinkRow(
                                  label: 'Prevzem zamuja',
                                  value: action.pickupLate.length,
                                  valueColor: AppColors.danger,
                                  onTap: () =>
                                      openOrdersPhase(ref, OrderPhase.intake),
                                ),
                              if (action.notCalled.isNotEmpty)
                                _LinkRow(
                                  label: 'Ni klicano (osebni prevzem)',
                                  value: action.notCalled.length,
                                  onTap: () =>
                                      openOrdersPhase(ref, OrderPhase.ready),
                                ),
                              if (action.stuckItems.isNotEmpty)
                                _LinkRow(
                                  label: 'Kosi v "Mere in cena"',
                                  value: action.stuckItems.length,
                                  onTap: () =>
                                      openOrdersPhase(ref, OrderPhase.drying),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderRows({
    required List<WorkOrder> orders,
    required String empty,
    required OrderPhase overflowPhase,
    required String Function(WorkOrder) subtitle,
    required String actionLabel,
    required void Function(WorkOrder) onAction,
  }) {
    if (orders.isEmpty) return _EmptyLine(empty);
    final shown = orders.take(_maxRowsPerBlock).toList();
    final more = orders.length - shown.length;
    return Column(
      children: [
        for (final o in shown)
          _OrderRow(
            order: o,
            subtitle: subtitle(o),
            actionLabel: actionLabel,
            onAction: () => onAction(o),
          ),
        if (more > 0)
          TextButton(
            onPressed: () => openOrdersPhase(ref, overflowPhase),
            child: Text('Še $more · odpri seznam'),
          ),
      ],
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
}

/// Zaprt blok s števcem; razpre se na klik.
class _Accordion extends StatelessWidget {
  const _Accordion({
    required this.title,
    required this.icon,
    required this.color,
    required this.count,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color color;
  final int count;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: count == 0
                          ? AppColors.border.withValues(alpha: 0.6)
                          : color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: count == 0 ? AppColors.textMuted : color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (open) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
              child: child,
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
      ),
    ),
  );
}

/// Vrstica z imenom in številko, ki odpre ustrezen zavihek.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.valueColor,
  });

  final String label;
  final int value;
  final VoidCallback onTap;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.text,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
        ],
      ),
    ),
  );
}

/// Kompaktna vrstica naročila z eno akcijo (Prevzemi / Vrni).
class _OrderRow extends StatelessWidget {
  const _OrderRow({
    required this.order,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final WorkOrder order;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${order.number}  ${order.customerName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: onAction,
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
}

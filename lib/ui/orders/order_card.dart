import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../widgets/common.dart';
import 'order_detail_screen.dart';

class OrderCard extends ConsumerWidget {
  const OrderCard(this.order, {super.key, this.showChannel = false});

  final WorkOrder order;
  final bool showChannel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final items = state.itemsOf(order.id);
    final ready = state.readyCount(order.id);
    final overdue = order.isOverdue(DateTime.now());

    return AppCard(
      borderColor: overdue ? AppColors.danger.withValues(alpha: 0.5) : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderDetailScreen(orderId: order.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showChannel) ...[
                Icon(
                  AppIcons.forChannel(order.channel),
                  size: 16,
                  color: AppColors.forChannel(order.channel),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                order.number,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusChip.order(order.status, dense: true),
            ],
          ),
          const SizedBox(height: 8),
          _line(context),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  Fmt.pieces(items.length),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ReadyProgress(ready: ready, total: items.length),
              ),
            ],
          ),
          if (overdue) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 15, color: AppColors.danger),
                const SizedBox(width: 5),
                Text(
                  'Rok potekel ${Fmt.dateShort(order.dueAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Druga vrstica pove tisto, kar delavec potrebuje za naslednji korak:
  /// naslov in uro pri dostavi, rok pri osebnem prevzemu.
  Widget _line(BuildContext context) {
    IconData icon;
    String text;

    switch (order.status) {
      case OrderStatus.scheduledPickup:
        icon = Icons.local_shipping_outlined;
        text = 'Prevzem ${Fmt.dayHeader(order.pickupAt ?? order.createdAt)}'
            ' ob ${Fmt.time(order.pickupAt)} · ${order.customerAddress}';
      case OrderStatus.awaitingDelivery:
        icon = Icons.local_shipping_outlined;
        text = order.deliveryAt == null
            ? 'Za vračilo · ${order.customerAddress}'
            : 'Vračilo ${Fmt.dayHeader(order.deliveryAt!)}'
                ' ob ${Fmt.time(order.deliveryAt)} · ${order.customerAddress}';
      case OrderStatus.awaitingCollection:
        icon = Icons.storefront_outlined;
        text = 'Pripravljeno od ${Fmt.dateShort(order.readyAt)}'
            ' · ${order.customerPhone}';
      case OrderStatus.completed:
        icon = Icons.assignment_turned_in_outlined;
        text = 'Zaključeno ${Fmt.dateTime(order.completedAt)}';
      case OrderStatus.cancelled:
        icon = Icons.cancel_outlined;
        text = 'Preklicano';
      case OrderStatus.inProduction:
        icon = Icons.schedule;
        text = order.dueAt == null
            ? 'Sprejeto ${Fmt.dateShort(order.createdAt)}'
            : 'Rok ${Fmt.dayHeader(order.dueAt!)}';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

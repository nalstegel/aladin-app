import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../widgets/common.dart';
import 'order_detail_screen.dart';

/// Dejanje, ki ga je mogoče sprožiti kar s kartice na nadzorni plošči.
class OrderCardAction {
  const OrderCardAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

class OrderCard extends ConsumerWidget {
  const OrderCard(this.order, {super.key, this.action});

  final WorkOrder order;

  /// Gumb na dnu kartice ("Prevzemi", "Vrni"). Brez njega je kartica samo
  /// povezava na podrobnosti.
  final OrderCardAction? action;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final items = state.itemsOf(order.id);
    final progress = StageProgress.of(items);
    final now = DateTime.now();
    // Naročilo, ki čaka naš planiran prevzem, je normalno stanje: preproga je
    // še pri stranki. Rdeče postane šele, ko je termin prevzema mimo (QA v4 §8).
    final pendingIntake = order.status == OrderStatus.scheduledPickup;
    final pickupLate = order.isPickupOverdue(now);
    // Rdeče samo za resnično težavo: zamujen naš prevzem. Rok vračila je
    // nevsiljiv opomnik, "Zamuja" je nadomestil "Klicano" (V8 §4).
    final flagged = pickupLate;
    final accent = flagged
        ? AppColors.danger
        : pendingIntake
            ? AppColors.border
            : AppColors.forOrder(order.status);

    return AppCard(
      accent: accent,
      borderColor: flagged ? AppColors.danger.withValues(alpha: 0.4) : null,
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
              Text(
                order.number,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
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
              const SizedBox(width: 8),
              StatusChip(
                label: order.channel.label,
                color: AppColors.forChannel(order.channel),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (pendingIntake) ..._intakeLines() else _line(),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                flagged ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
                size: 15,
                color: flagged ? AppColors.danger : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                Fmt.pieces(items.length),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: flagged ? AppColors.danger : AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                // Pred prevzemom ni kaj meriti — "0/2 prevzeto" bi bil šum.
                child: items.isEmpty || pendingIntake
                    ? const SizedBox.shrink()
                    : StageProgressBar(progress),
              ),
              if (action != null) ...[
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: action!.onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        accent == AppColors.border ? AppColors.primary : accent,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(action!.label),
                ),
              ],
            ],
          ),
          if (pickupLate) ...[
            const SizedBox(height: 6),
            Text(
              'Prevzem zamuja · termin ${_pickupSlot()}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _pickupSlot() => '${Fmt.dayHeader(order.pickupAt!)} '
      '${Fmt.timeRange(order.pickupAt, order.pickupWindowEnd)}';

  /// Za naročila pred prevzemom so osnovni podatki vidni že na kartici:
  /// termin, naslov in telefon — brez odpiranja naročila (QA v4 §8).
  List<Widget> _intakeLines() => [
        _infoRow(
          Icons.schedule,
          order.pickupAt != null
              ? _pickupSlot()
              : 'Sprejeto ${Fmt.dateShort(order.createdAt)}',
        ),
        if (order.customerAddress.isNotEmpty) ...[
          const SizedBox(height: 4),
          _infoRow(Icons.place_outlined, order.customerAddress),
        ],
        if (order.customerPhone.isNotEmpty) ...[
          const SizedBox(height: 4),
          _infoRow(Icons.phone_outlined, Fmt.phone(order.customerPhone)),
        ],
      ];

  Widget _infoRow(IconData icon, String text) => Row(
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

  /// Druga vrstica pove tisto, kar delavec potrebuje za naslednji korak:
  /// naslov in uro pri dostavi, rok pri osebnem prevzemu.
  Widget _line() {
    IconData icon;
    String text;

    switch (order.status) {
      case OrderStatus.scheduledPickup:
        icon = Icons.schedule;
        if (order.pickupAt != null) {
          // Dostava ima dogovorjen termin, za katerega delavec še gre ven.
          text = '${Fmt.timeRange(order.pickupAt, order.pickupWindowEnd)} · '
              '${order.customerAddress}';
        } else {
          // Brez termina (npr. Pripeljano) je pomembnejši rok naročila.
          text = order.dueAt == null
              ? 'Sprejeto ${Fmt.dateShort(order.createdAt)}'
              : 'Rok ${Fmt.dayHeader(order.dueAt!)}';
        }
      case OrderStatus.awaitingDelivery:
        icon = Icons.schedule;
        text = order.deliveryAt == null
            ? 'Za vračilo · ${order.customerAddress}'
            : '${Fmt.time(order.deliveryAt)} · ${order.customerAddress}';
      case OrderStatus.awaitingCollection:
        icon = Icons.hourglass_empty;
        text = 'Čaka od ${Fmt.dateShort(order.readyAt)} · ${order.customerPhone}';
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

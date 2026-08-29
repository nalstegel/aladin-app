import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/rug_item.dart';
import '../orders/order_detail_screen.dart';
import '../widgets/common.dart';
import 'finish_sheet.dart';
import 'measure_sheet.dart';

/// Ena preproga. To okno se odpre ob vsakem skeniranju QR kode.
class RugDetailScreen extends ConsumerWidget {
  const RugDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final item = state.item(itemId);
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.help_outline,
          title: 'Kos $itemId ne obstaja',
          message: 'Etiketa je morda z drugega sistema ali poškodovana.',
        ),
      );
    }
    final order = state.order(item.orderId);
    final color = AppColors.forRug(item.status);

    return Scaffold(
      appBar: AppBar(title: Text(item.id)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          AppCard(
            padding: const EdgeInsets.all(18),
            accent: color,
            borderColor: color.withValues(alpha: 0.5),
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(AppIcons.forRug(item.status),
                      color: color, size: 30),
                ),
                const SizedBox(height: 12),
                Text(
                  item.status.label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.label} · naročilo #${item.orderNumber}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (order != null) ...[
            const SizedBox(height: 10),
            AppCard(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderDetailScreen(orderId: order.id),
                ),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.forChannel(order.channel),
                      size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.customerName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${state.readyCount(order.id)}/${order.itemCount} pripravljeno · ${order.status.label}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: AppColors.textMuted),
                ],
              ),
            ),
          ],
          if (item.condition.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppCard(
              borderColor: AppColors.awaitingWash.withValues(alpha: 0.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppColors.awaitingWash),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.condition,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SectionHeader('Mere in cena'),
          AppCard(
            child: item.isMeasured
                ? Column(
                    children: [
                      DetailRow('Vrsta', item.rugTypeName),
                      DetailRow(
                        'Mere',
                        item.manualM2 != null
                            ? 'ročni vnos'
                            : Fmt.dimensions(item.widthCm, item.lengthCm),
                      ),
                      DetailRow('Površina', Fmt.m2(item.m2)),
                      if (item.usesMinCharge)
                        DetailRow('Obračunano',
                            '${Fmt.m2(item.chargeableM2)} (minimalni obračun)'),
                      DetailRow(
                        'Osnova',
                        '${Fmt.money(item.basePrice)} '
                            '(${item.pricePerM2.toStringAsFixed(0)} €/m²)',
                      ),
                      for (final e in item.extras)
                        DetailRow(
                          e.name,
                          Fmt.money(e.amount(
                            base: item.basePrice,
                            m2: item.chargeableM2,
                          )),
                        ),
                      if (item.discountPercent > 0)
                        DetailRow(
                          'Popust ${item.discountPercent.toStringAsFixed(0)} %',
                          '−${Fmt.money(item.discountAmount)}',
                        ),
                      const Divider(height: 18),
                      DetailRow(
                        item.confirmedPrice != null
                            ? 'Potrjena cena'
                            : 'Izračun',
                        Fmt.money(item.price),
                        strong: true,
                      ),
                    ],
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Mere se vnesejo, ko preproga pride iz sušilnice.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
          ),
          if (item.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.sticky_note_2_outlined,
                      size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item.notes,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
          const SectionHeader('Zgodovina'),
          AppCard(child: _history(item)),
          const SectionHeader('Etiketa'),
          AppCard(
            child: Row(
              children: [
                QrImageView(
                  data: item.id,
                  size: 84,
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.id,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Ta koda vodi vedno na to preprogo.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
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
      bottomNavigationBar: _actions(context, ref, item),
    );
  }

  Widget _history(RugItem item) {
    if (item.history.isEmpty) {
      return const Text(
        'Ni zapisov.',
        style: TextStyle(fontSize: 13, color: AppColors.textMuted),
      );
    }
    final events = item.history.reversed.toList();
    return Column(
      children: [
        for (var i = 0; i < events.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: AppColors.forRug(events[i].status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        events[i].status.label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${Fmt.dateTime(events[i].at)} · ${events[i].userName}'
                        '${events[i].note.isEmpty ? '' : ' · ${events[i].note}'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _actions(BuildContext context, WidgetRef ref, RugItem item) {
    final repo = ref.read(repositoryProvider.notifier);
    final isAdmin = ref.watch(currentUserProvider)?.isAdmin ?? false;

    Widget? primary;
    switch (item.status) {
      case RugStatus.awaitingPickup:
      case RugStatus.awaitingWash:
        primary = FilledButton.icon(
          onPressed: () {
            repo.advance(item.id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${item.id}: korak zabeležen')),
            );
          },
          icon: const Icon(Icons.arrow_forward),
          label: Text(item.status.nextActionLabel!),
        );
      case RugStatus.drying:
        primary = FilledButton.icon(
          onPressed: () => MeasureSheet.show(context, item),
          icon: const Icon(Icons.straighten),
          label: const Text('Suho → vnesi mere'),
        );
      case RugStatus.finishing:
        primary = FilledButton.icon(
          onPressed: () => FinishSheet.show(context, item),
          icon: const Icon(Icons.euro),
          label: const Text('Vnesi mere in ceno'),
        );
      case RugStatus.ready:
      case RugStatus.returned:
        primary = null;
    }

    final canRewash =
        item.status != RugStatus.returned && item.status.order >= 2;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?primary,
            if (primary != null && (canRewash || isAdmin))
              const SizedBox(height: 8),
            Row(
              children: [
                if (canRewash)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _rewash(context, ref, item),
                      icon: const Icon(Icons.replay, size: 18),
                      label: const Text('Nazaj na pranje'),
                    ),
                  ),
                if (canRewash && isAdmin) const SizedBox(width: 10),
                if (isAdmin)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _override(context, ref, item),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Popravi status'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _rewash(
    BuildContext context,
    WidgetRef ref,
    RugItem item,
  ) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nazaj na pranje'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Razlog',
            hintText: 'Npr. madež ni šel ven',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Prekliči'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Potrdi'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    ref
        .read(repositoryProvider.notifier)
        .sendBackToWash(item.id, controller.text.trim());
  }

  Future<void> _override(
    BuildContext context,
    WidgetRef ref,
    RugItem item,
  ) async {
    var status = item.status;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Ročni popravek statusa'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<RugStatus>(
                initialValue: status,
                items: [
                  for (final s in RugStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => status = v ?? status),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'Razlog'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Prekliči'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Shrani'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    ref
        .read(repositoryProvider.notifier)
        .overrideStatus(item.id, status, reason.text.trim());
  }
}

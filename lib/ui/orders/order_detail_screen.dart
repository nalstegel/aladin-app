import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/return_proof.dart';
import '../../models/rug_item.dart';
import '../rugs/rug_detail_screen.dart';
import '../widgets/common.dart';
import 'labels_screen.dart';
import 'return_flow_screen.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final order = state.order(orderId);
    if (order == null) {
      return const Scaffold(body: Center(child: Text('Naročilo ne obstaja')));
    }
    final items = state.itemsOf(orderId);
    final ready = state.readyCount(orderId);
    final repo = ref.read(repositoryProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('Naročilo ${order.number}'),
        actions: [
          IconButton(
            tooltip: 'Etikete',
            icon: const Icon(Icons.qr_code_2),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LabelsScreen(orderId: orderId),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          _header(context, ref, ready, items.length),
          const SectionHeader('Podatki'),
          AppCard(
            child: Column(
              children: [
                DetailRow('Stranka', order.customerName),
                if (order.customerPhone.isNotEmpty)
                  DetailRow('Telefon', order.customerPhone),
                if (order.customerAddress.isNotEmpty)
                  DetailRow('Naslov', order.customerAddress),
                DetailRow('Način', order.channel.label),
                DetailRow('Predaja', order.handover.label),
                if (order.pickupAt != null)
                  DetailRow(
                    'Prevzem',
                    '${Fmt.date(order.pickupAt)} '
                        '${Fmt.timeRange(order.pickupAt, order.pickupWindowEnd)}',
                  ),
                if (order.deliveryAt != null)
                  DetailRow('Vračilo', Fmt.dateTime(order.deliveryAt)),
                if (order.dueAt != null)
                  DetailRow('Rok', Fmt.dateTime(order.dueAt)),
                DetailRow('Sprejeto',
                    '${Fmt.dateTime(order.createdAt)} · ${order.createdByName}'),
              ],
            ),
          ),
          if (order.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppCard(
              borderColor: AppColors.awaitingWash.withValues(alpha: 0.4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.sticky_note_2_outlined,
                      size: 18, color: AppColors.awaitingWash),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      order.notes,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SectionHeader(
            'Kosi',
            subtitle: 'Vsak kos ima svojo QR etiketo in svojo pot.',
            trailing: order.status.isOpen
                ? TextButton.icon(
                    onPressed: () {
                      final item = repo.addItemToOrder(orderId);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Dodan kos ${item.id}')),
                      );
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Dodaj kos'),
                  )
                : null,
          ),
          for (final item in items) ...[
            _ItemRow(item: item),
            const SizedBox(height: 8),
          ],
          const SectionHeader('Obračun'),
          _totals(state.orderM2(orderId), state.orderTotal(orderId), items),
          if (order.returnProof != null) ...[
            const SectionHeader('Dokazilo o vračilu'),
            _proof(order.returnProof!),
          ],
        ],
      ),
      bottomNavigationBar: _actions(context, ref, ready, items.length),
    );
  }

  Widget _header(
    BuildContext context,
    WidgetRef ref,
    int ready,
    int total,
  ) {
    final order = ref.watch(repositoryProvider).order(orderId)!;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.forChannel(order.channel)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(AppIcons.forChannel(order.channel),
                        size: 13,
                        color: AppColors.forChannel(order.channel)),
                    const SizedBox(width: 5),
                    Text(
                      order.channel.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.forChannel(order.channel),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              StatusChip.order(order.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            order.customerName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          PlainProgressBar(done: ready, total: total, label: 'pripravljeno'),
        ],
      ),
    );
  }

  Widget _totals(double m2, double total, List<RugItem> items) {
    final measured = items.where((i) => i.isMeasured).length;
    return AppCard(
      child: Column(
        children: [
          DetailRow('Izmerjeni kosi', '$measured / ${items.length}'),
          DetailRow('Skupaj površina', Fmt.m2(m2)),
          const Divider(height: 18),
          DetailRow('Skupaj za plačilo', Fmt.money(total), strong: true),
          if (measured < items.length)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Znesek še ni končen — nekateri kosi še niso izmerjeni.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _proof(ReturnProof proof) {
    return AppCard(
      borderColor: AppColors.ready.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DetailRow('Vrnjeno', Fmt.dateTime(proof.returnedAt)),
          DetailRow('Izvedel', proof.userName),
          DetailRow('Prevzel', proof.receivedByName.isEmpty
              ? '—'
              : proof.receivedByName),
          DetailRow(
              'Poskenirani kosi', Fmt.pieces(proof.scannedItemIds.length)),
          if (proof.hasSignature) ...[
            const SizedBox(height: 10),
            const Text(
              'Podpis stranke',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 6),
            Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: proof.signatureUrl != null && proof.signatureUrl!.isNotEmpty
                  ? Image.network(proof.signatureUrl!, fit: BoxFit.contain)
                  : Image.memory(
                      base64Decode(proof.signatureBase64!),
                      fit: BoxFit.contain,
                    ),
            ),
          ],
          if (proof.isOverride) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Brez podpisa · ${proof.overrideReason}'
                '${proof.overrideByName == null ? '' : ' (odobril: ${proof.overrideByName})'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _actions(
    BuildContext context,
    WidgetRef ref,
    int ready,
    int total,
  ) {
    final order = ref.watch(repositoryProvider).order(orderId)!;
    final repo = ref.read(repositoryProvider.notifier);
    if (!order.status.isOpen) return null;

    Widget wrap(Widget child) => Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(top: false, child: child),
        );

    if (order.status == OrderStatus.scheduledPickup) {
      return wrap(FilledButton.icon(
        onPressed: () {
          repo.markOrderPickedUp(orderId);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Preproge prevzete — čakajo na pranje'),
            ),
          );
        },
        icon: const Icon(Icons.local_shipping),
        label: const Text('Prevzeto pri stranki'),
      ));
    }

    if (order.status.isHandoverReady) {
      return wrap(FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: AppColors.ready),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReturnFlowScreen(orderId: orderId),
          ),
        ),
        icon: const Icon(Icons.fact_check_outlined),
        label: Text(
          order.handover == HandoverMode.customerCollects
              ? 'Predaja stranki'
              : 'Vračilo na naslov',
        ),
      ));
    }

    return wrap(Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LabelsScreen(orderId: orderId),
              ),
            ),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Etikete'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.hourglass_bottom),
            label: Text('$ready/$total pripravljeno'),
          ),
        ),
      ],
    ));
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final RugItem item;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forRug(item.status);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RugDetailScreen(itemId: item.id)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(AppIcons.forRug(item.status), color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.id,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  item.isMeasured
                      ? '${item.rugTypeName} · ${Fmt.dimensions(item.widthCm, item.lengthCm)} · ${Fmt.m2(item.m2)}'
                      : 'Mere še niso vnesene',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusChip.rug(item.status, dense: true),
              const SizedBox(height: 4),
              Text(
                item.isMeasured ? Fmt.money(item.price) : '—',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

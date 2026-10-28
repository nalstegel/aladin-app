import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../data/billing.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../models/return_proof.dart';
import '../../models/rug_item.dart';
import '../rugs/edit_pricing_sheet.dart';
import '../rugs/rug_detail_screen.dart';
import '../widgets/common.dart';
import '../widgets/undo_snackbar.dart';
import 'call_customer.dart';
import 'edit_customer_sheet.dart';
import 'edit_order_screen.dart';
import 'labels_screen.dart';
import 'pickup_sheet.dart';
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
          if (order.status.isOpen)
            IconButton(
              tooltip: 'Uredi naročilo',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditOrderScreen(orderId: orderId),
                ),
              ),
            ),
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
          // Zaključeno naročilo hrani dokazilo o vračilu — tega ne brišemo.
          if (order.status.isOpen)
            IconButton(
              tooltip: 'Izbriši naročilo',
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              onPressed: () =>
                  _confirmDeleteOrder(context, repo, order, items.length),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          _header(context, ref, ready, items.length),
          SectionHeader(
            'Podatki',
            // Ime, telefon in naslov se popravijo kar tu (V10 §1); "Zamenjaj
            // stranko" ostane v Uredi naročilo samo za pravo menjavo.
            trailing: order.status.isOpen
                ? TextButton.icon(
                    onPressed: () => EditCustomerSheet.show(context, orderId),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Uredi'),
                  )
                : null,
          ),
          AppCard(
            child: Column(
              children: [
                _InfoRow('Stranka', order.customerName),
                if (order.customerPhone.isNotEmpty)
                  _InfoRow(
                    'Telefon',
                    Fmt.phone(order.customerPhone),
                    icon: Icons.call,
                    // Klic iz podrobnosti se zabeleži enako kot iz seznama
                    // Pripravljeno (V10 §2).
                    onTap: () => callCustomer(context, ref, order),
                  ),
                if (order.customerAddress.isNotEmpty)
                  _InfoRow(
                    'Naslov',
                    order.customerAddress,
                    icon: Icons.directions,
                    onTap: () => _launch(
                      context,
                      openMaps(order.customerAddress),
                      'Zemljevida ni bilo mogoče odpreti.',
                    ),
                  ),
                _InfoRow('Predaja', order.handover.label),
                if (order.pickupAt != null)
                  _InfoRow(
                    'Prevzem',
                    '${Fmt.date(order.pickupAt)} '
                        '${Fmt.timeRange(order.pickupAt, order.pickupWindowEnd)}',
                  ),
                if (order.deliveryAt != null)
                  _InfoRow('Vračilo', Fmt.dateTime(order.deliveryAt)),
                if (order.dueAt != null)
                  _InfoRow('Rok', Fmt.dateTime(order.dueAt)),
                if (order.calledAt != null)
                  _InfoRow(
                    'Klicano',
                    '${Fmt.dateShort(order.calledAt)} ob ${Fmt.time(order.calledAt)}',
                  ),
                if (order.inVanAt != null)
                  _InfoRow('V kombiju', Fmt.dateTime(order.inVanAt)),
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
            _ItemRow(
              item: item,
              // Vrsto, mere, doplačila in ceno je mogoče popraviti, ko je kos
              // obračunan; prej teh podatkov še ni.
              onEdit: order.status.isOpen &&
                      item.isMeasured &&
                      item.status != RugStatus.returned
                  ? () => EditPricingSheet.show(context, item)
                  : null,
              onDelete: order.status.isOpen && items.length > 1
                  ? () => _confirmRemoveItem(context, repo, item)
                  : null,
            ),
            const SizedBox(height: 8),
          ],
          const SectionHeader('Obračun'),
          _totals(
            state.orderM2(orderId),
            order,
            billingFor(order, items),
            items,
          ),
          if (order.returnProof != null) ...[
            const SectionHeader('Dokazilo o vračilu'),
            _proof(order.returnProof!),
          ],
        ],
      ),
      bottomNavigationBar: _actions(context, ref, ready, items.length),
    );
  }

  static Future<void> _launch(
    BuildContext context,
    Future<bool> launch,
    String error,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await launch;
    } catch (_) {}
    if (!ok) messenger.showSnackBar(SnackBar(content: Text(error)));
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

  Widget _totals(
    double m2,
    WorkOrder order,
    OrderBilling billing,
    List<RugItem> items,
  ) {
    final measured = items.where((i) => i.isMeasured).length;
    return AppCard(
      child: Column(
        children: [
          DetailRow('Izmerjeni kosi', '$measured / ${items.length}'),
          DetailRow('Skupaj površina', Fmt.m2(m2)),
          const Divider(height: 18),
          DetailRow('Kosi', Fmt.money(billing.itemsTotal)),
          // Doplačila prevzema (Vnos/Iznos) in dostava so informacija
          // prevzema, ki se samo prenese v končni obračun (V8 §2).
          for (final e in order.orderExtras)
            DetailRow(e.name, Fmt.money(e.amount(base: 0, m2: 0))),
          if (billing.deliveryFee > 0)
            DetailRow('Dostavno doplačilo', Fmt.money(billing.deliveryFee)),
          if (billing.minimumTopUp > 0)
            DetailRow(
              'Minimum ${minimumDeliveryOrderTotal.toStringAsFixed(0)} €',
              Fmt.money(billing.minimumTopUp),
            ),
          const Divider(height: 18),
          DetailRow('Skupaj za plačilo', Fmt.money(billing.total), strong: true),
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
        // Odpre hiter korak prevzema z doplačili (V8 §2); šele Potrdi premakne
        // kose v Čaka pranje.
        onPressed: () async {
          final confirmed = await PickupSheet.show(context, orderId);
          if (confirmed && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Preproge prevzete — čakajo na pranje'),
              ),
            );
          }
        },
        icon: const Icon(Icons.local_shipping),
        label: Text(order.channel == OrderChannel.dropoff
            ? 'Prevzeto v delavnico'
            : 'Prevzeto pri stranki'),
      ));
    }

    if (order.status.isHandoverReady) {
      final returnButton = FilledButton.icon(
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
      );
      // Dostava: glavna akcija je V kombi (V8 §4); ko je naročilo v kombiju,
      // je glavna akcija vračilo, V Pripravljeno pa ga vrne Iz kombija.
      if (order.status == OrderStatus.awaitingDelivery) {
        return wrap(Row(
          children: [
            Expanded(
              child: order.inVanAt == null
                  ? OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ReturnFlowScreen(orderId: orderId),
                        ),
                      ),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Vračilo'),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => repo.removeFromVan(orderId),
                      icon: const Icon(Icons.undo),
                      label: const Text('Iz kombija'),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: order.inVanAt == null
                  ? FilledButton.icon(
                      onPressed: () {
                        repo.sendToVan(orderId);
                        showUndoSnackBar(
                          context,
                          '${order.number} je v kombiju.',
                          () => repo.removeFromVan(orderId),
                        );
                      },
                      icon: const Icon(Icons.local_shipping),
                      label: const Text('V kombi'),
                    )
                  : returnButton,
            ),
          ],
        ));
      }
      return wrap(returnButton);
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

Future<void> _confirmRemoveItem(
  BuildContext context,
  Repository repo,
  RugItem item,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Odstrani kos?'),
      content: Text('Kos ${item.id} bo trajno odstranjen iz naročila.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Prekliči'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Odstrani'),
        ),
      ],
    ),
  );
  if (ok != true) return;

  repo.removeItemFromOrder(item.id);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Kos ${item.id} odstranjen')),
    );
  }
}

Future<void> _confirmDeleteOrder(
  BuildContext context,
  Repository repo,
  WorkOrder order,
  int itemCount,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Izbrišem naročilo ${order.number}?'),
      content: Text(
        '${order.customerName} · ${Fmt.pieces(itemCount)}\n\n'
        'Naročilo in vsi njegovi kosi bodo trajno izbrisani. Že natisnjene '
        'etikete ne bodo več delovale.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Prekliči'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Izbriši'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final route = ModalRoute.of(context);

  // Nazaj na prvi zaslon: zaslon pod tem (npr. kos tega naročila) bi sicer
  // ostal brez podatkov. Naročilo izbrišemo šele, ko se ta zaslon zapre —
  // sicer bi se med animacijo zaprtja pokazalo "Naročilo ne obstaja".
  navigator.popUntil((r) => r.isFirst);
  await route?.completed;

  final deleted = repo.deleteOrder(order.id);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        deleted
            ? 'Naročilo ${order.number} izbrisano'
            : 'Naročila ${order.number} ni bilo mogoče izbrisati.',
      ),
    ),
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, this.onEdit, this.onDelete});

  final RugItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

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
          // En sam gumb namesto dveh ikon: vrstica je že polna in na ožjih
          // telefonih bi se ID kosa prelomil.
          if (onEdit != null || onDelete != null)
            PopupMenuButton<_ItemAction>(
              tooltip: 'Več',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
              onSelected: (action) => switch (action) {
                _ItemAction.edit => onEdit?.call(),
                _ItemAction.remove => onDelete?.call(),
              },
              itemBuilder: (_) => [
                if (onEdit != null)
                  const PopupMenuItem(
                    value: _ItemAction.edit,
                    child: Text('Uredi kos'),
                  ),
                if (onDelete != null)
                  const PopupMenuItem(
                    value: _ItemAction.remove,
                    child: Text(
                      'Odstrani kos',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _ItemAction { edit, remove }

/// Vrstica bloka Podatki: labele v stolpcu enake širine, vrednosti poravnane
/// levo pod sabo, da se blok hitro prebere (QA v4 §8). Telefon in naslov sta
/// klikljiva (klic / Maps) in to kažeta z ikono na desni.
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.icon, this.onTap});

  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: onTap == null ? AppColors.text : AppColors.primary,
              ),
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: 8),
            Icon(icon, size: 18, color: AppColors.primary),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: row,
    );
  }
}

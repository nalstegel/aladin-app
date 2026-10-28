import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../data/order_phases.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../widgets/common.dart';
import '../widgets/undo_snackbar.dart';
import 'call_customer.dart';
import 'order_detail_screen.dart';
import 'pickup_sheet.dart';
import 'return_flow_screen.dart';

Future<void> _launch(
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

void _openOrder(BuildContext context, WorkOrder order) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: order.id)),
);

/// Vrstica filtrov Vse / LJ / MB / CE / DOL — enaka v Pripravljeno in Dostave
/// (V10 §2). Regije se berejo iz `OrderLocation.values`, zato nova regija
/// dobi svoj filter sama, brez dela v tem zaslonu.
class RegionFilterBar extends StatelessWidget {
  const RegionFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.total,
    required this.countOf,
  });

  /// null = Vse.
  final OrderLocation? selected;
  final ValueChanged<OrderLocation?> onSelected;
  final int total;
  final int Function(OrderLocation) countOf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterPill(
              dense: true,
              label: 'Vse ($total)',
              selected: selected == null,
              onTap: () => onSelected(null),
            ),
            for (final l in OrderLocation.values) ...[
              const SizedBox(width: 6),
              FilterPill(
                dense: true,
                label: '${l.code} (${countOf(l)})',
                selected: selected == l,
                onTap: () => onSelected(l),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Katere sekcije Pripravljeno so razprte. Privzeto so vse zaprte (V10 §2:
/// manj scrollanja); izbira ostane, ko zamenjaš zavihek.
final readyOpenSectionsProvider = StateProvider<Set<String>>(
  (ref) => const {},
);

/// Zavihek **Pripravljeno** (V8 §4, V10 §2): cela naročila, v katerih so vsi
/// kosi obračunani. En seznam, brez pod-zavihkov:
///
/// * filtri regij,
/// * *Za dostavo* z gumbom **V kombi** (naročilo gre v zavihek Dostave),
/// * *Ni klicano* → klic zabeleži `calledAt` → *Klicano · čaka stranko*
///   (nič od tega ni rdeče).
///
/// Sekcije so zložljive in kažejo število naročil; prazna sekcija je skrita.
class ReadyList extends ConsumerStatefulWidget {
  const ReadyList({super.key, this.channel});

  final OrderChannel? channel;

  @override
  ConsumerState<ReadyList> createState() => _ReadyListState();
}

class _ReadyListState extends ConsumerState<ReadyList> {
  /// null = Vse.
  OrderLocation? _region;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final all =
        state.orders
            .where((o) => widget.channel == null || o.channel == widget.channel)
            .where((o) => OrderPhase.ready.containsOrder(o, state.itemsOf(o.id)))
            .toList()
          ..sort(
            (a, b) =>
                (a.readyAt ?? a.createdAt).compareTo(b.readyAt ?? b.createdAt),
          );

    if (all.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Nič ni pripravljeno',
        message: 'Naročila se tu pokažejo, ko so vsi kosi obračunani.',
      );
    }

    final shown = all
        .where((o) => _region == null || o.location == _region)
        .toList();
    final delivery = shown
        .where((o) => o.handover == HandoverMode.weDeliver)
        .toList();
    final notCalled = shown
        .where(
          (o) =>
              o.handover == HandoverMode.customerCollects && o.calledAt == null,
        )
        .toList();
    final waiting = shown
        .where(
          (o) =>
              o.handover == HandoverMode.customerCollects && o.calledAt != null,
        )
        .toList();

    return Column(
      children: [
        RegionFilterBar(
          selected: _region,
          onSelected: (r) => setState(() => _region = r),
          total: all.length,
          countOf: (l) => all.where((o) => o.location == l).length,
        ),
        UnitCaption(Fmt.orders(shown.length)),
        Expanded(
          child: shown.isEmpty
              ? EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Nič ni pripravljeno',
                  message: 'V regiji ${_region!.code} ni pripravljenih naročil.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                  children: [
                    _ReadySection(
                      id: 'delivery',
                      label: 'Za dostavo',
                      icon: Icons.local_shipping_outlined,
                      orders: delivery,
                    ),
                    _ReadySection(
                      id: 'notCalled',
                      label: 'Ni klicano',
                      icon: Icons.phone_missed_outlined,
                      orders: notCalled,
                    ),
                    _ReadySection(
                      id: 'waiting',
                      label: 'Klicano · čaka stranko',
                      icon: Icons.phone_in_talk_outlined,
                      orders: waiting,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Zložljiva sekcija s številom naročil; prazna se ne pokaže.
class _ReadySection extends ConsumerWidget {
  const _ReadySection({
    required this.id,
    required this.label,
    required this.icon,
    required this.orders,
  });

  final String id;
  final String label;
  final IconData icon;
  final List<WorkOrder> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (orders.isEmpty) return const SizedBox.shrink();
    final open = ref.watch(readyOpenSectionsProvider).contains(id);

    void toggle() {
      final notifier = ref.read(readyOpenSectionsProvider.notifier);
      final next = {...notifier.state};
      if (!next.remove(id)) next.add(id);
      notifier.state = next;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: AppColors.ready),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.ready.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${orders.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ready,
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
              for (var i = 0; i < orders.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _ReadyRow(order: orders[i]),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadyRow extends ConsumerWidget {
  const _ReadyRow({required this.order});

  final WorkOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final pieces = state.itemsOf(order.id).length;
    final repo = ref.read(repositoryProvider.notifier);
    final delivery = order.handover == HandoverMode.weDeliver;
    final phone = Fmt.phone(order.customerPhone);

    final String sub;
    if (delivery) {
      sub = [
        order.location.code,
        if (order.customerAddress.isNotEmpty) order.customerAddress,
      ].join(' · ');
    } else if (order.calledAt == null) {
      sub = [
        if (phone.isNotEmpty) phone,
        'pripravljeno ${Fmt.dateShort(order.readyAt)}',
      ].join(' · ');
    } else {
      final reminder = order.returnReminderAt;
      sub = [
        'Klicano ${Fmt.dateShort(order.calledAt)} ob ${Fmt.time(order.calledAt)}',
        'čaka stranko',
        if (reminder != null) 'rok vračila ${Fmt.dateShort(reminder)}',
      ].join(' · ');
    }

    // Klik na telefon zabeleži prvi klic (V8 §4), nato odpre klicalnik — enako
    // kot klic iz podrobnosti naročila (V10 §2).
    void call() => callCustomer(context, ref, order);

    final Widget action;
    if (delivery) {
      action = FilledButton(
        onPressed: () {
          repo.sendToVan(order.id);
          showUndoSnackBar(
            context,
            '${order.number} je v kombiju.',
            () => repo.removeFromVan(order.id),
          );
        },
        style: _smallButton(),
        child: const Text('V kombi'),
      );
    } else if (order.calledAt == null) {
      action = FilledButton.icon(
        onPressed: order.customerPhone.isEmpty ? null : call,
        icon: const Icon(Icons.phone, size: 16),
        label: const Text('Pokliči'),
        style: _smallButton(),
      );
    } else {
      action = IconButton.filledTonal(
        tooltip: 'Pokliči',
        onPressed: order.customerPhone.isEmpty ? null : call,
        icon: const Icon(Icons.phone, size: 18),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openOrder(context, order),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        order.number,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          order.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        Fmt.pieces(pieces),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 2,
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
            action,
          ],
        ),
      ),
    );
  }
}

ButtonStyle _smallButton() => FilledButton.styleFrom(
  minimumSize: const Size(0, 36),
  padding: const EdgeInsets.symmetric(horizontal: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
);

/// Peti zavihek **Dostave** (V8 §4, V10 §3): manifest robe v kombiju. Vsebuje
/// samo naročila, označena V kombi; naročilo ga zapusti šele z vračilom
/// (preverjanje kosov → podpis → Vrnjeno) ali z "Iz kombija".
///
/// Vrstni red je ročen: kartico primeš za ročaj (ali jo dolgo pritisneš) in
/// povlečeš gor/dol. Shrani se v bazi (`WorkOrder.vanOrder`), zato ostane po
/// menjavi zavihka in ponovnem zagonu. Poti ne generiramo — ruto sestavi
/// voznik sproti in Maps odpre sam.
class DeliveriesList extends ConsumerStatefulWidget {
  const DeliveriesList({super.key, this.channel});

  final OrderChannel? channel;

  @override
  ConsumerState<DeliveriesList> createState() => _DeliveriesListState();
}

class _DeliveriesListState extends ConsumerState<DeliveriesList> {
  /// null = Vse.
  OrderLocation? _region;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final all = sortedForVan(
      state.orders
          .where((o) => widget.channel == null || o.channel == widget.channel)
          .where(
            (o) => OrderPhase.deliveries.containsOrder(o, state.itemsOf(o.id)),
          ),
    );
    final list = all.where((o) => _region == null || o.location == _region).toList();

    return Column(
      children: [
        RegionFilterBar(
          selected: _region,
          onSelected: (r) => setState(() => _region = r),
          total: all.length,
          countOf: (l) => all.where((o) => o.location == l).length,
        ),
        UnitCaption(Fmt.orders(list.length)),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: 'Kombi je prazen',
                  message:
                      'Naročila za dostavo se tu pokažejo, ko jih v '
                      'Pripravljeno označiš V kombi.',
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: list.length,
                  onReorderItem: (oldIndex, newIndex) {
                    final ids = [for (final o in list) o.id];
                    ids.insert(newIndex, ids.removeAt(oldIndex));
                    // Pri filtriranem seznamu je to samo podmnožica — ostale
                    // regije obdržijo svoja mesta.
                    ref.read(repositoryProvider.notifier).reorderVan(ids);
                  },
                  itemBuilder: (_, i) => Padding(
                    key: ValueKey(list[i].id),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _DeliveryRow(order: list[i], index: i),
                  ),
                ),
        ),
      ],
    );
  }
}

class _DeliveryRow extends ConsumerWidget {
  const _DeliveryRow({required this.order, required this.index});

  final WorkOrder order;

  /// Mesto v prikazanem seznamu — za ročaj in zaporedno številko.
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final pieces = state.itemsOf(order.id).length;
    final total = state.orderTotal(order.id);
    final repo = ref.read(repositoryProvider.notifier);

    Widget link(IconData icon, String text, VoidCallback action) {
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AppCard(
      accent: AppColors.forChannel(order.channel),
      onTap: () => _openOrder(context, order),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Majhen ročaj za vlečenje; dolg pritisk kjerkoli na kartici
              // deluje enako.
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.drag_indicator,
                        size: 22,
                        color: AppColors.textMuted,
                      ),
                      Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  '${order.number}  ${order.customerName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StatusChip(
                label: order.location.code,
                color: AppColors.textMuted,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              Fmt.pieces(pieces),
              Fmt.money(total),
              if (order.deliveryAt != null)
                '${Fmt.dateShort(order.deliveryAt)} '
                    '${Fmt.time(order.deliveryAt)}',
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          if (order.customerPhone.isNotEmpty)
            link(
              Icons.phone_outlined,
              Fmt.phone(order.customerPhone),
              () => callCustomer(context, ref, order),
            ),
          if (order.customerAddress.isNotEmpty)
            link(
              Icons.place_outlined,
              order.customerAddress,
              () => _launch(
                context,
                openMaps(order.customerAddress),
                'Zemljevida ni bilo mogoče odpreti.',
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: _smallButton().merge(
                    FilledButton.styleFrom(backgroundColor: AppColors.ready),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReturnFlowScreen(orderId: order.id),
                    ),
                  ),
                  icon: const Icon(Icons.fact_check_outlined, size: 16),
                  label: const Text('Vrni'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  repo.removeFromVan(order.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${order.number} je spet v Pripravljeno.'),
                    ),
                  );
                },
                child: const Text('Iz kombija'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Gumb "Prevzeto" za kartice v zavihku Naročila — odpre hitri korak prevzema.
Future<void> startPickup(BuildContext context, WorkOrder order) async {
  final confirmed = await PickupSheet.show(context, order.id);
  if (confirmed && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${order.number} prevzeto — čaka na pranje.')),
    );
  }
}

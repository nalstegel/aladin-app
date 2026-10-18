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

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, this.count);

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
    child: Text(
      '${label.toUpperCase()} · $count',
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: AppColors.textMuted,
      ),
    ),
  );
}

/// Zavihek **Pripravljeno** (V8 §4): cela naročila, v katerih so vsi kosi
/// obračunani. En seznam, brez pod-zavihkov:
///
/// * osebni prevzem: *Ni klicano* → klik na telefon zabeleži *Klicano …* →
///   *Čaka stranko* (nič od tega ni rdeče),
/// * dostava: glavna akcija **V kombi** premakne naročilo v zavihek Dostave.
class ReadyList extends ConsumerWidget {
  const ReadyList({super.key, this.channel});

  final OrderChannel? channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final all =
        state.orders
            .where((o) => channel == null || o.channel == channel)
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

    final notCalled = all
        .where(
          (o) =>
              o.handover == HandoverMode.customerCollects && o.calledAt == null,
        )
        .toList();
    final delivery = all
        .where((o) => o.handover == HandoverMode.weDeliver)
        .toList();
    final waiting = all
        .where(
          (o) =>
              o.handover == HandoverMode.customerCollects && o.calledAt != null,
        )
        .toList();

    Widget group(String label, List<WorkOrder> list) => list.isEmpty
        ? const SizedBox.shrink()
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GroupLabel(label, list.length),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _ReadyRow(order: list[i]),
                    ],
                  ],
                ),
              ),
            ],
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        group('Ni klicano', notCalled),
        group('Za dostavo', delivery),
        group('Klicano · čaka stranko', waiting),
      ],
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

    Future<void> call() async {
      // Klik na telefon zabeleži prvi klic (V8 §4), nato odpre klicalnik.
      repo.markCalled(order.id);
      await _launch(
        context,
        callPhone(order.customerPhone),
        'Klica ni bilo mogoče začeti.',
      );
    }

    final Widget action;
    if (delivery) {
      action = FilledButton(
        onPressed: () {
          repo.sendToVan(order.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${order.number} je v kombiju.'),
              action: SnackBarAction(
                label: 'Razveljavi',
                onPressed: () => repo.removeFromVan(order.id),
              ),
            ),
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

/// Peti zavihek **Dostave** (V8 §4): manifest robe v kombiju. Vsebuje samo
/// naročila, označena V kombi; naročilo ga zapusti šele z vračilom (preverjanje
/// kosov → podpis → Vrnjeno) ali z "Iz kombija".
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
    final all =
        state.orders
            .where((o) => widget.channel == null || o.channel == widget.channel)
            .where(
              (o) => OrderPhase.deliveries.containsOrder(o, state.itemsOf(o.id)),
            )
            .toList()
          ..sort(
            (a, b) => (a.deliveryAt ?? a.inVanAt ?? a.createdAt).compareTo(
              b.deliveryAt ?? b.inVanAt ?? b.createdAt,
            ),
          );
    final list = all.where((o) => _region == null || o.location == _region).toList();
    int count(OrderLocation l) => all.where((o) => o.location == l).length;

    final withAddress = list.where((o) => o.customerAddress.isNotEmpty).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterPill(
                  label: 'Vse (${all.length})',
                  selected: _region == null,
                  onTap: () => setState(() => _region = null),
                ),
                for (final l in OrderLocation.values) ...[
                  const SizedBox(width: 8),
                  FilterPill(
                    label: '${l.code} (${count(l)})',
                    selected: _region == l,
                    onTap: () => setState(() => _region = l),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: withAddress.isEmpty
                  ? null
                  : () => _openRoute(context, withAddress),
              icon: const Icon(Icons.alt_route, size: 18),
              label: Text('Odpri pot · ${withAddress.length} postankov'),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: 'Kombi je prazen',
                  message:
                      'Naročila za dostavo se tu pokažejo, ko jih v '
                      'Pripravljeno označiš V kombi.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _DeliveryRow(order: list[i]),
                ),
        ),
      ],
    );
  }

  Future<void> _openRoute(BuildContext context, List<WorkOrder> orders) async {
    final messenger = ScaffoldMessenger.of(context);
    final addresses = [for (final o in orders) o.customerAddress];
    if (addresses.length > maxRouteStops) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Zemljevid prenese največ $maxRouteStops postankov — odprtih '
            'je prvih $maxRouteStops.',
          ),
        ),
      );
    }
    var ok = false;
    try {
      ok = await openMapsRoute(addresses);
    } catch (_) {}
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Zemljevida ni bilo mogoče odpreti.')),
      );
    }
  }
}

class _DeliveryRow extends ConsumerWidget {
  const _DeliveryRow({required this.order});

  final WorkOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final pieces = state.itemsOf(order.id).length;
    final total = state.orderTotal(order.id);
    final repo = ref.read(repositoryProvider.notifier);

    Widget link(IconData icon, String text, Future<bool> Function() action,
        String error) {
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _launch(context, action(), error),
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
              () => callPhone(order.customerPhone),
              'Klica ni bilo mogoče začeti.',
            ),
          if (order.customerAddress.isNotEmpty)
            link(
              Icons.place_outlined,
              order.customerAddress,
              () => openMaps(order.customerAddress),
              'Zemljevida ni bilo mogoče odpreti.',
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

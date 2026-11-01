import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/launch.dart';
import '../../core/order_id.dart';
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

/// Vrstica filtrov Vse / LJ / MB / CE / DOL — enaka v Naročila, Pripravljeno in
/// Dostave (V10 §2). Regije se berejo iz `OrderLocation.values`, zato nova regija
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

/// Trije hitri zavihki znotraj Pripravljeno (po stanju naročila, ne po regiji).
enum ReadyTab {
  delivery('Za dostavo'),
  notCalled('Ni klicano'),
  called('Klicano');

  const ReadyTab(this.label);

  final String label;

  bool contains(WorkOrder o) => switch (this) {
    ReadyTab.delivery => o.handover == HandoverMode.weDeliver,
    ReadyTab.notCalled =>
      o.handover == HandoverMode.customerCollects && o.calledAt == null,
    ReadyTab.called =>
      o.handover == HandoverMode.customerCollects && o.calledAt != null,
  };

  String get emptyTitle => switch (this) {
    ReadyTab.delivery => 'Ni naročil za dostavo',
    ReadyTab.notCalled => 'Ni neklicanih strank',
    ReadyTab.called => 'Nobena stranka še ni klicana',
  };
}

/// Izbrani zavihek Pripravljeno. Ostane, ko zamenjaš zavihek strani Naročila
/// in se vrneš.
final readyTabProvider = StateProvider<ReadyTab>((ref) => ReadyTab.delivery);

/// Zavihek **Pripravljeno** (V8 §4, V10 §2): cela naročila, v katerih so vsi
/// kosi obračunani. Dva neodvisna filtra, brez drsenja med sekcijami:
///
/// * zgoraj filtri regij Vse / LJ / MB / CE / DOL,
/// * pod njimi trije zavihki s števcem, ki takoj zamenjajo seznam:
///   *Za dostavo*: naročilo ostane tu do dogovorjenega dne vračila (Rok →
///   Uredi na podrobnostih), nato se samo prestavi v Dostave. Gumb **V kombi**
///   ga tja prestavi ročno, če termina ni,
///   *Ni klicano* → klic zabeleži `calledAt` → *Klicano* (nič od tega ni
///   rdeče).
///
/// Regijski filter velja v vseh treh zavihkih, zato so števci zavihkov števci
/// izbrane regije. Števci pri regijah pa so vedno čez vse tri zavihke.
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
    // Ob polnoči se naročilo z dogovorjenim vračilom samo prestavi v Dostave.
    final today = ref.watch(todayProvider);
    final all =
        state.orders
            .where((o) => widget.channel == null || o.channel == widget.channel)
            .where(
              (o) => OrderPhase.ready.containsOrder(
                o,
                state.itemsOf(o.id),
                now: today,
              ),
            )
            .toList()
          ..sort((a, b) => compareOrderIds(a.id, b.id));

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
    final tab = ref.watch(readyTabProvider);
    final list = shown.where(tab.contains).toList();

    return Column(
      children: [
        RegionFilterBar(
          selected: _region,
          onSelected: (r) => setState(() => _region = r),
          total: all.length,
          countOf: (l) => all.where((o) => o.location == l).length,
        ),
        _ReadyTabBar(
          selected: tab,
          onSelected: (t) => ref.read(readyTabProvider.notifier).state = t,
          countOf: (t) => shown.where(t.contains).length,
        ),
        UnitCaption(Fmt.orders(list.length)),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: tab.emptyTitle,
                  message: _region == null
                      ? null
                      : 'V regiji ${_region!.code} ni takih naročil.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ReadyRow(order: list[i]),
                ),
        ),
      ],
    );
  }
}

/// Za dostavo | Ni klicano | Klicano, vsak s številom naročil. Namenoma ni
/// `TabBar`: ta bi se tepel z vodoravnim poteznim drsanjem zunanjih zavihkov
/// strani, tu pa zavihek zamenja samo tap.
class _ReadyTabBar extends StatelessWidget {
  const _ReadyTabBar({
    required this.selected,
    required this.onSelected,
    required this.countOf,
  });

  final ReadyTab selected;
  final ValueChanged<ReadyTab> onSelected;
  final int Function(ReadyTab) countOf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.border.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final t in ReadyTab.values)
              Expanded(
                child: _ReadyTabCell(
                  tab: t,
                  count: countOf(t),
                  selected: t == selected,
                  onTap: () => onSelected(t),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReadyTabCell extends StatelessWidget {
  const _ReadyTabCell({
    required this.tab,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final ReadyTab tab;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.ready : AppColors.textMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: color,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                tab.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: color,
                ),
              ),
            ),
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
        // Dogovorjen termin: naročilo je do tega dne tu, nato v Dostavah.
        if (order.deliveryAt != null)
          'vračilo ${Fmt.dateShort(order.deliveryAt)} '
              '${Fmt.timeRange(order.deliveryAt, order.deliveryWindowEnd)}',
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

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      onTap: () => _openOrder(context, order),
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
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

ButtonStyle _smallButton() => FilledButton.styleFrom(
  minimumSize: const Size(0, 36),
  padding: const EdgeInsets.symmetric(horizontal: 14),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
);

/// Peti zavihek **Dostave** (V8 §4, V10 §3): zjutraj vidimo vse, kar ta dan
/// peljemo. Vsebuje naročila z dogovorjenim vračilom danes (ali prej, če še
/// niso predana) in ročno označena V kombi — kombi ni pogoj. Naročilo ga
/// zapusti šele z vračilom (preverjanje kosov → podpis → Vrnjeno), s
/// spremembo dne vračila ali z "Iz kombija".
///
/// Privzeto so naročila po ID-ju kot povsod. Ročno jih urediš tako, da kartico
/// primeš za ročaj (ali jo dolgo pritisneš) in povlečeš gor/dol. Ročni vrstni
/// red se shrani v bazi (`WorkOrder.vanOrder`), zato ostane po menjavi zavihka
/// in ponovnem zagonu; naročila, dodana pozneje, pridejo za urejena. Poti ne generiramo — ruto sestavi
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
    final today = ref.watch(todayProvider);
    final all = sortedForVan(
      state.orders
          .where((o) => widget.channel == null || o.channel == widget.channel)
          .where(
            (o) => OrderPhase.deliveries.containsOrder(
              o,
              state.itemsOf(o.id),
              now: today,
            ),
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
                  title: 'Ni dostav',
                  message:
                      'Naročila za dostavo se tu pokažejo na dogovorjen dan '
                      'vračila (Rok → Uredi) ali ko jih v Pripravljeno '
                      'označiš V kombi.',
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
    final today = ref.watch(todayProvider);
    // Na seznamu je zaradi dogovorjenega dne, ne zaradi kombija: "Iz kombija"
    // je tu brez pomena — termin se spremeni na podrobnostih (Rok → Uredi).
    final byTerm = order.isDeliveryDay(today);

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
            [Fmt.pieces(pieces), Fmt.money(total)].join(' · '),
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          // Časovni okvir vračila — voznik zjutraj vidi, kdaj mora biti kje.
          // Zamujen dan (še ni predano) je izpisan z datumom.
          if (order.deliveryAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  // Expanded: dolg "Ponedeljek, 31. 10. · 09:00–11:00" se na
                  // ozkem telefonu prelomi, okvir pa ostane cel viden.
                  Expanded(
                    child: Text(
                      _isSameDay(order.deliveryAt!, today)
                          ? Fmt.timeRange(
                              order.deliveryAt,
                              order.deliveryWindowEnd,
                            )
                          : Fmt.dayWindow(
                              order.deliveryAt,
                              order.deliveryWindowEnd,
                            ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
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
              if (!byTerm) ...[
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
                        content: Text(
                          '${order.number} je spet v Pripravljeno.',
                        ),
                      ),
                    );
                  },
                  child: const Text('Iz kombija'),
                ),
              ],
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

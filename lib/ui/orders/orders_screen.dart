import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/order_phases.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/rug_item.dart';
import '../rugs/quick_finish_sheet.dart';
import '../rugs/rug_detail_screen.dart';
import '../widgets/common.dart';
import 'new_order_screen.dart';
import 'order_card.dart';
import 'order_detail_screen.dart';

/// Filter nad seznamom naročil. Kanal ni več zavihek — naročila vseh treh
/// poti so v istem seznamu, kanal pa je oznaka na kartici. Faza (korak
/// proizvodnje) ni več ločen filter, ker to zdaj predstavljajo zavihki.
class OrderFilter {
  const OrderFilter({this.channel});

  final OrderChannel? channel;

  bool get isEmpty => channel == null;
  int get count => channel == null ? 0 : 1;

  OrderFilter copyWith({OrderChannel? channel, bool clearChannel = false}) =>
      OrderFilter(channel: clearChannel ? null : (channel ?? this.channel));
}

final orderFilterProvider = StateProvider<OrderFilter>(
  (ref) => const OrderFilter(),
);

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: OrderPhase.values.length,
    vsync: this,
  );
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(orderFilterProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageHeader(
              'Naročila',
              trailing: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.tune, size: 24),
                    tooltip: 'Filter',
                    onPressed: _openFilter,
                  ),
                  if (!filter.isEmpty)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppColors.surface,
                            width: 1.5,
                          ),
                        ),
                        constraints: const BoxConstraints(minWidth: 18),
                        child: Text(
                          '${filter.count}',
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
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SearchField(
                controller: _search,
                hint: 'Išči po ID-ju, imenu, telefonu, naslovu',
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            if (_query.isNotEmpty)
              Expanded(child: _SearchResults(query: _query))
            else ...[
              TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: AppColors.border,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                tabs: [for (final p in OrderPhase.values) Tab(text: p.label)],
              ),
              if (!filter.isEmpty) _activeFilterBar(filter),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    for (final p in OrderPhase.values)
                      if (p.showsItems)
                        _ItemGroupList(phase: p)
                      else if (p == OrderPhase.ready)
                        const _ReadyList()
                      else
                        const _IntakeList(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const NewOrderScreen()),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Novo naročilo'),
      ),
    );
  }

  Widget _activeFilterBar(OrderFilter filter) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (filter.channel != null)
                  _removableChip(
                    filter.channel!.label,
                    AppColors.forChannel(filter.channel!),
                    () => ref.read(orderFilterProvider.notifier).state = filter
                        .copyWith(clearChannel: true),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => ref.read(orderFilterProvider.notifier).state =
                const OrderFilter(),
            child: const Text('Počisti'),
          ),
        ],
      ),
    );
  }

  Widget _removableChip(String label, Color color, VoidCallback onRemove) {
    return GestureDetector(
      onTap: onRemove,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.close, size: 14, color: color),
          ],
        ),
      ),
    );
  }

  Future<void> _openFilter() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _FilterSheet(),
    );
  }
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(orderFilterProvider);
    void set(OrderFilter f) => ref.read(orderFilterProvider.notifier).state = f;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const Text(
              'Kanal',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterPill(
                  label: 'Vse',
                  selected: filter.channel == null,
                  onTap: () => set(filter.copyWith(clearChannel: true)),
                ),
                for (final c in OrderChannel.values)
                  FilterPill(
                    label: c.label,
                    selected: filter.channel == c,
                    onTap: () => set(filter.copyWith(channel: c)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => set(const OrderFilter()),
                    child: const Text('Počisti'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Pokaži'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Zavihek "Naročila": cela naročila, ki še niso prišla v proces — v praksi
/// skoraj vedno naši planirani prevzemi. Najbližji termin zgoraj.
class _IntakeList extends ConsumerWidget {
  const _IntakeList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final filter = ref.watch(orderFilterProvider);

    final list =
        state.orders
            .where((o) => filter.channel == null || o.channel == filter.channel)
            .where(
              (o) => OrderPhase.intake.containsOrder(o, state.itemsOf(o.id)),
            )
            .toList()
          ..sort(
            (a, b) => (a.pickupAt ?? a.createdAt).compareTo(
              b.pickupAt ?? b.createdAt,
            ),
          );

    if (list.isEmpty) {
      return _empty(
        filter,
        'Ni novih naročil',
        'Novo naročilo dodaš z gumbom spodaj desno.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => OrderCard(list[i]),
    );
  }
}

/// Zavihek "Pripravljeno": cela naročila, v katerih so vsi kosi obračunani.
/// Razdeljena sta avtomatsko po načinu predaje — kaj čaka osebni prevzem in
/// kaj moramo peljati na naslov.
class _ReadyList extends ConsumerStatefulWidget {
  const _ReadyList();

  @override
  ConsumerState<_ReadyList> createState() => _ReadyListState();
}

class _ReadyListState extends ConsumerState<_ReadyList> {
  HandoverMode _mode = HandoverMode.customerCollects;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final filter = ref.watch(orderFilterProvider);

    final all =
        state.orders
            .where((o) => filter.channel == null || o.channel == filter.channel)
            .where(
              (o) => OrderPhase.ready.containsOrder(o, state.itemsOf(o.id)),
            )
            .toList()
          ..sort(
            (a, b) =>
                (a.readyAt ?? a.createdAt).compareTo(b.readyAt ?? b.createdAt),
          );
    int count(HandoverMode m) => all.where((o) => o.handover == m).length;
    final list = all.where((o) => o.handover == _mode).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              FilterPill(
                label: 'Pripeljano (${count(HandoverMode.customerCollects)})',
                selected: _mode == HandoverMode.customerCollects,
                onTap: () =>
                    setState(() => _mode = HandoverMode.customerCollects),
              ),
              const SizedBox(width: 8),
              FilterPill(
                label: 'Dostave (${count(HandoverMode.weDeliver)})',
                selected: _mode == HandoverMode.weDeliver,
                onTap: () => setState(() => _mode = HandoverMode.weDeliver),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _empty(
                  filter,
                  _mode == HandoverMode.customerCollects
                      ? 'Nič ne čaka osebnega prevzema'
                      : 'Nič ne čaka dostave',
                  null,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => OrderCard(list[i]),
                ),
        ),
      ],
    );
  }
}

/// Zavihka "Čaka pranje" in "Sušenje": posamezni kosi, grupirani po
/// naročilu, najstarejši prihod zgoraj.
class _ItemGroupList extends ConsumerWidget {
  const _ItemGroupList({required this.phase});

  final OrderPhase phase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final filter = ref.watch(orderFilterProvider);
    final groups = groupsFor(state, phase, channel: filter.channel);

    if (groups.isEmpty) {
      return _empty(
        filter,
        phase == OrderPhase.washing
            ? 'Nič ne čaka na pranje'
            : 'Nič ni trenutno v sušenju',
        null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _GroupCard(group: groups[i], phase: phase),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.phase});

  final PhaseGroup group;
  final OrderPhase phase;

  @override
  Widget build(BuildContext context) {
    final order = group.order;
    return AppCard(
      padding: EdgeInsets.zero,
      accent: AppColors.forChannel(order.channel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderDetailScreen(orderId: order.id),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
              child: Row(
                children: [
                  Text(
                    order.number,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
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
                  Text(
                    'prispelo ${Fmt.dateShort(group.arrivedAt)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatusChip(
                    label: order.channel.label,
                    color: AppColors.forChannel(order.channel),
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          for (final item in group.items)
            _ItemRow(
              item: item,
              onTap: phase == OrderPhase.drying
                  // Iz Sušenja gre tap naravnost v Hitri obračun (QA v4 §5).
                  ? () => QuickFinishSheet.show(context, item)
                  : () => _openRug(context, item),
            ),
          for (final item in group.readySiblings)
            _ItemRow(
              item: item,
              muted: true,
              onTap: () => _openRug(context, item),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _openRug(BuildContext context, RugItem item) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => RugDetailScreen(itemId: item.id)),
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onTap, this.muted = false});

  final RugItem item;
  final VoidCallback onTap;

  /// Že pripravljen kos naročila, ki še čaka na ostale.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forRug(item.status);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        child: Opacity(
          opacity: muted ? 0.5 : 1,
          child: Row(
            children: [
              Icon(AppIcons.forRug(item.status), size: 18, color: color),
              const SizedBox(width: 10),
              Text(
                item.id,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label.toLowerCase(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              if (muted)
                Text(
                  Fmt.money(item.price),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else if (item.status == RugStatus.finishing)
                StatusChip.rug(item.status)
              else if (item.lastChangeAt != null)
                Text(
                  Fmt.relative(item.lastChangeAt!),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rezultati iskanja čez vse štiri zavihke. Vsak rezultat pove, v katerem
/// zavihku se naročilo (ali iskani kos) trenutno nahaja.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final results =
        state.orders
            .where((o) => o.status.isOpen)
            .where((o) => matchesSearch(o, state.itemsOf(o.id), query))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: 'Ni zadetkov',
        message: 'Iskanje zajame odprta naročila v vseh štirih zavihkih.',
      );
    }

    final q = foldForSearch(query);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        final order = results[i];
        final items = state.itemsOf(order.id);
        // Če iskanje zadane ID kosa, pokažemo, kje je ta kos — ne samo
        // naročilo.
        final hitItems = foldForSearch(order.id).contains(q)
            ? const <RugItem>[]
            : items.where((it) => foldForSearch(it.id).contains(q)).toList();
        final itemPhases = {
          for (final it in hitItems)
            for (final p in OrderPhase.values)
              if (p.showsItems && p.containsItem(it)) p,
        }.toList();
        final phases = itemPhases.isNotEmpty
            ? itemPhases
            : phasesOf(order, items);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'V zavihku',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  for (final p in phases)
                    StatusChip(
                      label: p.label,
                      color: AppColors.primary,
                      dense: true,
                    ),
                  if (phases.isEmpty)
                    StatusChip(
                      label: order.status.label,
                      color: AppColors.textMuted,
                      dense: true,
                    ),
                  for (final it in hitItems)
                    StatusChip(
                      label: '${it.id} · ${it.status.label}',
                      color: AppColors.forRug(it.status),
                      dense: true,
                    ),
                ],
              ),
            ),
            OrderCard(order),
          ],
        );
      },
    );
  }
}

Widget _empty(OrderFilter filter, String title, String? message) {
  return EmptyState(
    icon: filter.isEmpty
        ? Icons.receipt_long_outlined
        : Icons.filter_alt_off_outlined,
    title: filter.isEmpty ? title : 'Filtru ne ustreza nobeno naročilo',
    message: filter.isEmpty ? message : 'Poskusi s širšim filtrom.',
  );
}

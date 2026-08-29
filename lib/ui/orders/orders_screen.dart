import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/navigation.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../widgets/common.dart';
import 'new_order_screen.dart';
import 'order_card.dart';

/// Filter nad seznamom naročil. Kanal ni več zavihek — naročila vseh treh
/// poti so v istem seznamu, kanal pa je oznaka na kartici.
class OrderFilter {
  const OrderFilter({this.channel, this.step});

  final OrderChannel? channel;

  /// Naročila, ki imajo vsaj en kos v tem koraku. Tako delavec najde, kje je
  /// še kaj za postoriti, tudi če je naročilo kot celota drugje.
  final RugStatus? step;

  bool get isEmpty => channel == null && step == null;
  int get count => (channel == null ? 0 : 1) + (step == null ? 0 : 1);

  OrderFilter copyWith({
    OrderChannel? channel,
    RugStatus? step,
    bool clearChannel = false,
    bool clearStep = false,
  }) =>
      OrderFilter(
        channel: clearChannel ? null : (channel ?? this.channel),
        step: clearStep ? null : (step ?? this.step),
      );
}

final orderFilterProvider =
    StateProvider<OrderFilter>((ref) => const OrderFilter());

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_syncProvider);

  void _syncProvider() {
    if (_tabs.indexIsChanging) return;
    ref.read(ordersTabProvider.notifier).state = _tabs.index;
  }

  @override
  void dispose() {
    _tabs.removeListener(_syncProvider);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(orderFilterProvider);

    // Meni Več lahko skoči naravnost na "Zaključena" — zato zavihek sledi
    // providerju, namesto da bi isti seznam obstajal še enkrat drugje.
    ref.listen(ordersTabProvider, (_, next) {
      if (next != _tabs.index) _tabs.animateTo(next);
    });

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
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                          border:
                              Border.all(color: AppColors.surface, width: 1.5),
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
            TabBar(
              controller: _tabs,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMuted,
              indicatorColor: AppColors.primary,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: AppColors.border,
              labelStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              tabs: const [Tab(text: 'Aktivna'), Tab(text: 'Zaključena')],
            ),
            if (!filter.isEmpty) _activeFilterBar(filter),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: const [
                  _OrderList(active: true),
                  _OrderList(active: false),
                ],
              ),
            ),
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
                    () => ref.read(orderFilterProvider.notifier).state =
                        filter.copyWith(clearChannel: true),
                  ),
                if (filter.step != null)
                  _removableChip(
                    filter.step!.label,
                    AppColors.forRug(filter.step!),
                    () => ref.read(orderFilterProvider.notifier).state =
                        filter.copyWith(clearStep: true),
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
    void set(OrderFilter f) =>
        ref.read(orderFilterProvider.notifier).state = f;

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
            const Text(
              'Ima kos v koraku',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterPill(
                  label: 'Vse',
                  selected: filter.step == null,
                  onTap: () => set(filter.copyWith(clearStep: true)),
                ),
                for (final s in RugStatus.values)
                  if (s != RugStatus.returned)
                    FilterPill(
                      label: s.label,
                      selected: filter.step == s,
                      onTap: () => set(filter.copyWith(step: s)),
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

class _OrderList extends ConsumerWidget {
  const _OrderList({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final filter = ref.watch(orderFilterProvider);

    var list = state.orders
        .where((o) => o.status.isOpen == active)
        .where((o) => filter.channel == null || o.channel == filter.channel)
        .where((o) =>
            filter.step == null ||
            state.itemsOf(o.id).any((i) => i.status == filter.step))
        .toList();

    list.sort(active ? _byUrgency : _byRecent);

    if (list.isEmpty) {
      return EmptyState(
        icon: filter.isEmpty
            ? Icons.receipt_long_outlined
            : Icons.filter_alt_off_outlined,
        title: filter.isEmpty
            ? (active ? 'Ni aktivnih naročil' : 'Zgodovina je prazna')
            : 'Filtru ne ustreza nobeno naročilo',
        message: filter.isEmpty
            ? (active ? 'Novo naročilo dodaš z gumbom spodaj desno.' : null)
            : 'Poskusi s širšim filtrom.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => OrderCard(list[i]),
    );
  }

  static int _byUrgency(WorkOrder a, WorkOrder b) {
    // Pripravljena naročila na vrh — nekdo jih čaka.
    final ar = a.status.isHandoverReady ? 0 : 1;
    final br = b.status.isHandoverReady ? 0 : 1;
    if (ar != br) return ar - br;

    final ad = a.dueAt ?? a.deliveryAt ?? a.pickupAt;
    final bd = b.dueAt ?? b.deliveryAt ?? b.pickupAt;
    if (ad == null && bd == null) return b.createdAt.compareTo(a.createdAt);
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  }

  static int _byRecent(WorkOrder a, WorkOrder b) =>
      (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt);
}

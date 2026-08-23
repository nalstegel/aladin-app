import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../widgets/common.dart';
import 'new_order_screen.dart';
import 'order_card.dart';

/// Trije zavihki na vrhu — trije načini, kako naročilo pride v isti sistem.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Naročila'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: [
            for (final c in OrderChannel.values)
              Tab(
                height: 46,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(AppIcons.forChannel(c), size: 16),
                      const SizedBox(width: 6),
                      Text(c.label),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final c in OrderChannel.values) _ChannelTab(channel: c),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final channel = OrderChannel.values[_tabs.index];
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NewOrderScreen(initialChannel: channel),
            ),
          );
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Novo naročilo'),
      ),
    );
  }
}

class _ChannelTab extends ConsumerStatefulWidget {
  const _ChannelTab({required this.channel});

  final OrderChannel channel;

  @override
  ConsumerState<_ChannelTab> createState() => _ChannelTabState();
}

enum _Filter { open, ready, done }

class _ChannelTabState extends ConsumerState<_ChannelTab> {
  _Filter _filter = _Filter.open;

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(ordersByChannelProvider(widget.channel));
    final done = ref.watch(completedOrdersProvider(widget.channel));

    final ready = open.where((o) => o.status.isHandoverReady).toList();
    final inProgress = open.where((o) => !o.status.isHandoverReady).toList();

    final List<WorkOrder> list = switch (_filter) {
      _Filter.open => [...ready, ...inProgress],
      _Filter.ready => ready,
      _Filter.done => done,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _chip('Aktivna', open.length, _Filter.open),
              const SizedBox(width: 8),
              _chip(
                widget.channel == OrderChannel.dropoff
                    ? 'Čaka na prevzem'
                    : 'Za vračilo',
                ready.length,
                _Filter.ready,
              ),
              const SizedBox(width: 8),
              _chip('Zgodovina', done.length, _Filter.done),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: AppIcons.forChannel(widget.channel),
                  title: _emptyTitle(),
                  message: 'Novo naročilo dodaš z gumbom spodaj desno.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => OrderCard(list[i]),
                ),
        ),
      ],
    );
  }

  String _emptyTitle() => switch (_filter) {
        _Filter.open => 'Ni aktivnih naročil',
        _Filter.ready => 'Nič ni pripravljeno za predajo',
        _Filter.done => 'Zgodovina je prazna',
      };

  Widget _chip(String label, int count, _Filter value) {
    final selected = _filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppColors.primary,
                  height: 1.1,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

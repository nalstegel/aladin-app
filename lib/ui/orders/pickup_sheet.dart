import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/catalog.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../../models/rug_item.dart';
import '../widgets/common.dart';
import '../widgets/extra_choice.dart';
import 'labels_screen.dart';

/// Kratek korak ob fizičnem prevzemu (V8 §2): tu se vnesejo doplačila, ki jih
/// delavec dejansko vidi — Vnos / Iznos na naročilo, Urin / Dlake na kos.
/// Šele "Potrdi" premakne kose v Čaka pranje; tisk etiket tega nikoli ne stori.
class PickupSheet extends ConsumerStatefulWidget {
  const PickupSheet({super.key, required this.orderId});

  final String orderId;

  /// Vrne true, če je bil prevzem potrjen.
  static Future<bool> show(BuildContext context, String orderId) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => PickupSheet(orderId: orderId),
    );
    return confirmed == true;
  }

  @override
  ConsumerState<PickupSheet> createState() => _PickupSheetState();
}

class _PickupSheetState extends ConsumerState<PickupSheet> {
  /// Izbrana doplačila na naročilu (ime → predloga).
  final _orderSel = <String>{};

  /// Izbrana doplačila na kosu: ID kosa → (ime doplačila → znesek).
  final _itemSel = <String, Map<String, double>>{};

  String? _expandedItem;

  @override
  void initState() {
    super.initState();
    final state = ref.read(repositoryProvider);
    final order = state.order(widget.orderId);
    if (order == null) return;
    for (final e in order.orderExtras) {
      _orderSel.add(e.name);
    }
    for (final i in state.itemsOf(widget.orderId)) {
      if (i.status != RugStatus.awaitingPickup) continue;
      if (i.extras.isNotEmpty) {
        _itemSel[i.id] = {for (final e in i.extras) e.name: e.value};
      }
    }
  }

  ExtraTemplate _template(
    List<ExtraTemplate> catalog,
    ExtraTemplate fallback,
  ) {
    for (final t in catalog) {
      if (t.active && t.name == fallback.name) return t;
    }
    return fallback;
  }

  Future<void> _toggleItemExtra(RugItem item, ExtraTemplate t) async {
    final sel = _itemSel.putIfAbsent(item.id, () => {});
    if (!t.hasChoices) {
      setState(() {
        if (sel.containsKey(t.name)) {
          sel.remove(t.name);
        } else {
          sel[t.name] = t.value;
        }
      });
      return;
    }
    final picked = await pickExtraChoice(context, t, current: sel[t.name]);
    if (picked == null || !mounted) return;
    setState(() {
      if (picked == 0) {
        sel.remove(t.name);
      } else {
        sel[t.name] = picked;
      }
    });
  }

  void _confirm(
    List<ExtraTemplate> orderTemplates,
    List<ExtraTemplate> itemTemplates,
    List<RugItem> items,
  ) {
    final orderExtras = [
      for (final t in orderTemplates)
        if (_orderSel.contains(t.name)) AppliedExtra.fromTemplate(t),
    ];
    final itemExtras = <String, List<AppliedExtra>>{
      for (final i in items)
        i.id: [
          for (final t in itemTemplates)
            if (_itemSel[i.id]?.containsKey(t.name) ?? false)
              AppliedExtra.fromTemplate(t, value: _itemSel[i.id]![t.name]),
        ],
    };
    ref.read(repositoryProvider.notifier).confirmPickup(
          widget.orderId,
          orderExtras: orderExtras,
          itemExtras: itemExtras,
          note: 'Prevzeto pri stranki',
        );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final order = state.order(widget.orderId);
    if (order == null) return const SizedBox.shrink();
    final items = state
        .itemsOf(widget.orderId)
        .where((i) => i.status == RugStatus.awaitingPickup)
        .toList();

    final orderTemplates = [
      for (final f in fallbackOrderExtras) _template(state.extraTemplates, f),
    ];
    final itemTemplates = [
      for (final f in fallbackItemExtras) _template(state.extraTemplates, f),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  children: [
                    Text(
                      order.channel == OrderChannel.dropoff
                          ? 'Prevzeto v delavnico · ${order.number}'
                          : 'Prevzeto pri stranki · ${order.number}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${order.customerName} · doplačila izberi samo, če '
                      'dejansko veljajo.',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SectionHeader('Naročilo'),
                    Row(
                      children: [
                        for (final t in orderTemplates) ...[
                          if (t != orderTemplates.first)
                            const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: ChoiceTile(
                                label: '${t.name} +${formatExtraValue(t.value, t)}',
                                selected: _orderSel.contains(t.name),
                                onTap: () => setState(() {
                                  if (!_orderSel.remove(t.name)) {
                                    _orderSel.add(t.name);
                                  }
                                }),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SectionHeader(
                      'Kosi',
                      subtitle: 'Tapni kos za Urin / Dlake.',
                    ),
                    for (final item in items) ...[
                      _itemCard(item, itemTemplates),
                      const SizedBox(height: 8),
                    ],
                    if (items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Vsi kosi so že prevzeti.',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: items.isEmpty
                        ? null
                        : () => _confirm(orderTemplates, itemTemplates, items),
                    icon: const Icon(Icons.check),
                    label: const Text('Potrdi → Čaka pranje'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemCard(RugItem item, List<ExtraTemplate> templates) {
    final sel = _itemSel[item.id] ?? const <String, double>{};
    final open = _expandedItem == item.id;
    final summary = [
      for (final t in templates)
        if (sel.containsKey(t.name))
          t.hasChoices ? '${t.name} ${formatExtraValue(sel[t.name]!, t)}' : t.name,
    ].join(' · ');

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _expandedItem = open ? null : item.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
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
                      summary.isEmpty ? item.label.toLowerCase() : summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            summary.isEmpty ? FontWeight.w500 : FontWeight.w700,
                        color: summary.isEmpty
                            ? AppColors.textMuted
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  for (final t in templates) ...[
                    if (t != templates.first) const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ChoiceTile(
                          label: t.hasChoices
                              ? '${t.name} +${t.choices.first.toStringAsFixed(0)}–'
                                  '${t.choices.last.toStringAsFixed(0)} ${t.kind.label}'
                              : '${t.name} +${formatExtraValue(t.value, t)}',
                          selected: sel.containsKey(t.name),
                          onTap: () => _toggleItemExtra(item, t),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Po ustvarjenem naročilu (V8 §2): pri Pripeljano se hiter korak prevzema
/// odpre takoj po sprejemu, nato sledi tisk etiket. Pri Našem prevzemu so
/// preproge še pri stranki, zato gremo takoj na etikete.
Future<void> continueAfterOrderCreated(
  BuildContext context,
  WorkOrder order,
) async {
  final navigator = Navigator.of(context);
  if (order.channel == OrderChannel.dropoff) {
    await PickupSheet.show(context, order.id);
  }
  if (!navigator.mounted) return;
  navigator.push(
    MaterialPageRoute(
      builder: (_) => LabelsScreen(orderId: order.id, isNew: true),
    ),
  );
}

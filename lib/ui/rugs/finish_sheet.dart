import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/catalog.dart';
import '../../models/enums.dart';
import '../../models/rug_item.dart';
import '../widgets/common.dart';

/// Končno sesanje: kaj se je dejansko delalo, potrditev cene → Pripravljeno.
class FinishSheet extends ConsumerStatefulWidget {
  const FinishSheet({super.key, required this.item});

  final RugItem item;

  static Future<void> show(BuildContext context, RugItem item) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => FinishSheet(item: item),
    );
  }

  @override
  ConsumerState<FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends ConsumerState<FinishSheet> {
  final _selected = <String>{};
  late double _discount;
  final _override = TextEditingController();
  bool _useOverride = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(repositoryProvider);
    final order = state.order(widget.item.orderId);
    final customer =
        order == null ? null : state.customer(order.customerId);

    // Popust stranke predlagamo samodejno, delavec ga lahko spremeni.
    _discount = widget.item.discountPercent > 0
        ? widget.item.discountPercent
        : (customer?.defaultDiscountPercent ?? 0);

    for (final e in widget.item.extras) {
      final match = state.extraTemplates.where((t) => t.name == e.name);
      if (match.isNotEmpty) _selected.add(match.first.id);
    }
  }

  @override
  void dispose() {
    _override.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final templates =
        state.extraTemplates.where((t) => t.active).toList();
    final chosen = templates
        .where((t) => _selected.contains(t.id))
        .map(AppliedExtra.fromTemplate)
        .toList();

    final preview = widget.item.copyWith(
      extras: chosen,
      discountPercent: _discount,
      clearConfirmedPrice: true,
    );

    final overrideValue =
        double.tryParse(_override.text.replaceAll(',', '.'));
    final finalPrice = _useOverride && overrideValue != null
        ? overrideValue
        : preview.computedPrice;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Mere in cena · ${widget.item.id}',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.item.rugTypeName} · '
              '${Fmt.dimensions(widget.item.widthCm, widget.item.lengthCm)} · '
              '${Fmt.m2(widget.item.m2)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
            const SectionHeader('Kaj se je dejansko delalo'),
            for (final t in templates.where((t) => !t.isDiscount))
              _extraTile(t, preview),
            const SectionHeader('Popusti'),
            for (final t in templates.where((t) => t.isDiscount))
              _extraTile(t, preview),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Dodatni popust na kos',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: TextFormField(
                    initialValue: _discount == 0
                        ? ''
                        : _discount.toStringAsFixed(0),
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      suffixText: '%',
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() {
                      _discount =
                          double.tryParse(v.replaceAll(',', '.')) ?? 0;
                    }),
                  ),
                ),
              ],
            ),
            const SectionHeader('Obračun'),
            AppCard(
              child: Column(
                children: [
                  DetailRow(
                    'Osnova (${Fmt.m2(preview.chargeableM2)} × '
                    '${preview.pricePerM2.toStringAsFixed(0)} €)',
                    Fmt.money(preview.basePrice),
                  ),
                  for (final e in chosen)
                    DetailRow(
                      e.name,
                      Fmt.money(e.amount(
                        base: preview.basePrice,
                        m2: preview.chargeableM2,
                      )),
                    ),
                  if (_discount > 0)
                    DetailRow(
                      'Popust ${_discount.toStringAsFixed(0)} %',
                      '−${Fmt.money(preview.discountAmount)}',
                    ),
                  const Divider(height: 18),
                  DetailRow('Končna cena', Fmt.money(finalPrice),
                      strong: true),
                ],
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() {
                _useOverride = !_useOverride;
                if (_useOverride && _override.text.isEmpty) {
                  _override.text = preview.computedPrice.toStringAsFixed(2);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _useOverride
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                      color: _useOverride
                          ? AppColors.primary
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Ročno določim končno ceno',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            if (_useOverride)
              TextField(
                controller: _override,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(
                  labelText: 'Končna cena',
                  suffixText: '€',
                ),
              ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.ready),
              onPressed: () {
                ref.read(repositoryProvider.notifier).finishItem(
                      widget.item.id,
                      extras: chosen,
                      discountPercent: _discount,
                      priceOverride: _useOverride ? overrideValue : null,
                      notes: widget.item.notes,
                    );
                Navigator.pop(context);
              },
              icon: const Icon(Icons.check_circle_outline),
              label: Text('Potrdi ${Fmt.money(finalPrice)} → Pripravljeno'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _extraTile(ExtraTemplate t, RugItem preview) {
    final selected = _selected.contains(t.id);
    final amount = AppliedExtra.fromTemplate(t).amount(
      base: preview.basePrice,
      m2: preview.chargeableM2,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          if (selected) {
            _selected.remove(t.id);
          } else {
            _selected.add(t.id);
          }
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_box : Icons.check_box_outline_blank,
                size: 20,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _templateLabel(t),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${amount >= 0 ? '+' : '−'}${Fmt.money(amount.abs())}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: amount >= 0 ? AppColors.primary : AppColors.ready,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _templateLabel(ExtraTemplate t) {
    final v = t.value.abs();
    return switch (t.kind) {
      ExtraKind.percent => '${t.value < 0 ? '−' : '+'}${v.toStringAsFixed(0)} % osnove',
      ExtraKind.perM2 => '${t.value < 0 ? '−' : '+'}${v.toStringAsFixed(2)} € na m²',
      ExtraKind.fixed => '${t.value < 0 ? '−' : '+'}${v.toStringAsFixed(2)} € pavšal',
    };
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/billing.dart';
import '../../data/providers.dart';
import '../../models/catalog.dart';
import '../../models/order.dart';
import '../../models/rug_item.dart';
import '../widgets/common.dart';
import '../widgets/extra_choice.dart';

/// Hitre mere. Prve tri so gumbi za površino (v3 spec §4: "1 m²", "2 m²",
/// "3 m²") za steze / tekoče metre — širina×dolžina je tam le interna
/// predstavitev. Ostale so standardne mere preprog (QA v4 §4, V10 §1). "Drugo"
/// ostane edina pot za ročni vnos dejanskih mer kosa.
const _quickSizes = [
  (label: '1 m²', widthCm: 100.0, lengthCm: 100.0),
  (label: '2 m²', widthCm: 100.0, lengthCm: 200.0),
  (label: '3 m²', widthCm: 100.0, lengthCm: 300.0),
  (label: '1,2 × 1,7', widthCm: 120.0, lengthCm: 170.0),
  (label: '1,35 × 1,95', widthCm: 135.0, lengthCm: 195.0),
  (label: '2,3 × 1,7', widthCm: 230.0, lengthCm: 170.0),
  (label: '3 × 2', widthCm: 300.0, lengthCm: 200.0),
  (label: '3,5 × 2,5', widthCm: 350.0, lengthCm: 250.0),
  (label: '4 × 3', widthCm: 400.0, lengthCm: 300.0),
];
const _areaSizeCount = 3;

/// Hitri obračun kosa (v3 spec §3/§4): vrsta, mere, doplačila, cena — vse na
/// enem zaslonu, naravnost iz Sušenja v Pripravljeno. Nadomešča ločena
/// `MeasureSheet` + `FinishSheet` za normalni potek dela; ta dva ostajata za
/// urejanje kosov, ki so bili ročno vrnjeni na "Mere in cena".
class QuickFinishSheet extends ConsumerStatefulWidget {
  const QuickFinishSheet({super.key, required this.item});

  final RugItem item;

  static Future<void> show(BuildContext context, RugItem item) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => QuickFinishSheet(item: item),
    );
  }

  @override
  ConsumerState<QuickFinishSheet> createState() => _QuickFinishSheetState();
}

class _QuickFinishSheetState extends ConsumerState<QuickFinishSheet> {
  late final _width = TextEditingController(
    text: widget.item.widthCm?.toStringAsFixed(0) ?? '',
  );
  late final _length = TextEditingController(
    text: widget.item.lengthCm?.toStringAsFixed(0) ?? '',
  );
  final _override = TextEditingController();

  String? _typeId;
  int? _selectedQuickSize;
  bool _customSize = false;

  /// Izbrana doplačila: ID predloge → vrednost (pri postavkah z izbiro, npr.
  /// "Dlake" 5 € / 10 €, tista, ki jo je izbral delavec).
  final _selected = <String, double>{};
  late double _discount;
  bool _useOverride = false;

  @override
  void initState() {
    super.initState();
    _typeId = widget.item.rugTypeId;

    final w = widget.item.widthCm;
    final l = widget.item.lengthCm;
    final matchIndex = w == null || l == null
        ? -1
        : _quickSizes.indexWhere((q) => q.widthCm == w && q.lengthCm == l);
    if (matchIndex >= 0) {
      _selectedQuickSize = matchIndex;
    } else if (w != null && l != null) {
      _customSize = true;
    }

    final state = ref.read(repositoryProvider);
    final order = state.order(widget.item.orderId);
    final customer = order == null ? null : state.customer(order.customerId);
    _discount = widget.item.discountPercent > 0
        ? widget.item.discountPercent
        : (customer?.defaultDiscountPercent ?? 0);

    for (final e in widget.item.extras) {
      final match = state.extraTemplates.where((t) => t.name == e.name);
      if (match.isNotEmpty) _selected[match.first.id] = e.value;
    }
  }

  @override
  void dispose() {
    _width.dispose();
    _length.dispose();
    _override.dispose();
    super.dispose();
  }

  double get _m2 {
    final w = double.tryParse(_width.text.replaceAll(',', '.')) ?? 0;
    final l = double.tryParse(_length.text.replaceAll(',', '.')) ?? 0;
    return w * l / 10000;
  }

  void _pickQuickSize(int index) {
    setState(() {
      _selectedQuickSize = index;
      _customSize = false;
      _width.text = _quickSizes[index].widthCm.toStringAsFixed(0);
      _length.text = _quickSizes[index].lengthCm.toStringAsFixed(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final types = sortedRugTypes(state.rugTypes.where((t) => t.active));
    // Vnos / Iznos sta informacija prevzema (V8 §2) — ne na tem zaslonu.
    final templates = sortedQuickExtras(
      state.extraTemplates.where((t) => t.active && !t.isOrderLevel),
    );
    final type = _typeId == null ? null : state.rugType(_typeId!);

    final chosen = [
      for (final t in templates)
        if (_selected.containsKey(t.id))
          AppliedExtra.fromTemplate(t, value: _selected[t.id]),
    ];

    final preview = widget.item.copyWith(
      widthCm: double.tryParse(_width.text.replaceAll(',', '.')),
      lengthCm: double.tryParse(_length.text.replaceAll(',', '.')),
      rugTypeId: type?.id,
      rugTypeName: type?.name,
      pricePerM2: type?.pricePerM2,
      minChargeM2: type?.minChargeM2,
      extras: chosen,
      discountPercent: _discount,
      clearConfirmedPrice: true,
    );

    final overrideValue = double.tryParse(_override.text.replaceAll(',', '.'));
    final finalPrice = _useOverride && overrideValue != null
        ? overrideValue
        : preview.computedPrice;
    final valid = _m2 > 0 && type != null;

    // Obračun celega naročila z ravnokar obračunanim kosom: doplačila prevzema,
    // dostava in minimum 50 € (V8 §3) — minimum se pokaže, ko je to zadnji kos.
    final order = state.order(widget.item.orderId);
    final billing = order == null
        ? null
        : billingFor(
            order,
            state.itemsOf(order.id),
            priceOverrides: {widget.item.id: finalPrice},
          );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        maxChildSize: 0.96,
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
            const SizedBox(height: 14),
            Text(
              'Hitri obračun · ${widget.item.id}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SectionHeader('Vrsta preproge'),
            _typeGrid(types),
            const SectionHeader('Hitre mere'),
            _sizeGrid(),
            if (_customSize) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _numField(_width, 'Širina (cm)')),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '×',
                      style: TextStyle(
                        fontSize: 20,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  Expanded(child: _numField(_length, 'Dolžina (cm)')),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text(
              _m2 == 0
                  ? 'Površina: —'
                  : (_selectedQuickSize != null &&
                            _selectedQuickSize! < _areaSizeCount
                        ? 'Površina: ${Fmt.m2(_m2)}'
                        : 'Mere: ${Fmt.dimensions(double.tryParse(_width.text.replaceAll(',', '.')), double.tryParse(_length.text.replaceAll(',', '.')))} · ${Fmt.m2(_m2)}'),
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SectionHeader('Doplačila'),
            _extrasGrid(templates),
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
                  width: 90,
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
                      _discount = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                    }),
                  ),
                ),
              ],
            ),
            const SectionHeader('Obračun'),
            AppCard(
              borderColor: AppColors.primary.withValues(alpha: 0.4),
              child: Column(
                children: [
                  DetailRow(
                    type == null
                        ? 'Osnova'
                        : 'Osnova (${Fmt.m2(preview.chargeableM2)} × '
                              '${type.pricePerM2.toStringAsFixed(0)} €)',
                    Fmt.money(preview.basePrice),
                  ),
                  for (final e in chosen)
                    DetailRow(
                      e.name,
                      Fmt.money(
                        e.amount(
                          base: preview.basePrice,
                          m2: preview.chargeableM2,
                        ),
                      ),
                    ),
                  if (_discount > 0)
                    DetailRow(
                      'Popust ${_discount.toStringAsFixed(0)} %',
                      '−${Fmt.money(preview.discountAmount)}',
                    ),
                  const Divider(height: 18),
                  DetailRow('Končna cena', Fmt.money(finalPrice), strong: true),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
            if (order != null && billing != null) _orderSummary(order, billing, finalPrice),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.ready),
              onPressed: valid
                  ? () {
                      ref
                          .read(repositoryProvider.notifier)
                          .finishRugFromDrying(
                            widget.item.id,
                            widthCm: double.tryParse(
                              _width.text.replaceAll(',', '.'),
                            ),
                            lengthCm: double.tryParse(
                              _length.text.replaceAll(',', '.'),
                            ),
                            rugType: type,
                            extras: chosen,
                            discountPercent: _discount,
                            priceOverride: _useOverride ? overrideValue : null,
                            notes: widget.item.notes,
                          );
                      Navigator.pop(context);
                    }
                  : null,
              icon: const Icon(Icons.check_circle_outline),
              label: Text('Končano · ${Fmt.money(finalPrice)} → Pripravljeno'),
            ),
          ],
        ),
      ),
    );
  }

  /// Povzetek naročila pod obračunom kosa. Kaže se samo, če ima naročilo
  /// kaj poleg kosov (Vnos/Iznos, dostava) ali velja minimum 50 €.
  Widget _orderSummary(WorkOrder order, OrderBilling b, double thisPrice) {
    final others = b.itemsTotal - thisPrice;
    final hasExtras = order.orderExtras.isNotEmpty || b.deliveryFee > 0;
    if (!hasExtras && b.minimumTopUp == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(
          children: [
            DetailRow('Naročilo ${order.number}', '', strong: true),
            DetailRow('Ta kos', Fmt.money(thisPrice)),
            if (others > 0.004) DetailRow('Ostali kosi', Fmt.money(others)),
            for (final e in order.orderExtras)
              DetailRow(e.name, Fmt.money(e.amount(base: 0, m2: 0))),
            if (b.deliveryFee > 0)
              DetailRow('Dostavno doplačilo', Fmt.money(b.deliveryFee)),
            if (b.minimumTopUp > 0)
              DetailRow(
                'Minimum ${minimumDeliveryOrderTotal.toStringAsFixed(0)} €',
                Fmt.money(b.minimumTopUp),
              ),
            const Divider(height: 18),
            DetailRow(
              b.allPriced ? 'Skupaj naročilo' : 'Skupaj do zdaj',
              Fmt.money(b.total),
              strong: true,
            ),
          ],
        ),
      ),
    );
  }

  /// 2 gumba v vrsto, kot v predlogi — kompaktno, da je čim več možnosti
  /// vidnih brez drsenja (QA v4 §4).
  Widget _grid({
    required int columns,
    required double aspectRatio,
    required List<Widget> children,
  }) {
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: aspectRatio,
      children: children,
    );
  }

  Widget _typeGrid(List<RugType> types) {
    return _grid(
      columns: 2,
      aspectRatio: 4.2,
      children: [
        for (final t in types)
          _choiceButton(
            label: t.name,
            selected: _typeId == t.id,
            onTap: () => setState(() => _typeId = t.id),
          ),
      ],
    );
  }

  /// Mere so kratke oznake, zato 4 v vrsto: najprej 1/2/3 m² in Drugo, nato
  /// standardne mere preprog.
  Widget _sizeGrid() {
    Widget size(int i) => _choiceButton(
      label: _quickSizes[i].label,
      selected: _selectedQuickSize == i && !_customSize,
      onTap: () => _pickQuickSize(i),
    );
    return _grid(
      columns: 4,
      aspectRatio: 2.1,
      children: [
        for (var i = 0; i < _areaSizeCount; i++) size(i),
        _choiceButton(
          label: 'Drugo',
          selected: _customSize,
          onTap: () => setState(() {
            _customSize = true;
            _selectedQuickSize = null;
          }),
        ),
        for (var i = _areaSizeCount; i < _quickSizes.length; i++) size(i),
      ],
    );
  }

  /// Ena tipka na doplačilo, z zneskom na tipki: "Urin +3 €/m²", "Dlake +5 €",
  /// "Dlake +10 €", "Ponovno pranje +30 %" (V10 §1). Postavka z izbiro
  /// (Dlake) dobi tipko za vsak znesek — ena sama tapnitev, brez izbirnika;
  /// druga tipka iste postavke zamenja prvo, ponovni dotik izbiro odstrani.
  Widget _extrasGrid(List<ExtraTemplate> templates) {
    String label(ExtraTemplate t, double v) =>
        '${t.name} ${v < 0 ? '−' : '+'}${formatExtraValue(v, t)}';

    final tiles = <Widget>[
      for (final t in templates)
        if (t.hasChoices)
          for (final c in t.choices)
            _choiceButton(
              label: label(t, c),
              selected: _selected[t.id] == c,
              onTap: () => setState(
                () => _selected[t.id] == c
                    ? _selected.remove(t.id)
                    : _selected[t.id] = c,
              ),
            )
        else
          _choiceButton(
            label: label(t, t.value),
            selected: _selected.containsKey(t.id),
            onTap: () => setState(
              () => _selected.containsKey(t.id)
                  ? _selected.remove(t.id)
                  : _selected[t.id] = t.value,
            ),
          ),
    ];
    return _grid(columns: 2, aspectRatio: 4.2, children: tiles);
  }

  Widget _choiceButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? AppColors.primary : AppColors.text,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      decoration: InputDecoration(labelText: label),
    );
  }
}

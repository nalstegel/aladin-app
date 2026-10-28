import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/catalog.dart';
import '../../models/rug_item.dart';
import '../widgets/common.dart';
import '../widgets/extra_choice.dart';

/// Popravek že obračunanega kosa: vrsta, mere, doplačila, popust in končna
/// cena — brez vračanja kosa v Sušenje. Status ostane, površina, osnova in
/// obračun naročila se izpeljejo iz kosa, zato se osvežijo sami.
class EditPricingSheet extends ConsumerStatefulWidget {
  const EditPricingSheet({super.key, required this.item});

  final RugItem item;

  static Future<void> show(BuildContext context, RugItem item) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EditPricingSheet(item: item),
    );
  }

  @override
  ConsumerState<EditPricingSheet> createState() => _EditPricingSheetState();
}

class _EditPricingSheetState extends ConsumerState<EditPricingSheet> {
  late final _width = TextEditingController(text: _plain(widget.item.widthCm));
  late final _length =
      TextEditingController(text: _plain(widget.item.lengthCm));
  late final _manualM2 =
      TextEditingController(text: _plain(widget.item.manualM2));
  late final _discount = TextEditingController(
    text: widget.item.discountPercent == 0
        ? ''
        : _plain(widget.item.discountPercent),
  );
  late final _price =
      TextEditingController(text: widget.item.price.toStringAsFixed(2));

  late String? _typeId = widget.item.rugTypeId;

  /// Doplačila, ki jih je mogoče izbrati: šifrant in doplačila, ki so že na
  /// kosu, šifrant pa jih ne pozna več (izbrisana ali preimenovana predloga) —
  /// sicer bi jih popravek tiho odstranil.
  late final List<ExtraTemplate> _templates;

  /// Izbrana doplačila po imenu. Ohranijo se takšna, kot so zapisana na kosu
  /// (vrsta in znesek), da popravek drugega polja ne spremeni njihove cene.
  late final Map<String, AppliedExtra> _selected;

  /// Cena sledi izračunu, dokler je delavec sam ne spremeni. Že prej ročno
  /// določena cena se zato ne povozi tiho, ko se popravijo mere ali doplačila.
  late bool _priceTouched;

  /// Ročni vnos površine imajo nepravilne oblike (RugItem.manualM2).
  bool get _isManual => widget.item.manualM2 != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final catalog = [
      for (final t in ref.read(repositoryProvider).extraTemplates)
        // Vnos / Iznos sta doplačili naročila, ne kosa.
        if (t.active && !t.isOrderLevel) t,
    ];
    final known = {for (final t in catalog) t.name};
    _templates = [
      // Enak vrstni red kot v Hitrem obračunu.
      ...sortedQuickExtras(catalog),
      for (final e in item.extras)
        if (!known.contains(e.name))
          ExtraTemplate(
            id: 'applied-${e.name}',
            name: e.name,
            kind: e.kind,
            value: e.value,
          ),
    ];
    _selected = {for (final e in item.extras) e.name: e};

    final computed = item.copyWith(clearConfirmedPrice: true).computedPrice;
    final confirmed = item.confirmedPrice;
    _priceTouched = confirmed != null && (confirmed - computed).abs() > 0.005;
  }

  @override
  void dispose() {
    _width.dispose();
    _length.dispose();
    _manualM2.dispose();
    _discount.dispose();
    _price.dispose();
    super.dispose();
  }

  static String _plain(double? v) {
    if (v == null) return '';
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    return s.replaceAll('.', ',');
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  double get _discountPercent => _num(_discount) ?? 0;

  double get _m2 {
    if (_isManual) return _num(_manualM2) ?? 0;
    return (_num(_width) ?? 0) * (_num(_length) ?? 0) / 10000;
  }

  /// Vrsta, kakršna je zapisana na kosu. Cena na m² in minimalni obračun sta
  /// ob obračunu prepisana na kos, zato popravek, ki vrste ne menja, kosa ne
  /// sme tiho preceniti po današnjem ceniku — in ne sme odpovedati, če je
  /// vrsta medtem izbrisana iz šifranta.
  RugType? get _ownType {
    final item = widget.item;
    if (item.rugTypeId == null) return null;
    return RugType(
      id: item.rugTypeId!,
      name: item.rugTypeName,
      pricePerM2: item.pricePerM2,
      minChargeM2: item.minChargeM2,
    );
  }

  RugType? get _type {
    final id = _typeId;
    if (id == null) return null;
    if (id == widget.item.rugTypeId) return _ownType;
    return ref.read(repositoryProvider).rugType(id);
  }

  /// Kos z vnesenimi vrednostmi — za izračun osnove in cene. Veljavno samo,
  /// ko je površina večja od 0 (prazno polje pusti staro vrednost).
  RugItem _preview() {
    final type = _type;
    return widget.item.copyWith(
      widthCm: _isManual ? null : _num(_width),
      lengthCm: _isManual ? null : _num(_length),
      manualM2: _isManual ? _num(_manualM2) : null,
      clearManualM2: !_isManual,
      rugTypeId: type?.id,
      rugTypeName: type?.name,
      pricePerM2: type?.pricePerM2,
      minChargeM2: type?.minChargeM2,
      extras: _selected.values.toList(),
      discountPercent: _discountPercent,
      clearConfirmedPrice: true,
    );
  }

  /// Po vsaki spremembi vrste, mer, doplačil ali popusta: cena sledi izračunu,
  /// razen če jo je delavec že sam popravil. Kliče se znotraj setState.
  void _syncPrice() {
    if (_priceTouched || _type == null || _m2 <= 0) return;
    _price.text = _preview().computedPrice.toStringAsFixed(2);
  }

  /// Dotik doplačila z zneskom [value]. Postavka z izbiro (Dlake 5 € / 10 €)
  /// ima tipko za vsak znesek: druga tipka iste postavke zamenja prvo, ponovni
  /// dotik izbiro odstrani — enako kot v Hitrem obračunu.
  void _tapExtra(ExtraTemplate t, double value) {
    setState(() {
      final current = _selected[t.name];
      if (t.hasChoices) {
        if (current?.value == value) {
          _selected.remove(t.name);
        } else {
          _selected[t.name] = AppliedExtra.fromTemplate(t, value: value);
        }
      } else if (current != null) {
        _selected.remove(t.name);
      } else {
        _selected[t.name] = AppliedExtra.fromTemplate(t);
      }
      _syncPrice();
    });
  }

  /// Ena tipka na doplačilo, z zneskom na tipki: "Urin +3 €/m²", "Dlake +5 €",
  /// "Dlake +10 €". Zapisano doplačilo ohrani svoj znesek in vrsto tudi na
  /// tipki, če se je šifrant medtem spremenil.
  List<Widget> _extraTiles() {
    String label(ExtraTemplate t, double v) =>
        '${t.name} ${v < 0 ? '−' : '+'}${formatExtraValue(v, t)}';

    return [
      for (final t in _templates)
        if (t.hasChoices)
          // Zapisan znesek, ki ga izbira ne pozna več, ostane viden in ga je
          // mogoče odstraniti.
          for (final c in {
            ...t.choices,
            if (_selected[t.name] != null) _selected[t.name]!.value,
          })
            ChoiceTile(
              label: label(t, c),
              selected: _selected[t.name]?.value == c,
              onTap: () => _tapExtra(t, c),
            )
        else
          ChoiceTile(
            label: label(
              _selected[t.name] == null
                  ? t
                  : t.copyWith(kind: _selected[t.name]!.kind),
              _selected[t.name]?.value ?? t.value,
            ),
            selected: _selected.containsKey(t.name),
            onTap: () => _tapExtra(t, t.value),
          ),
    ];
  }

  void _save(RugType type, double price) {
    ref.read(repositoryProvider.notifier).editItemPricing(
          widget.item.id,
          widthCm: _isManual ? null : _num(_width),
          lengthCm: _isManual ? null : _num(_length),
          manualM2: _isManual ? _num(_manualM2) : null,
          rugType: type,
          extras: _selected.values.toList(),
          discountPercent: _discountPercent,
          price: price,
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final item = widget.item;
    final own = _ownType;
    final types = sortedRugTypes([
      for (final t in state.rugTypes)
        if (t.active || t.id == item.rugTypeId) t,
      // Vrsta, ki je šifrant ne pozna več, ostane izbrana na kosu.
      if (own != null && state.rugType(own.id) == null) own,
    ]);

    final type = _type;
    final area = _m2;
    final preview = _preview();
    final price = _num(_price);
    final discount = _discountPercent;
    final valid = type != null &&
        area > 0 &&
        price != null &&
        price >= 0 &&
        discount >= 0 &&
        discount <= 100;
    final differs =
        area > 0 && price != null && (price - preview.computedPrice).abs() > 0.005;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
              'Uredi kos · ${item.id}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SectionHeader('Vrsta preproge'),
            _grid([
              for (final t in types)
                ChoiceTile(
                  label: t.name,
                  selected: _typeId == t.id,
                  onTap: () => setState(() {
                    _typeId = t.id;
                    _syncPrice();
                  }),
                ),
            ]),
            const SectionHeader('Mere'),
            if (_isManual)
              _numField(_manualM2, 'Površina (m²)')
            else
              Row(
                children: [
                  Expanded(child: _numField(_width, 'Širina (cm)')),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      '×',
                      style: TextStyle(fontSize: 20, color: AppColors.textMuted),
                    ),
                  ),
                  Expanded(child: _numField(_length, 'Dolžina (cm)')),
                ],
              ),
            const SizedBox(height: 8),
            Text(
              area <= 0
                  ? 'Površina: —'
                  : 'Površina: ${Fmt.m2(area)}'
                        '${preview.usesMinCharge ? ' (obračun ${Fmt.m2(preview.chargeableM2)})' : ''}'
                        ' · osnova ${Fmt.money(preview.basePrice)}',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            if (_templates.isNotEmpty) ...[
              const SectionHeader('Doplačila'),
              _grid(_extraTiles()),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Popust na kos',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _discount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      suffixText: '%',
                      isDense: true,
                    ),
                    onChanged: (_) => setState(_syncPrice),
                  ),
                ),
              ],
            ),
            const SectionHeader('Končna cena'),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: (_) => setState(() => _priceTouched = true),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'Končna cena',
                suffixText: '€',
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Izračun z doplačili in popustom: '
                    '${area > 0 ? Fmt.money(preview.computedPrice) : '—'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                if (differs)
                  TextButton(
                    onPressed: () => setState(() {
                      _priceTouched = false;
                      _syncPrice();
                    }),
                    child: const Text('Uporabi izračun'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: valid ? () => _save(type, price) : null,
              icon: const Icon(Icons.check),
              label: Text('Shrani · ${Fmt.money(price ?? 0)}'),
            ),
          ],
        ),
      ),
    );
  }

  /// 2 gumba v vrsto, enako kot v Hitrem obračunu.
  Widget _grid(List<Widget> children) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 4.2,
      children: children,
    );
  }

  Widget _numField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      onChanged: (_) => setState(_syncPrice),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      decoration: InputDecoration(labelText: label),
    );
  }
}

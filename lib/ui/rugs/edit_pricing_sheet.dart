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

/// Direktno urejanje po obračunu (V10 §1): vrsta, širina, dolžina in končna
/// cena že obračunanega kosa — brez vračanja kosa v Sušenje. Shrani takoj
/// osveži površino, osnovo in skupni obračun naročila (vse se izpelje iz kosa).
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
  late final _width = TextEditingController(
    text: widget.item.widthCm?.toStringAsFixed(0) ?? '',
  );
  late final _length = TextEditingController(
    text: widget.item.lengthCm?.toStringAsFixed(0) ?? '',
  );
  late final _manualM2 = TextEditingController(
    text: widget.item.manualM2?.toString().replaceAll('.', ',') ?? '',
  );
  late final _price = TextEditingController(
    text: widget.item.price.toStringAsFixed(2),
  );

  String? _typeId;

  /// Cena sledi izračunu, dokler je delavec sam ne spremeni. Že prej ročno
  /// določena cena se zato ne povozi tiho, ko se popravijo mere.
  late bool _priceTouched;

  /// Ročni vnos površine imajo nepravilne oblike (RugItem.manualM2).
  bool get _isManual => widget.item.manualM2 != null;

  @override
  void initState() {
    super.initState();
    _typeId = widget.item.rugTypeId;
    final computed = widget.item.copyWith(clearConfirmedPrice: true).computedPrice;
    final confirmed = widget.item.confirmedPrice;
    _priceTouched = confirmed != null && (confirmed - computed).abs() > 0.005;
  }

  @override
  void dispose() {
    _width.dispose();
    _length.dispose();
    _manualM2.dispose();
    _price.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  /// Kos z vnešenimi vrednostmi — za površino, osnovo in izračun cene.
  RugItem _preview(RugType? type) => widget.item.copyWith(
    widthCm: _isManual ? null : _num(_width),
    lengthCm: _isManual ? null : _num(_length),
    manualM2: _isManual ? _num(_manualM2) : null,
    clearManualM2: !_isManual,
    rugTypeId: type?.id,
    rugTypeName: type?.name,
    pricePerM2: type?.pricePerM2,
    minChargeM2: type?.minChargeM2,
    clearConfirmedPrice: true,
  );

  /// Po vsaki spremembi vrste ali mer: cena sledi izračunu, razen če jo je
  /// delavec že sam popravil.
  void _changed() {
    setState(() {
      if (!_priceTouched) {
        final type = _typeId == null
            ? null
            : ref.read(repositoryProvider).rugType(_typeId!);
        _price.text = _preview(type).computedPrice.toStringAsFixed(2);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final types = sortedRugTypes(
      state.rugTypes.where((t) => t.active || t.id == widget.item.rugTypeId),
    );
    final type = _typeId == null ? null : state.rugType(_typeId!);
    final preview = _preview(type);
    final price = _num(_price);
    final valid = type != null && preview.m2 > 0 && price != null && price >= 0;
    final differs =
        price != null && (price - preview.computedPrice).abs() > 0.005;

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
              'Uredi mere in ceno · ${widget.item.id}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SectionHeader('Vrsta preproge'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 4.2,
              children: [
                for (final t in types)
                  ChoiceTile(
                    label: t.name,
                    selected: _typeId == t.id,
                    onTap: () {
                      _typeId = t.id;
                      _changed();
                    },
                  ),
              ],
            ),
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
              preview.m2 == 0
                  ? 'Površina: —'
                  : 'Površina: ${Fmt.m2(preview.m2)}'
                        '${preview.usesMinCharge ? ' (obračun ${Fmt.m2(preview.chargeableM2)})' : ''}'
                        ' · osnova ${Fmt.money(preview.basePrice)}',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
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
                    '${Fmt.money(preview.computedPrice)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                if (differs)
                  TextButton(
                    onPressed: () {
                      _priceTouched = false;
                      _changed();
                    },
                    child: const Text('Uporabi izračun'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: valid
                  ? () {
                      ref
                          .read(repositoryProvider.notifier)
                          .editItemPricing(
                            widget.item.id,
                            widthCm: preview.widthCm,
                            lengthCm: preview.lengthCm,
                            manualM2: preview.manualM2,
                            rugType: type,
                            price: price,
                          );
                      Navigator.pop(context);
                    }
                  : null,
              icon: const Icon(Icons.check),
              label: Text('Shrani · ${Fmt.money(price ?? 0)}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      onChanged: (_) => _changed(),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      decoration: InputDecoration(labelText: label),
    );
  }
}

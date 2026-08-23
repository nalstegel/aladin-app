import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/catalog.dart';
import '../../models/rug_item.dart';
import '../widgets/common.dart';

/// Korak iz sušilnice: mere + vrsta. Iz tega app izračuna m² in osnovno ceno.
class MeasureSheet extends ConsumerStatefulWidget {
  const MeasureSheet({super.key, required this.item});

  final RugItem item;

  static Future<void> show(BuildContext context, RugItem item) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => MeasureSheet(item: item),
    );
  }

  @override
  ConsumerState<MeasureSheet> createState() => _MeasureSheetState();
}

class _MeasureSheetState extends ConsumerState<MeasureSheet> {
  late final _width = TextEditingController(
    text: widget.item.widthCm?.toStringAsFixed(0) ?? '',
  );
  late final _length = TextEditingController(
    text: widget.item.lengthCm?.toStringAsFixed(0) ?? '',
  );
  late final _manual = TextEditingController(
    text: widget.item.manualM2?.toStringAsFixed(2) ?? '',
  );
  late final _notes = TextEditingController(text: widget.item.notes);

  String? _typeId;
  bool _irregular = false;

  @override
  void initState() {
    super.initState();
    _typeId = widget.item.rugTypeId;
    _irregular = widget.item.manualM2 != null;
  }

  @override
  void dispose() {
    _width.dispose();
    _length.dispose();
    _manual.dispose();
    _notes.dispose();
    super.dispose();
  }

  double get _m2 {
    if (_irregular) return double.tryParse(_manual.text.replaceAll(',', '.')) ?? 0;
    final w = double.tryParse(_width.text.replaceAll(',', '.')) ?? 0;
    final l = double.tryParse(_length.text.replaceAll(',', '.')) ?? 0;
    return w * l / 10000;
  }

  RugType? get _type {
    if (_typeId == null) return null;
    return ref.read(repositoryProvider).rugType(_typeId!);
  }

  @override
  Widget build(BuildContext context) {
    final types =
        ref.watch(repositoryProvider).rugTypes.where((t) => t.active).toList();
    final type = _type;
    final chargeable =
        type != null && _m2 < type.minChargeM2 ? type.minChargeM2 : _m2;
    final base = type == null ? 0.0 : chargeable * type.pricePerM2;
    final valid = _m2 > 0 && type != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                'Mere in vrsta · ${widget.item.id}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Vnesi v centimetrih. Površino in ceno izračuna aplikacija.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              if (!_irregular)
                Row(
                  children: [
                    Expanded(child: _numField(_width, 'Širina (cm)')),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('×',
                          style: TextStyle(
                              fontSize: 20, color: AppColors.textMuted)),
                    ),
                    Expanded(child: _numField(_length, 'Dolžina (cm)')),
                  ],
                )
              else
                _numField(_manual, 'Površina (m²)', decimal: true),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _irregular = !_irregular),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _irregular
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 20,
                        color: _irregular
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Nepravilna oblika — vpišem m² ročno',
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Vrsta / material',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in types)
                    ChoiceChip(
                      label: Text(
                        '${t.name} · ${t.pricePerM2.toStringAsFixed(0)} €/m²',
                      ),
                      selected: _typeId == t.id,
                      onSelected: (_) => setState(() => _typeId = t.id),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Opomba (neobvezno)',
                  hintText: 'Npr. rob rahlo obrabljen',
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                borderColor: AppColors.primary.withValues(alpha: 0.4),
                child: Column(
                  children: [
                    DetailRow('Površina', _m2 == 0 ? '—' : Fmt.m2(_m2)),
                    if (type != null && _m2 > 0 && _m2 < type.minChargeM2)
                      DetailRow(
                        'Minimalni obračun',
                        Fmt.m2(type.minChargeM2),
                      ),
                    DetailRow(
                      'Osnovna cena',
                      base == 0 ? '—' : Fmt.money(base),
                      strong: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: valid ? _save : null,
                icon: const Icon(Icons.check),
                label: const Text('Shrani in nadaljuj'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numField(
    TextEditingController c,
    String label, {
    bool decimal = false,
  }) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      decoration: InputDecoration(labelText: label),
    );
  }

  void _save() {
    final type = _type!;
    ref.read(repositoryProvider.notifier).setMeasurements(
          widget.item.id,
          widthCm: _irregular
              ? null
              : double.tryParse(_width.text.replaceAll(',', '.')),
          lengthCm: _irregular
              ? null
              : double.tryParse(_length.text.replaceAll(',', '.')),
          manualM2: _irregular
              ? double.tryParse(_manual.text.replaceAll(',', '.'))
              : null,
          rugType: type,
          notes: _notes.text.trim(),
        );
    Navigator.pop(context);
  }
}

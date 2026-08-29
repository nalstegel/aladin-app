import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/catalog.dart';
import '../widgets/common.dart';

/// Vrste preprog s ceno na m² in minimalnim obračunom.
///
/// Cena se ob vnosu mer prepiše na kos, zato sprememba tukaj ne premakne cen
/// že izmerjenim preprogam — kar je namerno: obračunana cena mora ostati
/// takšna, kot je bila dogovorjena.
class RugTypesScreen extends ConsumerWidget {
  const RugTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(repositoryProvider).rugTypes;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mere in cena'),
        actions: [
          TextButton.icon(
            onPressed: () => editRugType(context, ref, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Dodaj'),
          ),
        ],
      ),
      body: types.isEmpty
          ? const EmptyState(
              icon: Icons.straighten,
              title: 'Cenik vrst je prazen',
              message: 'Brez vrste preproge ni mogoče izračunati cene.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: types.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                if (i == types.length) return const _Note();
                final t = types[i];
                return AppCard(
                  onTap: () => editRugType(context, ref, t),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.minChargeM2 > 0
                                  ? 'Minimalni obračun ${Fmt.m2(t.minChargeM2)}'
                                  : 'Brez minimalnega obračuna',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${t.pricePerM2.toStringAsFixed(2).replaceAll('.', ',')} €/m²',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 8),
      child: Text(
        'Sprememba cene velja za nove izmere. Preproge, ki so že izmerjene, '
        'obdržijo ceno, po kateri so bile obračunane.',
        style: TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
    );
  }
}

Future<void> editRugType(
  BuildContext context,
  WidgetRef ref,
  RugType? existing,
) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final price = TextEditingController(
    text: existing?.pricePerM2.toStringAsFixed(2) ?? '',
  );
  final minCharge = TextEditingController(
    text: existing?.minChargeM2.toStringAsFixed(1) ?? '0',
  );

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(existing == null ? 'Nova vrsta' : 'Uredi vrsto'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Naziv'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Cena',
              suffixText: '€/m²',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: minCharge,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(
              labelText: 'Minimalni obračun',
              suffixText: 'm²',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Prekliči'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Shrani'),
        ),
      ],
    ),
  );

  if (ok == true) {
    final repo = ref.read(repositoryProvider.notifier);
    final p = double.tryParse(price.text.replaceAll(',', '.')) ?? 0;
    final m = double.tryParse(minCharge.text.replaceAll(',', '.')) ?? 0;
    if (name.text.trim().isNotEmpty && p > 0) {
      if (existing == null) {
        repo.createRugType(name.text.trim(), p, m);
      } else {
        repo.upsertRugType(existing.copyWith(
          name: name.text.trim(),
          pricePerM2: p,
          minChargeM2: m,
        ));
      }
    }
  }

  name.dispose();
  price.dispose();
  minCharge.dispose();
}

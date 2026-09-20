import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/catalog.dart';
import '../../models/enums.dart';
import '../widgets/common.dart';

/// Doplačila in popusti, ki se ponudijo pri končni obdelavi.
class ExtrasScreen extends ConsumerWidget {
  const ExtrasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extras = ref.watch(repositoryProvider).extraTemplates;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cenik'),
        actions: [
          TextButton.icon(
            onPressed: () => editExtra(context, ref, null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Dodaj'),
          ),
        ],
      ),
      body: extras.isEmpty
          ? const EmptyState(
              icon: Icons.local_offer_outlined,
              title: 'Ni doplačil ne popustov',
              message: 'Postavke se ponudijo delavcu pri končni obdelavi.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: extras.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = extras[i];
                return AppCard(
                  onTap: () => editExtra(context, ref, e),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${e.value > 0 ? '+' : '−'}'
                        '${e.value.abs().toStringAsFixed(e.kind == ExtraKind.percent ? 0 : 2).replaceAll('.', ',')} '
                        '${e.kind.label}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color:
                              e.isDiscount ? AppColors.ready : AppColors.primary,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Izbriši',
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.danger, size: 20),
                        onPressed: () => _confirmDeleteExtra(context, ref, e),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

Future<void> _confirmDeleteExtra(
  BuildContext context,
  WidgetRef ref,
  ExtraTemplate extra,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Izbriši postavko?'),
      content: Text('"${extra.name}" ne bo več na voljo pri končni obdelavi.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Prekliči'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Izbriši'),
        ),
      ],
    ),
  );
  if (ok == true) {
    ref.read(repositoryProvider.notifier).deleteExtraTemplate(extra.id);
  }
}

Future<void> editExtra(
  BuildContext context,
  WidgetRef ref,
  ExtraTemplate? existing,
) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final value = TextEditingController(
    text: existing?.value.toStringAsFixed(2) ?? '',
  );
  var kind = existing?.kind ?? ExtraKind.percent;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? 'Nova postavka' : 'Uredi postavko'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Naziv'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: value,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Vrednost',
                helperText: 'Negativna vrednost pomeni popust.',
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<ExtraKind>(
              segments: const [
                ButtonSegment(value: ExtraKind.percent, label: Text('%')),
                ButtonSegment(value: ExtraKind.perM2, label: Text('€/m²')),
                ButtonSegment(value: ExtraKind.fixed, label: Text('€')),
              ],
              selected: {kind},
              onSelectionChanged: (s) => setState(() => kind = s.first),
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
    ),
  );

  if (ok == true) {
    final repo = ref.read(repositoryProvider.notifier);
    final v = double.tryParse(value.text.replaceAll(',', '.'));
    if (name.text.trim().isNotEmpty && v != null && v != 0) {
      if (existing == null) {
        repo.createExtraTemplate(name.text.trim(), kind, v);
      } else {
        repo.upsertExtraTemplate(
          existing.copyWith(name: name.text.trim(), kind: kind, value: v),
        );
      }
    }
  }

  name.dispose();
  value.dispose();
}

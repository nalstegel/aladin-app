import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/catalog.dart';
import '../../models/enums.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final repo = ref.read(repositoryProvider.notifier);
    final user = ref.watch(currentUserProvider);

    final completed =
        state.orders.where((o) => o.status == OrderStatus.completed);
    final revenue = completed.fold<double>(
      0,
      (s, o) => s + state.orderTotal(o.id),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Več')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          AppCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                    (user?.name ?? '?').substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'Ni prijave',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        user?.role.label ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _switchUser(context, ref),
                  child: const Text('Zamenjaj'),
                ),
              ],
            ),
          ),
          const SectionHeader('Pregled'),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${state.orders.where((o) => o.status.isOpen).length}',
                  label: 'aktivnih naročil',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: '${completed.length}',
                  label: 'zaključenih',
                  color: AppColors.ready,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppCard(
            child: DetailRow(
              'Promet zaključenih naročil',
              Fmt.money(revenue),
              strong: true,
            ),
          ),
          SectionHeader(
            'Cenik',
            subtitle: 'Cena na m² in minimalni obračun.',
            trailing: TextButton.icon(
              onPressed: () => _editRugType(context, ref, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Dodaj'),
            ),
          ),
          for (final t in state.rugTypes) ...[
            AppCard(
              onTap: () => _editRugType(context, ref, t),
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
            ),
            const SizedBox(height: 8),
          ],
          SectionHeader(
            'Doplačila in popusti',
            subtitle: 'Ponudijo se pri končni obdelavi.',
            trailing: TextButton.icon(
              onPressed: () => _editExtra(context, ref, null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Dodaj'),
            ),
          ),
          for (final e in state.extraTemplates) ...[
            AppCard(
              onTap: () => _editExtra(context, ref, e),
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
                      color: e.isDiscount ? AppColors.ready : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SectionHeader('Zaposleni'),
          for (final u in state.users) ...[
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          u.role.label,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (u.id == user?.id)
                    const StatusChip(
                      label: 'Prijavljen',
                      color: AppColors.ready,
                      dense: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SectionHeader('Podatki'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Podatki so trenutno shranjeni lokalno na tej napravi. '
                  'Za skupno delo več telefonov se priklopi Firebase.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Ponastavi na demo podatke?'),
                        content: const Text(
                          'Vsa lokalno vnesena naročila in stranke bodo '
                          'izbrisani.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Prekliči'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.danger,
                            ),
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Ponastavi'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) await repo.resetToSeed();
                  },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Ponastavi demo podatke'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _switchUser(BuildContext context, WidgetRef ref) {
    final state = ref.read(repositoryProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Kdo dela?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            for (final u in state.users.where((u) => u.active))
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: Text(
                    u.name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                title: Text(u.name),
                subtitle: Text(u.role.label),
                onTap: () {
                  ref.read(repositoryProvider.notifier).setCurrentUser(u.id);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _editRugType(
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
    if (ok != true) return;

    final repo = ref.read(repositoryProvider.notifier);
    final p = double.tryParse(price.text.replaceAll(',', '.')) ?? 0;
    final m = double.tryParse(minCharge.text.replaceAll(',', '.')) ?? 0;
    if (name.text.trim().isEmpty || p <= 0) return;

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

  Future<void> _editExtra(
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
    if (ok != true) return;

    final repo = ref.read(repositoryProvider.notifier);
    final v = double.tryParse(value.text.replaceAll(',', '.'));
    if (name.text.trim().isEmpty || v == null || v == 0) return;

    if (existing == null) {
      repo.createExtraTemplate(name.text.trim(), kind, v);
    } else {
      repo.upsertExtraTemplate(
        existing.copyWith(name: name.text.trim(), kind: kind, value: v),
      );
    }
  }
}

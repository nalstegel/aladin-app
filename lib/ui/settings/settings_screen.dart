import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/auth.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../models/app_user.dart';
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
                        [user?.role.label, user?.email]
                            .where((e) => e != null && e.isNotEmpty)
                            .join(' · '),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => _signOut(context, ref),
                  child: const Text('Odjava'),
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
          if (user?.isAdmin ?? false)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Kot skrbnik lahko urejaš vloge in dostop. Nov zaposleni se '
                'na seznamu pojavi sam, ko se prvič prijavi.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
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
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: u.active ? null : AppColors.textMuted,
                            decoration: u.active
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        Text(
                          [
                            u.role.label,
                            if (u.email.isNotEmpty) u.email,
                            if (!u.active) 'nima dostopa',
                          ].join(' · '),
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
                  if ((user?.isAdmin ?? false) && u.id != user?.id)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Uredi zaposlenega',
                      onPressed: () => _editUser(context, repo, u),
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
                  'Podatki so v skupni bazi (Firebase). Vsi zaposleni vidijo '
                  'iste podatke, spremembe se sproti prenašajo med telefoni.',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                ),
                // Ponastavitev pobriše SKUPNO bazo, ne le tega telefona —
                // zato je na voljo samo skrbniku.
                if (user?.isAdmin ?? false) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _resetData(context, repo),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Ponastavi demo podatke'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Skrbnik ureja ime, vlogo in dostop drugih zaposlenih.
  ///
  /// Svojega zapisa namenoma ni mogoče urejati tu — sicer bi si zadnji
  /// skrbnik lahko odvzel vlogo in nihče več ne bi mogel dodeljevati
  /// pravic (`firestore.rules` tega tudi ne dovoli).
  Future<void> _editUser(
    BuildContext context,
    Repository repo,
    AppUser target,
  ) async {
    final name = TextEditingController(text: target.name);
    var role = target.role;
    var active = target.active;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: Text(target.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Ime'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Vloga',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              SegmentedButton<UserRole>(
                segments: [
                  for (final r in UserRole.values)
                    ButtonSegment(value: r, label: Text(r.label)),
                ],
                selected: {role},
                onSelectionChanged: (s) => setInner(() => role = s.first),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ima dostop'),
                subtitle: const Text(
                  'Izklop obdrži zgodovino, a zaposlenega skrije s seznamov.',
                  style: TextStyle(fontSize: 12),
                ),
                value: active,
                onChanged: (v) => setInner(() => active = v),
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
      repo.upsertUser(target.copyWith(
        name: name.text.trim().isEmpty ? target.name : name.text.trim(),
        role: role,
        active: active,
      ));
    }
    name.dispose();
  }

  /// Ponastavitev izbriše skupno bazo za vse zaposlene, zato zahteva
  /// izrecno potrditev z vpisom besede — en napačen dotik ne sme
  /// pobrisati podjetju vseh naročil.
  Future<void> _resetData(BuildContext context, Repository repo) async {
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ponastavi na demo podatke?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Izbrisana bodo VSA naročila, kosi in stranke iz skupne baze '
              '— pri vseh zaposlenih, ne le na tem telefonu. Tega ni mogoče '
              'razveljaviti.\n\nZa potrditev vpiši PONASTAVI:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirm,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(hintText: 'PONASTAVI'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Prekliči'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(
              context,
              confirm.text.trim().toUpperCase() == 'PONASTAVI',
            ),
            child: const Text('Ponastavi'),
          ),
        ],
      ),
    );
    confirm.dispose();
    if (ok == true) await repo.resetToSeed();
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Odjava'),
        content: const Text(
          'Za nadaljevanje dela se bo treba znova prijaviti s svojim '
          'e-naslovom in geslom.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Prekliči'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Odjavi se'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    ref.read(repositoryProvider.notifier).clearCurrentUser();
    await ref.read(authServiceProvider).signOut();
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

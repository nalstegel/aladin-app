import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/auth.dart';
import '../../data/providers.dart';
import '../../data/push.dart';
import '../../data/repository.dart';
import '../../models/app_user.dart';
import '../../models/enums.dart';
import '../widgets/common.dart';

/// Zaposleni. Tu je tudi lastni račun in odjava — vse, kar je vezano na
/// ljudi, je na enem mestu.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final repo = ref.read(repositoryProvider.notifier);
    final me = ref.watch(currentUserProvider);
    final isAdmin = me?.isAdmin ?? false;

    final others = state.users.where((u) => u.id != me?.id).toList()
      ..sort((a, b) {
        if (a.active != b.active) return a.active ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Uporabniki')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SectionHeader('Moj račun'),
          AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    AvatarCircle(me?.name ?? '?'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            me?.name ?? 'Ni prijave',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [me?.role.label, me?.email]
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
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _signOut(context, ref),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Odjava'),
                ),
              ],
            ),
          ),
          const SectionHeader('Zaposleni'),
          if (isAdmin)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Kot skrbnik lahko urejaš vloge in dostop. Nov zaposleni se '
                'na seznamu pojavi sam, ko se prvič prijavi.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          for (final u in others) ...[
            AppCard(
              onTap: isAdmin ? () => _editUser(context, repo, u) : null,
              child: Row(
                children: [
                  AvatarCircle(
                    u.name,
                    radius: 18,
                    color: u.active ? AppColors.primary : AppColors.textMuted,
                  ),
                  const SizedBox(width: 12),
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
                            decoration:
                                u.active ? null : TextDecoration.lineThrough,
                          ),
                        ),
                        Text(
                          [
                            u.role.label,
                            if (u.email.isNotEmpty) u.email,
                            if (!u.active) 'nima dostopa',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    const Icon(Icons.chevron_right,
                        size: 20, color: AppColors.textMuted),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (others.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Drugih zaposlenih še ni. Račun se ustvari v Firebase konzoli, '
                'zaposleni pa se na seznamu pojavi ob prvi prijavi.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }

  /// Skrbnik ureja ime, vlogo in dostop drugih zaposlenih.
  ///
  /// Svojega zapisa namenoma ni mogoče urejati tu — sicer bi si zadnji
  /// skrbnik lahko odvzel vlogo in nihče več ne bi mogel dodeljevati pravic
  /// (`firestore.rules` tega tudi ne dovoli).
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

    // Vrstni red je pomemben: naročnino odjavimo, dokler je seja še živa.
    await ref.read(pushServiceProvider).signOut();
    ref.read(repositoryProvider.notifier).clearCurrentUser();
    await ref.read(authServiceProvider).signOut();
  }
}

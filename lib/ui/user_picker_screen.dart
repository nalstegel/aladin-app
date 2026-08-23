import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../models/enums.dart';

/// Kdo dela? Vsak korak v proizvodnji se zabeleži na tega zaposlenega.
class UserPickerScreen extends ConsumerWidget {
  const UserPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final users = state.users.where((u) => u.active).toList();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.layers_outlined,
                    color: Colors.white, size: 30),
              ),
              const SizedBox(height: 20),
              const Text(
                'Aladin',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Kdo dela?',
                style: TextStyle(fontSize: 16, color: AppColors.textMuted),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final u = users[i];
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => ref
                            .read(repositoryProvider.notifier)
                            .setCurrentUser(u.id),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    AppColors.primary.withValues(alpha: 0.12),
                                child: Text(
                                  u.name.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      u.name,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      u.role.label,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: AppColors.textMuted),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _addUser(context, ref),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Dodaj zaposlenega'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addUser(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    var role = UserRole.worker;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Nov zaposleni'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Ime'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<UserRole>(
                segments: const [
                  ButtonSegment(
                      value: UserRole.worker, label: Text('Zaposleni')),
                  ButtonSegment(
                      value: UserRole.admin, label: Text('Administrator')),
                ],
                selected: {role},
                onSelectionChanged: (s) => setState(() => role = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Prekliči'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Dodaj'),
            ),
          ],
        ),
      ),
    );
    if (name == null || name.isEmpty) return;
    final repo = ref.read(repositoryProvider.notifier);
    final user = repo.createUser(name, role);
    repo.setCurrentUser(user.id);
  }
}

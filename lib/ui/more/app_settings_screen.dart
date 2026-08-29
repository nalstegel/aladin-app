import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/push.dart';
import '../../data/repository.dart';
import '../widgets/common.dart';

class AppSettingsScreen extends ConsumerWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(repositoryProvider.notifier);
    final user = ref.watch(currentUserProvider);
    final pushEnabled = ref.watch(pushEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nastavitve')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SectionHeader('Obvestila'),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Potisna obvestila',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Pripravljena naročila, zamude in jutranji povzetek dneva.',
                style: TextStyle(fontSize: 12),
              ),
              value: pushEnabled.valueOrNull ?? false,
              onChanged: pushEnabled.isLoading
                  ? null
                  : (v) async {
                      final actual =
                          await ref.read(pushServiceProvider).setEnabled(v);
                      ref.invalidate(pushEnabledProvider);
                      if (!context.mounted) return;
                      if (v && !actual) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Obvestila so zavrnjena v nastavitvah telefona.',
                            ),
                          ),
                        );
                      }
                    },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(
              'Obvestila so vezana na ta telefon. Ista obvestila so vedno na '
              'voljo tudi pod zvončkom na zaslonu Danes.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          if (user?.isAdmin ?? false) ...[
            const SectionHeader('Podatki'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ponastavitev pobriše SKUPNO bazo — pri vseh zaposlenih, '
                    'ne le na tem telefonu.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _resetData(context, repo),
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Ponastavi demo podatke'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: BorderSide(
                        color: AppColors.danger.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Ponastavitev izbriše skupno bazo za vse zaposlene, zato zahteva izrecno
  /// potrditev z vpisom besede — en napačen dotik ne sme pobrisati podjetju
  /// vseh naročil.
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
}

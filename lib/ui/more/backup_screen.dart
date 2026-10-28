import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../widgets/common.dart';

/// Stanje varnostnega kopiranja.
///
/// Namenoma **brez izvoza v datoteko**: izvoz bi vseboval imena, telefone in
/// naslove vseh strank in bi v trenutku, ko ga nekdo deli naprej, zapustil
/// varnostna pravila, ki te podatke sicer varujejo. Podatki so v Firestore,
/// ki jih podvaja na Googlovi strani.
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Varnostne kopije')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppCard(
            accent: AppColors.ready,
            child: Row(
              children: [
                const Icon(Icons.cloud_done_outlined,
                    size: 22, color: AppColors.ready),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Podatki so v skupni bazi',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Zadnja sprememba ${Fmt.relative(_lastChange(ref))}',
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
          ),
          const SectionHeader('Kaj je shranjeno'),
          AppCard(
            child: Column(
              children: [
                DetailRow('Naročila', '${state.orders.length}'),
                DetailRow('Kosi', '${state.items.length}'),
                DetailRow('Stranke', '${state.customers.length}'),
                DetailRow('Zaposleni', '${state.users.length}'),
              ],
            ),
          ),
          const SectionHeader('Kako deluje'),
          const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Point(
                  icon: Icons.sync,
                  text: 'Vsaka sprememba se takoj zapiše v skupno bazo in se '
                      'pokaže na vseh telefonih.',
                ),
                SizedBox(height: 12),
                _Point(
                  icon: Icons.signal_wifi_off,
                  text: 'Brez signala aplikacija dela naprej — spremembe se '
                      'shranijo v telefon in oddajo, ko se signal vrne.',
                ),
                SizedBox(height: 12),
                _Point(
                  icon: Icons.shield_outlined,
                  text: 'Kopije hrani Google v okviru storitve Firestore. '
                      'Ročno kopiranje ni potrebno.',
                ),
              ],
            ),
          ),
          const SectionHeader('Zakaj ni gumba za izvoz'),
          const AppCard(
            child: Text(
              'Izvožena datoteka bi vsebovala imena, telefonske številke in '
              'naslove vseh strank. Ko je enkrat na telefonu ali v e-pošti, je '
              'zunaj varnostnih pravil aplikacije in je ni več mogoče '
              'preklicati. Če izvoz kdaj potrebuješ (npr. za računovodstvo), '
              'ga je bolje pripraviti enkratno in ciljano, ne kot gumb, ki je '
              'vedno pri roki.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  DateTime _lastChange(WidgetRef ref) {
    final state = ref.read(repositoryProvider);
    var latest = DateTime.fromMillisecondsSinceEpoch(0);
    for (final o in state.orders) {
      final d = o.completedAt ?? o.readyAt ?? o.createdAt;
      if (d.isAfter(latest)) latest = d;
    }
    for (final i in state.items) {
      final d = i.lastChangeAt;
      if (d != null && d.isAfter(latest)) latest = d;
    }
    return latest.millisecondsSinceEpoch == 0 ? DateTime.now() : latest;
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

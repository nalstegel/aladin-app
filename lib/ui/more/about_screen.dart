import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../firebase_options.dart';
import '../../models/enums.dart';
import '../widgets/common.dart';

final _packageInfoProvider =
    FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final info = ref.watch(_packageInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('O aplikaciji')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.qr_code_scanner,
                        color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Aladin',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'Interna aplikacija za pralnico preprog',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader('Različica'),
          AppCard(
            child: Column(
              children: [
                DetailRow('Različica', info.valueOrNull?.version ?? '…'),
                DetailRow('Gradnja', info.valueOrNull?.buildNumber ?? '…'),
              ],
            ),
          ),
          const SectionHeader('Baza'),
          AppCard(
            child: Column(
              children: [
                DetailRow(
                  'Firebase projekt',
                  DefaultFirebaseOptions.currentPlatform.projectId,
                ),
                DetailRow('Prijavljen', user?.email ?? '—'),
                DetailRow('Vloga', user?.role.label ?? '—'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Podatki so v skupni bazi. Vsi zaposleni vidijo iste podatke, '
            'spremembe se sproti prenašajo med telefoni.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

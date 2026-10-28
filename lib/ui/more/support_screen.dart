import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../widgets/common.dart';

/// Kontakt za pomoč.
///
/// TODO(lastnik): vpiši prave podatke. Nikjer v projektu ni zapisano, na koga
/// naj se zaposleni obrne, zato so spodnje vrednosti prazne — raje prazno kot
/// izmišljena številka, ki bi jo nekdo v stiski poklical.
const _supportName = '';
const _supportPhone = '';
const _supportEmail = '';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  bool get _configured =>
      _supportPhone.isNotEmpty || _supportEmail.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Podpora')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (!_configured)
            const AppCard(
              accent: AppColors.awaitingWash,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: AppColors.awaitingWash),
                      SizedBox(width: 8),
                      Text(
                        'Kontakt še ni vpisan',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Podatke za podporo vpiše skrbnik v datoteki '
                    'lib/ui/more/support_screen.dart. Dokler niso vpisani, '
                    'ta zaslon namenoma ne kaže nobene številke.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            const SectionHeader('Kontakt'),
            AppCard(
              child: Column(
                children: [
                  if (_supportName.isNotEmpty)
                    DetailRow('Skrbnik', _supportName),
                  if (_supportPhone.isNotEmpty)
                    _CopyRow(
                      label: 'Telefon',
                      value: _supportPhone,
                      icon: Icons.phone_outlined,
                    ),
                  if (_supportEmail.isNotEmpty)
                    _CopyRow(
                      label: 'E-pošta',
                      value: _supportEmail,
                      icon: Icons.mail_outline,
                    ),
                ],
              ),
            ),
          ],
          const SectionHeader('Preden pokličeš'),
          const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Check('Ali telefon sploh ima signal? Brez njega aplikacija '
                    'dela naprej, spremembe pa se prenesejo šele pozneje.'),
                _Check('Ali si prijavljen s svojim računom? Zgodovina se '
                    'pripiše računu, ki je prijavljen na tem telefonu.'),
                _Check('Če se kos ne odpre, preveri oznako na etiketi in '
                    'poskusi Ročni vnos kode pod skenerjem.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label kopiran.')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.copy, size: 16, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 17, color: AppColors.ready),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

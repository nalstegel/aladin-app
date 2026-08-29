import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../widgets/common.dart';

/// Navodila za delo. Vsebina je povzeta po opisu lastnika in README.md —
/// namenoma opisuje, kako se dela, ne kako aplikacija deluje.
class ManualScreen extends StatelessWidget {
  const ManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Navodila')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: const [
          _Intro(),
          SectionHeader('Pot preproge'),
          _Step(
            n: '1',
            title: 'Sprejem naročila',
            body: 'Naročilo → Novo naročilo. Izbereš stranko (ali jo dodaš), '
                'vpišeš število kosov in rok. Aplikacija sama naredi etikete '
                'za vsak kos posebej.',
          ),
          _Step(
            n: '2',
            title: 'Etikete',
            body: 'V naročilu tapneš ikono QR in natisneš polo. Na vsaki '
                'etiketi so ime stranke, številka naročila, KOS x/y in koda.',
          ),
          _Step(
            n: '3',
            title: 'Prevzem',
            body: 'Ko preproge pridejo v obrat, na zaslonu Danes tapneš '
                'Prevzemi. Vsi kosi naročila gredo na pranje.',
          ),
          _Step(
            n: '4',
            title: 'Pranje in sušenje',
            body: 'Ob stroju vklopiš Hitri način v zavihku Skeniraj. Vsak '
                'skeniran kos gre samodejno korak naprej — brez dotikanja '
                'zaslona z mokrimi rokami.',
          ),
          _Step(
            n: '5',
            title: 'Mere in cena',
            body: 'Ko je preproga suha, jo skeniraš in vpišeš širino, dolžino '
                'in vrsto. Aplikacija izračuna m² in osnovno ceno. Pri končni '
                'obdelavi dodaš doplačila ali popust in potrdiš ceno — kos '
                'postane Pripravljeno.',
          ),
          _Step(
            n: '6',
            title: 'Vračilo',
            body: 'Ko so vsi kosi pripravljeni, se naročilo samo prestavi med '
                'čakajoča. Pri predaji odpreš Vrni, poskeniraš vse kose in '
                'stranka se podpiše na telefon.',
            last: true,
          ),
          SectionHeader('Dobro je vedeti'),
          _Tip(
            icon: Icons.calculate_outlined,
            text: 'Statusa naročila ni mogoče nastaviti ročno. Aplikacija ga '
                'vedno izračuna iz stanja posameznih kosov — če je 2 od 3 '
                'kosov pripravljenih, naročilo še ni pripravljeno.',
          ),
          _Tip(
            icon: Icons.verified_user_outlined,
            text: 'Naročila ni mogoče zaključiti, dokler niso poskenirani vsi '
                'kosi. To je namerno: podpis je dokazilo, da so bile preproge '
                'res vrnjene.',
          ),
          _Tip(
            icon: Icons.edit_outlined,
            text: 'Če je etiketa strgana ali umazana, uporabi Ročni vnos kode '
                'pod skenerjem in vpiši oznako (npr. 1847-2).',
          ),
          _Tip(
            icon: Icons.signal_wifi_off,
            text: 'Brez signala aplikacija dela naprej. Spremembe se shranijo '
                'v telefon in oddajo, ko se signal vrne.',
          ),
          _Tip(
            icon: Icons.person_off_outlined,
            text: 'Če stranka podpisa ne more ali noče dati, ima skrbnik obvod '
                'z obveznim razlogom — naročilo se nikoli ne blokira.',
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      accent: AppColors.primary,
      child: Text(
        'Naročilo je skupek preprog. Vsaka preproga ima svojo QR etiketo in '
        'svojo pot skozi proizvodnjo — zato vedno veš, kateri konkretni kos '
        'še manjka.',
        style: TextStyle(fontSize: 14, height: 1.4),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.title,
    required this.body,
    this.last = false,
  });

  final String n;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  n,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: AppColors.border),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 12),
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
      ),
    );
  }
}

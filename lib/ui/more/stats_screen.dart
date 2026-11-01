import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../data/stats.dart';
import '../../models/enums.dart';
import '../widgets/common.dart';

/// Obdobje za Proizvodnjo in Dodatno statistiko.
enum StatsPeriod { today, week, month, custom }

extension on StatsPeriod {
  String get label => switch (this) {
    StatsPeriod.today => 'Danes',
    StatsPeriod.week => 'Ta teden',
    StatsPeriod.month => 'Ta mesec',
    StatsPeriod.custom => 'Po meri datuma',
  };
}

/// Pregledna plošča: promet, zaloga na policah, proizvodnja, trenutno delo in
/// dodatna statistika na eni strani. Vse je izračunano iz naročil
/// (`data/stats.dart`) — nič se ne vodi posebej, zato se ne more razhajati.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  StatsPeriod _period = StatsPeriod.month;

  /// Po meri datuma: dokler ni izbrano, velja od začetka meseca do danes
  /// (izpeljano, zato sledi dnevu).
  DateTime? _customFrom;
  DateTime? _customTo;

  DateTime _from(DateTime today) =>
      _customFrom ?? DateTime(today.year, today.month);
  DateTime _to(DateTime today) => _customTo ?? today;

  StatsRange _rangeFor(DateTime today) => switch (_period) {
    StatsPeriod.today => StatsRange.day(today),
    StatsPeriod.week => StatsRange.week(today),
    StatsPeriod.month => StatsRange.month(today),
    StatsPeriod.custom => StatsRange.days(_from(today), _to(today)),
  };

  Future<void> _pick({required bool isFrom}) async {
    final today = ref.read(todayProvider);
    final current = isFrom ? _from(today) : _to(today);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isAfter(today) ? today : current,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      final from = _from(today);
      final to = _to(today);
      if (isFrom) {
        _customFrom = picked;
        _customTo = to.isBefore(picked) ? picked : to;
      } else {
        _customTo = picked;
        _customFrom = from.isAfter(picked) ? picked : from;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final today = ref.watch(todayProvider);
    final range = _rangeFor(today);
    final stats = computeStats(state, now: today, period: range);
    final rangeText = _rangeText(range);

    return Scaffold(
      appBar: AppBar(title: const Text('Statistika in promet')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // 1. Zgornji pregled
          const SectionHeader('Pregled'),
          _TilePair(
            StatTile(
              value: Fmt.money(stats.revenue),
              label: 'Realiziran promet',
              caption: '${Fmt.orders(stats.completedOrders)} vrnjenih',
              color: AppColors.primary,
              icon: Icons.payments_outlined,
            ),
            StatTile(
              value: Fmt.money(stats.monthRevenue),
              label: 'Ta mesec',
              caption: '${Fmt.orders(stats.monthOrders)} vrnjenih',
              color: AppColors.primary,
              icon: Icons.calendar_month_outlined,
            ),
          ),
          const SizedBox(height: 10),
          _TilePair(
            StatTile(
              value: Fmt.money(stats.averageOrder),
              label: 'Povprečno naročilo',
              caption: 'vrnjena naročila',
              color: AppColors.returned,
              icon: Icons.functions,
            ),
            StatTile(
              value: Fmt.money(stats.inProgressValue),
              label: 'V teku',
              caption: 'še ni pripravljeno',
              color: AppColors.awaitingWash,
              icon: Icons.autorenew,
            ),
          ),
          const SizedBox(height: 10),
          _TilePair(
            StatTile(
              value: Fmt.money(stats.shelfValue),
              label: 'Pripravljeno',
              caption: 'še ni vrnjeno',
              color: AppColors.ready,
              icon: Icons.check_circle_outline,
            ),
            StatTile(
              value: '${stats.shelfOrders} / ${stats.shelfPieces}',
              label: 'Pripravljeno: naročil / kosov',
              color: AppColors.ready,
              icon: Icons.inventory_2_outlined,
            ),
          ),

          // 2. Pripravljeno na policah
          const SectionHeader(
            'Pripravljeno na policah',
            subtitle:
                'Vsi pripravljeni kosi, ki še niso vrnjeni (tudi v Dostavah)',
          ),
          AppCard(
            child: Column(
              children: [
                DetailRow('Naročil', '${stats.shelfOrders}'),
                DetailRow('Kosov', '${stats.shelfPieces}'),
                DetailRow('Skupaj m²', Fmt.m2(stats.shelfM2)),
                DetailRow(
                  'Skupna vrednost',
                  Fmt.money(stats.shelfValue),
                  strong: true,
                ),
                const Divider(height: 22),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: _Caption('Starost zaloge'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < stats.shelfAge.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _AgeCell(stats.shelfAge[i], old: i == 2)),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // 3. Proizvodnja
          const SectionHeader(
            'Proizvodnja',
            subtitle:
                'Kos je dokončan, ko po Hitrem obračunu preide v '
                'Pripravljeno',
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in StatsPeriod.values)
                FilterPill(
                  label: p.label,
                  selected: _period == p,
                  dense: true,
                  onTap: () => setState(() => _period = p),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_period == StatsPeriod.custom)
            Row(
              children: [
                Expanded(
                  child: _DateChip(
                    label: 'Od',
                    date: _from(today),
                    onTap: () => _pick(isFrom: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateChip(
                    label: 'Do',
                    date: _to(today),
                    onTap: () => _pick(isFrom: false),
                  ),
                ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _Caption(rangeText),
            ),
          const SizedBox(height: 10),
          _TilePair(
            StatTile(
              value: '${stats.producedPieces}',
              label: 'Dokončanih kosov',
              color: AppColors.ready,
              icon: Icons.check_circle_outline,
            ),
            StatTile(
              value: '${stats.producedOrders}',
              label: 'Dokončanih naročil',
              color: AppColors.ready,
              icon: Icons.receipt_long_outlined,
            ),
          ),
          const SizedBox(height: 10),
          _TilePair(
            StatTile(
              value: Fmt.m2(stats.producedM2),
              label: 'Skupaj m²',
              color: AppColors.drying,
              icon: Icons.texture,
            ),
            StatTile(
              value: Fmt.money(stats.producedValue),
              label: 'Proizvedena vrednost',
              color: AppColors.primary,
              icon: Icons.payments_outlined,
            ),
          ),

          // 4. Trenutno delo
          const SectionHeader(
            'Trenutno delo',
            subtitle: 'Stanje zdaj, ne glede na obdobje',
          ),
          AppCard(
            child: Column(
              children: [
                _PipelineRow(
                  color: AppColors.forRug(RugStatus.awaitingWash),
                  label: 'Čaka pranje',
                  value: Fmt.pieces(stats.washingPieces),
                ),
                _PipelineRow(
                  color: AppColors.forRug(RugStatus.drying),
                  label: 'Sušenje',
                  value: Fmt.pieces(stats.dryingPieces),
                ),
                _PipelineRow(
                  color: AppColors.forRug(RugStatus.ready),
                  label: 'Pripravljeno',
                  value: Fmt.pieces(stats.shelfPieces),
                  detail:
                      '${Fmt.m2(stats.shelfM2)} · '
                      '${Fmt.money(stats.shelfValue)}',
                ),
                const Divider(height: 22),
                DetailRow(
                  'Skupna vrednost odprtih naročil '
                  '(${Fmt.orders(stats.openOrders)})',
                  Fmt.money(stats.openValue),
                  strong: true,
                ),
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: _Caption(
                    'm² pri Čaka pranje in Sušenje ni prikazan: mere vnesemo '
                    'šele pri Hitrem obračunu.',
                  ),
                ),
              ],
            ),
          ),

          // 5. Dodatna statistika
          SectionHeader('Dodatna statistika', subtitle: 'Obdobje: $rangeText'),
          AppCard(
            child: Column(
              children: [
                _AverageRow(
                  label: 'Prevzeto → Pripravljeno',
                  duration: stats.avgToReady,
                  pieces: stats.avgToReadyPieces,
                  basis: 'dokončani v obdobju',
                ),
                const Divider(height: 22),
                _AverageRow(
                  label: 'Pripravljeno → Vrnjeno',
                  duration: stats.avgToReturn,
                  pieces: stats.avgToReturnPieces,
                  basis: 'vrnjeni v obdobju',
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _BreakdownCard(
            title: 'Po tipu preproge',
            rows: stats.byRugType,
            detail: (g) => '${Fmt.pieces(g.pieces)} · ${Fmt.m2(g.m2)}',
          ),
          const SizedBox(height: 10),
          _BreakdownCard(
            title: 'Po regiji',
            rows: stats.byRegion,
            detail: (g) => Fmt.orders(g.orders),
          ),
          const SizedBox(height: 10),
          _BreakdownCard(
            title: 'Naš prevzem in Pripeljano',
            rows: stats.byChannel,
            detail: (g) => Fmt.orders(g.orders),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: _Caption(
              'Razrez zajema kose, ki so v obdobju prešli v Pripravljeno. '
              'Naročilo je dokončano, ko je to storil zadnji kos; promet pa '
              'se šteje šele ob vračilu.',
            ),
          ),
        ],
      ),
    );
  }

  static String _rangeText(StatsRange r) {
    final last = r.lastDay;
    if (r.from == last) return Fmt.date(r.from);
    return '${Fmt.dateShort(r.from)} – ${Fmt.date(last)}';
  }
}

/// Dve kartici v vrsti, enako visoki.
class _TilePair extends StatelessWidget {
  const _TilePair(this.left, this.right);

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    ),
  );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    ),
  );
}

class _AgeCell extends StatelessWidget {
  const _AgeCell(this.bucket, {required this.old});

  final AgeBucket bucket;

  /// Najstarejša skupina je opozorilo, a ne alarm (brez rdeče — V8).
  final bool old;

  @override
  Widget build(BuildContext context) {
    final color = old && bucket.pieces > 0
        ? AppColors.awaitingWash
        : AppColors.text;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '${bucket.pieces}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            bucket.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          Text(
            Fmt.money(bucket.value),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.event, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            '$label ',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          Flexible(
            child: Text(
              Fmt.date(date),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PipelineRow extends StatelessWidget {
  const _PipelineRow({
    required this.color,
    required this.label,
    required this.value,
    this.detail,
  });

  final Color color;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        // Podrobnost je pod oznako: velik znesek bi na ozkem telefonu
        // stisnil oznako na nič in prelil vrstico.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textMuted,
                ),
              ),
              if (detail != null)
                Text(
                  detail!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _AverageRow extends StatelessWidget {
  const _AverageRow({
    required this.label,
    required this.duration,
    required this.pieces,
    required this.basis,
  });

  final String label;
  final Duration? duration;
  final int pieces;
  final String basis;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Caption('Povprečen čas'),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            Text(
              duration == null
                  ? 'ni podatkov v obdobju'
                  : '${Fmt.pieces(pieces)}, $basis',
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      Text(
        duration == null ? '—' : Fmt.duration(duration!),
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

/// Razrez po skupinah: vrstica na skupino z zneskom, podrobnostmi in deležem
/// vrednosti.
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.title,
    required this.rows,
    required this.detail,
  });

  final String title;
  final List<GroupStat> rows;
  final String Function(GroupStat) detail;

  @override
  Widget build(BuildContext context) {
    // Delež v stotinkih, da je PlainProgressBar (int) natančen.
    final total = rows.fold<int>(0, (s, g) => s + (g.value * 100).round());
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Caption(title),
          const SizedBox(height: 6),
          for (final g in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          g.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        Fmt.money(g.value),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    detail(g),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  PlainProgressBar(
                    done: (g.value * 100).round(),
                    total: total,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

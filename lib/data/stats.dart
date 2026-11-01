import '../models/enums.dart';
import '../models/rug_item.dart';
import 'app_state.dart';
import 'billing.dart';
import 'order_phases.dart';

/// Izračuni za Več → Statistika in promet. Čista funkcija stanja: nič se ne
/// vodi posebej, zato se številke ne morejo razhajati s seznami.
///
/// Dva različna pojma, ki ju ne mešaj (plan.md §4.18):
///
/// * **Proizvodnja** je časovnica kosov. Kos je dokončan, ko PRVIČ preide v
///   Pripravljeno (Hitri obračun); naročilo je dokončano, ko je to storil
///   zadnji kos. Šteje se po datumu tega dogodka.
/// * **Realiziran promet** je časovnica vračil: naročilo šteje, ko je vrnjeno
///   (`completedAt`).
///
/// Naročilo, dokončano 30. 10. in vrnjeno 2. 11., je zato proizvodnja oktobra
/// in promet novembra.

/// Pol odprt razpon [from, to) v lokalnem času.
class StatsRange {
  const StatsRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  /// En koledarski dan, ki vsebuje [d].
  factory StatsRange.day(DateTime d) => StatsRange(
    DateTime(d.year, d.month, d.day),
    DateTime(d.year, d.month, d.day + 1),
  );

  /// Teden (ponedeljek–nedelja), ki vsebuje [d].
  factory StatsRange.week(DateTime d) {
    final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    return StatsRange(
      monday,
      DateTime(monday.year, monday.month, monday.day + 7),
    );
  }

  /// Koledarski mesec, ki vsebuje [d].
  factory StatsRange.month(DateTime d) =>
      StatsRange(DateTime(d.year, d.month), DateTime(d.year, d.month + 1));

  /// Od začetka dneva [first] do konca dneva [last] (oba vključena). Če sta
  /// obrnjena, ju zamenja — izbirnik datuma sme biti nastavljen v poljubnem
  /// vrstnem redu.
  factory StatsRange.days(DateTime first, DateTime last) {
    final a = DateTime(first.year, first.month, first.day);
    final b = DateTime(last.year, last.month, last.day);
    final lo = a.isAfter(b) ? b : a;
    final hi = a.isAfter(b) ? a : b;
    return StatsRange(lo, DateTime(hi.year, hi.month, hi.day + 1));
  }

  bool contains(DateTime t) => !t.isBefore(from) && t.isBefore(to);

  /// Zadnji vključeni dan (za izpis).
  DateTime get lastDay => DateTime(to.year, to.month, to.day - 1);

  @override
  bool operator ==(Object other) =>
      other is StatsRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// Seštevek za eno skupino (vrsta preproge, območje, kanal).
class GroupStat {
  const GroupStat({
    required this.label,
    this.pieces = 0,
    this.orders = 0,
    this.m2 = 0,
    this.value = 0,
  });

  final String label;
  final int pieces;
  final int orders;
  final double m2;
  final double value;
}

/// Zaloga na policah, razdeljena po starosti.
class AgeBucket {
  const AgeBucket({required this.label, this.pieces = 0, this.value = 0});

  final String label;
  final int pieces;
  final double value;
}

class DashboardStats {
  const DashboardStats({
    required this.revenue,
    required this.completedOrders,
    required this.monthRevenue,
    required this.monthOrders,
    required this.openValue,
    required this.openOrders,
    required this.shelfOrders,
    required this.shelfPieces,
    required this.shelfM2,
    required this.shelfValue,
    required this.shelfAge,
    required this.washingPieces,
    required this.dryingPieces,
    required this.producedPieces,
    required this.producedOrders,
    required this.producedM2,
    required this.producedValue,
    required this.avgToReady,
    required this.avgToReadyPieces,
    required this.avgToReturn,
    required this.avgToReturnPieces,
    required this.byRugType,
    required this.byRegion,
    required this.byChannel,
  });

  /// Realiziran promet: vrnjena naročila, vsa. [monthRevenue] samo tista,
  /// vrnjena ta mesec.
  final double revenue;
  final int completedOrders;
  final double monthRevenue;
  final int monthOrders;

  double get averageOrder =>
      completedOrders == 0 ? 0 : revenue / completedOrders;

  /// Vrednost vseh odprtih naročil (tudi že pripravljenih kosov) in njihovo
  /// število.
  final double openValue;
  final int openOrders;

  /// Pripravljeno in še ne vrnjeno — kosi, ne naročila: kos na polici je na
  /// polici, tudi če njegov sosed še suši. [shelfOrders] so naročila, ki imajo
  /// vsaj en tak kos.
  final int shelfOrders;
  final int shelfPieces;
  final double shelfM2;
  final double shelfValue;

  /// 0–3 / 4–7 / 8+ dni od zadnjega prehoda kosa v Pripravljeno.
  final List<AgeBucket> shelfAge;

  /// V teku brez Pripravljeno: odprta naročila minus vrednost kosov na polici.
  /// Skupaj z [shelfValue] da [openValue].
  double get inProgressValue => openValue - shelfValue;

  /// Kosi v Čaka pranje in Sušenje (kot zavihka; "Mere in cena" je v Sušenju).
  /// m² tu ni — mere vnesemo šele pri Hitrem obračunu.
  final int washingPieces;
  final int dryingPieces;

  /// Proizvodnja v izbranem obdobju.
  final int producedPieces;
  final int producedOrders;
  final double producedM2;
  final double producedValue;

  /// Povprečni čas Prevzeto → Pripravljeno (kosi, dokončani v obdobju) in
  /// Pripravljeno → Vrnjeno (kosi, vrnjeni v obdobju); null brez podatkov.
  final Duration? avgToReady;
  final int avgToReadyPieces;
  final Duration? avgToReturn;
  final int avgToReturnPieces;

  /// Razrez dokončanih kosov v obdobju. Seštevki so enaki Proizvodnji.
  final List<GroupStat> byRugType;
  final List<GroupStat> byRegion;
  final List<GroupStat> byChannel;
}

/// Prvi dogodek kosa v [status]. Prvi, ne zadnji: če kos po ročnem popravku
/// znova gre skozi isti korak, se v obdobju ne sme šteti dvakrat (enako kot
/// `functions/summaries.js`).
DateTime? firstEventAt(RugItem item, RugStatus status) {
  for (final e in item.history) {
    if (e.status == status) return e.at;
  }
  return null;
}

/// Zadnji dogodek kosa v [status], po možnosti ne po [notAfter].
DateTime? lastEventAt(RugItem item, RugStatus status, {DateTime? notAfter}) {
  DateTime? found;
  for (final e in item.history) {
    if (e.status != status) continue;
    if (notAfter != null && e.at.isAfter(notAfter)) continue;
    found = e.at;
  }
  return found;
}

/// Število koledarskih dni med [from] in [to] (ura se ne šteje).
int calendarDaysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

class _Acc {
  int pieces = 0;
  int orders = 0;
  double m2 = 0;
  double value = 0;

  GroupStat toStat(String label) => GroupStat(
    label: label,
    pieces: pieces,
    orders: orders,
    m2: m2,
    value: value,
  );
}

DashboardStats computeStats(
  AppState state, {
  required DateTime now,
  required StatsRange period,
}) {
  final itemsByOrder = <String, List<RugItem>>{};
  for (final i in state.items) {
    (itemsByOrder[i.orderId] ??= []).add(i);
  }

  final month = StatsRange.month(now);
  final today = DateTime(now.year, now.month, now.day);

  var revenue = 0.0, monthRevenue = 0.0, openValue = 0.0;
  var completedOrders = 0, monthOrders = 0, openOrders = 0;

  var shelfOrders = 0, shelfPieces = 0;
  var shelfM2 = 0.0, shelfValue = 0.0;
  final agePieces = [0, 0, 0];
  final ageValue = [0.0, 0.0, 0.0];

  var washing = 0, drying = 0;

  final produced = _Acc();
  final byType = <String, _Acc>{};
  final byRegion = {for (final l in OrderLocation.values) l: _Acc()};
  final byChannel = {for (final c in OrderChannel.values) c: _Acc()};

  var toReadyMicros = 0, toReadyCount = 0;
  var toReturnMicros = 0, toReturnCount = 0;

  for (final o in state.orders) {
    // Arhivirana naročila so izven vsake statistike (§4.15).
    if (o.isArchived || o.status == OrderStatus.cancelled) continue;
    final items = itemsByOrder[o.id] ?? const <RugItem>[];
    final total = billingFor(o, items).total;

    if (o.status == OrderStatus.completed) {
      revenue += total;
      completedOrders++;
      final c = o.completedAt;
      if (c != null && month.contains(c)) {
        monthRevenue += total;
        monthOrders++;
      }
    } else {
      openValue += total;
      openOrders++;
    }

    var onShelf = false;
    DateTime? orderDoneAt; // zadnji prvi "ready" med kosi
    var everyPieceWasReady = items.isNotEmpty;

    for (final i in items) {
      // Zaloga na policah.
      if (i.status == RugStatus.ready) {
        onShelf = true;
        shelfPieces++;
        shelfM2 += i.m2;
        shelfValue += i.price;
        final since =
            lastEventAt(i, RugStatus.ready) ?? o.readyAt ?? i.lastChangeAt;
        if (since != null) {
          final days = calendarDaysBetween(since, today);
          final b = days <= 3 ? 0 : (days <= 7 ? 1 : 2);
          agePieces[b]++;
          ageValue[b] += i.price;
        }
      }

      // Pipeline (kot zavihka Čaka pranje / Sušenje).
      if (OrderPhase.washing.containsItem(i)) washing++;
      if (OrderPhase.drying.containsItem(i)) drying++;

      // Proizvodnja: kos je dokončan ob prvem prehodu v Pripravljeno.
      final readyAt = firstEventAt(i, RugStatus.ready);
      if (readyAt == null) {
        everyPieceWasReady = false;
      } else {
        if (orderDoneAt == null || readyAt.isAfter(orderDoneAt)) {
          orderDoneAt = readyAt;
        }
        if (period.contains(readyAt)) {
          produced
            ..pieces += 1
            ..m2 += i.m2
            ..value += i.price;
          for (final acc in [
            byType.putIfAbsent(i.rugTypeName, _Acc.new),
            byRegion[o.location]!,
            byChannel[o.channel]!,
          ]) {
            acc
              ..pieces += 1
              ..m2 += i.m2
              ..value += i.price;
          }

          final pickedUp = firstEventAt(i, RugStatus.awaitingWash);
          if (pickedUp != null && !readyAt.isBefore(pickedUp)) {
            toReadyMicros += readyAt.difference(pickedUp).inMicroseconds;
            toReadyCount++;
          }
        }
      }

      // Pripravljeno → Vrnjeno za kose, vrnjene v obdobju.
      final returnedAt = firstEventAt(i, RugStatus.returned);
      if (returnedAt != null && period.contains(returnedAt)) {
        final since = lastEventAt(i, RugStatus.ready, notAfter: returnedAt);
        if (since != null) {
          toReturnMicros += returnedAt.difference(since).inMicroseconds;
          toReturnCount++;
        }
      }
    }

    if (onShelf) shelfOrders++;

    if (everyPieceWasReady &&
        orderDoneAt != null &&
        period.contains(orderDoneAt)) {
      for (final acc in [
        produced,
        byRegion[o.location]!,
        byChannel[o.channel]!,
      ]) {
        acc.orders += 1;
      }
    }
  }

  // Vrste preprog: najprej šifrant (v vrstnem redu cenika, tudi če je 0), nato
  // imena, ki jih ni več v šifrantu (preimenovana / izbrisana vrsta).
  final typeLabels = <String>[
    for (final t in state.rugTypes) t.name,
    ...byType.keys.where(
      (n) => n.isNotEmpty && !state.rugTypes.any((t) => t.name == n),
    ),
  ];
  final rugTypeStats = <GroupStat>[
    for (final name in typeLabels) (byType[name] ?? _Acc()).toStat(name),
    if ((byType[''] ?? _Acc()).pieces > 0) byType['']!.toStat('Brez vrste'),
  ];

  const ageLabels = ['0–3 dni', '4–7 dni', '8+ dni'];
  return DashboardStats(
    revenue: revenue,
    completedOrders: completedOrders,
    monthRevenue: monthRevenue,
    monthOrders: monthOrders,
    openValue: openValue,
    openOrders: openOrders,
    shelfOrders: shelfOrders,
    shelfPieces: shelfPieces,
    shelfM2: shelfM2,
    shelfValue: shelfValue,
    shelfAge: [
      for (var b = 0; b < 3; b++)
        AgeBucket(
          label: ageLabels[b],
          pieces: agePieces[b],
          value: ageValue[b],
        ),
    ],
    washingPieces: washing,
    dryingPieces: drying,
    producedPieces: produced.pieces,
    producedOrders: produced.orders,
    producedM2: produced.m2,
    producedValue: produced.value,
    avgToReady: toReadyCount == 0
        ? null
        : Duration(microseconds: toReadyMicros ~/ toReadyCount),
    avgToReadyPieces: toReadyCount,
    avgToReturn: toReturnCount == 0
        ? null
        : Duration(microseconds: toReturnMicros ~/ toReturnCount),
    avgToReturnPieces: toReturnCount,
    byRugType: rugTypeStats,
    byRegion: [
      for (final l in OrderLocation.values) byRegion[l]!.toStat(l.code),
    ],
    byChannel: [
      for (final c in OrderChannel.values)
        // B2B se pokaže samo, če ima podatke: ticket primerja dva kanala.
        if (c != OrderChannel.b2b ||
            byChannel[c]!.pieces > 0 ||
            byChannel[c]!.orders > 0)
          byChannel[c]!.toStat(channelLabel(c)),
    ],
  );
}

/// Kanal v statistiki: lastnik pravi "Naš prevzem" (`OrderChannel.delivery`,
/// na zavihku "Dostava") in "Pripeljano".
String channelLabel(OrderChannel c) => switch (c) {
  OrderChannel.delivery => 'Naš prevzem',
  OrderChannel.dropoff => 'Pripeljano',
  OrderChannel.b2b => 'B2B',
};

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/format.dart';
import '../models/enums.dart';
import '../models/order.dart';
import 'order_phases.dart';
import 'providers.dart';

/// Minimalna obvestila (V10 §5) — samo to, kar pomaga operativi, brez spama:
///
/// * [uncalled]: pripravljena naročila, ki jih po 24 h še nismo poklicali,
/// * [vanLeft]: naročila, ki so po koncu delovnika še v kombiju,
/// * [daySummary]: kratek dnevni povzetek prevzemov in dostav.
///
/// Vsako je ena združena vrstica, nikoli ena na stranko.
enum AlertKind { uncalled, vanLeft, daySummary }

/// Ura, po kateri se šteje, da je delovnik končan — od tu naprej opozori na
/// naročila, ki so še v kombiju.
const workdayEndHour = 17;

/// Po koliko urah od pripravljenosti nepoklicano naročilo postane obvestilo.
const uncalledAfter = Duration(hours: 24);

/// Obvestilo, izpeljano iz stanja naročil.
///
/// Obvestil namenoma ne shranjujemo v bazo: vsa izhajajo iz podatkov, ki jih
/// že imamo, zato jih ni mogoče "izgubiti" niti podvojiti med telefoni.
/// Shranjuje se samo, katera je ta telefon že videl.
class Alert {
  const Alert({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.at,
    required this.phase,
  });

  final String id;
  final AlertKind kind;
  final String title;
  final String body;
  final DateTime at;

  /// Zavihek strani Naročila, ki ga obvestilo odpre; null = ne odpre ničesar.
  final OrderPhase? phase;
}

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "3 pripravljena naročila še niso klicana." — samostalnik in glagol se
/// ujemata po slovenski množini (ednina, dvojina, 3–4, ostalo).
String _uncalledTitle(int n) => switch (Fmt.pluralForm(n)) {
      0 => '$n pripravljeno naročilo še ni klicano.',
      1 => '$n pripravljeni naročili še nista klicani.',
      2 => '$n pripravljena naročila še niso klicana.',
      _ => '$n pripravljenih naročil še ni klicanih.',
    };

/// "2 naročili sta še v kombiju."
String _vanTitle(int n) => switch (Fmt.pluralForm(n)) {
      0 => '$n naročilo je še v kombiju.',
      1 => '$n naročili sta še v kombiju.',
      2 => '$n naročila so še v kombiju.',
      _ => '$n naročil je še v kombiju.',
    };

String _summaryTitle(int pickups, int deliveries) {
  final p = switch (Fmt.pluralForm(pickups)) {
    0 => '$pickups prevzem',
    1 => '$pickups prevzema',
    2 => '$pickups prevzemi',
    _ => '$pickups prevzemov',
  };
  final d = switch (Fmt.pluralForm(deliveries)) {
    0 => '$deliveries dostava',
    1 => '$deliveries dostavi',
    2 => '$deliveries dostave',
    _ => '$deliveries dostav',
  };
  return 'Danes: $p, $d.';
}

/// "LJ-001, LJ-002, MB-004 …" — kratek seznam, da se vidi, za katera naročila
/// gre, brez da bi obvestilo postalo seznam.
String _numbers(List<WorkOrder> orders) {
  final shown = orders.take(4).map((o) => o.number).join(', ');
  return orders.length > 4 ? '$shown …' : shown;
}

List<Alert> buildAlerts(
  List<WorkOrder> orders,
  DateTime now, {
  int workdayEnd = workdayEndHour,
}) {
  final list = <Alert>[];
  final today = DateTime(now.year, now.month, now.day);

  // 1) Pripravljeno za osebni prevzem, 24 h brez klica.
  final uncalled = orders
      .where(
        (o) =>
            o.status == OrderStatus.awaitingCollection &&
            o.calledAt == null &&
            o.readyAt != null &&
            !now.isBefore(o.readyAt!.add(uncalledAfter)),
      )
      .toList()
    ..sort((a, b) => a.readyAt!.compareTo(b.readyAt!));
  if (uncalled.isNotEmpty) {
    list.add(Alert(
      id: 'uncalled:${uncalled.map((o) => o.id).join(',')}',
      kind: AlertKind.uncalled,
      title: _uncalledTitle(uncalled.length),
      body: _numbers(uncalled),
      // Obvestilo je nastalo, ko je zadnje od njih prekoračilo 24 h.
      at: uncalled.last.readyAt!.add(uncalledAfter),
      phase: OrderPhase.ready,
    ));
  }

  // 2) Po koncu delovnika še kaj v kombiju.
  if (now.hour >= workdayEnd) {
    final inVan = sortedForVan(orders.where((o) => o.isInVan));
    if (inVan.isNotEmpty) {
      list.add(Alert(
        id: 'van:${_day(now)}:${inVan.length}',
        kind: AlertKind.vanLeft,
        title: _vanTitle(inVan.length),
        body: _numbers(inVan),
        at: DateTime(now.year, now.month, now.day, workdayEnd),
        phase: OrderPhase.deliveries,
      ));
    }
  }

  // 3) Dnevni povzetek (opcijsko): ena vrstica na dan, število se osvežuje.
  bool notAfterToday(DateTime d) => d.isBefore(today.add(const Duration(days: 1)));
  final pickups = orders
      .where(
        (o) =>
            o.status == OrderStatus.scheduledPickup &&
            o.pickupAt != null &&
            notAfterToday(o.pickupAt!),
      )
      .length;
  final deliveries = orders
      .where(
        (o) =>
            o.status == OrderStatus.awaitingDelivery &&
            (o.inVanAt != null ||
                (o.deliveryAt != null && notAfterToday(o.deliveryAt!))),
      )
      .length;
  if (pickups + deliveries > 0) {
    list.add(Alert(
      id: 'today:${_day(now)}',
      kind: AlertKind.daySummary,
      title: _summaryTitle(pickups, deliveries),
      body: 'Povzetek dneva.',
      at: DateTime(now.year, now.month, now.day, 7),
      phase: pickups >= deliveries ? OrderPhase.intake : OrderPhase.deliveries,
    ));
  }

  list.sort((a, b) => b.at.compareTo(a.at));
  return list;
}

/// Ura, ki se osveži vsako minuto — obvestila so odvisna od časa (24 h, konec
/// delovnika), zato se sama od sebe ne smejo ustaviti, ko se podatki ne
/// spremenijo.
final minuteClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});

final alertsProvider = Provider<List<Alert>>((ref) {
  final state = ref.watch(repositoryProvider);
  final now = ref.watch(minuteClockProvider).valueOrNull ?? DateTime.now();
  return buildAlerts(state.orders, now);
});

/// Katera obvestila je ta telefon že videl. Per-naprava, kot prijava —
/// to, da je Ana obvestilo prebrala, ne sme ugasniti pike Marku.
class SeenAlerts extends StateNotifier<Set<String>> {
  SeenAlerts() : super(const {}) {
    _load();
  }

  static const _key = 'seen_alerts';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = (prefs.getStringList(_key) ?? const []).toSet();
  }

  /// Ob ogledu seznama so videna natanko tista obvestila, ki takrat obstajajo.
  ///
  /// Zato `state = live` in ne unija: stara obvestila, ki jih ni več, s tem
  /// same izpadejo in seznam ne raste v nedogled.
  Future<void> markSeen(Set<String> live) async {
    if (state.length == live.length && state.containsAll(live)) return;
    state = live;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, live.toList());
  }
}

final seenAlertsProvider =
    StateNotifierProvider<SeenAlerts, Set<String>>((ref) => SeenAlerts());

final unreadAlertCountProvider = Provider<int>((ref) {
  final alerts = ref.watch(alertsProvider);
  final seen = ref.watch(seenAlertsProvider);
  return alerts.where((a) => !seen.contains(a.id)).length;
});

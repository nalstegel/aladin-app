import '../models/enums.dart';
import '../models/order.dart';
import '../models/rug_item.dart';
import 'app_state.dart';

/// Štirje zavihki strani Naročila so dejanski koraki proizvodnje (QA v4 §1/§3):
///
/// * **Naročila** in **Pripravljeno** prikazujeta cela naročila,
/// * **Čaka pranje** in **Sušenje** prikazujeta posamezne kose, grupirane po
///   naročilu — pri pranju in sušenju delamo s posameznim tepihom.
///
/// Zaključena naročila tu niso prikazana — najdeš jih v zgodovini stranke.
enum OrderPhase { intake, washing, drying, ready }

extension OrderPhaseX on OrderPhase {
  String get label => switch (this) {
        OrderPhase.intake => 'Naročila',
        OrderPhase.washing => 'Čaka pranje',
        OrderPhase.drying => 'Sušenje',
        OrderPhase.ready => 'Pripravljeno',
      };

  /// Ali zavihek prikazuje posamezne kose (in ne celih naročil).
  bool get showsItems =>
      this == OrderPhase.washing || this == OrderPhase.drying;

  /// Ali je kos v tem koraku. "Mere in cena" nima svojega zavihka in šteje
  /// pod Sušenje (glej `Repository.finishRugFromDrying`).
  bool containsItem(RugItem item) => switch (this) {
        OrderPhase.intake => item.status == RugStatus.awaitingPickup,
        OrderPhase.washing => item.status == RugStatus.awaitingWash,
        OrderPhase.drying => item.status == RugStatus.drying ||
            item.status == RugStatus.finishing,
        OrderPhase.ready => item.status == RugStatus.ready,
      };

  /// Ali se naročilo pokaže v tem zavihku. Naročila in Pripravljeno sta
  /// izključujoča (celo naročilo še ni v procesu / je v celoti pripravljeno),
  /// Čaka pranje in Sušenje pa pokažeta naročilo, če je vsaj en kos tam.
  bool containsOrder(WorkOrder order, List<RugItem> items) {
    if (!order.status.isOpen) return false;
    return switch (this) {
      OrderPhase.intake => order.status == OrderStatus.scheduledPickup,
      OrderPhase.ready => order.status.isHandoverReady,
      _ => items.any(containsItem),
    };
  }
}

/// Zavihki, v katerih se naročilo trenutno nahaja — za prikaz rezultatov
/// iskanja ("v katerem tabu je").
List<OrderPhase> phasesOf(WorkOrder order, List<RugItem> items) => [
      for (final p in OrderPhase.values)
        if (p.containsOrder(order, items)) p,
    ];

/// Kosi enega naročila v zavihku Čaka pranje / Sušenje.
class PhaseGroup {
  const PhaseGroup({
    required this.order,
    required this.items,
    required this.readySiblings,
    required this.arrivedAt,
  });

  final WorkOrder order;

  /// Kosi tega naročila, ki so v tem koraku, po vrsti (KOS 1, 2, …).
  final List<RugItem> items;

  /// Samo v Sušenju: kosi istega naročila, ki so že obračunani, a naročilo
  /// še ni v celoti pripravljeno. Prikazani so sivo, da ne izginejo iz
  /// pregleda, dokler čakajo na ostale kose.
  final List<RugItem> readySiblings;

  /// Kdaj je naročilo prišlo v proces — po tem se skupine razvrščajo.
  final DateTime arrivedAt;
}

/// Skupine kosov za zavihek Čaka pranje ali Sušenje, razvrščene po
/// dejanskem vrstnem redu prihoda: najstarejši prevzeti / pripeljani zgoraj.
List<PhaseGroup> groupsFor(
  AppState state,
  OrderPhase phase, {
  OrderChannel? channel,
}) {
  assert(phase.showsItems);
  final groups = <PhaseGroup>[];
  for (final order in state.orders) {
    if (!order.status.isOpen) continue;
    if (channel != null && order.channel != channel) continue;
    final all = state.itemsOf(order.id);
    final inPhase = all.where(phase.containsItem).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (inPhase.isEmpty) continue;

    final ready = phase == OrderPhase.drying && !order.status.isHandoverReady
        ? (all.where((i) => i.status == RugStatus.ready).toList()
          ..sort((a, b) => a.index.compareTo(b.index)))
        : const <RugItem>[];

    groups.add(PhaseGroup(
      order: order,
      items: inPhase,
      readySiblings: ready,
      arrivedAt: _arrivedAt(order, all),
    ));
  }
  groups.sort((a, b) {
    final c = a.arrivedAt.compareTo(b.arrivedAt);
    return c != 0 ? c : a.order.id.compareTo(b.order.id);
  });
  return groups;
}

/// Najzgodnejši prihod katerega koli kosa naročila; za stare zapise brez
/// zgodovine pa čas ustvarjanja naročila.
DateTime _arrivedAt(WorkOrder order, List<RugItem> items) {
  DateTime? earliest;
  for (final i in items) {
    final at = i.arrivedAt;
    if (at != null && (earliest == null || at.isBefore(earliest))) {
      earliest = at;
    }
  }
  return earliest ?? order.createdAt;
}

/// Iskanje čez stran Naročila (QA v4 §8): po ID-ju naročila ali kosa, imenu
/// stranke, telefonu ali naslovu. Šumnike lahko izpustiš ("klopcavar").
bool matchesSearch(WorkOrder order, List<RugItem> items, String query) {
  final q = foldForSearch(query.trim());
  if (q.isEmpty) return false;

  if (foldForSearch(order.id).contains(q)) return true;
  if (items.any((i) => foldForSearch(i.id).contains(q))) return true;
  if (foldForSearch(order.customerName).contains(q)) return true;
  if (foldForSearch(order.customerAddress).contains(q)) return true;

  // Telefon primerjamo samo po števkah, da "031 353" najde "031353517".
  final digits = q.replaceAll(RegExp(r'\D'), '');
  if (digits.length >= 3 &&
      order.customerPhone.replaceAll(RegExp(r'\D'), '').contains(digits)) {
    return true;
  }
  return false;
}

/// Male črke brez šumnikov.
String foldForSearch(String s) => s
    .toLowerCase()
    .replaceAll('č', 'c')
    .replaceAll('ć', 'c')
    .replaceAll('š', 's')
    .replaceAll('ž', 'z')
    .replaceAll('đ', 'd');

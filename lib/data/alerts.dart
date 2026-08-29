import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/enums.dart';
import '../models/order.dart';
import 'providers.dart';

enum AlertKind { readyForHandover, overdue }

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
    required this.orderId,
  });

  final String id;
  final AlertKind kind;
  final String title;
  final String body;
  final DateTime at;
  final String orderId;
}

List<Alert> buildAlerts(List<WorkOrder> orders, DateTime now) {
  final list = <Alert>[];

  for (final o in orders) {
    if (o.status.isHandoverReady) {
      list.add(Alert(
        id: 'ready:${o.id}',
        kind: AlertKind.readyForHandover,
        title: '${o.number} je pripravljeno',
        body: o.status == OrderStatus.awaitingCollection
            ? '${o.customerName} — čaka na prevzem v obratu.'
            : '${o.customerName} — čaka na vračilo.',
        at: o.readyAt ?? o.createdAt,
        orderId: o.id,
      ));
    }
    if (o.isOverdue(now)) {
      list.add(Alert(
        id: 'overdue:${o.id}',
        kind: AlertKind.overdue,
        title: '${o.number} zamuja',
        body: '${o.customerName} — rok je potekel.',
        at: o.dueAt ?? o.createdAt,
        orderId: o.id,
      ));
    }
  }

  list.sort((a, b) => b.at.compareTo(a.at));
  return list;
}

final alertsProvider = Provider<List<Alert>>((ref) {
  final state = ref.watch(repositoryProvider);
  return buildAlerts(state.orders, DateTime.now());
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

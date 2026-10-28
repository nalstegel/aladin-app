import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'order_phases.dart';

/// Izbrani zavihek v spodnji vrstici.
final shellTabProvider = StateProvider<int>((ref) => 0);

const shellTabDashboard = 0;
const shellTabOrders = 1;
const shellTabScanner = 2;
const shellTabCustomers = 3;
const shellTabMore = 4;

/// Zahteva za preklop na določen zavihek strani Naročila (npr. iz bloka
/// Delavnica na Danes). `nonce` poskrbi, da je vsaka zahteva nova vrednost,
/// zato poslušalec sproži tudi, če je isti zavihek zahtevan dvakrat.
final ordersPhaseRequestProvider =
    StateProvider<({OrderPhase phase, int nonce})?>((ref) => null);

/// Odpre stran Naročila na izbranem zavihku.
void openOrdersPhase(WidgetRef ref, OrderPhase phase) {
  ref.read(ordersPhaseRequestProvider.notifier).state = (
    phase: phase,
    nonce: DateTime.now().microsecondsSinceEpoch,
  );
  ref.read(shellTabProvider.notifier).state = shellTabOrders;
}

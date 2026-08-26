import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/enums.dart';
import '../models/order.dart';
import '../models/rug_item.dart';
import 'app_state.dart';
import 'repository.dart';
import 'store.dart';

final storeProvider = Provider<DataStore>((ref) => FirestoreStore());

final repositoryProvider =
    StateNotifierProvider<Repository, AppState>((ref) {
  return Repository(ref.watch(storeProvider));
});

/// Naloži shranjene podatke, preden pokažemo aplikacijo.
final bootstrapProvider = FutureProvider<void>((ref) async {
  await ref.read(repositoryProvider.notifier).init();
});

final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(repositoryProvider).currentUser,
);

/// Odprta naročila enega kanala, urejena po nujnosti.
final ordersByChannelProvider =
    Provider.family<List<WorkOrder>, OrderChannel>((ref, channel) {
  final state = ref.watch(repositoryProvider);
  final list = state.orders
      .where((o) => o.channel == channel && o.status.isOpen)
      .toList();
  list.sort(_byUrgency);
  return list;
});

final completedOrdersProvider =
    Provider.family<List<WorkOrder>, OrderChannel>((ref, channel) {
  final state = ref.watch(repositoryProvider);
  final list = state.orders
      .where((o) => o.channel == channel && !o.status.isOpen)
      .toList();
  list.sort((a, b) =>
      (b.completedAt ?? b.createdAt).compareTo(a.completedAt ?? a.createdAt));
  return list;
});

int _byUrgency(WorkOrder a, WorkOrder b) {
  final ad = a.dueAt ?? a.deliveryAt ?? a.pickupAt;
  final bd = b.dueAt ?? b.deliveryAt ?? b.pickupAt;
  if (ad == null && bd == null) return b.createdAt.compareTo(a.createdAt);
  if (ad == null) return 1;
  if (bd == null) return -1;
  return ad.compareTo(bd);
}

/// Kaj je danes za pobrati (dostava) — nadomešča list na mizi.
final todayPickupsProvider = Provider<List<WorkOrder>>((ref) {
  final state = ref.watch(repositoryProvider);
  final list = state.orders
      .where((o) =>
          o.status == OrderStatus.scheduledPickup &&
          o.pickupAt != null &&
          !_isAfterToday(o.pickupAt!))
      .toList();
  list.sort((a, b) => a.pickupAt!.compareTo(b.pickupAt!));
  return list;
});

/// Kaj je danes za vrniti.
final todayDeliveriesProvider = Provider<List<WorkOrder>>((ref) {
  final state = ref.watch(repositoryProvider);
  final list = state.orders
      .where((o) =>
          o.status == OrderStatus.awaitingDelivery &&
          (o.deliveryAt == null || !_isAfterToday(o.deliveryAt!)))
      .toList();
  list.sort((a, b) => (a.deliveryAt ?? a.createdAt)
      .compareTo(b.deliveryAt ?? b.createdAt));
  return list;
});

final awaitingCollectionProvider = Provider<List<WorkOrder>>((ref) {
  final state = ref.watch(repositoryProvider);
  final list = state.orders
      .where((o) => o.status == OrderStatus.awaitingCollection)
      .toList();
  list.sort((a, b) =>
      (a.readyAt ?? a.createdAt).compareTo(b.readyAt ?? b.createdAt));
  return list;
});

/// Števci po statusih za nadzorno ploščo.
final productionCountsProvider = Provider<Map<RugStatus, int>>((ref) {
  final state = ref.watch(repositoryProvider);
  final counts = <RugStatus, int>{for (final s in RugStatus.values) s: 0};
  for (final i in state.items) {
    final order = state.order(i.orderId);
    if (order == null || !order.status.isOpen) continue;
    counts[i.status] = (counts[i.status] ?? 0) + 1;
  }
  return counts;
});

final overdueOrdersProvider = Provider<List<WorkOrder>>((ref) {
  final state = ref.watch(repositoryProvider);
  final now = DateTime.now();
  final list = state.orders.where((o) => o.isOverdue(now)).toList();
  list.sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
  return list;
});

final itemProvider = Provider.family<RugItem?, String>(
  (ref, id) => ref.watch(repositoryProvider).item(id),
);

final orderProvider = Provider.family<WorkOrder?, String>(
  (ref, id) => ref.watch(repositoryProvider).order(id),
);

final orderItemsProvider = Provider.family<List<RugItem>, String>(
  (ref, id) => ref.watch(repositoryProvider).itemsOf(id),
);

bool _isAfterToday(DateTime d) {
  final now = DateTime.now();
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
  return d.isAfter(endOfToday);
}

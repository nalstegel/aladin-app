import 'package:aladin/data/repository.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// Urejanje naročila (`Repository.updateOrder`) sme spremeniti samo
/// podatke naročila — nikoli statusa, ki ostaja izpeljan iz kosov.
void main() {
  late Repository repo;

  setUp(() async {
    repo = Repository(InMemoryStore());
    await repo.init();
    repo.setCurrentUser('u-marko');
  });

  test('urejanje naročila spremeni stranko, kanal in termine, ne pa statusa',
      () {
    final customerA = repo.state.customers.first;
    final customerB = repo.createCustomer(
      type: CustomerType.private,
      name: 'Ana Kranjc',
      phone: '031 111 222',
    );

    final order = repo.createOrder(
      customer: customerA,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      itemCount: 2,
    );
    final statusBefore = repo.state.order(order.id)!.status;

    final deliveryAt = DateTime.now().add(const Duration(days: 2));
    final updated = order.copyWith(
      channel: OrderChannel.delivery,
      handover: HandoverMode.weDeliver,
      customerId: customerB.id,
      customerName: customerB.name,
      customerPhone: customerB.phone,
      deliveryAt: deliveryAt,
      notes: 'Pozvoni dvakrat',
    );
    repo.updateOrder(updated);

    final saved = repo.state.order(order.id)!;
    expect(saved.customerId, customerB.id);
    expect(saved.customerName, 'Ana Kranjc');
    expect(saved.channel, OrderChannel.delivery);
    expect(saved.handover, HandoverMode.weDeliver);
    expect(saved.deliveryAt, deliveryAt);
    expect(saved.notes, 'Pozvoni dvakrat');
    // Status ostaja izpeljan iz kosov, urejanje ga ne sme spremeniti.
    expect(saved.status, statusBefore);
    // Kosi in njihova zgodovina ostanejo nedotaknjeni.
    expect(repo.state.itemsOf(order.id).length, 2);
  });

  test('copyWith z clear zastavicami dejansko počisti termine na null', () {
    final customer = repo.state.customers.first;
    final order = repo.createOrder(
      customer: customer,
      location: OrderLocation.maribor,
      channel: OrderChannel.delivery,
      handover: HandoverMode.weDeliver,
      itemCount: 1,
      pickupAt: DateTime.now().add(const Duration(days: 1)),
      pickupWindowEnd: DateTime.now().add(const Duration(days: 1, hours: 2)),
      deliveryAt: DateTime.now().add(const Duration(days: 3)),
      dueAt: DateTime.now().add(const Duration(days: 5)),
    );

    final cleared = order.copyWith(
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      clearPickupAt: true,
      clearPickupWindowEnd: true,
      clearDeliveryAt: true,
      clearDueAt: true,
    );

    expect(cleared.pickupAt, isNull);
    expect(cleared.pickupWindowEnd, isNull);
    expect(cleared.deliveryAt, isNull);
    expect(cleared.dueAt, isNull);
  });
}

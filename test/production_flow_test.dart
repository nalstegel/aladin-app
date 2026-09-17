import 'package:aladin/data/repository.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/catalog.dart';
import 'package:aladin/models/enums.dart';
import 'package:aladin/models/return_proof.dart';
import 'package:flutter_test/flutter_test.dart';

/// Testi pokrivajo glavno logiko: naročilo je pripravljeno šele, ko so
/// pripravljeni vsi njegovi kosi.
void main() {
  late Repository repo;

  setUp(() async {
    repo = Repository(InMemoryStore());
    await repo.init();
    repo.setCurrentUser('u-marko');
  });

  test('naročilo se zaključi šele, ko je zadnji kos READY', () {
    final customer = repo.state.customers.first;
    final order = repo.createOrder(
      customer: customer,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      itemCount: 3,
    );

    expect(repo.state.itemsOf(order.id).length, 3);
    expect(repo.state.item('${order.id}-1')!.status, RugStatus.awaitingWash);
    expect(repo.state.order(order.id)!.status, OrderStatus.inProduction);

    final type = repo.state.rugTypes.firstWhere((t) => t.name == 'Volna');

    for (var n = 1; n <= 3; n++) {
      final id = '${order.id}-$n';
      repo.advance(id);
      expect(repo.state.item(id)!.status, RugStatus.drying);

      repo.setMeasurements(id, widthCm: 200, lengthCm: 300, rugType: type);
      final measured = repo.state.item(id)!;
      expect(measured.status, RugStatus.finishing);
      expect(measured.m2, closeTo(6, 0.001));
      expect(measured.basePrice, closeTo(90, 0.001));

      repo.finishItem(id, extras: const [], discountPercent: 0);
      expect(repo.state.item(id)!.status, RugStatus.ready);

      // Dokler manjka en kos, naročilo ostane v obdelavi.
      if (n < 3) {
        expect(repo.state.order(order.id)!.status, OrderStatus.inProduction);
        expect(repo.state.readyCount(order.id), n);
      }
    }

    // Osebni prevzem → naročilo čaka, da stranka pride.
    expect(repo.state.order(order.id)!.status, OrderStatus.awaitingCollection);
    expect(repo.state.orderTotal(order.id), closeTo(270, 0.01));
  });

  test('dostava se po zadnjem kosu prestavi v čakanje na vračilo', () {
    final customer = repo.state.customers.first;
    final order = repo.createOrder(
      customer: customer,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.delivery,
      handover: HandoverMode.weDeliver,
      itemCount: 1,
      pickupAt: DateTime.now().add(const Duration(days: 1)),
    );

    expect(repo.state.order(order.id)!.status, OrderStatus.scheduledPickup);
    expect(repo.state.item('${order.id}-1')!.status, RugStatus.awaitingPickup);

    repo.markOrderPickedUp(order.id);
    expect(repo.state.item('${order.id}-1')!.status, RugStatus.awaitingWash);

    final id = '${order.id}-1';
    final type = repo.state.rugTypes.first;
    repo.advance(id);
    repo.setMeasurements(id, widthCm: 100, lengthCm: 100, rugType: type);
    repo.finishItem(id, extras: const [], discountPercent: 0);

    expect(repo.state.order(order.id)!.status, OrderStatus.awaitingDelivery);
  });

  test('minimalni obračun dvigne ceno majhne preproge', () {
    final order = repo.createOrder(
      customer: repo.state.customers.first,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      itemCount: 1,
    );
    final id = '${order.id}-1';
    // Navadna: 12 €/m², minimalni obračun 3 m².
    final type = repo.state.rugTypes.firstWhere((t) => t.name == 'Navadna');

    repo.advance(id);
    repo.setMeasurements(id, widthCm: 100, lengthCm: 100, rugType: type);

    final item = repo.state.item(id)!;
    expect(item.m2, closeTo(1, 0.001));
    expect(item.usesMinCharge, isTrue);
    expect(item.basePrice, closeTo(36, 0.001));
  });

  test('doplačila in popust se pravilno seštejejo', () {
    final order = repo.createOrder(
      customer: repo.state.customers.first,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      itemCount: 1,
    );
    final id = '${order.id}-1';
    final type = repo.state.rugTypes.firstWhere((t) => t.name == 'Volna');
    repo.advance(id);
    repo.setMeasurements(id, widthCm: 200, lengthCm: 300, rugType: type);

    // Osnova 6 m² × 15 € = 90 €, +20 % madeži = 108 €, −10 % popust = 97,20 €.
    repo.finishItem(
      id,
      extras: const [
        AppliedExtra(
          name: 'Odstranjevanje madežev',
          kind: ExtraKind.percent,
          value: 20,
        ),
      ],
      discountPercent: 10,
    );

    expect(repo.state.item(id)!.price, closeTo(97.20, 0.01));
  });

  test('vračilo shrani dokazilo in zaključi naročilo', () {
    final order = repo.createOrder(
      customer: repo.state.customers.first,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      itemCount: 2,
    );
    final type = repo.state.rugTypes.first;
    for (var n = 1; n <= 2; n++) {
      final id = '${order.id}-$n';
      repo.advance(id);
      repo.setMeasurements(id, widthCm: 200, lengthCm: 300, rugType: type);
      repo.finishItem(id, extras: const [], discountPercent: 0);
    }

    repo.completeReturn(
      order.id,
      ReturnProof(
        returnedAt: DateTime.now(),
        userId: 'u-marko',
        userName: 'Marko',
        scannedItemIds: ['${order.id}-1', '${order.id}-2'],
        signatureBase64: 'ZmFrZQ==',
        receivedByName: 'Janez Novak',
      ),
    );

    final done = repo.state.order(order.id)!;
    expect(done.status, OrderStatus.completed);
    expect(done.returnProof!.scannedItemIds.length, 2);
    expect(done.returnProof!.hasSignature, isTrue);
    expect(
      repo.state.itemsOf(order.id).every((i) => i.status == RugStatus.returned),
      isTrue,
    );
  });

  test('hitri obračun premakne kos naravnost iz sušenja v pripravljeno', () {
    final order = repo.createOrder(
      customer: repo.state.customers.first,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      itemCount: 1,
    );
    final id = '${order.id}-1';
    final type = repo.state.rugTypes.firstWhere((t) => t.name == 'Volna');
    repo.advance(id);
    expect(repo.state.item(id)!.status, RugStatus.drying);

    // Osnova 6 m² × 15 € = 90 €, +20 % madeži = 108 €, −10 % popust = 97,20 €.
    repo.finishRugFromDrying(
      id,
      widthCm: 200,
      lengthCm: 300,
      rugType: type,
      extras: const [
        AppliedExtra(
          name: 'Odstranjevanje madežev',
          kind: ExtraKind.percent,
          value: 20,
        ),
      ],
      discountPercent: 10,
    );

    final item = repo.state.item(id)!;
    // Nikoli ne postane "finishing" — v3 spec §5 to namenoma ni več ločen
    // status, skozi katerega bi se kos ustavil.
    expect(item.status, RugStatus.ready);
    expect(item.rugTypeName, 'Volna');
    expect(item.price, closeTo(97.20, 0.01));
    expect(repo.state.order(order.id)!.status, OrderStatus.awaitingCollection);
  });

  test('ponovno pranje razveljavi potrjeno ceno', () {
    final order = repo.createOrder(
      customer: repo.state.customers.first,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      itemCount: 1,
    );
    final id = '${order.id}-1';
    final type = repo.state.rugTypes.first;
    repo.advance(id);
    repo.setMeasurements(id, widthCm: 200, lengthCm: 300, rugType: type);
    repo.finishItem(id, extras: const [], discountPercent: 0);
    expect(repo.state.order(order.id)!.status, OrderStatus.awaitingCollection);

    repo.sendBackToWash(id, 'madež ni šel ven');

    expect(repo.state.item(id)!.status, RugStatus.awaitingWash);
    expect(repo.state.item(id)!.confirmedPrice, isNull);
    expect(repo.state.order(order.id)!.status, OrderStatus.inProduction);
  });
}

import 'package:aladin/data/billing.dart';
import 'package:aladin/data/order_phases.dart';
import 'package:aladin/data/repository.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/catalog.dart';
import 'package:aladin/models/customer.dart';
import 'package:aladin/models/enums.dart';
import 'package:aladin/models/order.dart';
import 'package:aladin/models/return_proof.dart';
import 'package:flutter_test/flutter_test.dart';

/// Clean UX V8: prevzem z doplačili, V kombi → Dostave, Klicano, minimum 50 €.
void main() {
  late Repository repo;
  late Customer customer;
  late RugType type; // Navadna / sintetika: 12 €/m², minimum 3 m² → 36 €

  setUp(() async {
    repo = Repository(InMemoryStore());
    await repo.init();
    repo.setCurrentUser('u-marko');
    customer = repo.state.customers.first;
    type = repo.state.rugTypes.firstWhere((t) => t.name == 'Navadna / sintetika');
  });

  WorkOrder create({
    OrderLocation location = OrderLocation.ljubljana,
    OrderChannel channel = OrderChannel.dropoff,
    int items = 1,
    double deliveryFee = 0,
  }) {
    return repo.createOrder(
      customer: customer,
      location: location,
      channel: channel,
      handover: channel == OrderChannel.dropoff
          ? HandoverMode.customerCollects
          : HandoverMode.weDeliver,
      itemCount: items,
      deliveryFee: deliveryFee,
    );
  }

  /// Pripelje vse kose do Pripravljeno (Hitri obračun, 36 € na kos).
  void finishAll(WorkOrder order) {
    for (final item in repo.state.itemsOf(order.id)) {
      if (item.status == RugStatus.awaitingPickup) {
        repo.markOrderPickedUp(order.id);
      }
      repo.advance(item.id);
      repo.finishRugFromDrying(
        item.id,
        widthCm: 100,
        lengthCm: 200,
        rugType: type,
        extras: const [],
        discountPercent: 0,
      );
    }
  }

  test('Dolenjska ima svojo predpono DOL in neodvisno štetje', () {
    final a = create(location: OrderLocation.dolenjska);
    final b = create(location: OrderLocation.dolenjska);
    final lj = create();

    expect(a.id, 'DOL-001');
    expect(b.id, 'DOL-002');
    expect(a.id.startsWith(OrderLocation.dolenjska.code), isTrue);
    expect(lj.id.startsWith('LJ-'), isTrue);
    expect(repo.state.nextOrderSeqDolenjska, 3);
  });

  group('prevzem z doplačili', () {
    test('Potrdi zapiše Vnos/Iznos na naročilo in Urin/Dlake na kos', () {
      final order = create(items: 2);
      final vnos = fallbackOrderExtras.first;
      final urin = fallbackItemExtras.first;
      final dlake = fallbackItemExtras.last;

      repo.confirmPickup(
        order.id,
        orderExtras: [AppliedExtra.fromTemplate(vnos)],
        itemExtras: {
          '${order.id}-1': [
            AppliedExtra.fromTemplate(urin),
            AppliedExtra.fromTemplate(dlake, value: 10),
          ],
        },
      );

      final saved = repo.state.order(order.id)!;
      expect(saved.orderExtras.map((e) => e.name), ['Vnos']);
      final first = repo.state.item('${order.id}-1')!;
      expect(first.status, RugStatus.awaitingWash);
      expect(first.extras.map((e) => e.name), ['Urin', 'Dlake']);
      expect(first.extras.last.value, 10);
      // Kos brez označenih doplačil ostane čist, a je prav tako prevzet.
      final second = repo.state.item('${order.id}-2')!;
      expect(second.status, RugStatus.awaitingWash);
      expect(second.extras, isEmpty);
    });

    test('doplačila prevzema preživijo serializacijo naročila', () {
      final order = create();
      repo.confirmPickup(
        order.id,
        orderExtras: [AppliedExtra.fromTemplate(fallbackOrderExtras.last)],
      );
      final json = repo.state.order(order.id)!.toJson();
      final back = WorkOrder.fromJson(json);
      expect(back.orderExtras.single.name, 'Iznos');
      expect(back.deliveryFee, 0);
      expect(back.inVanAt, isNull);
    });
  });

  group('obračun naročila', () {
    test('minimum 50 € velja pri našem prevzemu, ko so vsi kosi obračunani', () {
      final order = create(channel: OrderChannel.delivery, items: 2);
      repo.markOrderPickedUp(order.id);
      final first = repo.state.itemsOf(order.id).first;
      repo.advance(first.id);
      repo.finishRugFromDrying(
        first.id,
        widthCm: 100,
        lengthCm: 200,
        rugType: type,
        extras: const [],
        discountPercent: 0,
      );

      // Še ne vsi kosi: minimum se ne uveljavi.
      final partial = repo.state.billing(order.id)!;
      expect(partial.allPriced, isFalse);
      expect(partial.minimumTopUp, 0);

      // Dva kosa po 36 € = 72 € → nad minimumom, brez doplačila.
      final second = repo.state.itemsOf(order.id).last;
      repo.advance(second.id);
      repo.finishRugFromDrying(
        second.id,
        widthCm: 100,
        lengthCm: 200,
        rugType: type,
        extras: const [],
        discountPercent: 0,
      );
      expect(repo.state.billing(order.id)!.minimumTopUp, 0);
      expect(repo.state.orderTotal(order.id), closeTo(72, 0.001));
    });

    test('en kos za 36 € → skupaj 50 €, razlika je ločena vrstica', () {
      final order = create(channel: OrderChannel.delivery);
      finishAll(order);

      final b = repo.state.billing(order.id)!;
      expect(b.itemsTotal, closeTo(36, 0.001));
      expect(b.minimumTopUp, closeTo(14, 0.001));
      expect(b.total, closeTo(50, 0.001));
      // Cena kosa ostane njegova — minimum je na ravni naročila.
      expect(repo.state.itemsOf(order.id).single.price, closeTo(36, 0.001));
    });

    test('dostavno doplačilo in Vnos se prištejejo in štejejo v minimum', () {
      final order = create(channel: OrderChannel.delivery, deliveryFee: 15);
      repo.confirmPickup(
        order.id,
        orderExtras: [AppliedExtra.fromTemplate(fallbackOrderExtras.first)],
      );
      for (final item in repo.state.itemsOf(order.id)) {
        repo.advance(item.id);
        repo.finishRugFromDrying(
          item.id,
          widthCm: 100,
          lengthCm: 200,
          rugType: type,
          extras: const [],
          discountPercent: 0,
        );
      }
      // 36 + 5 (Vnos) + 15 (dostava) = 56 → nad minimumom.
      final b = repo.state.billing(order.id)!;
      expect(b.subtotal, closeTo(56, 0.001));
      expect(b.minimumTopUp, 0);
      expect(b.total, closeTo(56, 0.001));
    });

    test('Pripeljano nima minimuma 50 €', () {
      final order = create(channel: OrderChannel.dropoff);
      finishAll(order);
      final b = repo.state.billing(order.id)!;
      expect(b.minimumTopUp, 0);
      expect(b.total, closeTo(36, 0.001));
    });

    test('predogled obračunanega kosa upošteva ročno ceno', () {
      final order = create(channel: OrderChannel.delivery);
      repo.markOrderPickedUp(order.id);
      final item = repo.state.itemsOf(order.id).single;
      final b = billingFor(
        repo.state.order(order.id)!,
        repo.state.itemsOf(order.id),
        priceOverrides: {item.id: 80},
      );
      expect(b.allPriced, isTrue);
      expect(b.itemsTotal, 80);
      expect(b.minimumTopUp, 0);
    });
  });

  group('V kombi → Dostave', () {
    test('naročilo za dostavo gre iz Pripravljeno v Dostave in nazaj', () {
      final order = create(channel: OrderChannel.delivery);
      finishAll(order);

      List<OrderPhase> phases() => phasesOf(
        repo.state.order(order.id)!,
        repo.state.itemsOf(order.id),
      );
      expect(phases(), [OrderPhase.ready]);

      repo.sendToVan(order.id);
      expect(repo.state.order(order.id)!.isInVan, isTrue);
      expect(phases(), [OrderPhase.deliveries]);

      repo.removeFromVan(order.id);
      expect(phases(), [OrderPhase.ready]);
      expect(repo.state.order(order.id)!.inVanAt, isNull);
    });

    test('V kombi ne deluje, dokler naročilo ni pripravljeno', () {
      final order = create(channel: OrderChannel.delivery);
      repo.markOrderPickedUp(order.id);
      repo.sendToVan(order.id);
      expect(repo.state.order(order.id)!.inVanAt, isNull);
    });

    test('kos nazaj v pranje naročilo vzame iz kombija', () {
      final order = create(channel: OrderChannel.delivery, items: 2);
      finishAll(order);
      repo.sendToVan(order.id);

      repo.sendBackToWash('${order.id}-1', 'madež');
      final o = repo.state.order(order.id)!;
      expect(o.status, OrderStatus.inProduction);
      expect(o.inVanAt, isNull);
      expect(
        phasesOf(o, repo.state.itemsOf(order.id)),
        isNot(contains(OrderPhase.deliveries)),
      );
    });

    test('po vračilu naročilo zapusti Dostave', () {
      final order = create(channel: OrderChannel.delivery);
      finishAll(order);
      repo.sendToVan(order.id);

      repo.completeReturn(
        order.id,
        ReturnProof(
          returnedAt: DateTime.now(),
          userId: 'u-marko',
          userName: 'Marko',
          scannedItemIds: ['${order.id}-1'],
          receivedByName: 'Stranka',
          signatureBase64: 'AAAA',
        ),
      );
      final o = repo.state.order(order.id)!;
      expect(o.status, OrderStatus.completed);
      expect(OrderPhase.deliveries.containsOrder(o, const []), isFalse);
    });

    test('števci zavihkov: kosi pri pranju/sušenju, naročila drugje', () {
      final base = phaseCounts(repo.state);
      final order = create(channel: OrderChannel.delivery, items: 3);
      repo.markOrderPickedUp(order.id);
      expect(
        phaseCounts(repo.state)[OrderPhase.washing],
        base[OrderPhase.washing]! + 3,
      );

      for (final item in repo.state.itemsOf(order.id)) {
        repo.advance(item.id);
        repo.finishRugFromDrying(
          item.id,
          widthCm: 100,
          lengthCm: 200,
          rugType: type,
          extras: const [],
          discountPercent: 0,
        );
      }
      var counts = phaseCounts(repo.state);
      expect(counts[OrderPhase.ready], base[OrderPhase.ready]! + 1);

      repo.sendToVan(order.id);
      counts = phaseCounts(repo.state);
      expect(counts[OrderPhase.ready], base[OrderPhase.ready]);
      expect(counts[OrderPhase.deliveries], base[OrderPhase.deliveries]! + 1);
    });
  });

  group('skeniranje', () {
    test('prevzem ni samodejen korak — skeniranje ga ne preskoči', () {
      final order = create();
      final item = repo.state.itemsOf(order.id).single;
      expect(repo.nextStatusFor(item), isNull);
      expect(repo.advance(item.id), isFalse);
      expect(repo.state.item(item.id)!.status, RugStatus.awaitingPickup);
    });

    test('skeniranje pranja → sušenje, Undo vrne kos in počisti zgodovino', () {
      final order = create();
      repo.markOrderPickedUp(order.id);
      final id = repo.state.itemsOf(order.id).single.id;
      final before = repo.state.item(id)!.history.length;

      expect(repo.advance(id), isTrue);
      expect(repo.state.item(id)!.status, RugStatus.drying);

      expect(repo.undoAdvance(id), isTrue);
      final back = repo.state.item(id)!;
      expect(back.status, RugStatus.awaitingWash);
      expect(back.history.length, before);
    });

    test('Undo ne naredi nič, če ni kaj razveljaviti', () {
      final order = create();
      final id = repo.state.itemsOf(order.id).single.id;
      expect(repo.undoAdvance(id), isFalse);
    });
  });

  group('Klicano', () {
    test('prvi klic se zabeleži, ponovni ga ne prepiše', () async {
      final order = create(channel: OrderChannel.dropoff);
      finishAll(order);
      expect(repo.state.order(order.id)!.calledAt, isNull);

      repo.markCalled(order.id);
      final first = repo.state.order(order.id)!.calledAt;
      expect(first, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      repo.markCalled(order.id);
      expect(repo.state.order(order.id)!.calledAt, first);
    });

    test('če se kos vrne v pranje, mora biti stranka poklicana znova', () {
      final order = create(channel: OrderChannel.dropoff, items: 2);
      finishAll(order);
      repo.markCalled(order.id);

      repo.sendBackToWash('${order.id}-2', '');
      expect(repo.state.order(order.id)!.calledAt, isNull);
    });

    test('rok vračila je privzeto 10 dni po pripravljenosti', () {
      final order = create();
      finishAll(order);
      final o = repo.state.order(order.id)!;
      expect(
        o.returnReminderAt!.difference(o.readyAt!).inDays,
        returnReminderDays,
      );
      expect(returnReminderDays, 10);
    });
  });
}

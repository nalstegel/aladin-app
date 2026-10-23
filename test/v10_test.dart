import 'package:aladin/core/format.dart';
import 'package:aladin/data/alerts.dart';
import 'package:aladin/data/billing.dart';
import 'package:aladin/data/order_phases.dart';
import 'package:aladin/data/repository.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/catalog.dart';
import 'package:aladin/models/customer.dart';
import 'package:aladin/models/enums.dart';
import 'package:aladin/models/order.dart';
import 'package:flutter_test/flutter_test.dart';

/// Post-live QA V10: Klicano iz vseh vstopnih točk, direktno urejanje po
/// obračunu, ročni vrstni red v Dostavah, vrstni red v Hitrem obračunu,
/// minimalna obvestila.
void main() {
  late Repository repo;
  late Customer customer;
  late RugType type; // Sintetika / tanki tepihi: 12 €/m², minimum 3 m² → 36 €

  setUp(() async {
    repo = Repository(InMemoryStore());
    await repo.init();
    repo.setCurrentUser('u-marko');
    customer = repo.state.customers.first;
    type = repo.state.rugTypes.firstWhere(
      (t) => t.name == 'Sintetika / tanki tepihi',
    );
  });

  WorkOrder create({
    OrderLocation location = OrderLocation.ljubljana,
    OrderChannel channel = OrderChannel.dropoff,
    int items = 1,
  }) {
    return repo.createOrder(
      customer: customer,
      location: location,
      channel: channel,
      handover: channel == OrderChannel.dropoff
          ? HandoverMode.customerCollects
          : HandoverMode.weDeliver,
      itemCount: items,
    );
  }

  /// Pripelje vse kose do Pripravljeno (Hitri obračun, 2 m² → 36 € na kos).
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

  WorkOrder inVan({OrderLocation location = OrderLocation.ljubljana}) {
    final o = create(location: location, channel: OrderChannel.delivery);
    finishAll(o);
    repo.sendToVan(o.id);
    return repo.state.order(o.id)!;
  }

  List<String> vanIds() => sortedForVan(
    repo.state.orders.where((o) => o.isInVan),
  ).map((o) => o.id).toList();

  group('Klicano', () {
    test('klic se zabeleži samo pri naročilu, ki čaka stranko', () {
      final order = create();
      // V proizvodnji klic ni pomemben: ne sme se prilepiti na naročilo.
      repo.markOrderPickedUp(order.id);
      repo.markCalled(order.id);
      expect(repo.state.order(order.id)!.calledAt, isNull);

      finishAll(order);
      repo.markCalled(order.id);
      expect(repo.state.order(order.id)!.calledAt, isNotNull);
    });

    test('naročilo za dostavo ne dobi Klicano', () {
      final order = create(channel: OrderChannel.delivery);
      finishAll(order);
      repo.markCalled(order.id);
      expect(repo.state.order(order.id)!.calledAt, isNull);
    });
  });

  group('direktno urejanje po obračunu', () {
    test('vrsta, mere in cena se spremenijo brez spremembe statusa', () {
      final order = create();
      finishAll(order);
      final id = repo.state.itemsOf(order.id).single.id;
      final shaggy = repo.state.rugTypes.firstWhere(
        (t) => t.name.startsWith('Shaggy'),
      ); // 16 €/m², minimum 3 m²

      repo.editItemPricing(
        id,
        widthCm: 200,
        lengthCm: 300,
        rugType: shaggy,
        price: 99,
      );

      final item = repo.state.item(id)!;
      expect(item.status, RugStatus.ready);
      expect(item.rugTypeName, shaggy.name);
      expect(item.widthCm, 200);
      expect(item.lengthCm, 300);
      expect(item.m2, 6);
      expect(item.basePrice, 96);
      expect(item.price, 99);
      expect(item.history.last.note, contains('popravljene'));
      // Naročilo je še vedno pripravljeno in njegov obračun se je osvežil.
      expect(repo.state.order(order.id)!.status, OrderStatus.awaitingCollection);
      expect(
        billingFor(repo.state.order(order.id)!, repo.state.itemsOf(order.id))
            .itemsTotal,
        99,
      );
    });

    test('ročni vnos površine ostane ročni', () {
      final order = create();
      finishAll(order);
      final id = repo.state.itemsOf(order.id).single.id;

      repo.editItemPricing(id, manualM2: 4.5, rugType: type, price: 54);
      expect(repo.state.item(id)!.m2, 4.5);
      expect(repo.state.item(id)!.manualM2, 4.5);

      repo.editItemPricing(
        id,
        widthCm: 100,
        lengthCm: 100,
        rugType: type,
        price: 36,
      );
      expect(repo.state.item(id)!.manualM2, isNull);
      expect(repo.state.item(id)!.m2, 1);
    });

    test('popravek stranke na naročilu se prenese na vsa njena naročila', () {
      final a = create();
      final b = create();
      repo.updateCustomer(
        customer.copyWith(name: 'Nova Ime', phone: '041 999 888'),
      );
      for (final o in [a, b]) {
        final saved = repo.state.order(o.id)!;
        expect(saved.customerName, 'Nova Ime');
        expect(saved.customerPhone, '041 999 888');
        expect(saved.customerId, customer.id);
      }
    });
  });

  group('Dostave: ročni vrstni red', () {
    test('novo naročilo v kombiju je vedno na koncu', () {
      final a = inVan();
      final b = inVan();
      final c = inVan();
      expect(vanIds(), [a.id, b.id, c.id]);
      expect(
        [a, b, c].map((o) => repo.state.order(o.id)!.vanOrder).toList(),
        [0, 1, 2],
      );
    });

    test('reorderVan zamenja vrstni red in ga shrani', () {
      final a = inVan();
      final b = inVan();
      final c = inVan();

      repo.reorderVan([c.id, a.id, b.id]);
      expect(vanIds(), [c.id, a.id, b.id]);

      // Novo naročilo gre še vedno na konec.
      final d = inVan();
      expect(vanIds(), [c.id, a.id, b.id, d.id]);
    });

    test('vrstni red preživi serializacijo (ponovni zagon)', () {
      final a = inVan();
      final b = inVan();
      repo.reorderVan([b.id, a.id]);

      final restored = repo.state.orders
          .map((o) => WorkOrder.fromJson(o.toJson()))
          .where((o) => o.isInVan);
      expect(sortedForVan(restored).map((o) => o.id), [b.id, a.id]);
    });

    test('preurejanje filtrirane regije ne premeša ostalih', () {
      final lj1 = inVan();
      final mb1 = inVan(location: OrderLocation.maribor);
      final lj2 = inVan();
      final mb2 = inVan(location: OrderLocation.maribor);
      expect(vanIds(), [lj1.id, mb1.id, lj2.id, mb2.id]);

      // Uporabnik vidi samo MB in zamenja obe.
      repo.reorderVan([mb2.id, mb1.id]);
      // MB zasedeta svoji prejšnji mesti (1 in 3); LJ ostaneta na 0 in 2.
      expect(vanIds(), [lj1.id, mb2.id, lj2.id, mb1.id]);
    });

    test('Iz kombija počisti vrstni red; ponovno V kombi gre na konec', () {
      final a = inVan();
      final b = inVan();
      repo.removeFromVan(a.id);
      expect(repo.state.order(a.id)!.vanOrder, isNull);

      repo.sendToVan(a.id);
      expect(vanIds(), [b.id, a.id]);
    });

    test('naročila brez številke (stara) so pred urejenimi', () {
      final a = inVan();
      final b = inVan();
      // Posnetek iz časa pred ročnim razvrščanjem: brez vanOrder.
      final legacy = repo.state.order(a.id)!;
      final orders = [
        WorkOrder.fromJson({...legacy.toJson(), 'vanOrder': null}),
        repo.state.order(b.id)!,
      ];
      expect(sortedForVan(orders).map((o) => o.id), [a.id, b.id]);
    });

    test('reorderVan prezre naročila, ki niso v kombiju', () {
      final a = inVan();
      final b = inVan();
      final loose = create();
      repo.reorderVan([b.id, loose.id, a.id]);
      expect(vanIds(), [b.id, a.id]);
    });
  });

  group('Hitri obračun: vrstni red', () {
    test('vrste: Sintetika, Shaggy, Volna, Perzija; neznane na koncu', () {
      const types = [
        RugType(id: 'a', name: 'Perzija / ročno vozlana', pricePerM2: 22),
        RugType(id: 'b', name: 'Volna', pricePerM2: 15),
        RugType(id: 'x', name: 'Svila', pricePerM2: 40),
        RugType(id: 'c', name: 'Shaggy / kosmati-debelejši', pricePerM2: 16),
        RugType(id: 'd', name: 'Sintetika / tanki tepihi', pricePerM2: 12),
      ];
      expect(sortedRugTypes(types).map((t) => t.id), ['d', 'c', 'b', 'a', 'x']);
    });

    test('seed je že v tem vrstnem redu', () {
      final names = repo.state.rugTypes.map((t) => t.name).toList();
      expect(sortedRugTypes(repo.state.rugTypes).map((t) => t.name), names);
    });

    test('doplačila: Urin, Dlake, Ponovno pranje, nato ostalo', () {
      const templates = [
        ExtraTemplate(
          id: '1',
          name: 'Ponovno pranje',
          kind: ExtraKind.percent,
          value: 30,
        ),
        ExtraTemplate(id: '2', name: 'Popust', kind: ExtraKind.fixed, value: -5),
        ExtraTemplate(id: '3', name: 'Dlake', kind: ExtraKind.fixed, value: 5),
        ExtraTemplate(id: '4', name: 'Urin', kind: ExtraKind.perM2, value: 3),
      ];
      expect(
        sortedQuickExtras(templates).map((t) => t.id),
        ['4', '3', '1', '2'],
      );
    });

    test('vnos / iznos nista med doplačili Hitrega obračuna', () {
      final quick = repo.state.extraTemplates.where((t) => !t.isOrderLevel);
      expect(
        sortedQuickExtras(quick).map((t) => t.name),
        ['Urin', 'Dlake', 'Ponovno pranje'],
      );
    });
  });

  group('slovenska množina', () {
    test('Fmt.orders', () {
      expect(Fmt.orders(1), '1 naročilo');
      expect(Fmt.orders(2), '2 naročili');
      expect(Fmt.orders(3), '3 naročila');
      expect(Fmt.orders(4), '4 naročila');
      expect(Fmt.orders(5), '5 naročil');
      expect(Fmt.orders(11), '11 naročil');
      expect(Fmt.orders(46), '46 naročil');
      expect(Fmt.pieces(68), '68 kosov');
      expect(Fmt.pieces(2), '2 kosa');
    });
  });

  group('minimalna obvestila', () {
    final base = DateTime(2026, 10, 22, 9);

    WorkOrder order(
      String id, {
      OrderStatus status = OrderStatus.awaitingCollection,
      DateTime? readyAt,
      DateTime? calledAt,
      DateTime? inVanAt,
      DateTime? pickupAt,
    }) => WorkOrder(
      id: id,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      status: status,
      customerId: 'c',
      customerName: 'Stranka',
      itemCount: 1,
      createdAt: base.subtract(const Duration(days: 5)),
      readyAt: readyAt,
      calledAt: calledAt,
      inVanAt: inVanAt,
      pickupAt: pickupAt,
    );

    test('po 24 h ena združena vrstica za nepoklicana naročila', () {
      final alerts = buildAlerts([
        order('LJ-001', readyAt: base.subtract(const Duration(hours: 30))),
        order('LJ-002', readyAt: base.subtract(const Duration(hours: 25))),
        order('LJ-003', readyAt: base.subtract(const Duration(hours: 24))),
        // Še ni 24 h, že poklicano, ni pripravljeno: ne štejejo.
        order('LJ-004', readyAt: base.subtract(const Duration(hours: 5))),
        order(
          'LJ-005',
          readyAt: base.subtract(const Duration(hours: 40)),
          calledAt: base.subtract(const Duration(hours: 2)),
        ),
        order('LJ-006', status: OrderStatus.inProduction),
      ], base);

      final uncalled = alerts.where((a) => a.kind == AlertKind.uncalled);
      expect(uncalled, hasLength(1));
      expect(uncalled.single.title, '3 pripravljena naročila še niso klicana.');
      expect(uncalled.single.body, 'LJ-001, LJ-002, LJ-003');
    });

    test('pred 24 h ni obvestila', () {
      final alerts = buildAlerts([
        order('LJ-001', readyAt: base.subtract(const Duration(hours: 23))),
      ], base);
      expect(alerts.where((a) => a.kind == AlertKind.uncalled), isEmpty);
    });

    test('stavki se ujemata s slovensko množino', () {
      String title(int n) => buildAlerts([
        for (var i = 0; i < n; i++)
          order('LJ-00$i', readyAt: base.subtract(const Duration(days: 3))),
      ], base).firstWhere((a) => a.kind == AlertKind.uncalled).title;

      expect(title(1), '1 pripravljeno naročilo še ni klicano.');
      expect(title(2), '2 pripravljeni naročili še nista klicani.');
      expect(title(3), '3 pripravljena naročila še niso klicana.');
      expect(title(5), '5 pripravljenih naročil še ni klicanih.');
    });

    test('po koncu delovnika: koliko naročil je še v kombiju', () {
      final inVanOrders = [
        for (var i = 1; i <= 2; i++)
          order(
            'LJ-00$i',
            status: OrderStatus.awaitingDelivery,
            inVanAt: base,
          ),
      ];
      final evening = DateTime(2026, 10, 22, workdayEndHour, 30);
      final alerts = buildAlerts(inVanOrders, evening);
      final van = alerts.where((a) => a.kind == AlertKind.vanLeft);
      expect(van, hasLength(1));
      expect(van.single.title, '2 naročili sta še v kombiju.');
    });

    test('čez dan kombi ni obvestilo, prazen kombi tudi ne', () {
      final inVanOrders = [
        order('LJ-001', status: OrderStatus.awaitingDelivery, inVanAt: base),
      ];
      expect(
        buildAlerts(inVanOrders, DateTime(2026, 10, 22, 12))
            .where((a) => a.kind == AlertKind.vanLeft),
        isEmpty,
      );
      expect(
        buildAlerts(const [], DateTime(2026, 10, 22, 20))
            .where((a) => a.kind == AlertKind.vanLeft),
        isEmpty,
      );
    });

    test('dnevni povzetek: prevzemi in dostave', () {
      final today = DateTime(2026, 10, 22, 14);
      final orders = [
        for (var i = 0; i < 6; i++)
          order(
            'LJ-10$i',
            status: OrderStatus.scheduledPickup,
            pickupAt: today,
          ),
        for (var i = 0; i < 4; i++)
          order(
            'LJ-20$i',
            status: OrderStatus.awaitingDelivery,
            inVanAt: base,
          ),
        // Jutrišnji prevzem ne šteje.
        order(
          'LJ-300',
          status: OrderStatus.scheduledPickup,
          pickupAt: today.add(const Duration(days: 1)),
        ),
      ];
      final summary = buildAlerts(orders, base)
          .singleWhere((a) => a.kind == AlertKind.daySummary);
      expect(summary.title, 'Danes: 6 prevzemov, 4 dostave.');
    });

    test('dnevni povzetek se ne pokaže, če danes ni nič', () {
      expect(buildAlerts(const [], base), isEmpty);
    });

    test('ni obvestila na vsako pripravljeno naročilo', () {
      final alerts = buildAlerts([
        for (var i = 0; i < 5; i++)
          order('LJ-00$i', readyAt: base.subtract(const Duration(hours: 1))),
      ], base);
      expect(alerts, isEmpty);
    });
  });
}

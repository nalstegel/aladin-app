import 'package:aladin/data/providers.dart';
import 'package:aladin/data/repository.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/catalog.dart';
import 'package:aladin/models/enums.dart';
import 'package:aladin/models/order.dart';
import 'package:aladin/models/return_proof.dart';
import 'package:aladin/models/rug_item.dart';
import 'package:aladin/ui/dashboard/quick_order_card.dart';
import 'package:aladin/ui/orders/edit_order_screen.dart';
import 'package:aladin/ui/orders/order_detail_screen.dart';
import 'package:aladin/ui/rugs/edit_pricing_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Brisanje naročil, popravek obračunanega kosa, Vnos / Iznos na naročilu in
/// vedno odprt Hiter vnos.
void main() {
  late InMemoryStore store;
  late ProviderContainer container;
  late Repository repo;

  setUp(() async {
    store = InMemoryStore();
    container = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(store)],
    );
    repo = container.read(repositoryProvider.notifier);
    await repo.init();
    repo.setCurrentUser('u-marko');
  });

  tearDown(() => container.dispose());

  WorkOrder newOrder({int items = 1}) => repo.createOrder(
        customer: repo.state.customers.first,
        location: OrderLocation.ljubljana,
        channel: OrderChannel.dropoff,
        handover: HandoverMode.customerCollects,
        itemCount: items,
      );

  /// Vrsta po začetku imena ("Perzij" → "Perzija / ročno vozlana").
  RugType type(String prefix) =>
      repo.state.rugTypes.firstWhere((t) => t.name.startsWith(prefix));

  /// Obračunan kos: Volna 200 × 300 cm = 6 m² × 15 € = 90 €.
  RugItem priced(WorkOrder order, int n, {double? price}) {
    final id = '${order.id}-$n';
    repo.markOrderPickedUp(order.id);
    repo.advance(id);
    repo.finishRugFromDrying(
      id,
      widthCm: 200,
      lengthCm: 300,
      rugType: type('Volna'),
      extras: const [],
      discountPercent: 0,
      priceOverride: price,
    );
    return repo.state.item(id)!;
  }

  group('izbris naročila', () {
    test('odstrani naročilo in vse njegove kose, drugih ne dotakne', () {
      final a = newOrder(items: 2);
      final b = newOrder(items: 3);
      final ordersBefore = repo.state.orders.length;
      final itemsBefore = repo.state.items.length;

      expect(repo.deleteOrder(a.id), isTrue);

      expect(repo.state.order(a.id), isNull);
      expect(repo.state.items.where((i) => i.orderId == a.id), isEmpty);
      expect(repo.state.orders.length, ordersBefore - 1);
      expect(repo.state.items.length, itemsBefore - 2);
      expect(repo.state.order(b.id), isNotNull);
      expect(repo.state.itemsOf(b.id).length, 3);
    });

    test('številka izbrisanega naročila se ne uporabi znova', () {
      final a = newOrder();
      repo.deleteOrder(a.id);

      final next = newOrder();

      expect(next.id, isNot(a.id));
    });

    test('deluje za naročilo v obdelavi in za pripravljeno naročilo', () {
      final inProduction = newOrder(items: 2);
      repo.markOrderPickedUp(inProduction.id);
      expect(repo.state.order(inProduction.id)!.status,
          OrderStatus.inProduction);

      final ready = newOrder();
      priced(ready, 1);
      expect(repo.state.order(ready.id)!.status, OrderStatus.awaitingCollection);

      expect(repo.deleteOrder(inProduction.id), isTrue);
      expect(repo.deleteOrder(ready.id), isTrue);
      expect(repo.state.order(inProduction.id), isNull);
      expect(repo.state.order(ready.id), isNull);
    });

    test('zaključenega naročila ni mogoče izbrisati — hrani dokazilo o vračilu',
        () {
      final order = newOrder();
      priced(order, 1);
      repo.completeReturn(
        order.id,
        ReturnProof(
          returnedAt: DateTime.now(),
          userId: 'u-marko',
          userName: 'Marko',
          scannedItemIds: ['${order.id}-1'],
          signatureBase64: 'ZmFrZQ==',
          receivedByName: 'Janez Novak',
        ),
      );

      expect(repo.deleteOrder(order.id), isFalse);

      expect(repo.state.order(order.id), isNotNull);
      expect(repo.state.itemsOf(order.id), isNotEmpty);
    });

    test('neznano naročilo: false in nič se ne spremeni', () {
      final before = repo.state;

      expect(repo.deleteOrder('XX-999'), isFalse);

      expect(identical(repo.state, before), isTrue);
    });

    test('izbris se shrani v shrambo', () async {
      final order = newOrder(items: 2);
      repo.deleteOrder(order.id);

      final saved = (await store.load())!;

      expect(saved.order(order.id), isNull);
      expect(saved.items.where((i) => i.orderId == order.id), isEmpty);
    });
  });

  group('popravek obračunanega kosa', () {
    test('vrsta, doplačilo in popust prešejo ceno; status ostane', () {
      final order = newOrder();
      final item = priced(order, 1);
      expect(item.price, 90);

      // Perzijska 22 €/m² × 6 m² = 132 €; Ponovno pranje +30 % = 171,60 €;
      // popust 10 % = 154,44 €.
      repo.editItemPricing(
        item.id,
        widthCm: 200,
        lengthCm: 300,
        rugType: type('Perzij'),
        extras: const [
          AppliedExtra(
            name: 'Ponovno pranje',
            kind: ExtraKind.percent,
            value: 30,
          ),
        ],
        discountPercent: 10,
        price: 154.44,
      );

      final edited = repo.state.item(item.id)!;
      expect(edited.rugTypeName, type('Perzij').name);
      expect(edited.pricePerM2, 22);
      expect(edited.computedPrice, 154.44);
      expect(edited.price, 154.44);
      expect(edited.status, RugStatus.ready);
      expect(repo.state.order(order.id)!.status, OrderStatus.awaitingCollection);
      expect(repo.state.billing(order.id)!.itemsTotal, closeTo(154.44, 0.001));
    });

    test('doplačila in popust ostanejo, če jih popravek ne poda', () {
      final order = newOrder();
      final item = priced(order, 1);
      repo.editItemPricing(
        item.id,
        widthCm: 200,
        lengthCm: 300,
        rugType: type('Volna'),
        extras: const [
          AppliedExtra(name: 'Dlake', kind: ExtraKind.fixed, value: 10),
        ],
        discountPercent: 5,
        price: 95,
      );

      repo.editItemPricing(
        item.id,
        widthCm: 200,
        lengthCm: 300,
        rugType: type('Volna'),
        price: 120,
      );

      final edited = repo.state.item(item.id)!;
      expect(edited.extras.map((e) => e.name), ['Dlake']);
      expect(edited.discountPercent, 5);
      expect(edited.price, 120);
    });

    test('zgodovina pove, kaj je bilo spremenjeno', () {
      final order = newOrder();
      final item = priced(order, 1);
      final eventsBefore = item.history.length;

      repo.editItemPricing(
        item.id,
        widthCm: 200,
        lengthCm: 300,
        rugType: type('Shaggy'),
        price: 96,
      );

      final history = repo.state.item(item.id)!.history;
      expect(history.length, eventsBefore + 1);
      expect(history.last.status, RugStatus.ready);
      expect(history.last.note, contains('vrsta'));
      expect(history.last.note, contains('cena'));
      expect(history.last.note, isNot(contains('mere')));
      expect(history.last.userName, isNotEmpty);
    });

    test('popravek brez sprememb ne zapiše ničesar', () {
      final order = newOrder();
      final item = priced(order, 1);
      final before = repo.state;

      repo.editItemPricing(
        item.id,
        widthCm: 200,
        lengthCm: 300,
        rugType: type('Volna'),
        extras: const [],
        discountPercent: 0,
        price: 90,
      );

      expect(identical(repo.state, before), isTrue);
    });

    test('mere spremenijo osnovo in minimalni obračun', () {
      final order = newOrder();
      final item = priced(order, 1);

      // 1 × 1 m = 1 m², Volna ima minimum 3 m² → 45 €.
      repo.editItemPricing(
        item.id,
        widthCm: 100,
        lengthCm: 100,
        rugType: type('Volna'),
        price: 45,
      );

      final edited = repo.state.item(item.id)!;
      expect(edited.m2, 1);
      expect(edited.usesMinCharge, isTrue);
      expect(edited.basePrice, 45);
      expect(edited.history.last.note, contains('mere'));
    });

    test('vrnjenega kosa ni mogoče popraviti', () {
      final order = newOrder();
      final item = priced(order, 1);
      repo.completeReturn(
        order.id,
        ReturnProof(
          returnedAt: DateTime.now(),
          userId: 'u-marko',
          userName: 'Marko',
          scannedItemIds: [item.id],
          signatureBase64: 'ZmFrZQ==',
          receivedByName: 'Janez Novak',
        ),
      );
      final before = repo.state;

      repo.editItemPricing(
        item.id,
        widthCm: 200,
        lengthCm: 300,
        rugType: type('Shaggy'),
        price: 1,
      );

      expect(identical(repo.state, before), isTrue);
    });
  });

  group('zasloni', () {
    /// Visok zaslon, da je vse na njem vidno brez drsenja.
    void tallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// Zaslon pride na vrh "korenskega" zaslona, kot v pravi aplikaciji.
    Future<void> show(WidgetTester tester, Widget screen) async {
      tallScreen(tester);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: Text('root'))),
        ),
      );
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(MaterialPageRoute<void>(builder: (_) => screen));
      await tester.pumpAndSettle();
    }

    TextField field(WidgetTester tester, bool Function(TextField) test) =>
        tester.widget<TextField>(
          find.byWidgetPredicate((w) => w is TextField && test(w)),
        );

    Finder discountField() => find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.suffixText == '%',
        );

    Finder priceField() => find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Končna cena',
        );

    group('Hiter vnos', () {
      testWidgets('je vedno odprt, brez zložljive glave', (tester) async {
        tallScreen(tester);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(child: QuickOrderCard()),
              ),
            ),
          ),
        );

        expect(find.text('Hiter vnos naročila'), findsOneWidget);
        expect(find.text('Telefon'), findsOneWidget);
        expect(find.textContaining('Ustvari naročilo'), findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsNothing);
        expect(find.byIcon(Icons.expand_less), findsNothing);

        // Tap na glavo ga ne zapre.
        await tester.tap(find.text('Hiter vnos naročila'));
        await tester.pump();
        expect(find.text('Telefon'), findsOneWidget);
      });
    });

    group('izbris naročila', () {
      testWidgets('koš vpraša, nato izbriše in vrne na prvi zaslon',
          (tester) async {
        final order = newOrder(items: 2);
        await show(tester, OrderDetailScreen(orderId: order.id));

        await tester.tap(find.byTooltip('Izbriši naročilo'));
        await tester.pumpAndSettle();
        expect(find.text('Izbrišem naročilo ${order.number}?'), findsOneWidget);

        // Prekliči ne izbriše ničesar.
        await tester.tap(find.text('Prekliči'));
        await tester.pumpAndSettle();
        expect(repo.state.order(order.id), isNotNull);
        expect(find.text('Naročilo ${order.number}'), findsOneWidget);

        await tester.tap(find.byTooltip('Izbriši naročilo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Izbriši'));
        await tester.pumpAndSettle();

        expect(repo.state.order(order.id), isNull);
        expect(repo.state.itemsOf(order.id), isEmpty);
        expect(find.text('root'), findsOneWidget);
        expect(find.text('Naročilo ne obstaja'), findsNothing);
        expect(find.text('Naročilo ${order.number} izbrisano'), findsOneWidget);
      });

      testWidgets('zaključeno naročilo nima koša', (tester) async {
        final order = newOrder();
        final item = priced(order, 1);
        // Brez podpisa (obvod skrbnika): zaslon sicer poskuša narisati
        // podpis, ki v testu ni prava slika.
        repo.completeReturn(
          order.id,
          ReturnProof(
            returnedAt: DateTime.now(),
            userId: 'u-marko',
            userName: 'Marko',
            scannedItemIds: [item.id],
            receivedByName: 'Janez Novak',
            overrideReason: 'Stranka se je mudila',
            overrideByName: 'Nal',
          ),
        );

        await show(tester, OrderDetailScreen(orderId: order.id));

        expect(find.byTooltip('Izbriši naročilo'), findsNothing);
      });
    });

    group('Uredi kos', () {
      testWidgets('meni ob obračunanem kosu odpre urejanje', (tester) async {
        final order = newOrder();
        final item = priced(order, 1);
        await show(tester, OrderDetailScreen(orderId: order.id));

        await tester.tap(find.byTooltip('Več'));
        await tester.pumpAndSettle();
        expect(find.text('Uredi kos'), findsOneWidget);
        // Edini kos naročila se ne sme odstraniti.
        expect(find.text('Odstrani kos'), findsNothing);

        await tester.tap(find.text('Uredi kos'));
        await tester.pumpAndSettle();
        expect(find.text('Uredi kos · ${item.id}'), findsOneWidget);
      });

      testWidgets('neobračunan kos ni za urejanje (vrste še nima)',
          (tester) async {
        final order = newOrder(items: 2);
        await show(tester, OrderDetailScreen(orderId: order.id));

        await tester.tap(find.byTooltip('Več').first);
        await tester.pumpAndSettle();

        expect(find.text('Odstrani kos'), findsOneWidget);
        expect(find.text('Uredi kos'), findsNothing);
      });

      testWidgets('vrsta, doplačilo in popust: cena sledi izračunu',
          (tester) async {
        final order = newOrder();
        final item = priced(order, 1);
        await show(tester, Scaffold(body: EditPricingSheet(item: item)));
        expect(field(tester, (f) => f.decoration?.labelText == 'Končna cena')
            .controller!
            .text, '90.00');

        await tester.tap(find.text(type('Perzij').name));
        await tester.tap(find.text('Ponovno pranje +30 %'));
        await tester.enterText(discountField(), '10');
        await tester.pump();

        expect(
          tester.widget<TextField>(priceField()).controller!.text,
          '154.44',
        );

        await tester.tap(find.textContaining('Shrani'));
        await tester.pumpAndSettle();

        final edited = repo.state.item(item.id)!;
        expect(edited.rugTypeName, type('Perzij').name);
        expect(edited.extras.map((e) => e.name), ['Ponovno pranje']);
        expect(edited.discountPercent, 10);
        expect(edited.price, 154.44);
        expect(edited.status, RugStatus.ready);
      });

      testWidgets('ročno določena cena se ob spremembi vrste ne povozi',
          (tester) async {
        final order = newOrder();
        final item = priced(order, 1, price: 100);
        await show(tester, Scaffold(body: EditPricingSheet(item: item)));

        await tester.tap(find.text(type('Perzij').name));
        await tester.pump();

        expect(
          tester.widget<TextField>(priceField()).controller!.text,
          '100.00',
        );
      });

      testWidgets(
          'Dlake: tipka za vsak znesek, druga zamenja prvo, ponovni dotik '
          'odstrani', (tester) async {
        final order = newOrder();
        final item = priced(order, 1);
        await show(tester, Scaffold(body: EditPricingSheet(item: item)));
        double shownPrice() => double.parse(
              tester.widget<TextField>(priceField()).controller!.text,
            );

        expect(find.text('Dlake +5 €'), findsOneWidget);
        expect(find.text('Dlake +10 €'), findsOneWidget);

        await tester.tap(find.text('Dlake +5 €'));
        await tester.pump();
        expect(shownPrice(), 95);

        await tester.tap(find.text('Dlake +10 €'));
        await tester.pump();
        expect(shownPrice(), 100);

        await tester.tap(find.text('Dlake +10 €'));
        await tester.pump();
        expect(shownPrice(), 90);

        await tester.tap(find.text('Dlake +5 €'));
        await tester.pump();
        await tester.tap(find.textContaining('Shrani'));
        await tester.pumpAndSettle();
        final edited = repo.state.item(item.id)!;
        expect(edited.extras.map((e) => '${e.name} ${e.value}'), ['Dlake 5.0']);
        expect(edited.price, 95);
      });

      testWidgets(
          'nespremenjena vrsta obdrži ceno na m², zapisano na kosu — cenik je '
          'medtem lahko drugačen', (tester) async {
        final order = newOrder();
        final item = priced(order, 1);
        repo.upsertRugType(type('Volna').copyWith(pricePerM2: 99));
        await show(tester, Scaffold(body: EditPricingSheet(item: item)));

        await tester.enterText(discountField(), '10');
        await tester.pump();
        await tester.tap(find.textContaining('Shrani'));
        await tester.pumpAndSettle();

        final edited = repo.state.item(item.id)!;
        expect(edited.pricePerM2, 15);
        expect(edited.price, 81);
      });

      testWidgets('doplačilo, ki ga šifrant ne pozna več, ostane na kosu',
          (tester) async {
        final order = newOrder();
        final item = priced(order, 1);
        // Doplačilo, ki ga ni (več) v šifrantu.
        repo.editItemPricing(
          item.id,
          widthCm: 200,
          lengthCm: 300,
          rugType: type('Volna'),
          extras: const [
            AppliedExtra(name: 'Posebno čiščenje', kind: ExtraKind.fixed, value: 12),
          ],
          price: 102,
        );
        final current = repo.state.item(item.id)!;
        await show(tester, Scaffold(body: EditPricingSheet(item: current)));

        expect(find.text('Posebno čiščenje +12 €'), findsOneWidget);
        await tester.enterText(discountField(), '10');
        await tester.pump();
        await tester.tap(find.textContaining('Shrani'));
        await tester.pumpAndSettle();

        final edited = repo.state.item(item.id)!;
        expect(edited.extras.map((e) => e.name), ['Posebno čiščenje']);
        // (90 + 12) − 10 % = 91,80
        expect(edited.price, 91.8);
      });

      testWidgets('shranjevanje je onemogočeno brez mer', (tester) async {
        final order = newOrder();
        final item = priced(order, 1);
        await show(tester, Scaffold(body: EditPricingSheet(item: item)));

        await tester.enterText(
          find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Širina (cm)',
          ),
          '',
        );
        await tester.pump();

        final save = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(save.onPressed, isNull);
      });
    });

    group('Vnos / Iznos na naročilu', () {
      testWidgets('naknadno dodan Iznos; že zapisani Vnos ohrani svoj znesek',
          (tester) async {
        final order = newOrder();
        // Ob prevzemu zapisan Vnos po 7 € — cena v šifrantu je zdaj 5 €.
        repo.updateOrder(order.copyWith(orderExtras: const [
          AppliedExtra(name: 'Vnos', kind: ExtraKind.fixed, value: 7),
        ]));
        await show(tester, EditOrderScreen(orderId: order.id));
        expect(find.text('Vnos +7 €'), findsOneWidget);
        expect(find.text('Iznos +5 €'), findsOneWidget);

        await tester.tap(find.text('Iznos +5 €'));
        await tester.pump();
        await tester.tap(find.text('Shrani spremembe'));
        await tester.pumpAndSettle();

        final extras = repo.state.order(order.id)!.orderExtras;
        expect(extras.map((e) => e.name), unorderedEquals(['Vnos', 'Iznos']));
        expect(extras.firstWhere((e) => e.name == 'Vnos').value, 7);
        expect(extras.firstWhere((e) => e.name == 'Iznos').value, 5);
        expect(repo.state.billing(order.id)!.orderExtrasTotal, 12);
      });

      testWidgets('Vnos je mogoče tudi odstraniti', (tester) async {
        final order = newOrder();
        repo.updateOrder(order.copyWith(orderExtras: const [
          AppliedExtra(name: 'Vnos', kind: ExtraKind.fixed, value: 5),
        ]));
        await show(tester, EditOrderScreen(orderId: order.id));

        await tester.tap(find.text('Vnos +5 €'));
        await tester.pump();
        await tester.tap(find.text('Shrani spremembe'));
        await tester.pumpAndSettle();

        expect(repo.state.order(order.id)!.orderExtras, isEmpty);
      });
    });
  });
}

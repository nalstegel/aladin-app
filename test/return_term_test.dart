import 'package:aladin/data/alerts.dart';
import 'package:aladin/data/order_phases.dart';
import 'package:aladin/data/providers.dart';
import 'package:aladin/data/repository.dart';
import 'package:aladin/data/seed.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/customer.dart';
import 'package:aladin/models/enums.dart';
import 'package:aladin/models/order.dart';
import 'package:aladin/models/return_proof.dart';
import 'package:aladin/ui/orders/edit_order_screen.dart';
import 'package:aladin/ui/orders/order_detail_screen.dart';
import 'package:aladin/ui/orders/ready_lists.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Planirana dostava iz Pripravljeno: ko se s stranko dogovorimo za dan in
/// časovno okno vračila (Rok → Uredi), se naročilo na ta dan samo pokaže v
/// Dostavah — brez novega statusa in brez V kombi.
void main() {
  late ProviderContainer container;
  late Repository repo;
  late Customer customer;

  setUp(() async {
    // Demo podatki (šifrant, stranke), a brez demo naročil — demo naročilo z
    // vračilom danes bi bilo zdaj tudi v Dostavah in bi motilo štetje.
    final store = InMemoryStore();
    await store.save(buildSeedState().copyWith(orders: [], items: []));
    container = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(store),
        // Brez periodičnega časovnika ure (glej minuteClockProvider).
        minuteClockProvider.overrideWith((ref) => Stream.value(DateTime.now())),
      ],
    );
    repo = container.read(repositoryProvider.notifier);
    await repo.init();
    repo.setCurrentUser('u-marko');
    customer = repo.state.customers.first;
  });

  tearDown(() => container.dispose());

  /// Naročilo, pripeljano do Pripravljeno (Hitri obračun).
  WorkOrder ready({
    HandoverMode handover = HandoverMode.weDeliver,
    bool finish = true,
  }) {
    final order = repo.createOrder(
      customer: customer,
      location: OrderLocation.ljubljana,
      channel: handover == HandoverMode.weDeliver
          ? OrderChannel.delivery
          : OrderChannel.dropoff,
      handover: handover,
      itemCount: 1,
    );
    if (!finish) return repo.state.order(order.id)!;
    final type = repo.state.rugTypes.first;
    repo.markOrderPickedUp(order.id);
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
    return repo.state.order(order.id)!;
  }

  WorkOrder current(WorkOrder o) => repo.state.order(o.id)!;

  List<OrderPhase> phases(WorkOrder o, {DateTime? now}) =>
      phasesOf(current(o), repo.state.itemsOf(o.id), now: now);

  DateTime at(DateTime day, int hour) =>
      DateTime(day.year, day.month, day.day, hour);

  DateTime today([int hour = 8]) => at(DateTime.now(), hour);

  DateTime daysFromNow(int days, [int hour = 8]) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + days, hour);
  }

  group('premik Pripravljeno → Dostave po datumu', () {
    test('brez termina naročilo ostane v Pripravljeno', () {
      final o = ready();
      expect(phases(o), [OrderPhase.ready]);
      expect(current(o).deliveryAt, isNull);
    });

    test('termin v prihodnosti: do tistega dne ostane v Pripravljeno', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: daysFromNow(2), end: daysFromNow(2, 10));

      expect(phases(o), [OrderPhase.ready]);
      expect(OrderPhase.deliveries.containsOrder(current(o), const []), isFalse);
    });

    test('na izbrani dan se samo pokaže v Dostavah, brez V kombi', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today(), end: today(10));

      expect(phases(o), [OrderPhase.deliveries]);
      expect(current(o).inVanAt, isNull);
      // Status je še vedno izpeljan iz kosov: nov status ne obstaja.
      expect(current(o).status, OrderStatus.awaitingDelivery);
    });

    test('premik je odvisen od dneva, ne od ure', () {
      final o = ready();
      // Dogovorjeno ob 23:30, a že zjutraj mora biti na seznamu vsega za danes.
      repo.setReturnTerm(o.id, start: today(23));
      expect(phases(o, now: at(DateTime.now(), 0)), [OrderPhase.deliveries]);
    });

    test('deterministično: ob polnoči pred dnevom še ne, ob polnoči da', () {
      final o = ready();
      repo.setReturnTerm(
        o.id,
        start: DateTime(2031, 5, 14, 8),
        end: DateTime(2031, 5, 14, 10),
      );

      expect(phases(o, now: DateTime(2031, 5, 13, 23, 59)), [OrderPhase.ready]);
      expect(phases(o, now: DateTime(2031, 5, 14)), [OrderPhase.deliveries]);
      expect(
        phases(o, now: DateTime(2031, 5, 14, 23, 59)),
        [OrderPhase.deliveries],
      );
    });

    test('meja meseca: 31. 5. → 1. 6.', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: DateTime(2031, 6, 1, 8));

      expect(phases(o, now: DateTime(2031, 5, 31, 23, 30)), [OrderPhase.ready]);
      expect(phases(o, now: DateTime(2031, 6, 1)), [OrderPhase.deliveries]);
    });

    test('zamujena dostava ostane v Dostavah, dokler ni predana', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: DateTime(2031, 5, 14, 8));
      expect(phases(o, now: DateTime(2031, 5, 20)), [OrderPhase.deliveries]);
    });

    test('sprememba datuma prilagodi premik novemu datumu', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today());
      expect(phases(o), [OrderPhase.deliveries]);

      // Stranka prestavi na pojutrišnjem: naročilo gre nazaj v Pripravljeno.
      repo.setReturnTerm(o.id, start: daysFromNow(2));
      expect(phases(o), [OrderPhase.ready]);

      // In obratno: predčasen dogovor za danes ga takoj pokaže v Dostavah.
      repo.setReturnTerm(o.id, start: today());
      expect(phases(o), [OrderPhase.deliveries]);
    });

    test('odstranjen termin: naročilo se ne premakne v Dostave', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: daysFromNow(3), end: daysFromNow(3, 10));
      repo.setReturnTerm(o.id);

      final saved = current(o);
      expect(saved.deliveryAt, isNull);
      expect(saved.deliveryWindowEnd, isNull);
      expect(phases(o, now: daysFromNow(3)), [OrderPhase.ready]);
    });

    test('odstranitev termina, ki je že danes, vrne naročilo v Pripravljeno', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today());
      expect(phases(o), [OrderPhase.deliveries]);

      repo.setReturnTerm(o.id);
      expect(phases(o), [OrderPhase.ready]);
    });

    test('V kombi še vedno deluje ročno, a ni pogoj', () {
      final manual = ready();
      repo.sendToVan(manual.id);
      expect(phases(manual), [OrderPhase.deliveries]);

      final planned = ready();
      repo.setReturnTerm(planned.id, start: today());
      expect(phases(planned), [OrderPhase.deliveries]);
      expect(current(planned).isInVan, isFalse);
    });

    test('naročilo, ki še ni pripravljeno, v Dostavah ni', () {
      final o = ready(finish: false);
      repo.markOrderPickedUp(o.id);
      repo.setReturnTerm(o.id, start: today());

      expect(phases(o), isNot(contains(OrderPhase.deliveries)));
      expect(phases(o), isNot(contains(OrderPhase.ready)));
    });

    test('po dejanski predaji se naročilo zaključi po obstoječem flowu', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today());

      repo.completeReturn(
        o.id,
        ReturnProof(
          returnedAt: DateTime.now(),
          userId: 'u-marko',
          userName: 'Marko',
          scannedItemIds: ['${o.id}-1'],
          receivedByName: 'Stranka',
          signatureBase64: 'AAAA',
        ),
      );
      expect(current(o).status, OrderStatus.completed);
      expect(phases(o), isEmpty);
    });

    test('arhivirano naročilo ni v Dostavah', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today());
      repo.archiveOrder(o.id);
      expect(phases(o), isEmpty);
    });

    test('kos nazaj v pranje vzame naročilo iz Dostav, termin ostane', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today());
      repo.sendBackToWash('${o.id}-1', 'madež');

      expect(phases(o), isNot(contains(OrderPhase.deliveries)));
      expect(current(o).deliveryAt, isNotNull);
    });
  });

  group('Stranka pride po preproge', () {
    test('termin ni mogoč, naročilo ostane v Pripravljeno', () {
      final o = ready(handover: HandoverMode.customerCollects);

      expect(repo.setReturnTerm(o.id, start: today()), isFalse);
      expect(current(o).deliveryAt, isNull);
      expect(phases(o), [OrderPhase.ready]);
    });

    test('tudi zastarel termin na takem naročilu ga ne premakne', () {
      final o = ready(handover: HandoverMode.customerCollects);
      repo.updateOrder(current(o).copyWith(deliveryAt: today()));

      expect(current(o).status, OrderStatus.awaitingCollection);
      expect(phases(o), [OrderPhase.ready]);
    });
  });

  group('časovni okvir', () {
    test('veljaven konec okna se shrani', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today(8), end: today(10));
      expect(current(o).deliveryAt, today(8));
      expect(current(o).deliveryWindowEnd, today(10));
    });

    test('enaka začetna in končna ura je točna ura', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today(9), end: today(9));
      expect(current(o).deliveryWindowEnd, today(9));
    });

    test('konec pred začetkom ali na drug dan se zavrže', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today(10), end: today(8));
      expect(current(o).deliveryAt, today(10));
      expect(current(o).deliveryWindowEnd, isNull);

      repo.setReturnTerm(o.id, start: today(10), end: daysFromNow(1, 12));
      expect(current(o).deliveryWindowEnd, isNull);
    });

    test('nov termin brez konca pobriše star konec okna', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today(8), end: today(10));
      repo.setReturnTerm(o.id, start: daysFromNow(1, 14));
      expect(current(o).deliveryWindowEnd, isNull);
    });

    test('okno preživi serializacijo; stari zapisi brez njega so veljavni', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today(8), end: today(10));

      final json = current(o).toJson();
      expect(WorkOrder.fromJson(json).deliveryWindowEnd, today(10));

      json.remove('deliveryWindowEnd');
      expect(WorkOrder.fromJson(json).deliveryWindowEnd, isNull);
    });
  });

  group('števci, Danes in ročni vrstni red', () {
    test('števca Pripravljeno in Dostave sledita datumu', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: DateTime(2031, 5, 14, 8));

      final before = phaseCounts(repo.state, now: DateTime(2031, 5, 13));
      expect(before[OrderPhase.ready], 1);
      expect(before[OrderPhase.deliveries], 0);

      final onDay = phaseCounts(repo.state, now: DateTime(2031, 5, 14));
      expect(onDay[OrderPhase.ready], 0);
      expect(onDay[OrderPhase.deliveries], 1);
    });

    test('Vračila danes so natanko tisto, kar je v Dostavah', () {
      final planned = ready();
      repo.setReturnTerm(planned.id, start: today());
      final inVan = ready();
      repo.sendToVan(inVan.id);
      final later = ready();
      repo.setReturnTerm(later.id, start: daysFromNow(2));

      final ids = container.read(todayDeliveriesProvider).map((o) => o.id);
      expect(ids, unorderedEquals([planned.id, inVan.id]));
    });

    test('dnevni povzetek šteje tudi planirano dostavo', () {
      final o = ready();
      repo.setReturnTerm(o.id, start: today());
      final alerts = buildAlerts(repo.state.orders, DateTime.now());
      expect(alerts.where((a) => a.kind == AlertKind.daySummary), hasLength(1));
    });

    test('reorderVan uredi planirana in kombi naročila skupaj', () {
      final planned = ready();
      repo.setReturnTerm(planned.id, start: today());
      final inVan = ready();
      repo.sendToVan(inVan.id);

      List<String> shown() => sortedForVan(
        repo.state.orders.where((o) => o.isInDeliveries(DateTime.now())),
      ).map((o) => o.id).toList();
      expect(shown(), [planned.id, inVan.id]);

      repo.reorderVan([inVan.id, planned.id]);
      expect(shown(), [inVan.id, planned.id]);
      expect(current(planned).vanOrder, 1);
    });

    test('nov dan je nova pot: ročni vrstni red planiranega se pobriše', () {
      final planned = ready();
      repo.setReturnTerm(planned.id, start: today());
      final other = ready();
      repo.setReturnTerm(other.id, start: today());
      repo.reorderVan([other.id, planned.id]);
      expect(current(planned).vanOrder, isNotNull);

      // Ista dneva: ročni vrstni red ostane.
      repo.setReturnTerm(planned.id, start: today(14));
      expect(current(planned).vanOrder, isNotNull);

      repo.setReturnTerm(planned.id, start: daysFromNow(2));
      expect(current(planned).vanOrder, isNull);
    });

    test('naročilo v kombiju obdrži mesto, ko se termin spremeni', () {
      final a = ready();
      repo.sendToVan(a.id);
      final b = ready();
      repo.sendToVan(b.id);
      repo.reorderVan([b.id, a.id]);

      repo.setReturnTerm(a.id, start: daysFromNow(2));
      expect(current(a).vanOrder, isNotNull);
    });
  });

  group('zasloni', () {
    Future<void> show(WidgetTester tester, Widget screen) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: Scaffold(body: screen)),
        ),
      );
      await tester.pump();
    }

    // Podrobnosti in Uredi naročilo v testni pisavi (Ahem, širša od prave)
    // prelijeta ozke kartice, zato dobita široko površino; seznami ostanejo na
    // 420 px kot v ostalih testih.
    Future<void> showWide(WidgetTester tester, Widget screen) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: screen),
        ),
      );
      await tester.pump();
    }

    Future<void> showDetail(WidgetTester tester, WorkOrder o) =>
        showWide(tester, OrderDetailScreen(orderId: o.id));

    group('podrobnosti naročila', () {
      testWidgets('Rok ima Uredi pri naročilu, ki ga vračamo mi', (
        tester,
      ) async {
        final o = ready();
        await showDetail(tester, o);

        expect(find.text('Rok'), findsOneWidget);
        // Uredi pri Podatkih + Uredi pri Roku.
        expect(find.text('Uredi'), findsNWidgets(2));
      });

      testWidgets('Stranka pride po preproge: Rok brez Uredi', (tester) async {
        final o = ready(handover: HandoverMode.customerCollects);
        repo.updateOrder(current(o).copyWith(dueAt: daysFromNow(3)));
        await showDetail(tester, o);

        expect(find.text('Rok'), findsOneWidget);
        // Samo Uredi pri Podatkih.
        expect(find.text('Uredi'), findsOneWidget);
      });

      testWidgets('Rok pokaže dogovorjen dan in okno', (tester) async {
        final o = ready();
        repo.setReturnTerm(o.id, start: daysFromNow(2), end: daysFromNow(2, 10));
        await showDetail(tester, o);

        expect(find.textContaining('08:00–10:00'), findsOneWidget);
      });

      testWidgets('brez ure termina ni mogoče shraniti', (tester) async {
        final o = ready();
        await showDetail(tester, o);

        await tester.tap(find.text('Uredi').last);
        await tester.pumpAndSettle();

        expect(find.text('Termin vračila'), findsOneWidget);
        expect(find.text('Datum vračila'), findsOneWidget);
        expect(find.text('Odstrani termin'), findsNothing);
        final save = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Izberi uro'),
        );
        expect(save.onPressed, isNull);
      });

      testWidgets('Shrani termin zapiše isti termin in potrdi', (tester) async {
        final o = ready();
        repo.setReturnTerm(o.id, start: daysFromNow(2), end: daysFromNow(2, 10));
        await showDetail(tester, o);

        await tester.tap(find.text('Uredi').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shrani termin'));
        await tester.pumpAndSettle();

        expect(current(o).deliveryAt, daysFromNow(2));
        expect(current(o).deliveryWindowEnd, daysFromNow(2, 10));
        expect(find.textContaining('Vračilo '), findsOneWidget);
      });

      testWidgets('Odstrani termin pobriše dogovor', (tester) async {
        final o = ready();
        repo.setReturnTerm(o.id, start: daysFromNow(2), end: daysFromNow(2, 10));
        await showDetail(tester, o);

        await tester.tap(find.text('Uredi').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Odstrani termin'));
        await tester.pumpAndSettle();

        expect(current(o).deliveryAt, isNull);
        expect(current(o).deliveryWindowEnd, isNull);
        expect(find.text('Termin vračila odstranjen.'), findsOneWidget);
      });

      testWidgets('na dan vračila je glavna akcija vračilo, ne V kombi', (
        tester,
      ) async {
        final o = ready();
        repo.setReturnTerm(o.id, start: today());
        await showDetail(tester, o);

        expect(find.text('Vračilo na naslov'), findsOneWidget);
        expect(find.text('V kombi'), findsNothing);
      });
    });

    group('Pripravljeno', () {
      testWidgets('planirano za jutri ostane tu in pokaže termin', (
        tester,
      ) async {
        final o = ready();
        repo.setReturnTerm(o.id, start: daysFromNow(1), end: daysFromNow(1, 10));
        await show(tester, const ReadyList());

        await tester.tap(find.text('Za dostavo'));
        await tester.pump();
        expect(find.textContaining(o.id), findsOneWidget);
        expect(find.textContaining('08:00–10:00'), findsOneWidget);
        expect(find.text('V kombi'), findsOneWidget);
      });

      testWidgets('planirano za danes ni več v Pripravljeno', (tester) async {
        final o = ready();
        repo.setReturnTerm(o.id, start: today());
        await show(tester, const ReadyList());

        expect(find.text('Nič ni pripravljeno'), findsOneWidget);
        expect(find.textContaining(o.id), findsNothing);
      });
    });

    group('Dostave', () {
      testWidgets('planirano naročilo je tu brez kombija; okvir je viden', (
        tester,
      ) async {
        final o = ready();
        repo.setReturnTerm(o.id, start: today(8), end: today(10));
        await show(tester, const DeliveriesList());

        expect(find.textContaining(o.id), findsOneWidget);
        expect(find.text('08:00–10:00'), findsOneWidget);
        expect(find.text('Vrni'), findsOneWidget);
        // Na seznamu je zaradi dne, ne zaradi kombija: "Iz kombija" nima pomena.
        expect(find.text('Iz kombija'), findsNothing);
      });

      testWidgets('kombi naročilo brez termina ima še vedno Iz kombija', (
        tester,
      ) async {
        final planned = ready();
        repo.setReturnTerm(planned.id, start: today(8), end: today(10));
        final manual = ready();
        repo.sendToVan(manual.id);
        await show(tester, const DeliveriesList());

        expect(find.text('Vse (2)'), findsOneWidget);
        expect(find.text('Vrni'), findsNWidgets(2));
        expect(find.text('Iz kombija'), findsOneWidget);
        expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));
      });

      testWidgets('zamujen dan je izpisan z datumom', (tester) async {
        final o = ready();
        repo.setReturnTerm(o.id, start: daysFromNow(-1, 9), end: daysFromNow(-1, 11));
        await show(tester, const DeliveriesList());

        expect(find.textContaining('Včeraj'), findsOneWidget);
        expect(find.textContaining('09:00–11:00'), findsOneWidget);
      });

      testWidgets('termin v prihodnosti: Dostave so prazne', (tester) async {
        final o = ready();
        repo.setReturnTerm(o.id, start: daysFromNow(2));
        await show(tester, const DeliveriesList());

        expect(find.text('Ni dostav'), findsOneWidget);
        expect(find.textContaining(o.id), findsNothing);
      });
    });

    group('Uredi naročilo', () {
      testWidgets('dogovorjen termin ostane, ko shraniš druge spremembe', (
        tester,
      ) async {
        final o = ready();
        repo.setReturnTerm(o.id, start: daysFromNow(2), end: daysFromNow(2, 10));
        await showWide(tester, EditOrderScreen(orderId: o.id));

        expect(find.text('Dogovorjeno vračilo'), findsOneWidget);
        expect(find.textContaining('08:00–10:00'), findsOneWidget);

        await tester.tap(find.text('Shrani spremembe'));
        await tester.pumpAndSettle();

        expect(current(o).deliveryAt, daysFromNow(2));
        expect(current(o).deliveryWindowEnd, daysFromNow(2, 10));
      });

      testWidgets('menjava na "Stranka pride" pobriše termin', (tester) async {
        final o = ready();
        repo.setReturnTerm(o.id, start: today(), end: today(10));
        await showWide(tester, EditOrderScreen(orderId: o.id));

        await tester.tap(find.text('Stranka'));
        await tester.pump();
        await tester.tap(find.text('Shrani spremembe'));
        await tester.pumpAndSettle();

        final saved = current(o);
        expect(saved.handover, HandoverMode.customerCollects);
        expect(saved.deliveryAt, isNull);
        expect(saved.deliveryWindowEnd, isNull);
        // Status se izpelje iz kosov in načina vračila: nazaj ni v Dostavah.
        expect(phases(o), isNot(contains(OrderPhase.deliveries)));
      });
    });
  });
}

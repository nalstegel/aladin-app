import 'package:aladin/data/providers.dart';
import 'package:aladin/data/seed.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/enums.dart';
import 'package:aladin/models/order.dart';
import 'package:aladin/ui/orders/order_detail_screen.dart';
import 'package:aladin/ui/orders/ready_lists.dart';
import 'package:aladin/ui/widgets/undo_snackbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Zasloni V10 (Pripravljeno, Dostave, klic iz podrobnosti naročila, snackbar
/// z Razveljavi): zaženejo se brez napak in delajo to, kar piše v PDF-ju.
void main() {
  late ProviderContainer container;

  setUp(() async {
    // Demo podatki (šifrant, stranke), a brez demo naročil — da števci v
    // testih štejejo samo to, kar ustvari test.
    final store = InMemoryStore();
    await store.save(buildSeedState().copyWith(orders: [], items: []));
    container = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(store)],
    );
    await container.read(repositoryProvider.notifier).init();
    container.read(repositoryProvider.notifier).setCurrentUser('u-marko');
  });

  tearDown(() => container.dispose());

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();
  }

  /// Naročilo, pripeljano do Pripravljeno (Hitri obračun).
  WorkOrder ready({
    OrderLocation location = OrderLocation.ljubljana,
    OrderChannel channel = OrderChannel.dropoff,
    String name = '',
  }) {
    final repo = container.read(repositoryProvider.notifier);
    var customer = repo.state.customers.first;
    if (name.isNotEmpty) {
      customer = repo.createCustomer(
        type: CustomerType.private,
        name: name,
        phone: '031 353 517',
      );
    }
    final order = repo.createOrder(
      customer: customer,
      location: location,
      channel: channel,
      handover: channel == OrderChannel.dropoff
          ? HandoverMode.customerCollects
          : HandoverMode.weDeliver,
      itemCount: 1,
    );
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

  WorkOrder inVan({
    OrderLocation location = OrderLocation.ljubljana,
    String name = '',
  }) {
    final o = ready(
      location: location,
      channel: OrderChannel.delivery,
      name: name,
    );
    container.read(repositoryProvider.notifier).sendToVan(o.id);
    return container.read(repositoryProvider).order(o.id)!;
  }

  group('Pripravljeno', () {
    testWidgets('sekcije so zaprte, kažejo število, prazne so skrite', (
      tester,
    ) async {
      ready(); // osebni prevzem, ni klicano
      ready(channel: OrderChannel.delivery); // za dostavo
      await pump(tester, const ReadyList());

      expect(find.text('Za dostavo'), findsOneWidget);
      expect(find.text('Ni klicano'), findsOneWidget);
      // Klicano · čaka stranko je prazno → skrito.
      expect(find.text('Klicano · čaka stranko'), findsNothing);
      // Zaprto: vrstice (in gumb Pokliči / V kombi) še niso vidne.
      expect(find.text('Pokliči'), findsNothing);
      expect(find.text('V kombi'), findsNothing);
      // Enota je izpisana.
      expect(find.text('2 naročili'), findsOneWidget);
    });

    testWidgets('vrstni red: filtri → Za dostavo → Ni klicano', (tester) async {
      ready();
      ready(channel: OrderChannel.delivery);
      await pump(tester, const ReadyList());

      final pills = tester.getTopLeft(find.text('Vse (2)')).dy;
      final delivery = tester.getTopLeft(find.text('Za dostavo')).dy;
      final notCalled = tester.getTopLeft(find.text('Ni klicano')).dy;
      expect(pills, lessThan(delivery));
      expect(delivery, lessThan(notCalled));
    });

    testWidgets('filtri regij so dinamični in filtrirajo seznam', (
      tester,
    ) async {
      ready();
      ready(location: OrderLocation.maribor, name: 'Marija Kovač');
      await pump(tester, const ReadyList());

      for (final l in OrderLocation.values) {
        expect(find.textContaining('${l.code} ('), findsOneWidget);
      }
      expect(find.text('Ni klicano'), findsOneWidget);
      expect(find.text('1 naročilo'), findsNothing);
      expect(find.text('2 naročili'), findsOneWidget);

      await tester.tap(find.text('MB (1)'));
      await tester.pump();
      expect(find.text('1 naročilo'), findsOneWidget);

      await tester.ensureVisible(find.text('CE (0)'));
      await tester.tap(find.text('CE (0)'));
      await tester.pump();
      expect(find.text('V regiji CE ni pripravljenih naročil.'), findsOneWidget);
    });

    testWidgets('klic iz seznama zabeleži Klicano in premakne naročilo', (
      tester,
    ) async {
      final order = ready();
      await pump(tester, const ReadyList());

      await tester.tap(find.text('Ni klicano'));
      await tester.pump();
      await tester.tap(find.text('Pokliči'));
      await tester.pumpAndSettle();

      expect(container.read(repositoryProvider).order(order.id)!.calledAt,
          isNotNull);
      // Izgine iz Ni klicano, pojavi se v Klicano.
      expect(find.text('Ni klicano'), findsNothing);
      expect(find.text('Klicano · čaka stranko'), findsOneWidget);
    });

    testWidgets('V kombi pokaže Razveljavi, ki ne obvisi', (tester) async {
      final order = ready(channel: OrderChannel.delivery);
      await pump(tester, const ReadyList());

      await tester.tap(find.text('Za dostavo'));
      await tester.pump();
      await tester.tap(find.text('V kombi'));
      await tester.pump();
      expect(find.text('${order.id} je v kombiju.'), findsOneWidget);
      expect(find.text('Razveljavi'), findsOneWidget);

      // Po ~5 s izgine sam, čeprav ima akcijo. (Časovnik steče šele, ko se
      // snackbar do konca prikaže, zato najprej počakamo vstopno animacijo.)
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(undoSnackBarDuration);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('${order.id} je v kombiju.'), findsNothing);
    });
  });

  group('klic iz podrobnosti naročila', () {
    testWidgets('tap na telefon zabeleži Klicano', (tester) async {
      final order = ready();
      expect(order.calledAt, isNull);

      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: OrderDetailScreen(orderId: order.id)),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.call));
      await tester.pumpAndSettle();

      expect(container.read(repositoryProvider).order(order.id)!.calledAt,
          isNotNull);
      expect(find.text('Klicano'), findsOneWidget);
    });

    testWidgets('Uredi na podatkih odpre urejanje stranke, ne zamenjave', (
      tester,
    ) async {
      final order = ready();
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: OrderDetailScreen(orderId: order.id)),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Uredi').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Podatki stranke'), findsOneWidget);
      expect(find.text('Telefon'), findsWidgets);

      await tester.enterText(find.widgetWithText(TextField, 'Telefon'), '041 555 666');
      await tester.tap(find.text('Shrani'));
      await tester.pumpAndSettle();

      expect(
        container.read(repositoryProvider).order(order.id)!.customerPhone,
        '041 555 666',
      );
    });
  });

  group('Dostave', () {
    testWidgets('brez Odpri pot; ročaji in zaporedne številke', (tester) async {
      inVan();
      inVan(name: 'Marija Kovač');
      await pump(tester, const DeliveriesList());

      expect(find.textContaining('Odpri pot'), findsNothing);
      expect(find.byIcon(Icons.alt_route), findsNothing);
      expect(find.byIcon(Icons.drag_indicator), findsNWidgets(2));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Vrni'), findsNWidgets(2));
      expect(find.text('Iz kombija'), findsNWidgets(2));
    });

    testWidgets('kartice sledijo shranjenemu ročnemu vrstnemu redu', (
      tester,
    ) async {
      final a = inVan();
      final b = inVan(name: 'Marija Kovač');
      container.read(repositoryProvider.notifier).reorderVan([b.id, a.id]);
      await pump(tester, const DeliveriesList());

      final top = tester.getTopLeft(find.textContaining(b.id)).dy;
      final bottom = tester.getTopLeft(find.textContaining(a.id)).dy;
      expect(top, lessThan(bottom));
    });

    testWidgets('vlečenje ročaja spremeni in shrani vrstni red', (
      tester,
    ) async {
      final a = inVan();
      final b = inVan(name: 'Marija Kovač');
      await pump(tester, const DeliveriesList());

      final handle = find.byIcon(Icons.drag_indicator).first;
      await tester.timedDrag(
        handle,
        const Offset(0, 320),
        const Duration(milliseconds: 600),
      );
      await tester.pumpAndSettle();

      final order = container
          .read(repositoryProvider)
          .orders
          .where((o) => o.isInVan)
          .toList()
        ..sort((x, y) => x.vanOrder!.compareTo(y.vanOrder!));
      expect(order.map((o) => o.id), [b.id, a.id]);
    });

    testWidgets('filter regije je med Dostavami še vedno na voljo', (
      tester,
    ) async {
      inVan();
      inVan(location: OrderLocation.maribor, name: 'Marija Kovač');
      await pump(tester, const DeliveriesList());

      expect(find.text('Vse (2)'), findsOneWidget);
      await tester.tap(find.text('MB (1)'));
      await tester.pump();
      expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
      expect(find.text('1 naročilo'), findsOneWidget);
    });
  });
}

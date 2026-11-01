import 'package:aladin/data/providers.dart';
import 'package:aladin/data/seed.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/enums.dart';
import 'package:aladin/models/order.dart';
import 'package:aladin/ui/orders/order_detail_screen.dart';
import 'package:aladin/ui/orders/orders_screen.dart';
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
      overrides: [
        storeProvider.overrideWithValue(store),
        // Pripravljeno / Dostave so odvisne od današnjega dne; periodični
        // časovnik ure bi po testu ostal viseti.
        minuteClockProvider.overrideWith((ref) => Stream.value(DateTime.now())),
      ],
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
    /// Število v zavihku Za dostavo / Ni klicano / Klicano: prvo besedilo v
    /// stolpcu, v katerem je napis zavihka.
    String tabCount(WidgetTester tester, String label) {
      final cell = find
          .ancestor(of: find.text(label), matching: find.byType(Column))
          .first;
      final count = find.descendant(of: cell, matching: find.byType(Text)).first;
      return tester.widget<Text>(count).data!;
    }

    testWidgets('trije zavihki s števci; seznam je viden brez razpiranja', (
      tester,
    ) async {
      final collect = ready(); // osebni prevzem, ni klicano
      final delivery = ready(channel: OrderChannel.delivery); // za dostavo
      await pump(tester, const ReadyList());

      expect(tabCount(tester, 'Za dostavo'), '1');
      expect(tabCount(tester, 'Ni klicano'), '1');
      expect(tabCount(tester, 'Klicano'), '0');
      // Prazen zavihek ni skrit — števec 0 je informacija.
      expect(find.text('Klicano'), findsOneWidget);

      // Privzeto je izbran Za dostavo in njegov seznam je takoj viden.
      expect(find.textContaining(delivery.id), findsOneWidget);
      expect(find.text('V kombi'), findsOneWidget);
      expect(find.textContaining(collect.id), findsNothing);
      expect(find.text('1 naročilo'), findsOneWidget);
    });

    testWidgets('klik na zavihek takoj zamenja seznam', (tester) async {
      final collect = ready();
      final delivery = ready(channel: OrderChannel.delivery);
      await pump(tester, const ReadyList());

      await tester.tap(find.text('Ni klicano'));
      await tester.pump();
      expect(find.textContaining(collect.id), findsOneWidget);
      expect(find.text('Pokliči'), findsOneWidget);
      expect(find.textContaining(delivery.id), findsNothing);
      expect(find.text('V kombi'), findsNothing);

      await tester.tap(find.text('Za dostavo'));
      await tester.pump();
      expect(find.textContaining(delivery.id), findsOneWidget);
      expect(find.textContaining(collect.id), findsNothing);
    });

    testWidgets('vrstni red: filtri regij → zavihki → seznam', (tester) async {
      final delivery = ready(channel: OrderChannel.delivery);
      ready();
      await pump(tester, const ReadyList());

      final pills = tester.getTopLeft(find.text('Vse (2)')).dy;
      final tabs = tester.getTopLeft(find.text('Za dostavo')).dy;
      final row = tester.getTopLeft(find.textContaining(delivery.id)).dy;
      expect(pills, lessThan(tabs));
      expect(tabs, lessThan(row));
    });

    testWidgets('izbrani zavihek ostane, ko se vrneš na seznam', (
      tester,
    ) async {
      ready();
      await pump(tester, const ReadyList());
      await tester.tap(find.text('Ni klicano'));
      await tester.pump();

      await pump(tester, const SizedBox());
      await pump(tester, const ReadyList());
      expect(find.text('Pokliči'), findsOneWidget);
    });

    testWidgets('regija in zavihek se ujemata: LJ + Ni klicano', (
      tester,
    ) async {
      final lj = ready();
      final mb = ready(location: OrderLocation.maribor, name: 'Marija Kovač');
      final mbDelivery = ready(
        location: OrderLocation.maribor,
        channel: OrderChannel.delivery,
        name: 'Janez Novak',
      );
      await pump(tester, const ReadyList());

      for (final l in OrderLocation.values) {
        expect(find.textContaining('${l.code} ('), findsOneWidget);
      }
      await tester.tap(find.text('Ni klicano'));
      await tester.pump();
      expect(tabCount(tester, 'Ni klicano'), '2');
      expect(find.textContaining(lj.id), findsOneWidget);
      expect(find.textContaining(mb.id), findsOneWidget);

      // Regija omeji seznam IN števce zavihkov.
      await tester.tap(find.text('LJ (1)'));
      await tester.pump();
      expect(tabCount(tester, 'Ni klicano'), '1');
      expect(tabCount(tester, 'Za dostavo'), '0');
      expect(find.textContaining(lj.id), findsOneWidget);
      expect(find.textContaining(mb.id), findsNothing);
      expect(find.text('1 naročilo'), findsOneWidget);

      await tester.tap(find.text('MB (2)'));
      await tester.pump();
      expect(tabCount(tester, 'Ni klicano'), '1');
      expect(tabCount(tester, 'Za dostavo'), '1');
      expect(find.textContaining(mb.id), findsOneWidget);
      expect(find.textContaining(lj.id), findsNothing);

      // Zavihek velja naprej, regija se ne izgubi.
      await tester.tap(find.text('Za dostavo'));
      await tester.pump();
      expect(find.textContaining(mbDelivery.id), findsOneWidget);
      expect(find.textContaining(mb.id), findsNothing);
    });

    testWidgets('prazen zavihek v regiji pove, katere regije ni', (
      tester,
    ) async {
      ready();
      await pump(tester, const ReadyList());

      await tester.ensureVisible(find.text('CE (0)'));
      await tester.tap(find.text('CE (0)'));
      await tester.pump();
      expect(find.text('V regiji CE ni takih naročil.'), findsOneWidget);
      // Filtri in zavihki ostanejo, da lahko regijo takoj zamenjaš.
      expect(find.text('Ni klicano'), findsOneWidget);
      expect(find.text('Vse (1)'), findsOneWidget);
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
      expect(tabCount(tester, 'Ni klicano'), '0');
      expect(tabCount(tester, 'Klicano'), '1');
      expect(find.text('Ni neklicanih strank'), findsOneWidget);

      await tester.tap(find.text('Klicano'));
      await tester.pump();
      expect(find.textContaining(order.id), findsOneWidget);
      expect(find.textContaining('čaka stranko'), findsOneWidget);
    });

    testWidgets('znotraj zavihka so naročila po ID-ju, ne po pripravi', (
      tester,
    ) async {
      final repo = container.read(repositoryProvider.notifier);
      final customer = repo.state.customers.first;
      final orders = [
        for (var i = 0; i < 2; i++)
          repo.createOrder(
            customer: customer,
            location: OrderLocation.ljubljana,
            channel: OrderChannel.dropoff,
            handover: HandoverMode.customerCollects,
            itemCount: 1,
          ),
      ];
      final type = repo.state.rugTypes.first;
      // Višji ID je pripravljen prvi.
      for (final o in orders.reversed) {
        repo.markOrderPickedUp(o.id);
        final item = repo.state.itemsOf(o.id).single;
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
      await pump(tester, const ReadyList());
      await tester.tap(find.text('Ni klicano'));
      await tester.pump();

      final low = tester.getTopLeft(find.text(orders.first.id).first).dy;
      final high = tester.getTopLeft(find.text(orders.last.id).first).dy;
      expect(low, lessThan(high));
    });

    testWidgets('V kombi pokaže Razveljavi, ki ne obvisi', (tester) async {
      final order = ready(channel: OrderChannel.delivery);
      await pump(tester, const ReadyList());

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

  group('Naročila', () {
    testWidgets('zavihek Naročila in iskanje: po ID-ju, ne po terminu', (
      tester,
    ) async {
      final repo = container.read(repositoryProvider.notifier);
      final customer = repo.state.customers.first;
      final now = DateTime.now();
      // Nižji ID ima poznejši termin prevzema.
      final low = repo.createOrder(
        customer: customer,
        location: OrderLocation.ljubljana,
        channel: OrderChannel.delivery,
        handover: HandoverMode.weDeliver,
        itemCount: 1,
        pickupAt: now.add(const Duration(days: 3)),
      );
      final high = repo.createOrder(
        customer: customer,
        location: OrderLocation.ljubljana,
        channel: OrderChannel.delivery,
        handover: HandoverMode.weDeliver,
        itemCount: 1,
        pickupAt: now.add(const Duration(days: 1)),
      );
      await pump(tester, const OrdersScreen());

      double dy(String id) => tester.getTopLeft(find.text(id).first).dy;
      expect(dy(low.id), lessThan(dy(high.id)));

      await tester.enterText(find.byType(TextField), 'LJ-');
      await tester.pump();
      expect(dy(low.id), lessThan(dy(high.id)));
    });

    testWidgets('zavihek Naročila ima filtre regij, ki samo omejijo seznam', (
      tester,
    ) async {
      final repo = container.read(repositoryProvider.notifier);
      final customer = repo.state.customers.first;
      WorkOrder planned(OrderLocation location) => repo.createOrder(
        customer: customer,
        location: location,
        channel: OrderChannel.delivery,
        handover: HandoverMode.weDeliver,
        itemCount: 1,
        pickupAt: DateTime.now().add(const Duration(days: 1)),
      );
      final lj = planned(OrderLocation.ljubljana);
      final mb = planned(OrderLocation.maribor);
      await pump(tester, const OrdersScreen());

      // Isti filtri kot v Pripravljeno: Vse + vse regije, s števci.
      expect(find.text('Vse (2)'), findsOneWidget);
      for (final l in OrderLocation.values) {
        expect(find.textContaining('${l.code} ('), findsOneWidget);
      }
      expect(find.textContaining(lj.id), findsOneWidget);
      expect(find.textContaining(mb.id), findsOneWidget);
      expect(find.text('2 naročili'), findsOneWidget);

      await tester.tap(find.text('MB (1)'));
      await tester.pump();
      expect(find.textContaining(mb.id), findsOneWidget);
      expect(find.textContaining(lj.id), findsNothing);
      expect(find.text('1 naročilo'), findsOneWidget);

      await tester.ensureVisible(find.text('CE (0)'));
      await tester.tap(find.text('CE (0)'));
      await tester.pump();
      expect(find.text('V regiji CE ni novih naročil.'), findsOneWidget);

      // Vse spet pokaže vse; filter ni spremenil podatkov. (Vrstica se je ob
      // CE odmaknila v desno, zato Vse najprej pripeljemo nazaj v pogled.)
      await tester.ensureVisible(find.text('Vse (2)'));
      await tester.tap(find.text('Vse (2)'));
      await tester.pump();
      expect(find.textContaining(lj.id), findsOneWidget);
      expect(find.textContaining(mb.id), findsOneWidget);
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

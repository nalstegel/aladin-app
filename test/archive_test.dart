import 'dart:convert';

import 'package:aladin/data/alerts.dart';
import 'package:aladin/data/order_phases.dart';
import 'package:aladin/data/providers.dart';
import 'package:aladin/data/repository.dart';
import 'package:aladin/data/seed.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/enums.dart';
import 'package:aladin/models/order.dart';
import 'package:aladin/models/return_proof.dart';
import 'package:aladin/models/rug_item.dart';
import 'package:aladin/ui/more/archive_screen.dart';
import 'package:aladin/ui/more/more_screen.dart';
import 'package:aladin/ui/more/stats_screen.dart';
import 'package:aladin/ui/orders/order_detail_screen.dart';
import 'package:aladin/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Archive (Več → Arhiv): an archived order is out of every tab, counter,
/// alert and statistic, but nothing is deleted and it can be restored.
void main() {
  late InMemoryStore store;
  late ProviderContainer container;
  late Repository repo;

  setUp(() async {
    // Demo catalogue and customers, but no demo orders — so counters in the
    // tests count only what the test creates.
    store = InMemoryStore();
    await store.save(buildSeedState().copyWith(orders: [], items: []));
    container = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(store)],
    );
    repo = container.read(repositoryProvider.notifier);
    await repo.init();
    repo.setCurrentUser('u-marko');
  });

  tearDown(() => container.dispose());

  WorkOrder newOrder({
    int items = 1,
    HandoverMode handover = HandoverMode.customerCollects,
    DateTime? pickupAt,
    DateTime? pickupWindowEnd,
    String? customerName,
    String phone = '',
  }) {
    final customer = customerName == null
        ? repo.state.customers.first
        : repo.createCustomer(
            type: CustomerType.private,
            name: customerName,
            phone: phone,
          );
    return repo.createOrder(
      customer: customer,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.dropoff,
      handover: handover,
      itemCount: items,
      pickupAt: pickupAt,
      pickupWindowEnd: pickupWindowEnd,
    );
  }

  /// Takes item [n] all the way to Pripravljeno (Volna 200 × 300 cm = 90 €).
  RugItem priced(WorkOrder order, int n) {
    final id = '${order.id}-$n';
    repo.markOrderPickedUp(order.id);
    repo.advance(id);
    repo.finishRugFromDrying(
      id,
      widthCm: 200,
      lengthCm: 300,
      rugType: repo.state.rugTypes.firstWhere((t) => t.name.startsWith('Volna')),
      extras: const [],
      discountPercent: 0,
    );
    return repo.state.item(id)!;
  }

  WorkOrder completed() {
    final order = newOrder();
    final item = priced(order, 1);
    repo.completeReturn(
      order.id,
      ReturnProof(
        returnedAt: DateTime.now(),
        userId: 'u-marko',
        userName: 'Marko',
        scannedItemIds: [item.id],
        receivedByName: 'Janez Novak',
        overrideReason: 'Customer was in a hurry',
        overrideByName: 'Nal',
      ),
    );
    return repo.state.order(order.id)!;
  }

  WorkOrder current(WorkOrder o) => repo.state.order(o.id)!;

  group('repository', () {
    test('archiving sets only the flag; nothing is deleted or changed', () {
      final order = newOrder(items: 2);
      priced(order, 1);
      final itemsBefore = repo.state.itemsOf(order.id);
      final totalBefore = repo.state.orderTotal(order.id);
      final statusBefore = current(order).status;
      expect(statusBefore, OrderStatus.inProduction);

      expect(repo.archiveOrder(order.id), isTrue);

      final archived = current(order);
      expect(archived.isArchived, isTrue);
      expect(archived.archivedAt, isNotNull);
      expect(archived.status, statusBefore);
      expect(repo.state.itemsOf(order.id), itemsBefore);
      expect(repo.state.orderTotal(order.id), totalBefore);
      expect(repo.state.item('${order.id}-1')!.history, isNotEmpty);
    });

    test('restoring returns the order exactly as it was', () {
      final order = newOrder(handover: HandoverMode.weDeliver);
      priced(order, 1);
      repo.sendToVan(order.id);
      final before = jsonEncode(current(order).toJson());
      expect(current(order).isInVan, isTrue);

      repo.archiveOrder(order.id);
      expect(current(order).isInVan, isFalse);
      expect(repo.unarchiveOrder(order.id), isTrue);

      expect(jsonEncode(current(order).toJson()), before);
      expect(current(order).isInVan, isTrue);
    });

    test('only an open order can be archived', () {
      final done = completed();
      expect(done.status, OrderStatus.completed);
      expect(repo.archiveOrder(done.id), isFalse);
      expect(current(done).isArchived, isFalse);

      expect(repo.archiveOrder('XX-999'), isFalse);

      final order = newOrder();
      expect(repo.archiveOrder(order.id), isTrue);
      final firstAt = current(order).archivedAt;
      expect(repo.archiveOrder(order.id), isFalse);
      expect(current(order).archivedAt, firstAt);

      expect(repo.unarchiveOrder(newOrder().id), isFalse);
      expect(repo.unarchiveOrder('XX-999'), isFalse);
    });

    test('an archived order is in no tab, counter or list', () {
      final intake = newOrder();
      final washing = newOrder(items: 2);
      repo.markOrderPickedUp(washing.id);
      final inVan = newOrder(handover: HandoverMode.weDeliver);
      priced(inVan, 1);
      repo.sendToVan(inVan.id);
      final ready = newOrder();
      priced(ready, 1);

      Map<OrderPhase, int> counts() => phaseCounts(repo.state);
      expect(counts()[OrderPhase.intake], 1);
      expect(counts()[OrderPhase.washing], 2); // pieces, not orders
      expect(counts()[OrderPhase.ready], 1);
      expect(counts()[OrderPhase.deliveries], 1);
      expect(container.read(productionCountsProvider)[RugStatus.awaitingWash], 2);

      for (final o in [intake, washing, inVan, ready]) {
        expect(repo.archiveOrder(o.id), isTrue);
      }

      expect(counts().values.every((n) => n == 0), isTrue);
      expect(
        container.read(productionCountsProvider).values.every((n) => n == 0),
        isTrue,
      );
      expect(groupsFor(repo.state, OrderPhase.washing), isEmpty);
      expect(groupsFor(repo.state, OrderPhase.drying), isEmpty);
      expect(
        container.read(ordersByChannelProvider(OrderChannel.dropoff)),
        isEmpty,
      );
      for (final phase in OrderPhase.values) {
        expect(
          phase.containsOrder(current(washing), repo.state.itemsOf(washing.id)),
          isFalse,
          reason: '$phase',
        );
      }
      expect(repo.state.archivedOrders.map((o) => o.id),
          [intake.id, washing.id, inVan.id, ready.id]);

      // And back: the order is counted again.
      repo.unarchiveOrder(washing.id);
      expect(counts()[OrderPhase.washing], 2);
    });

    test('the Danes blocks ignore archived orders', () {
      // The window end keeps today's pickup from already counting as late.
      final pickupToday = newOrder(
        pickupAt: DateTime.now(),
        pickupWindowEnd: DateTime.now().add(const Duration(hours: 1)),
      );
      final pickupLate = newOrder(
        pickupAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      final notCalled = newOrder();
      priced(notCalled, 1);
      final all = [pickupToday, pickupLate, notCalled];

      expect(container.read(todayPickupsProvider).length, 2);
      expect(container.read(actionNeededProvider).pickupLate.length, 1);
      expect(container.read(actionNeededProvider).notCalled.length, 1);

      for (final o in all) {
        repo.archiveOrder(o.id);
      }

      expect(container.read(todayPickupsProvider), isEmpty);
      expect(container.read(actionNeededProvider).total, 0);
      expect(current(pickupLate).isPickupOverdue(DateTime.now()), isFalse);
    });

    test('no bell alerts for archived orders', () {
      final uncalled = newOrder();
      priced(uncalled, 1);
      final inVan = newOrder(handover: HandoverMode.weDeliver);
      priced(inVan, 1);
      repo.sendToVan(inVan.id);
      final pickup = newOrder(pickupAt: DateTime.now());

      // 25 h later (past the 24 h limit), after the end of the workday.
      final now = DateTime.now().add(const Duration(hours: 25));
      List<Alert> alerts() =>
          buildAlerts(repo.state.orders, now, workdayEnd: 0);
      expect(
        alerts().map((a) => a.kind).toSet(),
        {AlertKind.uncalled, AlertKind.vanLeft, AlertKind.daySummary},
      );

      for (final o in [uncalled, inVan, pickup]) {
        repo.archiveOrder(o.id);
      }

      expect(alerts(), isEmpty);
    });

    test('a scan cannot move an item of an archived order', () {
      final order = newOrder();
      repo.markOrderPickedUp(order.id);
      final id = '${order.id}-1';
      repo.archiveOrder(order.id);

      expect(repo.advance(id), isFalse);
      expect(repo.state.item(id)!.status, RugStatus.awaitingWash);

      repo.unarchiveOrder(order.id);
      expect(repo.advance(id), isTrue);
      expect(repo.state.item(id)!.status, RugStatus.drying);
    });

    test('a call to an archived order is not recorded as Klicano', () {
      final order = newOrder();
      priced(order, 1);
      repo.archiveOrder(order.id);

      repo.markCalled(order.id);

      expect(current(order).calledAt, isNull);
    });

    test("a customer's history leaves archived orders out", () {
      final customer = repo.state.customers.first;
      final kept = newOrder();
      final archived = newOrder();
      repo.archiveOrder(archived.id);

      expect(repo.state.ordersOf(customer.id).map((o) => o.id), [kept.id]);
    });

    test('the archive survives a save and an old document has no archive', () async {
      final order = newOrder();
      repo.archiveOrder(order.id);

      final saved = await store.load();
      expect(saved!.order(order.id)!.isArchived, isTrue);
      expect(saved.order(order.id)!.archivedAt, current(order).archivedAt);

      repo.unarchiveOrder(order.id);
      expect((await store.load())!.order(order.id)!.isArchived, isFalse);

      final json = order.toJson()..remove('archivedAt');
      expect(WorkOrder.fromJson(json).isArchived, isFalse);
    });
  });

  group('screens', () {
    /// A tall screen, so everything is visible without scrolling.
    void tallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    /// The screen goes on top of a "root" screen, as in the real app.
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

    group('Več', () {
      testWidgets('every employee sees Arhiv and it opens the archive', (
        tester,
      ) async {
        tallScreen(tester);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: MoreScreen()),
          ),
        );

        await tester.tap(find.text('Arhiv'));
        await tester.pumpAndSettle();

        expect(find.text('Arhiv je prazen'), findsOneWidget);
      });
    });

    group('Arhiv', () {
      testWidgets('lists archived orders only, smallest ID first', (
        tester,
      ) async {
        final first = newOrder(customerName: 'Ana Kovač');
        final second = newOrder(customerName: 'Borut Zupan');
        newOrder(customerName: 'Cene Active');
        repo.archiveOrder(second.id);
        repo.archiveOrder(first.id);

        await show(tester, const ArchiveScreen());

        expect(find.text(first.number), findsOneWidget);
        expect(find.text(second.number), findsOneWidget);
        expect(find.text('Cene Active'), findsNothing);
        expect(find.text('2 naročili'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text(first.number)).dy,
          lessThan(tester.getTopLeft(find.text(second.number)).dy),
        );
      });

      testWidgets('search by ID, name (without diacritics) and phone', (
        tester,
      ) async {
        final ana = newOrder(customerName: 'Ana Kovač', phone: '041 111 222');
        final borut = newOrder(
          customerName: 'Borut Zupan',
          phone: '051 333 444',
        );
        repo.archiveOrder(ana.id);
        repo.archiveOrder(borut.id);
        await show(tester, const ArchiveScreen());

        Future<void> search(String q) async {
          await tester.enterText(find.byType(TextField), q);
          await tester.pump();
        }

        await search(borut.number);
        expect(find.text('Ana Kovač'), findsNothing);
        expect(find.text('Borut Zupan'), findsOneWidget);

        await search('kovac');
        expect(find.text('Ana Kovač'), findsOneWidget);
        expect(find.text('Borut Zupan'), findsNothing);

        await search('051 333');
        expect(find.text('Ana Kovač'), findsNothing);
        expect(find.text('Borut Zupan'), findsOneWidget);

        await search('zzz');
        expect(find.text('Ni zadetkov'), findsOneWidget);

        await search('');
        expect(find.text('Ana Kovač'), findsOneWidget);
        expect(find.text('Borut Zupan'), findsOneWidget);
      });

      testWidgets('Vrni iz arhiva restores the order; Razveljavi archives it', (
        tester,
      ) async {
        final order = newOrder(items: 2);
        repo.markOrderPickedUp(order.id);
        repo.archiveOrder(order.id);
        await show(tester, const ArchiveScreen());

        await tester.tap(find.text('Vrni iz arhiva'));
        await tester.pumpAndSettle();

        expect(current(order).isArchived, isFalse);
        expect(phaseCounts(repo.state)[OrderPhase.washing], 2);
        expect(find.text('Arhiv je prazen'), findsOneWidget);
        expect(find.text('${order.number} je spet v poteku.'), findsOneWidget);

        await tester.tap(find.text('Razveljavi'));
        await tester.pumpAndSettle();

        expect(current(order).isArchived, isTrue);
        expect(phaseCounts(repo.state)[OrderPhase.washing], 0);
      });
    });

    group('order detail', () {
      testWidgets('Premakni v arhiv asks first, then archives and goes back', (
        tester,
      ) async {
        final order = newOrder(items: 2);
        await show(tester, OrderDetailScreen(orderId: order.id));
        expect(find.text('Premakni v arhiv'), findsOneWidget);

        await tester.tap(find.text('Premakni v arhiv'));
        await tester.pumpAndSettle();
        expect(find.text('Premakni naročilo v arhiv?'), findsOneWidget);

        // Cancel archives nothing.
        await tester.tap(find.text('Prekliči'));
        await tester.pumpAndSettle();
        expect(current(order).isArchived, isFalse);
        expect(find.text('Naročilo ${order.number}'), findsOneWidget);

        await tester.tap(find.text('Premakni v arhiv'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Premakni'));
        await tester.pumpAndSettle();

        expect(current(order).isArchived, isTrue);
        expect(repo.state.itemsOf(order.id), hasLength(2));
        expect(find.text('root'), findsOneWidget);
        expect(find.text('${order.number} je v arhivu.'), findsOneWidget);

        await tester.tap(find.text('Razveljavi'));
        await tester.pumpAndSettle();
        expect(current(order).isArchived, isFalse);
      });

      testWidgets('a completed order cannot be archived from the detail', (
        tester,
      ) async {
        final done = completed();

        await show(tester, OrderDetailScreen(orderId: done.id));

        expect(find.text('Premakni v arhiv'), findsNothing);
      });

      testWidgets('an archived order is read-only and can be restored', (
        tester,
      ) async {
        final order = newOrder(items: 2);
        await show(tester, OrderDetailScreen(orderId: order.id));
        expect(find.text('Prevzeto v delavnico'), findsOneWidget);
        expect(find.byTooltip('Uredi naročilo'), findsOneWidget);

        repo.archiveOrder(order.id);
        await tester.pumpAndSettle();

        expect(find.textContaining('V arhivu od'), findsOneWidget);
        expect(find.text('Vrni iz arhiva'), findsOneWidget);
        expect(find.text('Premakni v arhiv'), findsNothing);
        expect(find.text('Prevzeto v delavnico'), findsNothing);
        expect(find.byTooltip('Uredi naročilo'), findsNothing);
        expect(find.byTooltip('Izbriši naročilo'), findsNothing);
        expect(find.text('Dodaj kos'), findsNothing);
        // Data stays readable.
        expect(find.text('${order.id}-1'), findsOneWidget);

        await tester.tap(find.text('Vrni iz arhiva'));
        await tester.pumpAndSettle();

        expect(current(order).isArchived, isFalse);
        expect(find.textContaining('V arhivu od'), findsNothing);
        expect(find.text('Premakni v arhiv'), findsOneWidget);
      });
    });

    testWidgets('statistics do not count archived orders', (tester) async {
      final kept = newOrder();
      final archived = newOrder();
      priced(kept, 1);
      priced(archived, 1);
      repo.setCurrentUser('u-nal');

      String? active() => tester
          .widgetList<StatTile>(find.byType(StatTile))
          .where((t) => t.label == 'aktivnih')
          .firstOrNull
          ?.value;

      await show(tester, const StatsScreen());
      expect(active(), '2');

      repo.archiveOrder(archived.id);
      await tester.pumpAndSettle();

      expect(active(), '1');
    });
  });
}

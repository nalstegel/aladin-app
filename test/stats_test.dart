import 'package:aladin/core/format.dart';
import 'package:aladin/data/app_state.dart';
import 'package:aladin/data/providers.dart';
import 'package:aladin/data/stats.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/catalog.dart';
import 'package:aladin/models/enums.dart';
import 'package:aladin/models/order.dart';
import 'package:aladin/models/rug_item.dart';
import 'package:aladin/models/status_event.dart';
import 'package:aladin/ui/more/stats_screen.dart';
import 'package:aladin/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Več → Statistika in promet (plan.md §4.18). The logic is a pure function of
/// the app state, so most tests build a state with explicit timestamps and a
/// fixed "now" instead of going through the repository.
void main() {
  // Wednesday: the week is Mon 2 Nov – Sun 8 Nov, the month is November.
  final now = DateTime(2026, 11, 4, 12);
  final nov = StatsRange.month(now);
  final oct = StatsRange.month(DateTime(2026, 10, 15));

  DateTime at(int month, int day, [int hour = 10]) =>
      DateTime(2026, month, day, hour);

  StatusEvent ev(RugStatus s, DateTime when) =>
      StatusEvent(status: s, at: when, userId: 'u', userName: 'U');

  /// A piece with an explicit history. [price] is its confirmed price.
  RugItem rug(
    String orderId,
    int n,
    RugStatus status, {
    List<StatusEvent> history = const [],
    double price = 0,
    double m2 = 0,
    String type = 'Volna',
    int of = 1,
  }) => RugItem(
    id: '$orderId-$n',
    orderId: orderId,
    index: n,
    ofTotal: of,
    status: status,
    manualM2: m2 == 0 ? null : m2,
    rugTypeName: type,
    confirmedPrice: price,
    history: history,
  );

  /// Wash → ready, the usual path through the workshop.
  List<StatusEvent> madeReady(DateTime pickedUp, DateTime ready) => [
    ev(RugStatus.awaitingPickup, pickedUp.subtract(const Duration(hours: 1))),
    ev(RugStatus.awaitingWash, pickedUp),
    ev(RugStatus.ready, ready),
  ];

  WorkOrder order(
    String id,
    OrderStatus status, {
    OrderLocation location = OrderLocation.ljubljana,
    OrderChannel channel = OrderChannel.dropoff,
    DateTime? completedAt,
    DateTime? archivedAt,
    double fee = 0,
    int count = 1,
  }) => WorkOrder(
    id: id,
    location: location,
    channel: channel,
    handover: HandoverMode.customerCollects,
    status: status,
    customerId: 'c',
    customerName: 'Stranka',
    itemCount: count,
    createdAt: at(10, 1),
    completedAt: completedAt,
    archivedAt: archivedAt,
    deliveryFee: fee,
  );

  const types = [
    RugType(id: 't1', name: 'Sintetika', pricePerM2: 12),
    RugType(id: 't2', name: 'Shaggy', pricePerM2: 16),
    RugType(id: 't3', name: 'Volna', pricePerM2: 15),
    RugType(id: 't4', name: 'Perzijska', pricePerM2: 22),
  ];

  AppState world(List<WorkOrder> orders, List<RugItem> items) =>
      AppState(orders: orders, items: items, rugTypes: types);

  DashboardStats stats(AppState s, {StatsRange? period, DateTime? clock}) =>
      computeStats(s, now: clock ?? now, period: period ?? nov);

  group('StatsRange', () {
    test('a week runs Monday to Sunday: Sunday belongs to the week before', () {
      final week = StatsRange.week(DateTime(2026, 11, 8, 23)); // Sunday
      expect(week.from, DateTime(2026, 11, 2));
      expect(week.to, DateTime(2026, 11, 9));
      expect(StatsRange.week(DateTime(2026, 11, 2)), week);
      expect(
        StatsRange.week(DateTime(2026, 11, 9)).from,
        DateTime(2026, 11, 9),
      );
    });

    test('a month rolls over into the next year', () {
      final dec = StatsRange.month(DateTime(2026, 12, 15));
      expect(dec.from, DateTime(2026, 12));
      expect(dec.to, DateTime(2027));
    });

    test('a custom range includes both end days, in either order', () {
      final r = StatsRange.days(
        DateTime(2026, 11, 5, 18),
        DateTime(2026, 11, 3),
      );
      expect(r.from, DateTime(2026, 11, 3));
      expect(r.to, DateTime(2026, 11, 6));
      expect(r.lastDay, DateTime(2026, 11, 5));
    });

    test(
      'contains is half-open: the start day is in, midnight after is out',
      () {
        final day = StatsRange.day(now);
        expect(day.contains(DateTime(2026, 11, 4)), isTrue);
        expect(day.contains(DateTime(2026, 11, 4, 23, 59, 59)), isTrue);
        expect(day.contains(DateTime(2026, 11, 5)), isFalse);
        expect(day.contains(DateTime(2026, 11, 3, 23, 59, 59)), isFalse);
      },
    );

    test('calendar days ignore the clock time and the DST change', () {
      // Europe goes back to winter time on Sun 25 Oct 2026.
      expect(
        calendarDaysBetween(
          DateTime(2026, 10, 24, 22),
          DateTime(2026, 10, 26, 1),
        ),
        2,
      );
      expect(
        calendarDaysBetween(
          DateTime(2026, 11, 1, 23),
          DateTime(2026, 11, 4, 0),
        ),
        3,
      );
      expect(calendarDaysBetween(now, now), 0);
    });
  });

  group('realiziran promet', () {
    test('counts returned orders by their full bill, never open ones', () {
      final s = world(
        [
          // 20 € of rugs, but a delivery order has a 50 € minimum.
          order(
            'LJ-1',
            OrderStatus.completed,
            channel: OrderChannel.delivery,
            completedAt: at(10, 20),
          ),
          order(
            'LJ-2',
            OrderStatus.completed,
            completedAt: at(11, 2),
            count: 2,
          ),
          order('LJ-3', OrderStatus.awaitingCollection),
        ],
        [
          rug('LJ-1', 1, RugStatus.returned, price: 20),
          rug('LJ-2', 1, RugStatus.returned, price: 40, of: 2),
          rug('LJ-2', 2, RugStatus.returned, price: 60, of: 2),
          rug('LJ-3', 1, RugStatus.ready, price: 30),
        ],
      );
      final r = stats(s);

      expect(r.revenue, closeTo(150, 0.001));
      expect(r.completedOrders, 2);
      expect(r.averageOrder, closeTo(75, 0.001));
      // Only LJ-2 was returned in November.
      expect(r.monthRevenue, closeTo(100, 0.001));
      expect(r.monthOrders, 1);
    });

    test('order finished on 30 Oct and returned on 2 Nov: production in '
        'October, revenue in November', () {
      final s = world(
        [
          order(
            'LJ-1',
            OrderStatus.completed,
            completedAt: at(11, 2),
            count: 2,
          ),
        ],
        [
          rug(
            'LJ-1',
            1,
            RugStatus.returned,
            price: 60,
            m2: 4,
            of: 2,
            history: madeReady(at(10, 28), at(10, 29)),
          ),
          rug(
            'LJ-1',
            2,
            RugStatus.returned,
            price: 90,
            m2: 6,
            of: 2,
            history: madeReady(at(10, 28), at(10, 30)),
          ),
        ],
      );

      final october = stats(s, period: oct, clock: at(10, 31));
      expect(october.producedPieces, 2);
      expect(october.producedOrders, 1);
      expect(october.producedValue, closeTo(150, 0.001));
      expect(october.monthRevenue, 0, reason: 'not returned until 2 Nov');

      final november = stats(s);
      expect(november.producedPieces, 0);
      expect(november.producedOrders, 0);
      expect(november.monthRevenue, closeTo(150, 0.001));
      expect(november.monthOrders, 1);
    });

    test('archived and cancelled orders are in no figure', () {
      final s = world(
        [
          order('LJ-1', OrderStatus.awaitingCollection, archivedAt: at(11, 1)),
          order('LJ-2', OrderStatus.cancelled),
        ],
        [
          rug(
            'LJ-1',
            1,
            RugStatus.ready,
            price: 90,
            m2: 6,
            history: madeReady(at(11, 2), at(11, 3)),
          ),
          rug(
            'LJ-2',
            1,
            RugStatus.ready,
            price: 40,
            history: madeReady(at(11, 2), at(11, 3)),
          ),
        ],
      );
      final r = stats(s);

      expect(r.openOrders, 0);
      expect(r.openValue, 0);
      expect(r.shelfPieces, 0);
      expect(r.producedPieces, 0);
      expect(r.producedOrders, 0);
    });
  });

  group('proizvodnja', () {
    test('a piece counts once, on the day it FIRST became ready', () {
      final s = world(
        [order('LJ-1', OrderStatus.awaitingCollection)],
        [
          rug(
            'LJ-1',
            1,
            RugStatus.ready,
            price: 60,
            m2: 4,
            history: [
              ev(RugStatus.awaitingWash, at(10, 20)),
              ev(RugStatus.ready, at(10, 25)),
              ev(RugStatus.awaitingWash, at(10, 26)), // sent back to wash
              ev(RugStatus.ready, at(11, 3)),
            ],
          ),
        ],
      );

      expect(stats(s, period: oct).producedPieces, 1);
      expect(stats(s, period: nov).producedPieces, 0);
    });

    test('pieces count on their own day, the order on its last piece', () {
      final s = world(
        [order('LJ-1', OrderStatus.awaitingCollection, count: 2)],
        [
          rug(
            'LJ-1',
            1,
            RugStatus.ready,
            price: 60,
            m2: 4,
            of: 2,
            history: madeReady(at(10, 28), at(10, 30)),
          ),
          rug(
            'LJ-1',
            2,
            RugStatus.ready,
            price: 90,
            m2: 6,
            of: 2,
            history: madeReady(at(10, 28), at(11, 3)),
          ),
        ],
      );

      final october = stats(s, period: oct);
      expect(october.producedPieces, 1);
      expect(october.producedOrders, 0, reason: 'second piece not ready yet');
      expect(october.producedM2, closeTo(4, 0.001));
      expect(october.producedValue, closeTo(60, 0.001));

      final november = stats(s);
      expect(november.producedPieces, 1);
      expect(november.producedOrders, 1);
      expect(november.producedM2, closeTo(6, 0.001));
      expect(november.producedValue, closeTo(90, 0.001));
    });

    test('an order with a piece still in the workshop is not finished', () {
      final s = world(
        [order('LJ-1', OrderStatus.inProduction, count: 2)],
        [
          rug(
            'LJ-1',
            1,
            RugStatus.ready,
            price: 60,
            m2: 4,
            of: 2,
            history: madeReady(at(11, 2), at(11, 3)),
          ),
          rug(
            'LJ-1',
            2,
            RugStatus.drying,
            of: 2,
            history: [ev(RugStatus.awaitingWash, at(11, 2))],
          ),
        ],
      );
      final r = stats(s);

      expect(r.producedPieces, 1);
      expect(r.producedOrders, 0);
    });

    test('today means the calendar day, midnight to midnight', () {
      final s = world(
        [order('LJ-1', OrderStatus.awaitingCollection, count: 3)],
        [
          rug(
            'LJ-1',
            1,
            RugStatus.ready,
            of: 3,
            history: madeReady(
              DateTime(2026, 11, 3, 8),
              DateTime(2026, 11, 3, 23, 59),
            ),
          ),
          rug(
            'LJ-1',
            2,
            RugStatus.ready,
            of: 3,
            history: madeReady(DateTime(2026, 11, 3, 8), DateTime(2026, 11, 4)),
          ),
          rug(
            'LJ-1',
            3,
            RugStatus.ready,
            of: 3,
            history: madeReady(
              DateTime(2026, 11, 3, 8),
              DateTime(2026, 11, 4, 9),
            ),
          ),
        ],
      );

      expect(stats(s, period: StatsRange.day(now)).producedPieces, 2);
      expect(stats(s, period: StatsRange.week(now)).producedPieces, 3);
    });
  });

  group('pripravljeno na policah', () {
    test('counts pieces on the shelf, also from a half-ready order', () {
      final s = world(
        [
          order('LJ-1', OrderStatus.inProduction, count: 2),
          order('LJ-2', OrderStatus.awaitingCollection, count: 2),
          order('LJ-3', OrderStatus.completed, completedAt: at(11, 2)),
          order('LJ-4', OrderStatus.awaitingCollection, archivedAt: at(11, 1)),
        ],
        [
          rug(
            'LJ-1',
            1,
            RugStatus.ready,
            price: 60,
            m2: 4,
            of: 2,
            history: madeReady(at(11, 2), at(11, 3)),
          ),
          rug('LJ-1', 2, RugStatus.drying, of: 2),
          rug(
            'LJ-2',
            1,
            RugStatus.ready,
            price: 90,
            m2: 6,
            of: 2,
            history: madeReady(at(11, 2), at(11, 3)),
          ),
          rug(
            'LJ-2',
            2,
            RugStatus.ready,
            price: 30,
            m2: 2,
            of: 2,
            history: madeReady(at(11, 2), at(11, 3)),
          ),
          rug('LJ-3', 1, RugStatus.returned, price: 500, m2: 9),
          rug(
            'LJ-4',
            1,
            RugStatus.ready,
            price: 700,
            m2: 9,
            history: madeReady(at(11, 2), at(11, 3)),
          ),
        ],
      );
      final r = stats(s);

      expect(r.shelfPieces, 3);
      expect(r.shelfOrders, 2);
      expect(r.shelfM2, closeTo(12, 0.001));
      expect(r.shelfValue, closeTo(180, 0.001));
    });

    test(
      'age buckets use calendar days since the LAST time it became ready',
      () {
        RugItem shelfPiece(
          int n,
          DateTime ready, {
          List<StatusEvent>? before,
        }) => rug(
          'LJ-1',
          n,
          RugStatus.ready,
          price: 10,
          of: 7,
          history: [...?before, ev(RugStatus.ready, ready)],
        );

        final s = world(
          [order('LJ-1', OrderStatus.inProduction, count: 7)],
          [
            shelfPiece(1, DateTime(2026, 11, 4, 8)), // today -> 0
            shelfPiece(2, DateTime(2026, 11, 1, 23)), // 3 days -> 0-3
            shelfPiece(3, DateTime(2026, 10, 31, 6)), // 4 days -> 4-7
            shelfPiece(4, DateTime(2026, 10, 28, 20)), // 7 days -> 4-7
            shelfPiece(5, DateTime(2026, 10, 27, 12)), // 8 days -> 8+
            // Ready long ago, sent back to wash, ready again yesterday.
            shelfPiece(
              6,
              DateTime(2026, 11, 3),
              before: [
                ev(RugStatus.ready, at(10, 1)),
                ev(RugStatus.awaitingWash, at(10, 2)),
              ],
            ),
            shelfPiece(7, DateTime(2026, 9, 1)),
          ],
        );
        final age = stats(s).shelfAge;

        expect(age.map((b) => b.label), ['0–3 dni', '4–7 dni', '8+ dni']);
        expect(age.map((b) => b.pieces), [3, 2, 2]);
        expect(age.fold<double>(0, (a, b) => a + b.value), closeTo(70, 0.001));
      },
    );

    test('V teku and Pripravljeno add up to all open orders', () {
      final s = world(
        [order('LJ-1', OrderStatus.inProduction, count: 2, fee: 10)],
        [
          rug(
            'LJ-1',
            1,
            RugStatus.ready,
            price: 60,
            m2: 4,
            of: 2,
            history: madeReady(at(11, 2), at(11, 3)),
          ),
          rug('LJ-1', 2, RugStatus.drying, of: 2),
        ],
      );
      final r = stats(s);

      expect(r.openValue, closeTo(70, 0.001), reason: '60 € piece + 10 € fee');
      expect(r.shelfValue, closeTo(60, 0.001));
      expect(r.inProgressValue, closeTo(10, 0.001));
      expect(r.openOrders, 1);
    });
  });

  group('trenutno delo', () {
    test('washing and drying count pieces like the tabs; "Mere in cena" is '
        'drying; archived orders do not count', () {
      final s = world(
        [
          order('LJ-1', OrderStatus.inProduction, count: 5),
          order('LJ-2', OrderStatus.inProduction, archivedAt: at(11, 1)),
        ],
        [
          rug('LJ-1', 1, RugStatus.awaitingWash, of: 5),
          rug('LJ-1', 2, RugStatus.awaitingWash, of: 5),
          rug('LJ-1', 3, RugStatus.drying, of: 5),
          rug('LJ-1', 4, RugStatus.finishing, of: 5),
          rug('LJ-1', 5, RugStatus.awaitingPickup, of: 5),
          rug('LJ-2', 1, RugStatus.awaitingWash),
          rug('LJ-2', 2, RugStatus.drying),
        ],
      );
      final r = stats(s);

      expect(r.washingPieces, 2);
      expect(r.dryingPieces, 2);
    });
  });

  group('povprečni časi', () {
    test('Prevzeto → Pripravljeno averages the pieces made ready in the '
        'period', () {
      final s = world(
        [order('LJ-1', OrderStatus.awaitingCollection, count: 5)],
        [
          // 24 h and 12 h -> 18 h.
          rug(
            'LJ-1',
            1,
            RugStatus.ready,
            of: 5,
            history: madeReady(at(11, 2), at(11, 3)),
          ),
          rug(
            'LJ-1',
            2,
            RugStatus.ready,
            of: 5,
            history: madeReady(at(11, 3, 8), at(11, 3, 20)),
          ),
          // Made ready in October: not in this period.
          rug(
            'LJ-1',
            3,
            RugStatus.ready,
            of: 5,
            history: madeReady(at(10, 1), at(10, 20)),
          ),
          // No pickup event (old data): nothing to measure from.
          rug(
            'LJ-1',
            4,
            RugStatus.ready,
            of: 5,
            history: [ev(RugStatus.ready, at(11, 3))],
          ),
        ],
      );
      final r = stats(s);

      expect(r.avgToReady, const Duration(hours: 18));
      expect(r.avgToReadyPieces, 2);
    });

    test('Pripravljeno → Vrnjeno counts from the last time it was ready, for '
        'pieces returned in the period', () {
      RugItem returned(int n, List<StatusEvent> h) =>
          rug('LJ-1', n, RugStatus.returned, of: 3, history: h);

      final s = world(
        [
          order(
            'LJ-1',
            OrderStatus.completed,
            completedAt: at(11, 4),
            count: 3,
          ),
        ],
        [
          // 2 days.
          returned(1, [
            ev(RugStatus.ready, at(11, 1)),
            ev(RugStatus.returned, at(11, 3)),
          ]),
          // Ready, sent back to wash, ready again 4 Nov: counts from there
          // (1 day), not from 1 Oct.
          returned(2, [
            ev(RugStatus.ready, at(10, 1)),
            ev(RugStatus.awaitingWash, at(10, 2)),
            ev(RugStatus.ready, at(11, 3)),
            ev(RugStatus.returned, at(11, 4)),
          ]),
          // Returned in October: another period.
          returned(3, [
            ev(RugStatus.ready, at(10, 1)),
            ev(RugStatus.returned, at(10, 30)),
          ]),
        ],
      );
      final r = stats(s);

      expect(r.avgToReturn, const Duration(hours: 36));
      expect(r.avgToReturnPieces, 2);
    });

    test('no data gives null, not zero', () {
      final r = stats(world(const [], const []));
      expect(r.avgToReady, isNull);
      expect(r.avgToReturn, isNull);
      expect(r.averageOrder, 0);
    });

    test('durations are shown short', () {
      expect(Fmt.duration(const Duration(minutes: 40)), '40 min');
      expect(Fmt.duration(const Duration(hours: 18, minutes: 30)), '18 h');
      expect(Fmt.duration(const Duration(hours: 36)), '1,5 d');
      expect(Fmt.duration(const Duration(days: 3)), '3,0 d');
    });
  });

  group('razrezi', () {
    final s = world(
      [
        order('LJ-1', OrderStatus.awaitingCollection),
        order(
          'MB-1',
          OrderStatus.awaitingCollection,
          location: OrderLocation.maribor,
          channel: OrderChannel.delivery,
          count: 2,
        ),
        order(
          'DOL-1',
          OrderStatus.inProduction,
          location: OrderLocation.dolenjska,
          channel: OrderChannel.delivery,
          count: 2,
        ),
      ],
      [
        rug(
          'LJ-1',
          1,
          RugStatus.ready,
          price: 100,
          m2: 5,
          type: 'Perzijska',
          history: madeReady(at(11, 2), at(11, 3)),
        ),
        rug(
          'MB-1',
          1,
          RugStatus.ready,
          price: 40,
          m2: 3,
          type: 'Volna',
          of: 2,
          history: madeReady(at(11, 2), at(11, 3)),
        ),
        rug(
          'MB-1',
          2,
          RugStatus.ready,
          price: 20,
          m2: 2,
          type: 'Volna',
          of: 2,
          history: madeReady(at(11, 2), at(11, 3)),
        ),
        // One piece of DOL-1 is ready, its sibling is not: a piece but no
        // finished order.
        rug(
          'DOL-1',
          1,
          RugStatus.ready,
          price: 30,
          m2: 3,
          type: 'Staro ime',
          of: 2,
          history: madeReady(at(11, 2), at(11, 3)),
        ),
        rug('DOL-1', 2, RugStatus.drying, of: 2),
      ],
    );

    test('by rug type: the whole catalogue in order, zeros included, plus '
        'names the catalogue no longer has', () {
      final byType = {for (final g in stats(s).byRugType) g.label: g};

      expect(stats(s).byRugType.map((g) => g.label), [
        'Sintetika',
        'Shaggy',
        'Volna',
        'Perzijska',
        'Staro ime',
      ]);
      expect(byType['Sintetika']!.pieces, 0);
      expect(byType['Volna']!.pieces, 2);
      expect(byType['Volna']!.m2, closeTo(5, 0.001));
      expect(byType['Volna']!.value, closeTo(60, 0.001));
      expect(byType['Perzijska']!.value, closeTo(100, 0.001));
      expect(byType['Staro ime']!.pieces, 1);
    });

    test('by region: LJ, MB, CE, DOL with orders and value', () {
      final byRegion = stats(s).byRegion;

      expect(byRegion.map((g) => g.label), ['LJ', 'MB', 'CE', 'DOL']);
      expect(byRegion.map((g) => g.orders), [1, 1, 0, 0]);
      expect(byRegion.map((g) => g.value), [100, 60, 0, 30]);
    });

    test('by channel: Naš prevzem vs Pripeljano; B2B only when used', () {
      final byChannel = stats(s).byChannel;

      expect(byChannel.map((g) => g.label), ['Naš prevzem', 'Pripeljano']);
      expect(byChannel.map((g) => g.orders), [1, 1]);
      expect(byChannel.map((g) => g.value), [90, 100]);

      final withB2b = world(
        [
          order(
            'LJ-9',
            OrderStatus.awaitingCollection,
            channel: OrderChannel.b2b,
          ),
        ],
        [
          rug(
            'LJ-9',
            1,
            RugStatus.ready,
            price: 10,
            history: madeReady(at(11, 2), at(11, 3)),
          ),
        ],
      );
      expect(stats(withB2b).byChannel.map((g) => g.label), [
        'Naš prevzem',
        'Pripeljano',
        'B2B',
      ]);
    });

    test('every breakdown adds up to the Proizvodnja figures', () {
      final r = stats(s);

      for (final rows in [r.byRugType, r.byRegion, r.byChannel]) {
        expect(
          rows.fold<double>(0, (a, g) => a + g.value),
          closeTo(r.producedValue, 0.001),
        );
      }
      for (final rows in [r.byRegion, r.byChannel]) {
        expect(rows.fold<int>(0, (a, g) => a + g.orders), r.producedOrders);
      }
      expect(
        r.byRugType.fold<int>(0, (a, g) => a + g.pieces),
        r.producedPieces,
      );
      expect(
        r.byRugType.fold<double>(0, (a, g) => a + g.m2),
        closeTo(r.producedM2, 0.001),
      );
    });
  });

  group('zaslon', () {
    /// November, Wed 4th: one piece made ready in October, one yesterday and
    /// one today.
    final screenState = world(
      [order('LJ-1', OrderStatus.awaitingCollection, count: 3)],
      [
        rug(
          'LJ-1',
          1,
          RugStatus.ready,
          price: 60,
          m2: 4,
          of: 3,
          history: madeReady(at(10, 20), at(10, 25)),
        ),
        rug(
          'LJ-1',
          2,
          RugStatus.ready,
          price: 90,
          m2: 6,
          of: 3,
          history: madeReady(at(11, 2), at(11, 3)),
        ),
        rug(
          'LJ-1',
          3,
          RugStatus.ready,
          price: 30,
          m2: 2,
          of: 3,
          history: madeReady(at(11, 3), at(11, 4)),
        ),
      ],
    );

    Future<ProviderContainer> show(
      WidgetTester tester, {
      AppState? data,
      Size size = const Size(800, 6000),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final store = InMemoryStore();
      await store.save(data ?? screenState);
      final container = ProviderContainer(
        overrides: [
          storeProvider.overrideWithValue(store),
          minuteClockProvider.overrideWith((ref) => Stream.value(now)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(repositoryProvider.notifier).init();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: StatsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    String? tile(WidgetTester tester, String label) => tester
        .widgetList<StatTile>(find.byType(StatTile))
        .where((t) => t.label == label)
        .firstOrNull
        ?.value;

    testWidgets('everything is on one page, in the order of the ticket', (
      tester,
    ) async {
      await show(tester);

      final headers = [
        'PREGLED',
        'PRIPRAVLJENO NA POLICAH',
        'PROIZVODNJA',
        'TRENUTNO DELO',
        'DODATNA STATISTIKA',
      ];
      double? lastY;
      for (final h in headers) {
        expect(find.text(h), findsOneWidget, reason: h);
        final y = tester.getTopLeft(find.text(h)).dy;
        if (lastY != null) expect(y, greaterThan(lastY), reason: h);
        lastY = y;
      }

      for (final label in [
        'Realiziran promet',
        'Povprečno naročilo',
        'V teku',
        'Pripravljeno: naročil / kosov',
        'Dokončanih kosov',
        'Dokončanih naročil',
      ]) {
        expect(tile(tester, label), isNotNull, reason: label);
      }
      for (final p in ['Danes', 'Ta teden', 'Ta mesec', 'Po meri datuma']) {
        expect(find.widgetWithText(FilterPill, p), findsOneWidget, reason: p);
      }
      for (final t in ['0–3 dni', '4–7 dni', '8+ dni']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(
        find.textContaining('mere vnesemo šele pri Hitrem obračunu'),
        findsOneWidget,
      );
      // No sub-pages: the stats screen is the only route.
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    });

    testWidgets('a narrow phone with large amounts does not overflow', (
      tester,
    ) async {
      final big = world(
        [
          order('LJ-1', OrderStatus.awaitingCollection),
          order('LJ-2', OrderStatus.completed, completedAt: at(11, 3)),
        ],
        [
          rug(
            'LJ-1',
            1,
            RugStatus.ready,
            price: 123456.78,
            m2: 9999.5,
            history: madeReady(at(10, 1), at(11, 4)),
          ),
          rug(
            'LJ-2',
            1,
            RugStatus.returned,
            price: 987654.32,
            m2: 8888.8,
            history: madeReady(at(10, 1), at(11, 3)),
          ),
        ],
      );
      await show(tester, data: big, size: const Size(360, 12000));
      await tester.tap(find.text('Po meri datuma'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tile(tester, 'Realiziran promet'), Fmt.money(987654.32));
    });

    testWidgets('the shelf matches the data', (tester) async {
      await show(tester);

      expect(tile(tester, 'Pripravljeno: naročil / kosov'), '1 / 3');
      expect(tile(tester, 'Pripravljeno'), Fmt.money(180));
      expect(tile(tester, 'V teku'), Fmt.money(0));
    });

    testWidgets('the period filter drives Proizvodnja', (tester) async {
      await show(tester);

      // Default: this month = yesterday's and today's piece.
      expect(tile(tester, 'Dokončanih kosov'), '2');
      expect(tile(tester, 'Dokončanih naročil'), '1');
      expect(tile(tester, 'Proizvedena vrednost'), Fmt.money(120));

      await tester.tap(find.text('Danes'));
      await tester.pumpAndSettle();
      expect(tile(tester, 'Dokončanih kosov'), '1');
      expect(tile(tester, 'Dokončanih naročil'), '1');
      expect(tile(tester, 'Proizvedena vrednost'), Fmt.money(30));

      await tester.tap(find.text('Ta teden'));
      await tester.pumpAndSettle();
      expect(tile(tester, 'Dokončanih kosov'), '2');
    });

    testWidgets('Po meri datuma: Od / Do on the same page, a picked day '
        'narrows the figures', (tester) async {
      await show(tester);

      await tester.tap(find.text('Po meri datuma'));
      await tester.pumpAndSettle();
      expect(find.text('Od '), findsOneWidget);
      expect(find.text('Do '), findsOneWidget);
      expect(tile(tester, 'Dokončanih kosov'), '2'); // 1. 11. – 4. 11.

      // Start the range on the 4th: only today's piece is left.
      await tester.tap(find.text('Od '));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('4'),
        ),
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(tile(tester, 'Dokončanih kosov'), '1');
      expect(find.textContaining('4. 11. 2026'), findsWidgets);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
      );
    });
  });
}

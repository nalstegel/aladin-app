import 'package:aladin/core/format.dart';
import 'package:aladin/data/order_phases.dart';
import 'package:aladin/data/repository.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/customer.dart';
import 'package:aladin/models/enums.dart';
import 'package:aladin/models/order.dart';
import 'package:flutter_test/flutter_test.dart';

/// QA v4 §3/§8: Čaka pranje in Sušenje kažeta kose, grupirane po naročilu in
/// razvrščene po prihodu; Pripravljeno samo v celoti pripravljena naročila;
/// iskanje čez vse zavihke.
void main() {
  late Repository repo;
  late Customer customer;

  setUp(() async {
    repo = Repository(InMemoryStore());
    await repo.init();
    repo.setCurrentUser('u-marko');
    customer = repo.createCustomer(
      type: CustomerType.private,
      name: 'Nataša Klopčavar',
      phone: '041662374',
      address: 'Smlednik 131',
      city: 'Medvode',
      postalCode: '1215',
    );
  });

  WorkOrder newOrder(int items, {Customer? c}) {
    final order = repo.createOrder(
      customer: c ?? customer,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      itemCount: items,
    );
    repo.markLabelsPrinted(order.id);
    return order;
  }

  List<String> groupIds(OrderPhase phase) =>
      groupsFor(repo.state, phase).map((g) => g.order.id).toList();

  test('kosi istega naročila so ena skupina, starejši prihod zgoraj', () async {
    final first = newOrder(3);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = newOrder(1);

    // Kasnejše premikanje starejšega naročila ne spremeni vrstnega reda.
    repo.advance('${first.id}-2');
    repo.advance('${second.id}-1');
    repo.advance('${first.id}-1');

    // Seed ima svoja demo naročila — gledamo samo naša dva.
    bool ours(PhaseGroup g) =>
        g.order.id == first.id || g.order.id == second.id;
    final drying = groupsFor(
      repo.state,
      OrderPhase.drying,
    ).where(ours).toList();
    expect(drying.map((g) => g.order.id), [first.id, second.id]);
    expect(drying.first.items.map((i) => i.id), [
      '${first.id}-1',
      '${first.id}-2',
    ]);

    final washing = groupsFor(repo.state, OrderPhase.washing).where(ours);
    expect(washing.single.items.single.id, '${first.id}-3');
  });

  test('naročilo pred tiskom etiket ni v Čaka pranje', () {
    final order = repo.createOrder(
      customer: customer,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      itemCount: 2,
    );
    final items = repo.state.itemsOf(order.id);

    expect(OrderPhase.intake.containsOrder(order, items), isTrue);
    expect(groupIds(OrderPhase.washing), isNot(contains(order.id)));
  });

  test('Pripravljeno pokaže samo v celoti pripravljena naročila', () {
    final order = newOrder(2);
    final type = repo.state.rugTypes.first;
    repo.advance('${order.id}-1');
    repo.advance('${order.id}-2');
    repo.finishRugFromDrying(
      '${order.id}-1',
      widthCm: 100,
      lengthCm: 100,
      rugType: type,
      extras: const [],
      discountPercent: 0,
    );

    var o = repo.state.order(order.id)!;
    expect(
      OrderPhase.ready.containsOrder(o, repo.state.itemsOf(o.id)),
      isFalse,
    );
    // Že pripravljen kos ostane viden (sivo) v skupini v Sušenju.
    final group = groupsFor(
      repo.state,
      OrderPhase.drying,
    ).firstWhere((g) => g.order.id == order.id);
    expect(group.items.single.id, '${order.id}-2');
    expect(group.readySiblings.single.id, '${order.id}-1');

    repo.finishRugFromDrying(
      '${order.id}-2',
      widthCm: 100,
      lengthCm: 100,
      rugType: type,
      extras: const [],
      discountPercent: 0,
    );
    o = repo.state.order(order.id)!;
    expect(OrderPhase.ready.containsOrder(o, repo.state.itemsOf(o.id)), isTrue);
    expect(groupIds(OrderPhase.drying), isNot(contains(order.id)));
  });

  test('iskanje najde po ID-ju, imenu brez šumnikov, telefonu in naslovu', () {
    final order = newOrder(2);
    final items = repo.state.itemsOf(order.id);
    bool hit(String q) => matchesSearch(order, items, q);

    expect(hit(order.id.toLowerCase()), isTrue);
    expect(hit('${order.id}-2'), isTrue);
    expect(hit('klopcavar'), isTrue);
    expect(hit('041 662'), isTrue);
    expect(hit('smlednik'), isTrue);
    expect(hit('medvode'), isTrue);
    expect(hit('novak'), isFalse);
    expect(hit(''), isFalse);
  });

  test('prevzem je zamujen šele po koncu dogovorjenega okna', () {
    final start = DateTime(2026, 9, 22, 8);
    final order = repo.createOrder(
      customer: customer,
      location: OrderLocation.ljubljana,
      channel: OrderChannel.delivery,
      handover: HandoverMode.weDeliver,
      itemCount: 1,
      pickupAt: start,
      pickupWindowEnd: start.add(const Duration(hours: 2)),
    );

    expect(order.isPickupOverdue(DateTime(2026, 9, 22, 9)), isFalse);
    expect(order.isPickupOverdue(DateTime(2026, 9, 22, 10, 1)), isTrue);
  });

  test('telefon s presledki', () {
    expect(Fmt.phone('031353517'), '031 353 517');
    expect(Fmt.phone('041 662374'), '041 662 374');
    expect(Fmt.phone('+38631353517'), '+386 31 353 517');
    expect(Fmt.phone('neznano'), 'neznano');
  });
}

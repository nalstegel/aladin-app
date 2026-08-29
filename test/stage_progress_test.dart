import 'package:aladin/models/enums.dart';
import 'package:aladin/models/rug_item.dart';
import 'package:aladin/ui/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

/// Napredek na kartici naročila meri korak, ki naročilo *zadržuje* — koliko
/// kosov ga je že prestopilo. Zato "3/8 oprano" in ne "5/8 na pranju".
List<RugItem> items(Map<RugStatus, int> counts) {
  final list = <RugItem>[];
  var n = 1;
  final total = counts.values.fold<int>(0, (a, b) => a + b);
  counts.forEach((status, count) {
    for (var i = 0; i < count; i++) {
      list.add(RugItem(
        id: '1847-$n',
        orderId: 'o1',
        index: n,
        ofTotal: total,
        status: status,
      ));
      n++;
    }
  });
  return list;
}

void main() {
  test('meri korak, v katerem obtiči največ kosov', () {
    // 5 čaka na pranje, 3 so že v sušenju → 3 od 8 opranih.
    final p = StageProgress.of(items({
      RugStatus.awaitingWash: 5,
      RugStatus.drying: 3,
    }));

    expect(p.done, 3);
    expect(p.total, 8);
    expect(p.label, 'oprano');
    expect(p.complete, isFalse);
  });

  test('ko so vsi pripravljeni, meri pripravljenost', () {
    final p = StageProgress.of(items({RugStatus.ready: 2}));

    expect(p.done, 2);
    expect(p.total, 2);
    expect(p.label, 'pripravljeno');
    expect(p.complete, isTrue);
  });

  test('vrnjeni kosi štejejo kot pripravljeni', () {
    // Sicer bi zaključeno naročilo kazalo 0/2 — kos, ki je vrnjen, je bil
    // očitno tudi pripravljen.
    final p = StageProgress.of(items({RugStatus.returned: 2}));

    expect(p.done, 2);
    expect(p.label, 'pripravljeno');
    expect(p.complete, isTrue);
  });

  test('en pripravljen med sušenjem ne premakne merila', () {
    // Največ kosov je v sušenju, zato merimo posušenost, ne pripravljenosti.
    final p = StageProgress.of(items({
      RugStatus.drying: 3,
      RugStatus.ready: 1,
    }));

    expect(p.label, 'posušeno');
    expect(p.done, 1);
    expect(p.total, 4);
  });

  test('naročilo brez kosov ne deli z nič', () {
    final p = StageProgress.of([]);

    expect(p.done, 0);
    expect(p.total, 0);
    expect(p.complete, isFalse);
  });
}

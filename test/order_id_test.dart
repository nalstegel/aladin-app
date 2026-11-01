import 'package:aladin/core/order_id.dart';
import 'package:aladin/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildOrderId', () {
    test('pads the sequence to 3 digits per location', () {
      expect(buildOrderId(OrderLocation.ljubljana, 1), 'LJ-001');
      expect(buildOrderId(OrderLocation.maribor, 42), 'MB-042');
      expect(buildOrderId(OrderLocation.celje, 1), 'CE-001');
      expect(buildOrderId(OrderLocation.ljubljana, 999), 'LJ-999');
    });

    test('adds a cycle digit right after the location code once past 999', () {
      expect(buildOrderId(OrderLocation.ljubljana, 1000), 'LJ1-001');
      expect(buildOrderId(OrderLocation.ljubljana, 1998), 'LJ1-999');
      expect(buildOrderId(OrderLocation.ljubljana, 1999), 'LJ2-001');
    });

    test('never resets — n keeps counting up across cycles', () {
      final ids = [for (var n = 997; n <= 1002; n++) buildOrderId(OrderLocation.ljubljana, n)];
      expect(ids, [
        'LJ-997',
        'LJ-998',
        'LJ-999',
        'LJ1-001',
        'LJ1-002',
        'LJ1-003',
      ]);
    });
  });

  group('compareOrderIds', () {
    List<String> sorted(List<String> ids) => [...ids]..sort(compareOrderIds);

    test('naročila v istem območju gredo od najmanjšega ID-ja', () {
      expect(sorted(['LJ-090', 'LJ-006', 'LJ-058', 'LJ-005', 'LJ-012']), [
        'LJ-005',
        'LJ-006',
        'LJ-012',
        'LJ-058',
        'LJ-090',
      ]);
    });

    test('številke primerja kot števila, ne kot besedilo', () {
      expect(sorted(['MB-10', 'MB-2', 'MB-1']), ['MB-1', 'MB-2', 'MB-10']);
    });

    test('krog za 999 je za prejšnjim, tudi pri LJ10 proti LJ2', () {
      expect(sorted(['LJ10-001', 'LJ2-001', 'LJ1-001', 'LJ-999', 'LJ-001']), [
        'LJ-001',
        'LJ-999',
        'LJ1-001',
        'LJ2-001',
        'LJ10-001',
      ]);
    });

    test('kosi istega naročila gredo po zaporedni številki kosa', () {
      expect(
        sorted(['LJ-100-10', 'LJ-100-2', 'LJ-101-1', 'LJ-100-1', 'LJ-099-3']),
        ['LJ-099-3', 'LJ-100-1', 'LJ-100-2', 'LJ-100-10', 'LJ-101-1'],
      );
    });

    test('območja si sledijo kot filtri LJ, MB, CE, DOL', () {
      expect(
        sorted(['DOL-001', 'CE-002', 'MB-002', 'LJ-050', 'CE-001', 'MB-001']),
        ['LJ-050', 'MB-001', 'MB-002', 'CE-001', 'CE-002', 'DOL-001'],
      );
    });

    test('ID, ki ne ustreza obliki, gre na konec', () {
      expect(sorted(['1847', 'LJ-002', 'abc', 'LJ-001']), [
        'LJ-001',
        'LJ-002',
        '1847',
        'abc',
      ]);
    });
  });
}

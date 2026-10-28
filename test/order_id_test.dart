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
}

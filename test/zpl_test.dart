import 'package:aladin/core/zpl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildLabelZpl', () {
    test('starts and ends with the ZPL frame commands', () {
      final zpl = buildLabelZpl(
        orderId: 'LJ-001',
        customerName: 'Novak',
        dimensions: '2,00 × 3,00 m',
        itemId: 'LJ-001-2',
      );

      expect(zpl, startsWith('^XA'));
      expect(zpl.trim(), endsWith('^XZ'));
    });

    test('encodes the item id as the QR payload and as visible text', () {
      final zpl = buildLabelZpl(
        orderId: 'LJ-001',
        customerName: 'Novak',
        dimensions: '2,00 × 3,00 m',
        itemId: 'LJ-001-2',
      );

      expect(zpl, contains('^BQN,2,5'));
      expect(zpl, contains('^FDLA,LJ-001-2^FS'));
      expect(zpl, contains('^FDLJ-001-2^FS'));
      expect(zpl, contains('^FDLJ-001^FS'));
    });

    test('omits the dimensions line entirely when not yet measured', () {
      final zpl = buildLabelZpl(
        orderId: 'LJ-001',
        customerName: 'Novak',
        dimensions: '',
        itemId: 'LJ-001-3',
      );

      expect(zpl, isNot(contains('^FO240,112')));
    });

    test('strips ZPL control characters out of order/customer data', () {
      final zpl = buildLabelZpl(
        orderId: 'LJ-001',
        customerName: 'Novak^~Trgovina',
        dimensions: '2,00 × 3,00 m',
        itemId: 'LJ-001-1',
      );

      expect(zpl, contains('NovakTrgovina'));
      expect(zpl, isNot(contains('Novak^~Trgovina')));
    });
  });
}

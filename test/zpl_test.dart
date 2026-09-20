import 'package:aladin/core/zpl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildLabelZpl', () {
    test('starts and ends with the ZPL frame commands', () {
      final zpl = buildLabelZpl(customerName: 'Novak', itemId: 'LJ-001-2');

      expect(zpl, startsWith('^XA'));
      expect(zpl.trim(), endsWith('^XZ'));
    });

    test('encodes the item id as the QR payload and as the title text', () {
      final zpl = buildLabelZpl(customerName: 'Novak', itemId: 'LJ-001-2');

      expect(zpl, contains('^FDLA,LJ-001-2^FS'));
      expect(zpl, contains('^A0N,40,40^FDLJ-001-2^FS'));
      expect(zpl, contains('^FDNovak^FS'));
    });

    test('prints everything upright and centered across the label', () {
      final zpl = buildLabelZpl(customerName: 'Novak', itemId: 'LJ-001-2');

      // Brez zasukanih polj — vse se bere naravnost.
      expect(zpl, isNot(contains('^A0R,')));
      expect(zpl, isNot(contains('^BQR,')));
      // Vsaka vrstica je centrirana čez celo širino nalepke.
      expect(zpl, contains('^FB$labelWidthDots,1,0,C,0'));
    });

    test('strips ZPL control characters out of customer data', () {
      final zpl = buildLabelZpl(
        customerName: 'Novak^~Trgovina',
        itemId: 'LJ-001-1',
      );

      expect(zpl, contains('NovakTrgovina'));
      expect(zpl, isNot(contains('Novak^~Trgovina')));
    });
  });
}

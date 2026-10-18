import 'package:aladin/core/zpl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildLabelZpl', () {
    test('starts and ends with the ZPL frame commands', () {
      final zpl = buildLabelZpl(
        customerName: 'Novak',
        dimensions: '2,00 × 3,00 m',
        itemId: 'LJ-001-2',
      );

      expect(zpl, startsWith('^XA'));
      expect(zpl.trim(), endsWith('^XZ'));
    });

    test('encodes the item id as the QR payload and as visible text', () {
      final zpl = buildLabelZpl(
        customerName: 'Novak',
        dimensions: '2,00 × 3,00 m',
        itemId: 'LJ-001-2',
      );

      expect(zpl, contains('^FDLA,LJ-001-2^FS'));
      expect(zpl, contains('^FDLJ-001-2^FS'));
    });

    test('prints everything upright and centered across the label', () {
      final zpl = buildLabelZpl(
        customerName: 'Novak',
        dimensions: '2,00 × 3,00 m',
        itemId: 'LJ-001-2',
      );

      // Brez zasukanih polj — vse se bere naravnost.
      expect(zpl, isNot(contains('^A0R,')));
      expect(zpl, isNot(contains('^BQR,')));
      // Vsaka vrstica je centrirana čez celo širino nalepke.
      expect(zpl, contains('^FB$labelWidthDots,1,0,C,0'));
    });

    test('omits the dimensions line entirely when not yet measured', () {
      final zpl = buildLabelZpl(
        customerName: 'Novak',
        dimensions: '',
        itemId: 'LJ-001-3',
      );

      expect(zpl, isNot(contains('^A0N,22,22')));
      expect(zpl, isNot(contains('—')));
    });

    test('strips ZPL control characters out of order/customer data', () {
      final zpl = buildLabelZpl(
        customerName: 'Novak^~Trgovina',
        dimensions: '2,00 × 3,00 m',
        itemId: 'LJ-001-1',
      );

      expect(zpl, contains('NovakTrgovina'));
      expect(zpl, isNot(contains('Novak^~Trgovina')));
    });

    test('Dostave: ID kosa je največje besedilo na nalepki', () {
      final zpl = buildLabelZpl(
        customerName: 'Novak',
        dimensions: '',
        itemId: 'LJ-021-1',
      );

      expect(zpl, contains('^A0N,48,48^FDLJ-021-1^FS'));
    });

    test('Pripeljano: ime, telefon in KOS x/y so večji od ID-ja', () {
      final zpl = buildLabelZpl(
        customerName: 'Nataša Klopčavar',
        dimensions: '',
        itemId: 'LJ-021-2',
        dropoff: true,
        phone: '031 353 517',
        pieceLabel: 'KOS 2/3',
      );

      expect(zpl, contains('^A0N,34,34^FDNataša Klopčavar^FS'));
      expect(zpl, contains('^A0N,30,30^FD031 353 517^FS'));
      expect(zpl, contains('^A0N,36,36^FDKOS 2/3^FS'));
      // Interni ID in QR ostaneta, da se skeniranje ne spremeni.
      expect(zpl, contains('^A0N,22,22^FDLJ-021-2^FS'));
      expect(zpl, contains('^FDLA,LJ-021-2^FS'));
    });
  });
}

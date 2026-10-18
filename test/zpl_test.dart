import 'package:aladin/core/zpl.dart';
import 'package:aladin/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

String _ljDelivery({String name = 'Novak', String item = 'LJ-099-3'}) =>
    buildLabelZpl(
      kind: LabelKind.ljDelivery,
      itemId: item,
      orderId: 'LJ-099',
      pieceLabel: '3/4',
      customerName: name,
    );

void main() {
  group('labelKindFor', () {
    test('MB/CE/DOL imajo vedno regijsko nalepko, ne glede na način', () {
      for (final l in [
        OrderLocation.maribor,
        OrderLocation.celje,
        OrderLocation.dolenjska,
      ]) {
        for (final c in OrderChannel.values) {
          expect(labelKindFor(location: l, channel: c), LabelKind.region);
        }
      }
    });

    test('Ljubljana: Pripeljano ime+telefon, ostalo velik ID', () {
      expect(
        labelKindFor(
          location: OrderLocation.ljubljana,
          channel: OrderChannel.dropoff,
        ),
        LabelKind.dropoff,
      );
      expect(
        labelKindFor(
          location: OrderLocation.ljubljana,
          channel: OrderChannel.delivery,
        ),
        LabelKind.ljDelivery,
      );
    });
  });

  group('buildLabelZpl', () {
    test('starts and ends with the ZPL frame commands', () {
      final zpl = _ljDelivery();
      expect(zpl, startsWith('^XA'));
      expect(zpl.trim(), endsWith('^XZ'));
    });

    test('QR vsebuje ID kosa, na nalepki je ID tudi kot majhno besedilo', () {
      final zpl = _ljDelivery();
      expect(zpl, contains('^FDLA,LJ-099-3^FS'));
      expect(zpl, contains('^A0N,20,20^FDLJ-099-3^FS'));
    });

    test('prints everything upright and centered across the label', () {
      final zpl = _ljDelivery();
      expect(zpl, isNot(contains('^A0R,')));
      expect(zpl, isNot(contains('^BQR,')));
      expect(zpl, contains('^FB$labelWidthDots,1,0,C,0'));
    });

    test('strips ZPL control characters out of order/customer data', () {
      final zpl = _ljDelivery(name: 'Novak^~Trgovina');
      expect(zpl, contains('NovakTrgovina'));
      expect(zpl, isNot(contains('Novak^~Trgovina')));
    });

    test('LJ dostava: velik interni ID naročila in jasno 3/4', () {
      final zpl = _ljDelivery();
      expect(zpl, contains('^A0N,72,72^FDLJ-099^FS'));
      expect(zpl, contains('^A0N,58,58^FD3/4^FS'));
      // Ime je manjše od ID-ja.
      expect(zpl, contains('^A0N,26,26^FDNovak^FS'));
    });

    test('Pripeljano: veliko ime + telefon + 3/4 + QR', () {
      final zpl = buildLabelZpl(
        kind: LabelKind.dropoff,
        itemId: 'LJ-021-2',
        orderId: 'LJ-021',
        pieceLabel: '2/3',
        customerName: 'Nataša Klopčavar',
        phone: '031 353 517',
      );
      expect(zpl, contains('^A0N,34,34^FDNataša Klopčavar^FS'));
      expect(zpl, contains('^A0N,30,30^FD031 353 517^FS'));
      expect(zpl, contains('^A0N,58,58^FD2/3^FS'));
      expect(zpl, contains('^FDLA,LJ-021-2^FS'));
    });

    test('Regija: velika oznaka, x/4, ime/telefon, brez prevzemne točke', () {
      final zpl = buildLabelZpl(
        kind: LabelKind.region,
        itemId: 'DOL-007-1',
        orderId: 'DOL-007',
        pieceLabel: '1/4',
        customerName: 'Novak',
        phone: '041 111 222',
        regionCode: 'DOL',
      );
      expect(zpl, contains('^A0N,100,100^FDDOL^FS'));
      expect(zpl, contains('^A0N,56,56^FD1/4^FS'));
      expect(zpl, contains('^FDNovak^FS'));
      expect(zpl, contains('^FD041 111 222^FS'));
      expect(zpl, contains('^FDLA,DOL-007-1^FS'));
      // Interni ID naročila ni natisnjen velik — regija je glavna oznaka.
      expect(zpl, isNot(contains('^A0N,72,72')));
    });

    test('vrstice brez podatka se preskočijo', () {
      final zpl = buildLabelZpl(
        kind: LabelKind.dropoff,
        itemId: 'LJ-021-2',
        orderId: 'LJ-021',
        pieceLabel: '2/3',
        customerName: 'Novak',
      );
      expect(zpl, isNot(contains('^A0N,30,30')));
      expect(zpl, isNot(contains('—')));
    });
  });
}

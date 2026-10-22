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

/// Zadnja ukazna vrstica `^FO` na nalepki, ki ni znotraj `^XA`/`^XZ` okvirja.
Iterable<RegExpMatch> _fields(String zpl) =>
    RegExp(r'\^FO(\d+),(\d+)').allMatches(zpl);

void main() {
  test('nalepka je ležeča 60×40 mm (480×320 pik pri 203 dpi)', () {
    // Fotografija prave nalepke je pokazala, da je medij ležeč; pokončna
    // različica je odrezala spodnji del postavitve.
    expect(labelWidthDots, 480);
    expect(labelHeightDots, 320);
    final zpl = _ljDelivery();
    expect(zpl, contains('^PW480'));
    expect(zpl, contains('^LL320'));
  });

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
      expect(zpl, contains('^A0N,24,24^FDLJ-099-3^FS'));
    });

    test('vse je pokonci, brez zasukanih polj', () {
      final zpl = _ljDelivery();
      expect(zpl, isNot(contains('^A0R,')));
      expect(zpl, isNot(contains('^BQR,')));
    });

    test('nič se ne začne izven varnega roba nalepke', () {
      for (final kind in LabelKind.values) {
        final zpl = buildLabelZpl(
          kind: kind,
          itemId: 'DOL-007-2',
          orderId: 'DOL-007',
          pieceLabel: '2/4',
          customerName: 'Nataša Klopčavar',
          phone: '031 353 517',
          regionCode: 'DOL',
        );
        for (final m in _fields(zpl)) {
          final x = int.parse(m.group(1)!);
          final y = int.parse(m.group(2)!);
          expect(x, greaterThanOrEqualTo(labelMarginDots), reason: '$kind');
          expect(x, lessThan(labelWidthDots - labelMarginDots), reason: '$kind');
          expect(y, lessThan(labelHeightDots - 20), reason: '$kind');
        }
      }
    });

    test('velika oznaka in x/y na isti črti se nikoli ne prekrivata', () {
      // Najdaljši ID (po 999 naročilih dobi številko cikla) in najdaljše x/y.
      for (final order in ['LJ-142', 'LJ1-001', 'LJ12-999']) {
        for (final piece in ['1/2', '3/4', '12/20', '10/10']) {
          final zpl = _ljDelivery(item: '$order-1').replaceAll('LJ-099', order);
          final layout = buildLabelLayout(
            kind: LabelKind.ljDelivery,
            itemId: '$order-1',
            orderId: order,
            pieceLabel: piece,
          );
          final big = layout.fields.firstWhere((f) => f.text == order);
          final small = layout.fields.firstWhere((f) => f.text == piece);
          final bigEnd = big.x + estimateTextWidth(order, big.size);
          final smallStart =
              small.x + small.w - estimateTextWidth(piece, small.size);
          expect(smallStart, greaterThan(bigEnd + 8),
              reason: '$order + $piece (zpl: ${zpl.length})');
        }
      }
      // Regija: oznaka + x/y.
      for (final region in ['MB', 'CE', 'DOL']) {
        for (final piece in ['1/4', '12/20']) {
          final layout = buildLabelLayout(
            kind: LabelKind.region,
            itemId: '$region-001-1',
            orderId: '$region-001',
            pieceLabel: piece,
            regionCode: region,
          );
          final big = layout.fields.firstWhere((f) => f.text == region);
          final small = layout.fields.firstWhere((f) => f.text == piece);
          final bigEnd = big.x + estimateTextWidth(region, big.size);
          final smallStart =
              small.x + small.w - estimateTextWidth(piece, small.size);
          expect(smallStart, greaterThan(bigEnd + 8), reason: '$region $piece');
        }
      }
    });

    test('besedilo v desnem stolpcu je ožje od stolpca', () {
      final layout = buildLabelLayout(
        kind: LabelKind.dropoff,
        itemId: 'LJ-021-2',
        orderId: 'LJ-021',
        pieceLabel: '12/20',
        customerName: 'Nataša Klopčavar',
        phone: '031 353 517',
      );
      for (final f in layout.fields.where((f) => f.x > 100)) {
        expect(estimateTextWidth(f.text, f.size), lessThanOrEqualTo(f.w),
            reason: f.text);
      }
    });

    test('QR je vedno na levi spodaj (mag. 7), besedilo desno od njega', () {
      for (final kind in LabelKind.values) {
        final zpl = buildLabelZpl(
          kind: kind,
          itemId: 'LJ-021-2',
          orderId: 'LJ-021',
          pieceLabel: '2/3',
          customerName: 'Novak',
          phone: '041 111 222',
          regionCode: 'MB',
        );
        expect(zpl, contains('^FO20,146^BQN,2,7'), reason: '$kind');
      }
    });

    test('strips ZPL control characters out of order/customer data', () {
      final zpl = _ljDelivery(name: 'Novak^~Trgovina');
      expect(zpl, contains('NovakTrgovina'));
      expect(zpl, isNot(contains('Novak^~Trgovina')));
    });

    test('LJ dostava: velik interni ID naročila in poleg jasno 3/4', () {
      final zpl = _ljDelivery();
      expect(zpl, contains('^A0N,84,84^FDLJ-099^FS'));
      expect(zpl, contains('^A0N,64,64^FD3/4^FS'));
      // Ime je manjše od ID-ja.
      expect(zpl, contains('^A0N,34,34^FDNovak^FS'));
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
      expect(zpl, contains('^A0N,50,50^FDNataša Klopčavar^FS'));
      expect(zpl, contains('^A0N,40,40^FD031 353 517^FS'));
      expect(zpl, contains('^A0N,76,76^FD2/3^FS'));
      expect(zpl, contains('^FDLA,LJ-021-2^FS'));
    });

    test('Regija: velika oznaka, x/4, ime/telefon in ID za ročni vnos', () {
      final zpl = buildLabelZpl(
        kind: LabelKind.region,
        itemId: 'DOL-007-1',
        orderId: 'DOL-007',
        pieceLabel: '1/4',
        customerName: 'Novak',
        phone: '041 111 222',
        regionCode: 'DOL',
      );
      expect(zpl, contains('^A0N,116,116^FDDOL^FS'));
      expect(zpl, contains('^A0N,92,92^FD1/4^FS'));
      expect(zpl, contains('^FDNovak^FS'));
      expect(zpl, contains('^FD041 111 222^FS'));
      expect(zpl, contains('^FDLA,DOL-007-1^FS'));
      // Brez ID-ja bi ročni vnos pri skeniranju na regijski nalepki odpovedal.
      expect(zpl, contains('^A0N,22,22^FDDOL-007-1^FS'));
    });

    test('vrstice brez podatka se preskočijo', () {
      final zpl = buildLabelZpl(
        kind: LabelKind.dropoff,
        itemId: 'LJ-021-2',
        orderId: 'LJ-021',
        pieceLabel: '2/3',
        customerName: 'Novak',
      );
      expect(zpl, isNot(contains('^A0N,40,40')));
      expect(zpl, isNot(contains('—')));
    });
  });
}

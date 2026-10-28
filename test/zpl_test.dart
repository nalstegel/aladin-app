import 'package:aladin/core/zpl.dart';
import 'package:aladin/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

String _ljDelivery({String name = 'Janez Novak', String item = 'LJ-021-3'}) =>
    buildLabelZpl(
      kind: LabelKind.ljDelivery,
      itemId: item,
      orderId: 'LJ-021',
      pieceLabel: '3/4',
      customerName: name,
    );

LabelLayout _layout(
  LabelKind kind, {
  String order = 'LJ-021',
  String piece = '3/4',
  String name = 'Janez Novak',
  String phone = '070 740 674',
}) =>
    buildLabelLayout(
      kind: kind,
      itemId: '$order-1',
      orderId: order,
      pieceLabel: piece,
      customerName: name,
      phone: phone,
    );

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

    test('Ljubljana: Pripeljano ime+telefon, ostalo ID naročila', () {
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

    test('QR vsebuje ID kosa in je na sredini zgoraj (mag. 7)', () {
      for (final kind in LabelKind.values) {
        final zpl = buildLabelZpl(
          kind: kind,
          itemId: 'LJ-021-3',
          orderId: 'LJ-021',
          pieceLabel: '3/4',
          customerName: 'Novak',
          phone: '041 111 222',
        );
        // (480 − 147) / 2 = 166
        expect(zpl, contains('^FO166,16^BQN,2,7'), reason: '$kind');
        expect(zpl, contains('^FDLA,LJ-021-3^FS'), reason: '$kind');
      }
    });

    test('vse je pokonci, brez zasukanih polj', () {
      final zpl = _ljDelivery();
      expect(zpl, isNot(contains('^A0R,')));
      expect(zpl, isNot(contains('^BQR,')));
    });

    test('strips ZPL control characters out of order/customer data', () {
      final zpl = _ljDelivery(name: 'Novak^~Trgovina');
      expect(zpl, contains('NovakTrgovina'));
      expect(zpl, isNot(contains('Novak^~Trgovina')));
    });
  });

  group('postavitev kot v predlogi', () {
    List<String> texts(LabelLayout l) => [for (final f in l.fields) f.text];

    test('1) Pripeljano: ime + x/y v veliki vrstici, pod njo telefon', () {
      final l = _layout(
        LabelKind.dropoff,
        name: 'Remec',
        piece: '2/4',
        phone: '070 740 674',
      );
      expect(texts(l), ['Remec  2/4', '070 740 674']);
    });

    test('2) LJ dostava: ID naročila + x/y, pod njim ime', () {
      final l = _layout(LabelKind.ljDelivery, name: 'Janez Novak');
      expect(texts(l), ['LJ-021  3/4', 'Janez Novak']);
    });

    test('3) Regija: ID naročila (predpona = regija) + x/y, pod njim ime', () {
      final l = _layout(
        LabelKind.region,
        order: 'MB-001',
        piece: '2/4',
        name: 'Marija Kovač',
      );
      expect(texts(l), ['MB-001  2/4', 'Marija Kovač']);
    });

    test('veliko besedilo je večje od druge vrstice', () {
      for (final kind in LabelKind.values) {
        final l = _layout(kind);
        expect(l.fields.first.size, greaterThan(l.fields.last.size),
            reason: '$kind');
      }
    });

    test('vse je na sredini in pod QR kodo', () {
      for (final kind in LabelKind.values) {
        final l = _layout(kind);
        final qrBottom = l.qrY + l.qrSize;
        var prevBottom = qrBottom;
        for (final f in l.fields) {
          expect(f.align, 'C', reason: '$kind ${f.text}');
          expect(f.y, greaterThanOrEqualTo(prevBottom), reason: f.text);
          prevBottom = f.y + f.size;
        }
      }
    });

    test('nič ne zleze čez varni rob ali spodnji rob', () {
      for (final kind in LabelKind.values) {
        for (final order in ['LJ-021', 'LJ1-001', 'DOL-007', 'LJ12-999']) {
          for (final piece in ['1/4', '12/20']) {
            final l = _layout(
              kind,
              order: order,
              piece: piece,
              name: 'Nataša Klopčavar-Horvat Novak',
              phone: '+386 31 353 517',
            );
            for (final f in l.fields) {
              final why = '$kind $order $piece "${f.text}"';
              expect(f.x, greaterThanOrEqualTo(labelMarginDots), reason: why);
              expect(f.x + f.w, lessThanOrEqualTo(labelWidthDots - labelMarginDots),
                  reason: why);
              expect(estimateTextWidth(f.text, f.size), lessThanOrEqualTo(f.w),
                  reason: why);
              expect(f.y + f.size, lessThanOrEqualTo(labelHeightDots - 16),
                  reason: why);
            }
          }
        }
      }
    });

    test('dolgo ime se skrajša, x/y ostane cel', () {
      final l = _layout(
        LabelKind.dropoff,
        name: 'Nataša Klopčavar-Horvat Novak',
        piece: '12/20',
      );
      final big = l.fields.first.text;
      expect(big, endsWith('  12/20'));
      expect(big, startsWith('Nataša'));
      expect(big.length, lessThan('Nataša Klopčavar-Horvat Novak  12/20'.length));
    });

    test('kratka velika vrstica je čim večja, a gre v širino nalepke', () {
      // "LJ-021  3/4" pri 66 je ~0.2 pike čez varnostno mejo, pri 64 gre.
      expect(_layout(LabelKind.ljDelivery).fields.first.size, 64);
      expect(_layout(LabelKind.dropoff, name: 'Remec').fields.first.size, 66);
    });

    test('vrstice brez podatka se preskočijo', () {
      final dropoff = buildLabelLayout(
        kind: LabelKind.dropoff,
        itemId: 'LJ-021-2',
        orderId: 'LJ-021',
        pieceLabel: '2/3',
        customerName: 'Novak',
      );
      expect(dropoff.fields.map((f) => f.text), ['Novak  2/3']);
      expect(
        buildLabelZpl(
          kind: LabelKind.dropoff,
          itemId: 'LJ-021-2',
          orderId: 'LJ-021',
          pieceLabel: '2/3',
          customerName: 'Novak',
        ),
        isNot(contains('—')),
      );
    });
  });

  group('qrModulesFor', () {
    test('ID kosa je vedno verzija 1 (21 modulov)', () {
      expect(qrModulesFor('LJ-021-3'), 21);
      expect(qrModulesFor('DOL-001-12'), 21);
      expect(qrModulesFor('LJ12-999-20'), 21);
    });

    test('daljša povezava zahteva večjo verzijo', () {
      expect(qrModulesFor('https://g.page/r/CabcdefghIJKLMNOP/review'), 29);
      expect(qrModulesFor('x' * 80), 37);
    });
  });

  group('nalepka Google ocene', () {
    const url = 'https://g.page/r/CabcdefghIJKLMNOP/review';

    test('besedilo povabila in velik QR s povezavo', () {
      final zpl = buildReviewZpl(url);
      expect(zpl, startsWith('^XA'));
      expect(zpl.trim(), endsWith('^XZ'));
      expect(zpl, contains('^FDHvala za zaupanje!^FS'));
      expect(zpl, contains('^FDSte zadovoljni?^FS'));
      expect(zpl, contains('^FDOcenite nas na Googlu^FS'));
      expect(zpl, contains('^FDLA,$url^FS'));
    });

    test('brez podatkov stranke ali ID-ja', () {
      final texts = buildReviewLayout(url).fields.map((f) => f.text).join(' ');
      expect(texts, isNot(contains('LJ-')));
      expect(texts, isNot(contains('/4')));
    });

    test('QR je čim večji, v mejah nalepke in ne pokriva besedila', () {
      for (final link in [url, 'https://g.page/r/x/review', 'x' * 80]) {
        final l = buildReviewLayout(link);
        expect(l.qrSize, greaterThanOrEqualTo(200), reason: link);
        expect(l.qrX + l.qrSize,
            lessThanOrEqualTo(labelWidthDots - labelMarginDots));
        expect(l.qrY, greaterThanOrEqualTo(0));
        expect(l.qrY + l.qrSize, lessThanOrEqualTo(labelHeightDots));
        for (final f in l.fields) {
          expect(f.x + f.w, lessThanOrEqualTo(l.qrX), reason: f.text);
        }
      }
    });

    test('najdaljša beseda povabila gre v stolpec ob QR-ju', () {
      for (final link in [url, 'x' * 80]) {
        final l = buildReviewLayout(link);
        for (final f in l.fields) {
          for (final word in f.text.split(' ')) {
            expect(estimateTextWidth(word, f.size), lessThanOrEqualTo(f.w),
                reason: '$word @ ${f.size} in ${f.w}');
          }
        }
      }
    });
  });
}

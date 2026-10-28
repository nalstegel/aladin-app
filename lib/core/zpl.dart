import 'dart:convert';

import '../models/enums.dart';

/// ZPL predloge za nalepke, natisnjene na Zebra ZD230 (glej
/// `lib/data/zebra_printer.dart` za pošiljanje po omrežju).
///
/// Nalepka je LEŽEČA: 60mm široka (vzdolž glave tiskalnika), 40mm visoka
/// (smer podajanja), pri 203 dpi (edina ločljivost, v kateri obstaja ZD230;
/// 8 dots/mm). To je potrdila fotografija prave natisnjene nalepke (V8): QR in
/// besedilo tečejo vzdolž daljše stranice. Prejšnja pokončna različica
/// (40×60) je natisnila samo zgornjih ~40mm postavitve — spodnji del (x/y,
/// ime, ID) je ostal odrezan. Če se medij v tiskalniku kdaj zamenja, spremeni
/// [labelWidthDots]/[labelHeightDots] in postavitev spodaj.
const labelWidthDots = 480; // 60mm @ 203dpi
const labelHeightDots = 320; // 40mm @ 203dpi

/// Varni rob (2.5mm): sponke in robovi nalepke ne smejo požreti besedila.
const labelMarginDots = 20;

/// Nalepka kosa (V10): QR na sredini zgoraj (magnifikacija 7 = 147 pik za
/// verzijo 1, kar je vsak ID kosa), pod njim velika vrstica in manjša vrstica.
const _qrMag = 7;
const _qrModules = 21;
const _qrSize = _qrModules * _qrMag;
const _qrTop = 16;
const _textTop = _qrTop + _qrSize + 8;
const _textW = labelWidthDots - 2 * labelMarginDots;

/// Ocenjena širina besedila v pikah. Vgrajena pisava 0 na ZD230 je pri
/// `^A0N,h,h` široka ~0.57 × h na znak (izmerjeno na fotografiji prave
/// nalepke: "LJ-142" pri h=72 je ~247 pik). Uporabljata jo prilagajanje
/// velikosti spodaj in preverjanje v testih.
double estimateTextWidth(String text, int size) => text.length * size * 0.57;

/// `^FB` z eno vrstico besedilo, ki ne gre v vrstico, prelomi in natisne čez
/// zadnjo vrstico — zato se besedilo raje pomanjša, kot da bi ga ocena
/// zadela na rob.
const _fitSafety = 0.94;

/// Največja velikost od [max] navzdol do [min], pri kateri [text] gre v [width].
int _fitSize(String text, {required int max, required int min, int width = _textW}) {
  var size = max;
  while (size > min &&
      estimateTextWidth(text, size) > width * _fitSafety) {
    size -= 2;
  }
  return size;
}

/// Skrajša [text] (s piko na koncu), da gre pri velikosti [size] v [width].
String _clip(String text, int size, int width) {
  final limit = width * _fitSafety;
  if (estimateTextWidth(text, size) <= limit) return text;
  var t = text;
  while (t.length > 1 && estimateTextWidth('$t.', size) > limit) {
    t = t.substring(0, t.length - 1);
  }
  return '${t.trimRight()}.';
}

/// Velika vrstica "vodilni del  x/y" (npr. "LJ-021  3/4" ali "Remec  2/4").
/// Velikost se prilagodi širini; če tudi najmanjša ne zadošča (dolgo ime), se
/// skrajša vodilni del — x/y mora ostati cel, saj pove, kateri kos je.
(String, int) _bigLine(
  String lead,
  String piece, {
  required int max,
  required int min,
}) {
  final suffix = piece.isEmpty ? '' : (lead.isEmpty ? piece : '  $piece');
  var text = lead;
  var size = _fitSize('$text$suffix', max: max, min: min);
  if (estimateTextWidth('$text$suffix', size) > _textW * _fitSafety) {
    while (text.length > 1 &&
        estimateTextWidth('$text.$suffix', min) > _textW * _fitSafety) {
      text = text.substring(0, text.length - 1);
    }
    text = '${text.trimRight()}.';
    size = min;
  }
  return ('$text$suffix', size);
}

/// Ubeži znakom s posebnim pomenom v ZPL (`^` ukazni, `~` nadzorni), da
/// podatki iz naročila (ime stranke, ID kosa) ne razbijejo predloge.
String _escapeZpl(String value) =>
    value.replaceAll('^', '').replaceAll('~', '').replaceAll('\n', ' ');

/// Eno besedilno polje na nalepki, v pikah od zgornjega levega kota. Isti opis
/// uporabita tiskalnik ([buildLabelZpl]) in predogled v aplikaciji, zato se
/// predogled ne more razlikovati od natisnjenega.
///
/// `^FB` pri tisku poskrbi za poravnavo ([align]: L / C / R) in prelom v
/// največ [maxLines] vrstic — ZPL sam besedila ne poravna ne prelomi.
class LabelField {
  const LabelField({
    required this.x,
    required this.y,
    required this.w,
    required this.size,
    required this.text,
    this.maxLines = 1,
    this.align = 'L',
  });

  final int x;
  final int y;
  final int w;
  final int size;
  final String text;
  final int maxLines;
  final String align;

  String toZpl() =>
      '^FO$x,$y^FB$w,$maxLines,0,$align,0^A0N,$size,$size^FD$text^FS\n';
}

/// Število modulov QR kode za [data] pri popravi napak L (verzija 1 = 21).
/// Ocena po zmogljivosti bajtnega načina — tiskalnik v samodejnem načinu
/// nikoli ne zasede več, tako da je lahko ocena največ eno stopnjo previsoka.
int qrModulesFor(String data) {
  const byteCapacityL = [17, 32, 53, 78, 106, 134, 154, 192, 230, 271];
  final bytes = utf8.encode(data).length;
  for (var v = 1; v <= byteCapacityL.length; v++) {
    if (bytes <= byteCapacityL[v - 1]) return 17 + 4 * v;
  }
  return 17 + 4 * byteCapacityL.length;
}

/// Celotna postavitev ene nalepke: besedilna polja + QR koda.
class LabelLayout {
  const LabelLayout({
    required this.fields,
    required this.qrData,
    required this.qrX,
    required this.qrY,
    required this.qrMag,
  });

  final List<LabelField> fields;

  /// Vsebina QR kode (ID kosa ali povezava).
  final String qrData;

  /// Položaj (levi zgornji kot) in magnifikacija QR kode v pikah.
  final int qrX;
  final int qrY;
  final int qrMag;

  /// Stranica QR kode v pikah.
  int get qrSize => qrModulesFor(qrData) * qrMag;
}

/// Tri vrste nalepk (V8 §5). Nalepka mora takoj povedati, kam kos sodi —
/// brez informacij o prevzemni točki.
enum LabelKind {
  /// MB / CE / DOL: ID naročila (MB-001, predpona je regija) + x/y + ime.
  region,

  /// LJ dostava: ID naročila (LJ-099) + x/y + ime.
  ljDelivery,

  /// LJ Pripeljano: ime + x/y + telefon.
  dropoff,
}

/// Vrsto nalepke določita naročilo samo: regija se napolni samodejno iz
/// naročila (pri tisku ni dodatnega izbiranja). Najprej odloča regija, nato
/// način — MB/CE/DOL imajo vedno regijsko nalepko.
LabelKind labelKindFor({
  required OrderLocation location,
  required OrderChannel channel,
}) {
  if (location != OrderLocation.ljubljana) return LabelKind.region;
  return channel == OrderChannel.dropoff
      ? LabelKind.dropoff
      : LabelKind.ljDelivery;
}

/// Postavitev nalepke kosa (60×40mm ležeče), vse poravnano na sredino:
/// QR zgoraj, pod njim velika vrstica z x/y in manjša vrstica pod tem.
///
/// * [LabelKind.dropoff]: "Remec  2/4" in telefon,
/// * [LabelKind.ljDelivery] / [LabelKind.region]: "LJ-021  3/4" / "MB-001  2/4"
///   in ime stranke. Predpona ID-ja naročila je že regija, zato posebne
///   oznake regije ni treba.
///
/// `itemId` je vsebina QR kode. Na nalepki ni natisnjen posebej: ID kosa je
/// `<ID naročila>-<številka kosa>`, torej "LJ-021  3/4" za ročni vnos
/// (glej `scanner_screen.dart`) zadošča — "LJ-021-3".
LabelLayout buildLabelLayout({
  required LabelKind kind,
  required String itemId,
  required String orderId,
  required String pieceLabel,
  String customerName = '',
  String phone = '',
}) {
  final name = _escapeZpl(customerName).trim();
  final order = _escapeZpl(orderId);
  final tel = _escapeZpl(phone).trim();
  final piece = _escapeZpl(pieceLabel);

  final fields = <LabelField>[];
  var y = _textTop;

  void centered(String text, int size) {
    if (text.isEmpty) return;
    fields.add(LabelField(
      x: labelMarginDots,
      y: y,
      w: _textW,
      size: size,
      text: text,
      align: 'C',
    ));
    y += size + 6;
  }

  final (big, bigSize) = _bigLine(
    kind == LabelKind.dropoff ? name : order,
    piece,
    max: 66,
    min: 34,
  );
  centered(big, bigSize);

  // Druga vrstica je vedno manjša od velike; brez podatka (npr. telefon, ki
  // ga stranka nima) se preskoči, da ne ostane luknja.
  final secondMax = bigSize - 6 < 46 ? bigSize - 6 : 46;
  if (kind == LabelKind.dropoff) {
    centered(tel, _fitSize(tel, max: secondMax, min: 28));
  } else {
    final size = _fitSize(name, max: secondMax, min: 28);
    centered(_clip(name, size, _textW), size);
  }

  return LabelLayout(
    fields: fields,
    qrData: _escapeZpl(itemId),
    qrX: (labelWidthDots - _qrSize) ~/ 2,
    qrY: _qrTop,
    qrMag: _qrMag,
  );
}

/// Postavitev generične nalepke za Google oceno (V10 §4): povabilo levo, velik
/// QR desno. Brez podatkov stranke in brez ID-ja — ista nalepka velja za vse.
LabelLayout buildReviewLayout(String url) {
  final data = _escapeZpl(url);
  final modules = qrModulesFor(data);
  // QR čim večji, a levo ostane dovolj prostora za najdaljšo besedo.
  final mag = (250 ~/ modules).clamp(3, 10);
  final size = modules * mag;
  final qrX = labelWidthDots - labelMarginDots - size;
  final textW = qrX - 16 - labelMarginDots;

  LabelField line(int y, int size, String text) => LabelField(
        x: labelMarginDots,
        y: y,
        w: textW,
        size: size,
        text: text,
        maxLines: 2,
      );

  return LabelLayout(
    fields: [
      line(44, 32, 'Hvala za zaupanje!'),
      line(122, 26, 'Ste zadovoljni?'),
      line(188, 26, 'Ocenite nas na Googlu'),
    ],
    qrData: data,
    qrX: qrX,
    qrY: (labelHeightDots - size) ~/ 2,
    qrMag: mag,
  );
}

/// ZPL za eno nalepko kosa — glej [buildLabelLayout] za postavitev.
String buildLabelZpl({
  required LabelKind kind,
  required String itemId,
  required String orderId,
  required String pieceLabel,
  String customerName = '',
  String phone = '',
}) =>
    _toZpl(buildLabelLayout(
      kind: kind,
      itemId: itemId,
      orderId: orderId,
      pieceLabel: pieceLabel,
      customerName: customerName,
      phone: phone,
    ));

/// ZPL za generično nalepko Google ocene.
String buildReviewZpl(String url) => _toZpl(buildReviewLayout(url));

String _toZpl(LabelLayout layout) => '^XA\n'
    '^CI28\n'
    '^PW$labelWidthDots\n'
    '^LL$labelHeightDots\n'
    '${layout.fields.map((f) => f.toZpl()).join()}'
    '^FO${layout.qrX},${layout.qrY}^BQN,2,${layout.qrMag}\n'
    '^FDLA,${layout.qrData}^FS\n'
    '^XZ\n';

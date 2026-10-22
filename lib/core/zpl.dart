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

/// Spodnja vrstica: QR levo (magnifikacija 7 = 147 pik za verzijo 1, kar je
/// vsak ID kosa), besedilo desno od njega.
const _rowY = 146;
const _qrMag = 7;
const _qrSize = 21 * _qrMag;
const _textX = labelMarginDots + _qrSize + 28;
const _textW = labelWidthDots - _textX - labelMarginDots;

/// Ocenjena širina besedila v pikah. Vgrajena pisava 0 na ZD230 je pri
/// `^A0N,h,h` široka ~0.57 × h na znak (izmerjeno na fotografiji prave
/// nalepke: "LJ-142" pri h=72 je ~247 pik). Uporabljata jo preverjanje
/// prekrivanja v testih in [_pieceSize].
double estimateTextWidth(String text, int size) => text.length * size * 0.57;

/// Velikost "x/y" ob veliki oznaki: dvomestna števila ("12/20") so daljša, zato
/// se pomanjšajo, da ne zlezejo čez oznako na isti črti.
int _pieceSize(String piece, int base) => switch (piece.length) {
  <= 3 => base,
  4 => (base * 0.78).round(),
  _ => (base * 0.64).round(),
};

/// Velikost ID-ja naročila: po 999 naročilih dobi številko cikla (LJ1-001), ID
/// je daljši in se mora pomanjšati, da x/y ostane poleg.
int _orderIdSize(String order) => switch (order.length) {
  <= 6 => 84,
  7 => 72,
  _ => 60,
};

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

/// Celotna postavitev ene nalepke: besedilna polja + QR kode.
class LabelLayout {
  const LabelLayout({required this.fields, required this.qrData});

  final List<LabelField> fields;

  /// Vsebina QR kode (ID kosa).
  final String qrData;

  /// QR levo spodaj: položaj in velikost v pikah.
  static const qrX = labelMarginDots;
  static const qrY = _rowY;
  static const qrMag = _qrMag;
  static const qrSize = _qrSize;
}

/// Tri vrste nalepk (V8 §5). Nalepka mora takoj povedati, kam kos sodi —
/// brez informacij o prevzemni točki.
enum LabelKind {
  /// MB / CE / DOL: velika oznaka regije + x/y + ime/telefon + QR.
  region,

  /// LJ dostava: velik interni ID naročila (LJ-099) + x/y + QR, ime manjše.
  ljDelivery,

  /// LJ Pripeljano: veliko ime + telefon + x/y + QR.
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

/// Postavitev nalepke (60×40mm ležeče). Zgornja vrstica je velika oznaka
/// (regija / ID naročila / ime), spodaj levo je QR kode kosa, desno od nje pa
/// preostalo besedilo glede na [kind].
///
/// `itemId` je hkrati vsebina QR kode in (majhen) natisnjen tekst na vseh
/// vrstah — brez tega ročni vnos oznake, ko QR ne skenira (glej
/// `scanner_screen.dart`), na nalepki ne bi imel kaj prepisati. [orderId]
/// (npr. LJ-099) je pri dostavi iz Ljubljane največje besedilo, [pieceLabel]
/// je "3/4".
LabelLayout buildLabelLayout({
  required LabelKind kind,
  required String itemId,
  required String orderId,
  required String pieceLabel,
  String customerName = '',
  String phone = '',
  String regionCode = '',
}) {
  final name = _escapeZpl(customerName);
  final id = _escapeZpl(itemId);
  final order = _escapeZpl(orderId);
  final tel = _escapeZpl(phone);
  final piece = _escapeZpl(pieceLabel);
  final region = _escapeZpl(regionCode);

  const left = labelMarginDots;
  const fullW = labelWidthDots - 2 * labelMarginDots;
  final fields = <LabelField>[];

  void top(int y, int w, int size, String text,
      {int maxLines = 1, String align = 'L'}) {
    if (text.isEmpty) return;
    fields.add(LabelField(
      x: left,
      y: y,
      w: w,
      size: size,
      text: text,
      maxLines: maxLines,
      align: align,
    ));
  }

  // Desni stolpec se sestavlja od zgoraj navzdol; vrstice brez podatka (npr.
  // telefon, ki ga stranka nima) se preskočijo, da ne ostane luknja.
  var y = _rowY;
  void line(String text, int size, {int maxLines = 1, int gap = 10}) {
    if (text.isEmpty) return;
    fields.add(LabelField(
      x: _textX,
      y: y,
      w: _textW,
      size: size,
      text: text,
      maxLines: maxLines,
    ));
    y += size * maxLines + gap;
  }

  switch (kind) {
    case LabelKind.region:
      // Velika oznaka regije levo, jasen x/4 desno na isti črti.
      top(12, 300, 116, region);
      top(31, fullW, _pieceSize(piece, 92), piece, align: 'R');
      line(name, 36, maxLines: 2);
      line(tel, 34);
      line(id, 22);
    case LabelKind.ljDelivery:
      // Velik ID naročila, poleg jasno x/y; ime je manjše.
      top(14, 360, _orderIdSize(order), order);
      top(30, fullW, _pieceSize(piece, 64), piece, align: 'R');
      line(name, 34, maxLines: 2);
      line(id, 24);
    case LabelKind.dropoff:
      // Veliko ime (do 2 vrstici), pod njim telefon in jasen x/y.
      top(14, fullW, 50, name, maxLines: 2);
      line(tel, 40);
      line(piece, 76);
      line(id, 22);
  }
  return LabelLayout(fields: fields, qrData: id);
}

/// ZPL za eno nalepko — glej [buildLabelLayout] za postavitev.
String buildLabelZpl({
  required LabelKind kind,
  required String itemId,
  required String orderId,
  required String pieceLabel,
  String customerName = '',
  String phone = '',
  String regionCode = '',
}) {
  final layout = buildLabelLayout(
    kind: kind,
    itemId: itemId,
    orderId: orderId,
    pieceLabel: pieceLabel,
    customerName: customerName,
    phone: phone,
    regionCode: regionCode,
  );
  final top = layout.fields.where((f) => f.y < _rowY).map((f) => f.toZpl());
  final side = layout.fields.where((f) => f.y >= _rowY).map((f) => f.toZpl());
  return '^XA\n'
      '^CI28\n'
      '^PW$labelWidthDots\n'
      '^LL$labelHeightDots\n'
      '${top.join()}'
      '^FO${LabelLayout.qrX},${LabelLayout.qrY}^BQN,2,${LabelLayout.qrMag}\n'
      '^FDLA,${layout.qrData}^FS\n'
      '${side.join()}'
      '^XZ\n';
}

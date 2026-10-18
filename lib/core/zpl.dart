import '../models/enums.dart';

/// ZPL predloge za nalepke, natisnjene na Zebra ZD230 (glej
/// `lib/data/zebra_printer.dart` za pošiljanje po omrežju).
///
/// Nalepka je pokončna (portret): 40mm široka, 60mm visoka, pri 203 dpi
/// (edina ločljivost, v kateri obstaja ZD230; 8 dots/mm). Če se medij v
/// tiskalniku kdaj zamenja, spremeni [labelWidthDots]/[labelHeightDots] in
/// postavitev spodaj.
const labelWidthDots = 320; // 40mm @ 203dpi
const labelHeightDots = 480; // 60mm @ 203dpi

/// Ubeži znakom s posebnim pomenom v ZPL (`^` ukazni, `~` nadzorni), da
/// podatki iz naročila (ime stranke, ID kosa) ne razbijejo predloge.
String _escapeZpl(String value) =>
    value.replaceAll('^', '').replaceAll('~', '').replaceAll('\n', ' ');

/// Besedilna vrstica, poravnana na sredino nalepke. `^FB` čez celotno širino
/// z `C` poskrbi za centriranje — ZPL sam po sebi besedila ne centrira.
String _centeredLine(int y, int fontSize, String text, {int maxLines = 1}) =>
    '^FO0,$y^FB$labelWidthDots,$maxLines,0,C,0'
    '^A0N,$fontSize,$fontSize^FD$text^FS\n';

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

/// Zgradi ZPL za eno nalepko kosa preproge. QR koda kosa je vedno na vrhu
/// (na sredini), pod njo pa besedilo glede na [kind].
///
/// `itemId` je hkrati vsebina QR kode in (majhen) natisnjen tekst — brez tega
/// ročni vnos oznake, ko QR ne skenira (glej `scanner_screen.dart`), na
/// nalepki ne bi imel kaj prepisati. [orderId] (npr. LJ-099) je pri dostavi
/// iz Ljubljane največje besedilo, [pieceLabel] je "3/4".
String buildLabelZpl({
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

  // Vrstice brez podatka (npr. telefon, ki ga stranka nima) se preskočijo in
  // naslednje se pomaknejo navzgor, da med njimi ne ostane luknja.
  final body = StringBuffer();
  var y = 215;
  void line(String text, int fontSize, {int maxLines = 1, int gap = 8}) {
    if (text.isEmpty) return;
    body.write(_centeredLine(y, fontSize, text, maxLines: maxLines));
    y += fontSize * maxLines + gap;
  }

  switch (kind) {
    case LabelKind.region:
      line(region, 100, gap: 6);
      line(piece, 56);
      line(name, 28);
      line(tel, 26);
    case LabelKind.ljDelivery:
      line(order, 72, gap: 6);
      line(piece, 58);
      line(name, 26, maxLines: 2);
      line(id, 20);
    case LabelKind.dropoff:
      line(name, 34, maxLines: 2);
      line(tel, 30);
      line(piece, 58);
      line(id, 20);
  }

  return '^XA\n'
      '^CI28\n'
      '^PW$labelWidthDots\n'
      '^LL$labelHeightDots\n'
      '^FO85,40^BQN,2,7\n'
      '^FDLA,$id^FS\n'
      '$body'
      '^XZ\n';
}

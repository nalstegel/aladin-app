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

/// Zgradi ZPL za eno nalepko kosa preproge. QR koda kosa je vedno na vrhu
/// (na sredini), pod njo pa besedilo, ki je odvisno od načina naročila (QA v4
/// §8 "Etikete"): etiketa mora zaposlenemu takoj povedati, kam kos odloži.
///
/// * Dostave ([dropoff] = false): najbolj viden je ID kosa (npr. LJ-021-1),
///   pod njim ime stranke in mere.
/// * Pripeljano ([dropoff] = true): najbolj vidni so ime stranke, telefon in
///   "KOS x/y", da se kosi iste stranke fizično združijo brez telefona. ID
///   kosa je pod tem manjši.
///
/// `itemId` je na obeh vrstah hkrati vsebina QR kode in natisnjen kot
/// besedilo — brez tega bi ročni vnos oznake, ko QR ne skenira (glej
/// `scanner_screen.dart`), na nalepki nimal kaj prepisati.
String buildLabelZpl({
  required String customerName,
  required String dimensions,
  required String itemId,
  bool dropoff = false,
  String phone = '',
  String pieceLabel = '',
}) {
  final name = _escapeZpl(customerName);
  final size = _escapeZpl(dimensions);
  final id = _escapeZpl(itemId);
  final tel = _escapeZpl(phone);
  final piece = _escapeZpl(pieceLabel);

  // Vrstice brez podatka (npr. mere, dokler kos ni izmerjen) se preskočijo
  // — sam pomišljaj na nalepki izgleda kot madež, ne kot podatek — in
  // naslednje se pomaknejo navzgor, da med njimi ne ostane luknja.
  final body = StringBuffer();
  var y = 215;
  void line(String text, int fontSize, {int maxLines = 1, int gap = 8}) {
    if (text.isEmpty) return;
    body.write(_centeredLine(y, fontSize, text, maxLines: maxLines));
    y += fontSize * maxLines + gap;
  }

  if (dropoff) {
    line(name, 34, maxLines: 2);
    line(tel, 30);
    line(piece, 36);
    line(id, 22);
    line(size, 20);
  } else {
    line(id, 48, gap: 12);
    line(name, 26, maxLines: 2);
    line(size, 22);
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

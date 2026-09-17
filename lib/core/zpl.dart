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

/// Zgradi ZPL za eno nalepko kosa preproge: QR koda kosa na vrhu (na sredini),
/// pod njo pa na sredino poravnani št. naročila, ime stranke, mere preproge
/// in ID kosa.
///
/// `itemId` je hkrati vsebina QR kode in natisnjen kot besedilo — brez tega
/// bi ročni vnos oznake, ko QR ne skenira (glej `scanner_screen.dart`), na
/// nalepki nimal kaj prepisati.
String buildLabelZpl({
  required String orderId,
  required String customerName,
  required String dimensions,
  required String itemId,
}) {
  final order = _escapeZpl(orderId);
  final name = _escapeZpl(customerName);
  final size = _escapeZpl(dimensions);
  final id = _escapeZpl(itemId);

  // Preskoči vrstico z merami, dokler kos ni izmerjen — sam pomišljaj na
  // nalepki izgleda kot madež, ne kot podatek. ID kosa se takrat pomakne
  // navzgor, da med vrsticami ne ostane luknja.
  final sizeLine = size.isEmpty ? '' : _centeredLine(310, 24, size);
  final idY = size.isEmpty ? 310 : 350;

  return '^XA\n'
      '^CI28\n'
      '^PW$labelWidthDots\n'
      '^LL$labelHeightDots\n'
      '^FO85,40^BQN,2,7\n'
      '^FDLA,$id^FS\n'
      '${_centeredLine(215, 40, order)}'
      '${_centeredLine(265, 28, name, maxLines: 2)}'
      '$sizeLine'
      '${_centeredLine(idY, 22, id)}'
      '^XZ\n';
}

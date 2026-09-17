/// ZPL predloge za nalepke, natisnjene na Zebra ZD230 (glej
/// `lib/data/zebra_printer.dart` za pošiljanje po omrežju).
///
/// Nalepka je pokončna (portret): 40mm široka, 60mm visoka, pri 203 dpi
/// (edina ločljivost, v kateri obstaja ZD230; 8 dots/mm) — kar so v resnici
/// izmerili na fizični nalepki, potem ko je prva različica (60×40 ležeče)
/// pustila velik prazen prostor na natisnjeni etiketi. Če se medij v
/// tiskalniku kdaj zamenja, spremeni [labelWidthDots]/[labelHeightDots] in
/// postavitev spodaj.
const labelWidthDots = 320; // 40mm @ 203dpi
const labelHeightDots = 480; // 60mm @ 203dpi

/// Ubeži znakom s posebnim pomenom v ZPL (`^` ukazni, `~` nadzorni), da
/// podatki iz naročila (ime stranke, ID kosa) ne razbijejo predloge.
String _escapeZpl(String value) =>
    value.replaceAll('^', '').replaceAll('~', '').replaceAll('\n', ' ');

/// Zgradi ZPL za eno nalepko kosa preproge: QR koda kosa na vrhu (na sredini),
/// pod njo pa št. naročila, ime stranke, mere preproge in ID kosa kot
/// besedilo. `itemId` je hkrati vsebina QR kode in natisnjen kot majhno
/// besedilo — brez tega bi ročni vnos oznake, ko QR ne skenira (glej
/// `scanner_screen.dart`), na nalepki nimal kaj prepisati.
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

  // Preskoči vrstico z merami, dokler kos ni izmerjen — prazna vrstica z
  // enim samim pomišljajem na nalepki izgleda kot madež, ne kot podatek.
  final sizeLine = size.isEmpty ? '' : '^FO16,314^A0N,20,20^FD$size^FS\n';

  return '^XA\n'
      '^CI28\n'
      '^PW$labelWidthDots\n'
      '^LL$labelHeightDots\n'
      '^FO76,20^BQN,2,8\n'
      '^FDLA,$id^FS\n'
      '^FO16,204^A0N,36,36^FD$order^FS\n'
      '^FO16,248^FB288,2,4,L,0^A0N,24,24^FD$name^FS\n'
      '$sizeLine'
      '^FO16,350^A0N,18,18^FD$id^FS\n'
      '^XZ\n';
}

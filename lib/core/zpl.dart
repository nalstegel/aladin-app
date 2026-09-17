/// ZPL predloge za nalepke, natisnjene na Zebra ZD230 (glej
/// `lib/data/zebra_printer.dart` za pošiljanje po omrežju).
///
/// Velikost nalepke je 60×40 mm pri 203 dpi (edina ločljivost, v kateri
/// obstaja ZD230; 8 dots/mm). Če se medij v tiskalniku kdaj zamenja,
/// spremeni [labelWidthDots]/[labelHeightDots] in postavitev spodaj.
const labelWidthDots = 480; // 60mm @ 203dpi
const labelHeightDots = 320; // 40mm @ 203dpi

/// Ubeži znakom s posebnim pomenom v ZPL (`^` ukazni, `~` nadzorni), da
/// podatki iz naročila (ime stranke, ID kosa) ne razbijejo predloge.
String _escapeZpl(String value) =>
    value.replaceAll('^', '').replaceAll('~', '').replaceAll('\n', ' ');

/// Zgradi ZPL za eno nalepko kosa preproge: QR koda kosa na levi, ob njej pa
/// št. naročila, ime stranke, mere preproge in ID kosa kot besedilo — postavitev
/// je namenoma vodoravna (QR levo, besedilo desno), da izkoristi daljšo (60mm)
/// stranico nalepke namesto da bi vse skladala navpično v ožjem levem stolpcu.
/// `itemId` je hkrati vsebina QR kode in natisnjen kot majhno besedilo poleg
/// nje — brez tega bi ročni vnos oznake, ko QR ne skenira (glej
/// `scanner_screen.dart`), na nalepki nimal kaj prepisati. QR je namenoma
/// velik (magnifikacija 8), da se zanesljivo skenira tudi na hitro, ob stroju.
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

  return '^XA\n'
      '^CI28\n'
      '^PW$labelWidthDots\n'
      '^LL$labelHeightDots\n'
      '^FO16,60^BQN,2,8\n'
      '^FDLA,$id^FS\n'
      '^FO240,20^A0N,32,32^FD$order^FS\n'
      '^FO240,58^FB220,2,4,L,0^A0N,20,20^FD$name^FS\n'
      '^FO240,112^A0N,18,18^FD$size^FS\n'
      '^FO240,144^A0N,16,16^FD$id^FS\n'
      '^XZ\n';
}

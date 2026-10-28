/// Sprejmemo golo oznako ("LJ-001-2") ali povezavo ("aladin://rug/LJ-001-2").
///
/// Isto pravilo velja za QR kodo in za ročni vnos, zato je tu na enem mestu.
String normalizeScanCode(String raw) {
  final trimmed = raw.trim();
  final slash = trimmed.lastIndexOf('/');
  final code = slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
  return code.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z\-]'), '');
}

import '../models/enums.dart';

/// Zaporedna številka naročila glede na poslovalnico:
/// LJ-001 … LJ-999, nato LJ1-001 … LJ1-999, nato LJ2-001 … in tako dalje.
///
/// [n] je zaporedno mesto naročila znotraj poslovalnice (1-based) in nikoli
/// ne teče nazaj — ko zapore 3-mestno zaporedje doseže 999, se doda/poveča
/// številka tik za oznako poslovalnice namesto da bi se "001" ponovil.
String buildOrderId(OrderLocation location, int n) {
  final cycle = (n - 1) ~/ 999;
  final seq = (n - 1) % 999 + 1;
  final cycleSuffix = cycle == 0 ? '' : '$cycle';
  return '${location.code}$cycleSuffix-${seq.toString().padLeft(3, '0')}';
}

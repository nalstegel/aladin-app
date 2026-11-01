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

final _idPattern = RegExp(r'^([A-Za-z]+)(\d*)-(\d+)(?:-(\d+))?$');

/// Razčlenjen ID naročila ("LJ-005", "LJ1-012") ali kosa ("LJ-100-2").
typedef _IdKey = ({String code, int cycle, int seq, int index});

_IdKey? _parseId(String id) {
  final m = _idPattern.firstMatch(id);
  if (m == null) return null;
  return (
    code: m.group(1)!.toUpperCase(),
    cycle: m.group(2)!.isEmpty ? 0 : int.parse(m.group(2)!),
    seq: int.parse(m.group(3)!),
    index: m.group(4) == null ? 0 : int.parse(m.group(4)!),
  );
}

/// Privzeti vrstni red naročil in kosov v vseh seznamih: po ID-ju od
/// najmanjšega — manjši ID je starejše naročilo, zato je višje.
///
/// Najprej po območju v vrstnem redu filtrov (LJ, MB, CE, DOL), nato po
/// številki znotraj območja (`LJ-005` → `LJ-012` → `LJ1-001`), nazadnje po
/// zaporedni številki kosa (`LJ-100-1` → `LJ-100-2` → `LJ-100-10`).
///
/// Niza ne primerjamo kot besedila: "LJ-100-10" bi bil pred "LJ-100-2", "LJ10-001"
/// pa pred "LJ2-001". ID-ji, ki ne ustrezajo obliki, gredo na konec.
int compareOrderIds(String a, String b) {
  final ka = _parseId(a);
  final kb = _parseId(b);
  if (ka == null || kb == null) {
    if (ka != null) return -1;
    if (kb != null) return 1;
    return a.compareTo(b);
  }
  int region(String code) {
    final i = OrderLocation.values.indexWhere((l) => l.code == code);
    return i < 0 ? OrderLocation.values.length : i;
  }

  final byRegion = region(ka.code).compareTo(region(kb.code));
  if (byRegion != 0) return byRegion;
  final byCode = ka.code.compareTo(kb.code);
  if (byCode != 0) return byCode;
  final byCycle = ka.cycle.compareTo(kb.cycle);
  if (byCycle != 0) return byCycle;
  final bySeq = ka.seq.compareTo(kb.seq);
  return bySeq != 0 ? bySeq : ka.index.compareTo(kb.index);
}

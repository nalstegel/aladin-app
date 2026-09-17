import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Zebra ZD230 ima trajni, statični IP naslov (fiksiran v routerju delovne
/// postaje, kjer stoji tiskalnik) — zato je zakodiran tukaj, ne kot
/// nastavitev v aplikaciji. Če se tiskalnik kdaj premakne na drug naslov,
/// popravi samo to vrednost.
const zebraPrinterIp = '192.168.1.138';

/// Pošiljanje ZPL na Zebra ZD230 po omrežju: surova vtičnica na vrata 9100,
/// ki jo Zebrini tiskalniki vedno poslušajo ("raw TCP" tiskalna storitev) —
/// tako ne potrebujemo nobenega proizvajalčevega SDK-ja ali plugina, ista
/// koda pa dela na Androidu in iOS-u.
class ZebraPrinterService {
  static const port = 9100;
  static const _timeout = Duration(seconds: 5);

  /// Odpre vtičnico, pošlje `zpl` in jo zapre. Nalepke več kosov so lahko
  /// sklopljene v en niz (vsaka s svojim `^XA`…`^XZ`) in poslane z enim klicem.
  Future<void> print(String zpl) async {
    final socket =
        await Socket.connect(zebraPrinterIp, port, timeout: _timeout);
    try {
      socket.add(utf8.encode(zpl));
      await socket.flush();
    } finally {
      await socket.close();
    }
  }
}

final zebraPrinterServiceProvider =
    Provider<ZebraPrinterService>((ref) => ZebraPrinterService());

import 'package:intl/intl.dart';

/// Slovensko oblikovanje datumov, cen in površin.
class Fmt {
  static final _date = DateFormat('d. M. yyyy');
  static final _dateShort = DateFormat('d. M.');
  static final _time = DateFormat('HH:mm');
  static final _dateTime = DateFormat('d. M. yyyy ob HH:mm');

  static const _dni = [
    'ponedeljek',
    'torek',
    'sreda',
    'četrtek',
    'petek',
    'sobota',
    'nedelja',
  ];

  static String date(DateTime? d) => d == null ? '—' : _date.format(d);
  static String dateShort(DateTime? d) => d == null ? '—' : _dateShort.format(d);
  static String time(DateTime? d) => d == null ? '—' : _time.format(d);
  static String dateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d);

  static String weekday(DateTime d) => _dni[d.weekday - 1];

  /// "danes", "jutri", "sreda, 12. 3." — kot na listu, ki ga zamenjujemo.
  static String dayHeader(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'Danes, ${_dateShort.format(d)}';
    if (diff == 1) return 'Jutri, ${_dateShort.format(d)}';
    if (diff == -1) return 'Včeraj, ${_dateShort.format(d)}';
    final name = weekday(d);
    return '${name[0].toUpperCase()}${name.substring(1)}, ${_dateShort.format(d)}';
  }

  static String money(double v) =>
      '${v.toStringAsFixed(2).replaceAll('.', ',')} €';

  static String m2(double v) =>
      '${v.toStringAsFixed(2).replaceAll('.', ',')} m²';

  static String cm(double? v) =>
      v == null ? '—' : '${v.toStringAsFixed(0)} cm';

  /// "2,00 × 3,00 m"
  static String dimensions(double? wCm, double? lCm) {
    if (wCm == null || lCm == null) return '—';
    String m(double c) => (c / 100).toStringAsFixed(2).replaceAll('.', ',');
    return '${m(wCm)} × ${m(lCm)} m';
  }

  /// "1 kos", "2 kosa", "3 kosi", "5 kosov"
  static String pieces(int n) {
    final mod100 = n % 100;
    final mod10 = n % 10;
    if (mod100 == 1 || (mod10 == 1 && mod100 != 11)) return '$n kos';
    if (mod100 == 2 || (mod10 == 2 && mod100 != 12)) return '$n kosa';
    if (mod10 == 3 || mod10 == 4) {
      if (mod100 != 13 && mod100 != 14) return '$n kosi';
    }
    return '$n kosov';
  }

  static String relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'pravkar';
    if (diff.inMinutes < 60) return 'pred ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'pred ${diff.inHours} h';
    if (diff.inDays == 1) return 'včeraj';
    if (diff.inDays < 7) return 'pred ${diff.inDays} dnevi';
    return date(d);
  }
}

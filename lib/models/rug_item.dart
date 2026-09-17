import 'catalog.dart';
import 'enums.dart';
import 'status_event.dart';

/// Ena preproga. Ima svojo QR etiketo in svojo pot skozi proizvodnjo.
class RugItem {
  /// Oblika "LJ-001-2" (`orderId` + "-" + `index`) — hkrati vsebina QR kode.
  final String id;
  final String orderId;

  /// Zaporedna številka kosa znotraj naročila (1-based) in skupno št. kosov.
  final int index;
  final int ofTotal;

  final RugStatus status;

  /// Mere v centimetrih, kot jih vnese delavec.
  final double? widthCm;
  final double? lengthCm;

  /// Ročno vpisana površina za nepravilne oblike (m²). Prevlada nad merami.
  final double? manualM2;

  final String? rugTypeId;
  final String rugTypeName;
  final double pricePerM2;

  /// Najmanjši obračunani m², prepisan iz cenika ob vnosu mer.
  final double minChargeM2;

  final List<AppliedExtra> extras;
  final double discountPercent;

  /// Potrjena končna cena. Dokler je null, se cena še računa sproti.
  final double? confirmedPrice;

  final String notes;

  /// Opozorila, zabeležena ob prevzemu (madeži, poškodbe, obraba).
  final String condition;

  final List<StatusEvent> history;

  const RugItem({
    required this.id,
    required this.orderId,
    required this.index,
    required this.ofTotal,
    required this.status,
    this.widthCm,
    this.lengthCm,
    this.manualM2,
    this.rugTypeId,
    this.rugTypeName = '',
    this.pricePerM2 = 0,
    this.minChargeM2 = 0,
    this.extras = const [],
    this.discountPercent = 0,
    this.confirmedPrice,
    this.notes = '',
    this.condition = '',
    this.history = const [],
  });

  String get label => 'KOS $index/$ofTotal';

  /// Enako kot [orderId] — ohranjeno kot getter, ker ga UI že uporablja za
  /// prikaz. Prej je parsiral [id] (`id.split('-').first`), kar se je
  /// pokvarilo, ko so ID-ji naročil sami dobili vezaj (npr. "LJ-001").
  String get orderNumber => orderId;

  /// Kdaj se je kos nazadnje premaknil — za delovne sezname ob stroju.
  DateTime? get lastChangeAt => history.isEmpty ? null : history.last.at;

  bool get isMeasured => m2 > 0 && rugTypeId != null;

  /// Površina v m². Nepravilne oblike imajo ročni vnos.
  double get m2 {
    if (manualM2 != null && manualM2! > 0) return manualM2!;
    if (widthCm == null || lengthCm == null) return 0;
    return (widthCm! * lengthCm!) / 10000;
  }

  /// m², ki se dejansko obračuna (upošteva minimalni obračun vrste).
  double get chargeableM2 => m2 < minChargeM2 ? minChargeM2 : m2;

  /// Ali je zaradi minimalnega obračuna cena višja od dejanske izmere.
  bool get usesMinCharge => m2 > 0 && m2 < minChargeM2;

  double get basePrice => chargeableM2 * pricePerM2;

  /// Vsota vseh doplačil (popusti iz šifranta so negativni).
  double get extrasTotal => extras.fold<double>(
        0,
        (sum, e) => sum + e.amount(base: basePrice, m2: chargeableM2),
      );

  double get discountAmount =>
      (basePrice + extrasTotal) * discountPercent / 100;

  /// Izračunana cena pred potrditvijo.
  double get computedPrice {
    final total = basePrice + extrasTotal - discountAmount;
    return total < 0 ? 0 : double.parse(total.toStringAsFixed(2));
  }

  /// Cena, ki šteje v naročilo.
  double get price => confirmedPrice ?? computedPrice;

  RugItem copyWith({
    int? ofTotal,
    RugStatus? status,
    double? widthCm,
    double? lengthCm,
    double? manualM2,
    String? rugTypeId,
    String? rugTypeName,
    double? pricePerM2,
    double? minChargeM2,
    List<AppliedExtra>? extras,
    double? discountPercent,
    double? confirmedPrice,
    String? notes,
    String? condition,
    List<StatusEvent>? history,
    bool clearManualM2 = false,
    bool clearConfirmedPrice = false,
  }) {
    return RugItem(
      id: id,
      orderId: orderId,
      index: index,
      ofTotal: ofTotal ?? this.ofTotal,
      status: status ?? this.status,
      widthCm: widthCm ?? this.widthCm,
      lengthCm: lengthCm ?? this.lengthCm,
      manualM2: clearManualM2 ? null : (manualM2 ?? this.manualM2),
      rugTypeId: rugTypeId ?? this.rugTypeId,
      rugTypeName: rugTypeName ?? this.rugTypeName,
      pricePerM2: pricePerM2 ?? this.pricePerM2,
      minChargeM2: minChargeM2 ?? this.minChargeM2,
      extras: extras ?? this.extras,
      discountPercent: discountPercent ?? this.discountPercent,
      confirmedPrice:
          clearConfirmedPrice ? null : (confirmedPrice ?? this.confirmedPrice),
      notes: notes ?? this.notes,
      condition: condition ?? this.condition,
      history: history ?? this.history,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderId': orderId,
        'index': index,
        'ofTotal': ofTotal,
        'status': status.name,
        'widthCm': widthCm,
        'lengthCm': lengthCm,
        'manualM2': manualM2,
        'rugTypeId': rugTypeId,
        'rugTypeName': rugTypeName,
        'pricePerM2': pricePerM2,
        'minChargeM2': minChargeM2,
        'extras': extras.map((e) => e.toJson()).toList(),
        'discountPercent': discountPercent,
        'confirmedPrice': confirmedPrice,
        'notes': notes,
        'condition': condition,
        'history': history.map((e) => e.toJson()).toList(),
      };

  factory RugItem.fromJson(Map<String, dynamic> j) => RugItem(
        id: j['id'] as String,
        orderId: j['orderId'] as String,
        index: j['index'] as int,
        ofTotal: j['ofTotal'] as int,
        status: RugStatus.values.byName(j['status'] as String),
        widthCm: (j['widthCm'] as num?)?.toDouble(),
        lengthCm: (j['lengthCm'] as num?)?.toDouble(),
        manualM2: (j['manualM2'] as num?)?.toDouble(),
        rugTypeId: j['rugTypeId'] as String?,
        rugTypeName: j['rugTypeName'] as String? ?? '',
        pricePerM2: (j['pricePerM2'] as num?)?.toDouble() ?? 0,
        minChargeM2: (j['minChargeM2'] as num?)?.toDouble() ?? 0,
        extras: (j['extras'] as List? ?? [])
            .map((e) => AppliedExtra.fromJson(e as Map<String, dynamic>))
            .toList(),
        discountPercent: (j['discountPercent'] as num?)?.toDouble() ?? 0,
        confirmedPrice: (j['confirmedPrice'] as num?)?.toDouble(),
        notes: j['notes'] as String? ?? '',
        condition: j['condition'] as String? ?? '',
        history: (j['history'] as List? ?? [])
            .map((e) => StatusEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

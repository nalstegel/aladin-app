import 'enums.dart';
import 'return_proof.dart';

/// Naročilo — skupek preprog ene stranke. Status se vedno izpelje iz kosov.
class WorkOrder {
  /// Zaporedna številka naročila, npr. "LJ-001" (glej `lib/core/order_id.dart`).
  /// Hkrati ID in osnova za ID-je kosov ("LJ-001-2").
  final String id;

  /// Območje, kjer je bilo naročilo sprejeto — določilo predpono [id],
  /// ko je bilo naročilo ustvarjeno. Nikoli se ne spreminja za obstoječe
  /// naročilo.
  final OrderLocation location;
  final OrderChannel channel;
  final HandoverMode handover;
  final OrderStatus status;

  final String customerId;

  /// Podvojeni podatki stranke, da seznam deluje tudi brez povezave.
  final String customerName;
  final String customerPhone;
  final String customerAddress;

  final int itemCount;

  /// Za dostavo: kdaj gremo po preproge. Začetek časovnega okna (npr. 8-10);
  /// pri "Drugo" je to vpisani "Od".
  final DateTime? pickupAt;

  /// Konec časovnega okna za prevzem, če je bilo izbrano (glej [pickupAt]).
  /// Null pri naročilih, ki so dobila samo eno uro (stari podatki) ali kjer
  /// termin ni bil izbran prek okenc.
  final DateTime? pickupWindowEnd;

  /// Za dostavo: dogovorjen termin vračila.
  final DateTime? deliveryAt;

  /// Obljubljen rok, do kdaj naj bo naročilo gotovo.
  final DateTime? dueAt;

  final String notes;
  final DateTime createdAt;
  final String createdByName;
  final DateTime? readyAt;
  final DateTime? completedAt;
  final ReturnProof? returnProof;

  const WorkOrder({
    required this.id,
    required this.location,
    required this.channel,
    required this.handover,
    required this.status,
    required this.customerId,
    required this.customerName,
    this.customerPhone = '',
    this.customerAddress = '',
    required this.itemCount,
    this.pickupAt,
    this.pickupWindowEnd,
    this.deliveryAt,
    this.dueAt,
    this.notes = '',
    required this.createdAt,
    this.createdByName = '',
    this.readyAt,
    this.completedAt,
    this.returnProof,
  });

  String get number => id;

  /// Naročilo je prepozno, če je rok mimo in še ni predano.
  bool isOverdue(DateTime now) =>
      dueAt != null && status.isOpen && dueAt!.isBefore(now);

  WorkOrder copyWith({
    OrderChannel? channel,
    HandoverMode? handover,
    OrderStatus? status,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    int? itemCount,
    DateTime? pickupAt,
    DateTime? pickupWindowEnd,
    DateTime? deliveryAt,
    DateTime? dueAt,
    String? notes,
    DateTime? readyAt,
    DateTime? completedAt,
    ReturnProof? returnProof,
    bool clearReadyAt = false,
    bool clearPickupAt = false,
    bool clearPickupWindowEnd = false,
    bool clearDeliveryAt = false,
    bool clearDueAt = false,
  }) {
    return WorkOrder(
      id: id,
      location: location,
      channel: channel ?? this.channel,
      handover: handover ?? this.handover,
      status: status ?? this.status,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      itemCount: itemCount ?? this.itemCount,
      pickupAt: clearPickupAt ? null : (pickupAt ?? this.pickupAt),
      pickupWindowEnd: clearPickupWindowEnd
          ? null
          : (pickupWindowEnd ?? this.pickupWindowEnd),
      deliveryAt: clearDeliveryAt ? null : (deliveryAt ?? this.deliveryAt),
      dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      notes: notes ?? this.notes,
      createdAt: createdAt,
      createdByName: createdByName,
      readyAt: clearReadyAt ? null : (readyAt ?? this.readyAt),
      completedAt: completedAt ?? this.completedAt,
      returnProof: returnProof ?? this.returnProof,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'location': location.name,
        'channel': channel.name,
        'handover': handover.name,
        'status': status.name,
        'customerId': customerId,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'customerAddress': customerAddress,
        'itemCount': itemCount,
        'pickupAt': pickupAt?.toIso8601String(),
        'pickupWindowEnd': pickupWindowEnd?.toIso8601String(),
        'deliveryAt': deliveryAt?.toIso8601String(),
        'dueAt': dueAt?.toIso8601String(),
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'createdByName': createdByName,
        'readyAt': readyAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'returnProof': returnProof?.toJson(),
      };

  factory WorkOrder.fromJson(Map<String, dynamic> j) {
    DateTime? d(String k) =>
        j[k] == null ? null : DateTime.parse(j[k] as String);
    return WorkOrder(
      id: j['id'] as String,
      // Privzeto Ljubljana za naročila iz časa pred uvedbo poslovalnic.
      location: j['location'] == null
          ? OrderLocation.ljubljana
          : OrderLocation.values.byName(j['location'] as String),
      channel: OrderChannel.values.byName(j['channel'] as String),
      handover: HandoverMode.values.byName(j['handover'] as String),
      status: OrderStatus.values.byName(j['status'] as String),
      customerId: j['customerId'] as String,
      customerName: j['customerName'] as String,
      customerPhone: j['customerPhone'] as String? ?? '',
      customerAddress: j['customerAddress'] as String? ?? '',
      itemCount: j['itemCount'] as int,
      pickupAt: d('pickupAt'),
      pickupWindowEnd: d('pickupWindowEnd'),
      deliveryAt: d('deliveryAt'),
      dueAt: d('dueAt'),
      notes: j['notes'] as String? ?? '',
      createdAt: DateTime.parse(j['createdAt'] as String),
      createdByName: j['createdByName'] as String? ?? '',
      readyAt: d('readyAt'),
      completedAt: d('completedAt'),
      returnProof: j['returnProof'] == null
          ? null
          : ReturnProof.fromJson(j['returnProof'] as Map<String, dynamic>),
    );
  }
}

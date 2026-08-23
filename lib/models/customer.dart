import 'enums.dart';

class Customer {
  final String id;
  final CustomerType type;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String city;
  final String postalCode;

  /// Samo za podjetja.
  final String taxId;
  final String contactPerson;

  /// Samodejno predlagan popust pri končni obdelavi (%).
  final double defaultDiscountPercent;
  final String notes;
  final DateTime createdAt;

  const Customer({
    required this.id,
    required this.type,
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.city = '',
    this.postalCode = '',
    this.taxId = '',
    this.contactPerson = '',
    this.defaultDiscountPercent = 0,
    this.notes = '',
    required this.createdAt,
  });

  bool get isCompany => type == CustomerType.company;

  String get fullAddress {
    final parts = [
      address,
      [postalCode, city].where((e) => e.isNotEmpty).join(' '),
    ].where((e) => e.isNotEmpty).toList();
    return parts.join(', ');
  }

  String get initials {
    final words =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    String head(String w, int n) =>
        (w.length <= n ? w : w.substring(0, n)).toUpperCase();
    if (words.length == 1) return head(words.first, 2);
    return '${head(words[0], 1)}${head(words[1], 1)}';
  }

  Customer copyWith({
    CustomerType? type,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? city,
    String? postalCode,
    String? taxId,
    String? contactPerson,
    double? defaultDiscountPercent,
    String? notes,
  }) {
    return Customer(
      id: id,
      type: type ?? this.type,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      taxId: taxId ?? this.taxId,
      contactPerson: contactPerson ?? this.contactPerson,
      defaultDiscountPercent:
          defaultDiscountPercent ?? this.defaultDiscountPercent,
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'city': city,
        'postalCode': postalCode,
        'taxId': taxId,
        'contactPerson': contactPerson,
        'defaultDiscountPercent': defaultDiscountPercent,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as String,
        type: CustomerType.values.byName(j['type'] as String),
        name: j['name'] as String,
        phone: j['phone'] as String? ?? '',
        email: j['email'] as String? ?? '',
        address: j['address'] as String? ?? '',
        city: j['city'] as String? ?? '',
        postalCode: j['postalCode'] as String? ?? '',
        taxId: j['taxId'] as String? ?? '',
        contactPerson: j['contactPerson'] as String? ?? '',
        defaultDiscountPercent:
            (j['defaultDiscountPercent'] as num?)?.toDouble() ?? 0,
        notes: j['notes'] as String? ?? '',
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

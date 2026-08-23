import 'enums.dart';

/// Vrsta / material preproge s ceno na m².
class RugType {
  final String id;
  final String name;
  final double pricePerM2;

  /// Najmanjši obračunani m² za ta tip (npr. 3 m²).
  final double minChargeM2;
  final bool active;

  const RugType({
    required this.id,
    required this.name,
    required this.pricePerM2,
    this.minChargeM2 = 0,
    this.active = true,
  });

  RugType copyWith({
    String? name,
    double? pricePerM2,
    double? minChargeM2,
    bool? active,
  }) =>
      RugType(
        id: id,
        name: name ?? this.name,
        pricePerM2: pricePerM2 ?? this.pricePerM2,
        minChargeM2: minChargeM2 ?? this.minChargeM2,
        active: active ?? this.active,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pricePerM2': pricePerM2,
        'minChargeM2': minChargeM2,
        'active': active,
      };

  factory RugType.fromJson(Map<String, dynamic> j) => RugType(
        id: j['id'] as String,
        name: j['name'] as String,
        pricePerM2: (j['pricePerM2'] as num).toDouble(),
        minChargeM2: (j['minChargeM2'] as num?)?.toDouble() ?? 0,
        active: j['active'] as bool? ?? true,
      );
}

/// Predloga doplačila ali popusta iz šifranta.
class ExtraTemplate {
  final String id;
  final String name;
  final ExtraKind kind;
  final double value;

  /// Negativna vrednost pomeni popust.
  final bool active;

  const ExtraTemplate({
    required this.id,
    required this.name,
    required this.kind,
    required this.value,
    this.active = true,
  });

  bool get isDiscount => value < 0;

  ExtraTemplate copyWith({
    String? name,
    ExtraKind? kind,
    double? value,
    bool? active,
  }) =>
      ExtraTemplate(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        value: value ?? this.value,
        active: active ?? this.active,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'value': value,
        'active': active,
      };

  factory ExtraTemplate.fromJson(Map<String, dynamic> j) => ExtraTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: ExtraKind.values.byName(j['kind'] as String),
        value: (j['value'] as num).toDouble(),
        active: j['active'] as bool? ?? true,
      );
}

/// Doplačilo/popust, dejansko pripet konkretni preprogi.
class AppliedExtra {
  final String name;
  final ExtraKind kind;
  final double value;

  const AppliedExtra({
    required this.name,
    required this.kind,
    required this.value,
  });

  /// Izračuna znesek glede na osnovo in površino.
  double amount({required double base, required double m2}) =>
      switch (kind) {
        ExtraKind.fixed => value,
        ExtraKind.perM2 => value * m2,
        ExtraKind.percent => base * value / 100,
      };

  Map<String, dynamic> toJson() =>
      {'name': name, 'kind': kind.name, 'value': value};

  factory AppliedExtra.fromJson(Map<String, dynamic> j) => AppliedExtra(
        name: j['name'] as String,
        kind: ExtraKind.values.byName(j['kind'] as String),
        value: (j['value'] as num).toDouble(),
      );

  factory AppliedExtra.fromTemplate(ExtraTemplate t) =>
      AppliedExtra(name: t.name, kind: t.kind, value: t.value);
}

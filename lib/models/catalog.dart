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
  }) => RugType(
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

  /// Če ni prazno, delavec ob obračunu izbere eno od teh vrednosti namesto
  /// [value] — npr. "Dlake" 5 € ali 10 € glede na dejansko delo (QA v4 §4).
  final List<double> choices;

  const ExtraTemplate({
    required this.id,
    required this.name,
    required this.kind,
    required this.value,
    this.active = true,
    this.choices = const [],
  });

  bool get isDiscount => value < 0;
  bool get hasChoices => choices.isNotEmpty;

  ExtraTemplate copyWith({
    String? name,
    ExtraKind? kind,
    double? value,
    bool? active,
    List<double>? choices,
  }) => ExtraTemplate(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    value: value ?? this.value,
    active: active ?? this.active,
    choices: choices ?? this.choices,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'value': value,
    'active': active,
    'choices': choices,
  };

  factory ExtraTemplate.fromJson(Map<String, dynamic> j) => ExtraTemplate(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: ExtraKind.values.byName(j['kind'] as String),
    value: (j['value'] as num).toDouble(),
    active: j['active'] as bool? ?? true,
    choices: (j['choices'] as List? ?? [])
        .map((e) => (e as num).toDouble())
        .toList(),
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
  double amount({required double base, required double m2}) => switch (kind) {
    ExtraKind.fixed => value,
    ExtraKind.perM2 => value * m2,
    ExtraKind.percent => base * value / 100,
  };

  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind.name,
    'value': value,
  };

  factory AppliedExtra.fromJson(Map<String, dynamic> j) => AppliedExtra(
    name: j['name'] as String,
    kind: ExtraKind.values.byName(j['kind'] as String),
    value: (j['value'] as num).toDouble(),
  );

  /// [value] prepiše privzeto vrednost predloge — za postavke z izbiro.
  factory AppliedExtra.fromTemplate(ExtraTemplate t, {double? value}) =>
      AppliedExtra(name: t.name, kind: t.kind, value: value ?? t.value);
}

/// Doplačila, ki se vnesejo ob fizičnem prevzemu (V8 §2) — ne v hitrem
/// obračunu. Vnos in Iznos veljata za celo naročilo, Urin in Dlake za kos.
/// Prepoznana so po imenu iz šifranta; če jih lastnik izbriše, ima prevzem
/// vgrajeno privzeto vrednost, da potek dela ne obstane.
const orderLevelExtraNames = {'Vnos', 'Iznos'};
const itemPickupExtraNames = {'Urin', 'Dlake'};

extension ExtraTemplateX on ExtraTemplate {
  /// Vnos / Iznos: samo ob prevzemu, nikoli na zaslonu Hitrega obračuna.
  bool get isOrderLevel => orderLevelExtraNames.contains(name);
}

/// Predloga doplačila po imenu iz šifranta; če je tam ni (več), vgrajena.
/// Prevzem in urejanje naročila morata delovati tudi, če je lastnik
/// Vnos / Iznos izbrisal iz šifranta.
ExtraTemplate templateOrFallback(
  Iterable<ExtraTemplate> catalog,
  ExtraTemplate fallback,
) {
  for (final t in catalog) {
    if (t.active && t.name == fallback.name) return t;
  }
  return fallback;
}

const fallbackOrderExtras = [
  ExtraTemplate(id: 'e-vnos', name: 'Vnos', kind: ExtraKind.fixed, value: 5),
  ExtraTemplate(id: 'e-iznos', name: 'Iznos', kind: ExtraKind.fixed, value: 5),
];

const fallbackItemExtras = [
  ExtraTemplate(id: 'e-urin', name: 'Urin', kind: ExtraKind.perM2, value: 3),
  ExtraTemplate(
    id: 'e-dlake',
    name: 'Dlake',
    kind: ExtraKind.fixed,
    value: 5,
    choices: [5, 10],
  ),
];

/// Vrstni red vrst preprog v Hitrem obračunu (V10 §1): Sintetika / tanki
/// tepihi, Shaggy / kosmati, Volna, Perzija / ročno vozlana.
///
/// Šifrant v bazi ureja lastnik in nima polja za vrstni red, zato se vrste
/// razvrstijo po imenu; neznane ostanejo na koncu v vrstnem redu iz šifranta.
List<RugType> sortedRugTypes(Iterable<RugType> types) {
  int rank(String name) {
    final n = name.toLowerCase();
    if (n.contains('sintet')) return 0;
    if (n.contains('shaggy') || n.contains('kosmat')) return 1;
    if (n.contains('voln')) return 2;
    if (n.contains('perzij') || n.contains('vozlan')) return 3;
    return 4;
  }

  final list = types.toList();
  final order = {for (var i = 0; i < list.length; i++) list[i].id: i};
  list.sort((a, b) {
    final c = rank(a.name).compareTo(rank(b.name));
    return c != 0 ? c : order[a.id]!.compareTo(order[b.id]!);
  });
  return list;
}

/// Vrstni red doplačil v Hitrem obračunu (V10 §1): Urin, Dlake, Ponovno
/// pranje; ostala doplačila in popusti za njimi.
List<ExtraTemplate> sortedQuickExtras(Iterable<ExtraTemplate> templates) {
  int rank(String name) {
    final n = name.toLowerCase();
    if (n.contains('urin')) return 0;
    if (n.contains('dlak')) return 1;
    if (n.contains('pranje')) return 2;
    return 3;
  }

  final list = templates.toList();
  final order = {for (var i = 0; i < list.length; i++) list[i].id: i};
  list.sort((a, b) {
    final c = rank(a.name).compareTo(rank(b.name));
    return c != 0 ? c : order[a.id]!.compareTo(order[b.id]!);
  });
  return list;
}

import 'enums.dart';

class AppUser {
  /// Za zaposlene s prijavo je to Firebase Auth UID, da je zapis o tem,
  /// kdo je izvedel korak, vezan na dejanski račun in ne na ime s seznama.
  final String id;
  final String name;

  /// E-pošta računa. Prazna pri starih (demo) zapisih brez prijave —
  /// po tem tudi ločimo, ali je kdo že povezan s pravim računom.
  final String email;
  final UserRole role;
  final bool active;

  const AppUser({
    required this.id,
    required this.name,
    this.email = '',
    this.role = UserRole.worker,
    this.active = true,
  });

  bool get isAdmin => role == UserRole.admin;

  /// Ali je ta zaposleni povezan s pravim računom za prijavo.
  bool get hasAccount => email.isNotEmpty;

  AppUser copyWith({
    String? name,
    String? email,
    UserRole? role,
    bool? active,
  }) =>
      AppUser(
        id: id,
        name: name ?? this.name,
        email: email ?? this.email,
        role: role ?? this.role,
        active: active ?? this.active,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role.name,
        'active': active,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        email: j['email'] as String? ?? '',
        role: UserRole.values.byName(j['role'] as String? ?? 'worker'),
        active: j['active'] as bool? ?? true,
      );
}

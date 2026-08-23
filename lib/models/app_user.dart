import 'enums.dart';

class AppUser {
  final String id;
  final String name;
  final UserRole role;
  final bool active;

  const AppUser({
    required this.id,
    required this.name,
    this.role = UserRole.worker,
    this.active = true,
  });

  bool get isAdmin => role == UserRole.admin;

  AppUser copyWith({String? name, UserRole? role, bool? active}) => AppUser(
        id: id,
        name: name ?? this.name,
        role: role ?? this.role,
        active: active ?? this.active,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'role': role.name, 'active': active};

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        role: UserRole.values.byName(j['role'] as String? ?? 'worker'),
        active: j['active'] as bool? ?? true,
      );
}

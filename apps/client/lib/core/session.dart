import 'role_permissions.dart';

class AuthSession {
  AuthSession({
    required this.token,
    required this.role,
    this.email,
    this.fullName,
    List<String>? permissions,
  }) : permissions = permissions ?? rolePermissions[role]?.toList() ?? const [];

  final String token;
  final String role;
  final String? email;
  final String? fullName;
  final List<String> permissions;

  bool can(String permission) =>
      role == 'admin' || permissions.contains(permission);
}


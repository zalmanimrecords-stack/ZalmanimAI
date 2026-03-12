class AuthSession {
  AuthSession({
    required this.token,
    required this.role,
    this.email,
    this.fullName,
  });

  final String token;
  final String role;
  final String? email;
  final String? fullName;
}


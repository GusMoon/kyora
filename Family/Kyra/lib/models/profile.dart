/// Quién eres en Kyora: el administrador (chat y música) o un pasante (solo música). Viene de la tabla `profiles`.
enum Role { admin, intern }

class Profile {
  const Profile({required this.id, required this.username, required this.role});

  final String id;
  final String username;
  final Role role;

  bool get isAdmin => role == Role.admin;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        username: (json['username'] as String?) ?? '',
        role: roleFromName(json['role'] as String?),
      );
}

/// Todo lo que no sea `admin` es pasante: ante la duda, la vista con menos permisos.
Role roleFromName(String? name) => name == 'admin' ? Role.admin : Role.intern;

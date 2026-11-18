/// Quién eres en Kyora: el administrador (todo) o un visitante (música y chat). Viene de la tabla `profiles`. En la base de datos el
/// visitante se llama `intern`; en pantalla es «Visitante».
enum Role { admin, intern }

class Profile {
  const Profile({required this.id, required this.username, required this.role, this.verified = true});

  final String id;
  final String username;
  final Role role;

  /// Ya canjeó su código de 6 dígitos (el administrador crea las cuentas con uno). Sin eso no entra al chat.
  final bool verified;

  bool get isAdmin => role == Role.admin;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        username: (json['username'] as String?) ?? '',
        role: roleFromName(json['role'] as String?),
        // un servidor sin la columna (esquema viejo) no pide código a nadie
        verified: (json['verified'] as bool?) ?? true,
      );
}

/// Todo lo que no sea `admin` es visitante: ante la duda, la vista con menos permisos.
Role roleFromName(String? name) => name == 'admin' ? Role.admin : Role.intern;

/// El nombre del rol tal como se enseña.
String roleLabel(Role role) => role == Role.admin ? 'Administrador' : 'Visitante';

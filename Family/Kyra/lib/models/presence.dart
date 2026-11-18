import 'profile.dart';

/// Una cuenta en el panel del administrador: quién es, su rol, si ya verificó su código y si está en línea (`list_presence`).
class PresenceEntry {
  const PresenceEntry({
    required this.id,
    required this.username,
    required this.role,
    required this.verified,
    required this.online,
    this.lastSeen,
    this.codePending = false,
    this.me = false,
  });

  final String id;
  final String username;
  final Role role;
  final bool verified;

  /// Visto en los últimos 90 segundos.
  final bool online;
  final DateTime? lastSeen;

  /// Tiene un código de 6 dígitos vigente que aún no canjeó.
  final bool codePending;

  /// Es la cuenta de quien mira el panel.
  final bool me;

  factory PresenceEntry.fromJson(Map<String, dynamic> json) {
    final seen = json['last_seen'] as String?;
    return PresenceEntry(
      id: json['id'] as String,
      username: (json['username'] as String?) ?? '',
      role: roleFromName(json['role'] as String?),
      verified: (json['verified'] as bool?) ?? false,
      online: (json['online'] as bool?) ?? false,
      lastSeen: seen == null ? null : DateTime.parse(seen).toUtc(),
      codePending: (json['code_pending'] as bool?) ?? false,
      me: (json['me'] as bool?) ?? false,
    );
  }
}

/// Lo que devuelve crear una cuenta (o pedir otro código): el código de 6 dígitos se enseña **una sola vez**.
class IssuedCode {
  const IssuedCode({required this.username, required this.code});

  final String username;
  final String code;
}

/// «en línea», «hace 5 min», «hace 3 h», «hace 2 d» o «nunca».
String lastSeenText(PresenceEntry entry, DateTime now) {
  if (entry.online) return 'en línea';
  final seen = entry.lastSeen;
  if (seen == null) return 'nunca entró';
  final gap = now.toUtc().difference(seen);
  if (gap.inMinutes < 1) return 'hace un momento';
  if (gap.inMinutes < 60) return 'hace ${gap.inMinutes} min';
  if (gap.inHours < 24) return 'hace ${gap.inHours} h';
  return 'hace ${gap.inDays} d';
}

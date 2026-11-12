/// Un recordatorio: un aviso a una hora. Por ahora vive solo en el teléfono (la estructura en Supabase se definirá más adelante).
class Reminder {
  const Reminder({
    required this.id,
    required this.notifId,
    required this.title,
    required this.at,
    required this.createdAt,
    this.notes = '',
    this.done = false,
  });

  final String id;

  /// El número con que se programa su aviso en Android (entero y propio de cada recordatorio).
  final int notifId;
  final String title;
  final String notes;

  /// Cuándo avisa (UTC).
  final DateTime at;
  final bool done;
  final DateTime createdAt;

  Reminder copyWith({String? title, String? notes, DateTime? at, bool? done}) => Reminder(
        id: id,
        notifId: notifId,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        at: at ?? this.at,
        done: done ?? this.done,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'notif_id': notifId,
        'title': title,
        'notes': notes,
        'at': at.toUtc().toIso8601String(),
        'done': done,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory Reminder.fromJson(Map<String, Object?> json) => Reminder(
        id: json['id']! as String,
        notifId: (json['notif_id']! as num).toInt(),
        title: json['title']! as String,
        notes: (json['notes'] as String?) ?? '',
        at: DateTime.parse(json['at']! as String).toUtc(),
        done: (json['done'] as bool?) ?? false,
        createdAt: DateTime.parse(json['created_at']! as String).toUtc(),
      );
}

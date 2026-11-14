import '../data/sync_rows.dart';

const _keep = Object();

/// El número del aviso de un recordatorio: siempre el mismo para el mismo id (también el de uno que llegó de otro dispositivo; la web no lo
/// tiene), en su propio rango (entre 2²⁰ y 2³⁰), lejos de los de los hábitos (desde 2³⁰) y de los antiguos, que cuentan desde 1.
int reminderNotifIdFor(String id) {
  var hash = 0x811C9DC5; // FNV-1a de 32 bits
  for (final unit in id.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return (1 << 20) + hash % ((1 << 30) - (1 << 20));
}

/// Un recordatorio: un aviso a una hora. Vive en el teléfono y en Supabase (tabla `reminders`, la misma que la web). Mismo esquema de
/// sincronización que las tareas: ids uuid del dispositivo, horas en UTC, gana el `updatedAt` más reciente y el borrado es suave.
class Reminder implements SyncRow {
  const Reminder({
    required this.id,
    required this.notifId,
    required this.title,
    required this.at,
    required this.createdAt,
    this.notes = '',
    this.done = false,
    DateTime? updatedAt,
    this.deletedAt,
    this.syncedAt,
    this.dirty = false,
  }) : _updatedAt = updatedAt; // ignore: prefer_initializing_formals

  @override
  final String id;

  /// El número con que se programa su aviso en Android (entero y propio de cada recordatorio; solo vale en este teléfono).
  final int notifId;
  final String title;
  final String notes;

  /// Cuándo avisa (UTC).
  final DateTime at;
  final bool done;
  final DateTime createdAt;
  final DateTime? _updatedAt;

  @override
  final DateTime? deletedAt;
  @override
  final String? syncedAt;
  @override
  final bool dirty;

  /// Los recordatorios guardados antes de sincronizarse no tienen hora de cambio: cuenta la de creación.
  @override
  DateTime get updatedAt => _updatedAt ?? createdAt;

  @override
  bool get isDeleted => deletedAt != null;

  Reminder copyWith({String? title, String? notes, DateTime? at, bool? done, DateTime? updatedAt, Object? deletedAt = _keep, bool? dirty}) => Reminder(
        id: id,
        notifId: notifId,
        title: title ?? this.title,
        notes: notes ?? this.notes,
        at: at ?? this.at,
        done: done ?? this.done,
        createdAt: createdAt,
        updatedAt: updatedAt ?? _updatedAt,
        deletedAt: identical(deletedAt, _keep) ? this.deletedAt : deletedAt as DateTime?,
        syncedAt: syncedAt,
        dirty: dirty ?? this.dirty,
      );

  @override
  Reminder withDirty(bool value) => copyWith(dirty: value);

  /// El mismo recordatorio con otro número de aviso (el de este teléfono manda sobre el que se calcula de un id que llega de fuera).
  Reminder withNotifId(int value) => Reminder(
        id: id,
        notifId: value,
        title: title,
        notes: notes,
        at: at,
        done: done,
        createdAt: createdAt,
        updatedAt: _updatedAt,
        deletedAt: deletedAt,
        syncedAt: syncedAt,
        dirty: dirty,
      );

  @override
  Reminder get fromServer => Reminder(
        id: id,
        notifId: notifId,
        title: title,
        notes: notes,
        at: at,
        done: done,
        createdAt: createdAt,
        updatedAt: _updatedAt,
        deletedAt: deletedAt,
        syncedAt: syncedAt,
      );

  /// Las columnas, tal cual van a Supabase.
  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'notes': notes,
        'remind_at': isoOf(at),
        'done': done,
        'created_at': isoOf(createdAt),
        'updated_at': isoOf(updatedAt),
        'deleted_at': isoOf(deletedAt),
      };

  /// Lo que se guarda en el teléfono: las columnas más lo que solo vale aquí.
  Map<String, Object?> toLocalJson() => {...toJson(), 'notif_id': notifId, 'synced_at': syncedAt, 'dirty': dirty};

  /// Lee una fila de Supabase o del teléfono. También las guardadas antes de sincronizar (`at` en vez de `remind_at`, sin `updated_at`): esas
  /// quedan «por subir» para que lleguen a Supabase.
  factory Reminder.fromJson(Map<String, Object?> json) {
    final id = json['id']! as String;
    final legacy = json['updated_at'] == null;
    return Reminder(
      id: id,
      notifId: (json['notif_id'] as num?)?.toInt() ?? reminderNotifIdFor(id),
      title: json['title']! as String,
      notes: (json['notes'] as String?) ?? '',
      at: parseTime(json['remind_at'] ?? json['at'])!,
      done: json['done'] == true || json['done'] == 1,
      createdAt: parseTime(json['created_at'])!,
      updatedAt: parseTime(json['updated_at']),
      deletedAt: parseTime(json['deleted_at']),
      syncedAt: json['synced_at'] as String?,
      dirty: legacy || json['dirty'] == true || json['dirty'] == 1,
    );
  }
}

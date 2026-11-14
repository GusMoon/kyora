import '../data/sync_rows.dart';

const _keep = Object();

/// Los colores de un evento (los mismos que Merida), como `#rrggbb`.
const eventColors = ['#35d4ff', '#c8f73a', '#ff5a1f', '#ff4fd8', '#ffd23f', '#c9cebc'];

/// Un evento del calendario: algo que pasa a una hora (o todo el día, o varios días). Vive en el teléfono y en Supabase (tabla `events`, la misma
/// que la web). Mismo esquema de sincronización que las tareas: ids uuid del dispositivo, horas en UTC, gana el `updatedAt` más reciente y el
/// borrado es suave.
class CalendarEvent implements SyncRow {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.endsAt,
    this.allDay = false,
    this.color = '#35d4ff',
    this.taskId,
    this.deletedAt,
    this.syncedAt,
    this.dirty = false,
  });

  @override
  final String id;
  final String title;
  final String description;

  /// Cuándo empieza (UTC). Con [allDay], el día de calendario local de ese instante.
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool allDay;
  final String color;
  final String? taskId;
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final String? syncedAt;
  @override
  final bool dirty;

  @override
  bool get isDeleted => deletedAt != null;

  CalendarEvent copyWith({
    String? title,
    String? description,
    DateTime? startsAt,
    Object? endsAt = _keep,
    bool? allDay,
    String? color,
    DateTime? updatedAt,
    Object? deletedAt = _keep,
    bool? dirty,
  }) =>
      CalendarEvent(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        startsAt: startsAt ?? this.startsAt,
        endsAt: identical(endsAt, _keep) ? this.endsAt : endsAt as DateTime?,
        allDay: allDay ?? this.allDay,
        color: color ?? this.color,
        taskId: taskId,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: identical(deletedAt, _keep) ? this.deletedAt : deletedAt as DateTime?,
        syncedAt: syncedAt,
        dirty: dirty ?? this.dirty,
      );

  @override
  CalendarEvent withDirty(bool value) => copyWith(dirty: value);

  @override
  CalendarEvent get fromServer => CalendarEvent(
        id: id,
        title: title,
        description: description,
        startsAt: startsAt,
        endsAt: endsAt,
        allDay: allDay,
        color: color,
        taskId: taskId,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        syncedAt: syncedAt,
      );

  /// Las columnas, tal cual van a Supabase.
  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'starts_at': isoOf(startsAt),
        'ends_at': isoOf(endsAt),
        'all_day': allDay,
        'color': color,
        'task_id': taskId,
        'created_at': isoOf(createdAt),
        'updated_at': isoOf(updatedAt),
        'deleted_at': isoOf(deletedAt),
      };

  /// Lo que se guarda en el teléfono: las columnas más lo que solo vale aquí.
  Map<String, Object?> toLocalJson() => {...toJson(), 'synced_at': syncedAt, 'dirty': dirty};

  factory CalendarEvent.fromJson(Map<String, Object?> json) => CalendarEvent(
        id: json['id']! as String,
        title: json['title']! as String,
        description: (json['description'] as String?) ?? '',
        startsAt: parseTime(json['starts_at'])!,
        endsAt: parseTime(json['ends_at']),
        allDay: json['all_day'] == true || json['all_day'] == 1,
        color: (json['color'] as String?) ?? eventColors.first,
        taskId: json['task_id'] as String?,
        createdAt: parseTime(json['created_at'])!,
        updatedAt: parseTime(json['updated_at'])!,
        deletedAt: parseTime(json['deleted_at']),
        syncedAt: json['synced_at'] as String?,
        dirty: json['dirty'] == true || json['dirty'] == 1,
      );
}

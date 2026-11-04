/// El estado de una tarea: los mismos cuatro que las columnas del Kanban del escritorio.
enum TaskStatus {
  pending('pending', 'Pendiente'),
  doing('doing', 'En proceso'),
  review('review', 'En revisión'),
  done('done', 'Finalizada');

  const TaskStatus(this.wire, this.label);

  /// Cómo se guarda (en el teléfono y en Supabase).
  final String wire;

  /// Cómo se lee en pantalla.
  final String label;

  static TaskStatus parse(String? wire) => values.firstWhere((s) => s.wire == wire, orElse: () => pending);
}

DateTime? _time(Object? value) => value == null ? null : DateTime.parse(value as String).toUtc();

String? _iso(DateTime? value) => value?.toUtc().toIso8601String();

const _keep = Object();

/// Una tarea o una subtarea (`parentId`: solo hay un nivel). Mismo modelo que `tasks` en el escritorio y en Supabase, con
/// ids únicos (uuid) y horas en UTC. `updatedAt` decide quién gana si dos dispositivos cambian lo mismo; `deletedAt` es el borrado
/// suave que se sincroniza.
class TaskItem {
  const TaskItem({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.position = 0,
    this.description = '',
    this.status = TaskStatus.pending,
    this.expectedMin,
    this.realS = 0,
    this.timerStarted,
    this.due,
    this.finished,
    this.deletedAt,
    this.syncedAt,
  });

  final String id;
  final String? parentId;

  /// El lugar entre sus hermanas (las subtareas van en orden).
  final int position;
  final String name;
  final String description;
  final TaskStatus status;

  /// Minutos que se espera que lleve.
  final int? expectedMin;

  /// Segundos acumulados por el cronómetro (el escritorio lo usa; aquí solo se conserva).
  final int realS;
  final DateTime? timerStarted;
  final DateTime? due;
  final DateTime? finished;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// La hora del servidor en que se guardó por última vez (solo viene de Supabase; sirve de punto de partida al pedir novedades).
  final String? syncedAt;

  bool get isDone => status == TaskStatus.done;
  bool get isSub => parentId != null;
  bool get isDeleted => deletedAt != null;

  TaskItem copyWith({
    Object? parentId = _keep,
    int? position,
    String? name,
    String? description,
    TaskStatus? status,
    Object? expectedMin = _keep,
    int? realS,
    Object? timerStarted = _keep,
    Object? due = _keep,
    Object? finished = _keep,
    DateTime? updatedAt,
    Object? deletedAt = _keep,
  }) =>
      TaskItem(
        id: id,
        parentId: identical(parentId, _keep) ? this.parentId : parentId as String?,
        position: position ?? this.position,
        name: name ?? this.name,
        description: description ?? this.description,
        status: status ?? this.status,
        expectedMin: identical(expectedMin, _keep) ? this.expectedMin : expectedMin as int?,
        realS: realS ?? this.realS,
        timerStarted: identical(timerStarted, _keep) ? this.timerStarted : timerStarted as DateTime?,
        due: identical(due, _keep) ? this.due : due as DateTime?,
        finished: identical(finished, _keep) ? this.finished : finished as DateTime?,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: identical(deletedAt, _keep) ? this.deletedAt : deletedAt as DateTime?,
        syncedAt: syncedAt,
      );

  /// Las columnas, tal cual van a Supabase y al teléfono.
  Map<String, Object?> toJson() => {
        'id': id,
        'parent_id': parentId,
        'position': position,
        'name': name,
        'description': description,
        'status': status.wire,
        'expected_min': expectedMin,
        'real_s': realS,
        'timer_started': _iso(timerStarted),
        'due': _iso(due),
        'finished': _iso(finished),
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
        'deleted_at': _iso(deletedAt),
      };

  factory TaskItem.fromJson(Map<String, Object?> json) => TaskItem(
        id: json['id'] as String,
        parentId: json['parent_id'] as String?,
        position: (json['position'] as num?)?.toInt() ?? 0,
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        status: TaskStatus.parse(json['status'] as String?),
        expectedMin: (json['expected_min'] as num?)?.toInt(),
        realS: (json['real_s'] as num?)?.toInt() ?? 0,
        timerStarted: _time(json['timer_started']),
        due: _time(json['due']),
        finished: _time(json['finished']),
        createdAt: _time(json['created_at'])!,
        updatedAt: _time(json['updated_at'])!,
        deletedAt: _time(json['deleted_at']),
        syncedAt: json['synced_at'] as String?,
      );
}

/// Una etiqueta (independiente de las tareas; se le pone a las que quieras).
class Tag {
  const Tag({required this.id, required this.name, required this.color, required this.updatedAt, this.deletedAt, this.syncedAt});

  final String id;
  final String name;

  /// Un color «#RRGGBB».
  final String color;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? syncedAt;

  Tag copyWith({DateTime? updatedAt, Object? deletedAt = _keep}) => Tag(
        id: id,
        name: name,
        color: color,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: identical(deletedAt, _keep) ? this.deletedAt : deletedAt as DateTime?,
        syncedAt: syncedAt,
      );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'color': color, 'updated_at': _iso(updatedAt), 'deleted_at': _iso(deletedAt)};

  factory Tag.fromJson(Map<String, Object?> json) => Tag(
        id: json['id'] as String,
        name: json['name'] as String,
        color: (json['color'] as String?) ?? '#888888',
        updatedAt: _time(json['updated_at'])!,
        deletedAt: _time(json['deleted_at']),
        syncedAt: json['synced_at'] as String?,
      );
}

/// Que una tarea lleva una etiqueta. Quitarla es un borrado suave (así también se sincroniza).
class TaskTag {
  const TaskTag({required this.taskId, required this.tagId, required this.updatedAt, this.deletedAt, this.syncedAt});

  final String taskId;
  final String tagId;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? syncedAt;

  String get key => '$taskId|$tagId';

  TaskTag copyWith({DateTime? updatedAt, Object? deletedAt = _keep}) => TaskTag(
        taskId: taskId,
        tagId: tagId,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: identical(deletedAt, _keep) ? this.deletedAt : deletedAt as DateTime?,
        syncedAt: syncedAt,
      );

  Map<String, Object?> toJson() => {'task_id': taskId, 'tag_id': tagId, 'updated_at': _iso(updatedAt), 'deleted_at': _iso(deletedAt)};

  factory TaskTag.fromJson(Map<String, Object?> json) => TaskTag(
        taskId: json['task_id'] as String,
        tagId: json['tag_id'] as String,
        updatedAt: _time(json['updated_at'])!,
        deletedAt: _time(json['deleted_at']),
        syncedAt: json['synced_at'] as String?,
      );
}

/// Un puñado de tareas, etiquetas y marcas de etiqueta: lo que se lee, se sube o se baja junto.
class TaskData {
  const TaskData({this.tasks = const [], this.tags = const [], this.links = const []});

  final List<TaskItem> tasks;
  final List<Tag> tags;
  final List<TaskTag> links;

  bool get isEmpty => tasks.isEmpty && tags.isEmpty && links.isEmpty;
  int get length => tasks.length + tags.length + links.length;
}

/// Los colores que se van repartiendo a las etiquetas nuevas, por turno.
const tagColors = ['#E3B25A', '#5DBB63', '#5B9BD5', '#E07A5F', '#B07CC6', '#4DB6AC', '#F2A65A', '#8D99AE'];

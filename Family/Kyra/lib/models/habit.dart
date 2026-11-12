DateTime? _time(Object? value) => value == null ? null : DateTime.parse(value as String).toUtc();

String? _iso(DateTime? value) => value?.toUtc().toIso8601String();

const _keep = Object();

/// El día de calendario de un instante, en la hora local: `2026-11-05`. Así se guarda la marca de un hábito (un día, no una hora).
String dayKey(DateTime moment) {
  final local = moment.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// Un hábito: algo que se quiere hacer ciertos días de la semana, con un aviso opcional a una hora. Mismo esquema de sincronización que
/// las tareas: ids uuid del dispositivo, horas en UTC, gana el `updatedAt` más reciente y el borrado es suave.
class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.weekdays = everyDay,
    this.remindAt,
    this.position = 0,
    this.deletedAt,
    this.syncedAt,
  });

  /// Todos los días: un bit por día, del lunes (bit 0) al domingo (bit 6).
  static const everyDay = 0x7F;

  final String id;
  final String name;

  /// Los días que toca (máscara: lunes = bit 0 … domingo = bit 6).
  final int weekdays;

  /// La hora del aviso, en minutos desde medianoche (hora local), o `null` si no avisa.
  final int? remindAt;
  final int position;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// La hora del servidor en que se guardó por última vez (solo viene de Supabase).
  final String? syncedAt;

  bool get isDeleted => deletedAt != null;

  /// ¿Toca ese día de la semana (`DateTime.weekday`, 1 = lunes)?
  bool on(int weekday) => weekdays & (1 << (weekday - 1)) != 0;

  /// La máscara de esos días de la semana (`DateTime.weekday`).
  static int maskOf(Iterable<int> days) => days.fold(0, (mask, day) => mask | (1 << (day - 1)));

  Habit copyWith({String? name, int? weekdays, Object? remindAt = _keep, int? position, DateTime? updatedAt, Object? deletedAt = _keep}) => Habit(
        id: id,
        name: name ?? this.name,
        weekdays: weekdays ?? this.weekdays,
        remindAt: identical(remindAt, _keep) ? this.remindAt : remindAt as int?,
        position: position ?? this.position,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: identical(deletedAt, _keep) ? this.deletedAt : deletedAt as DateTime?,
        syncedAt: syncedAt,
      );

  /// Las columnas, tal cual van a Supabase y al teléfono.
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'weekdays': weekdays,
        'remind_at': remindAt,
        'position': position,
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
        'deleted_at': _iso(deletedAt),
      };

  factory Habit.fromJson(Map<String, Object?> json) => Habit(
        id: json['id'] as String,
        name: json['name'] as String,
        weekdays: (json['weekdays'] as num?)?.toInt() ?? everyDay,
        remindAt: (json['remind_at'] as num?)?.toInt(),
        position: (json['position'] as num?)?.toInt() ?? 0,
        createdAt: _time(json['created_at'])!,
        updatedAt: _time(json['updated_at'])!,
        deletedAt: _time(json['deleted_at']),
        syncedAt: json['synced_at'] as String?,
      );
}

/// Que un hábito se cumplió (o se desmarcó: `done = false`) un día. Desmarcar no borra la fila, así el cambio también se sincroniza.
class HabitCheck {
  const HabitCheck({required this.habitId, required this.day, required this.done, required this.updatedAt, this.syncedAt});

  final String habitId;

  /// El día, `yyyy-MM-dd` (ver [dayKey]).
  final String day;
  final bool done;
  final DateTime updatedAt;
  final String? syncedAt;

  String get key => '$habitId|$day';

  Map<String, Object?> toJson() => {'habit_id': habitId, 'day': day, 'done': done, 'updated_at': _iso(updatedAt)};

  factory HabitCheck.fromJson(Map<String, Object?> json) => HabitCheck(
        habitId: json['habit_id'] as String,
        day: (json['day'] as String).substring(0, 10),
        done: json['done'] == true || json['done'] == 1,
        updatedAt: _time(json['updated_at'])!,
        syncedAt: json['synced_at'] as String?,
      );
}

/// Un puñado de hábitos y marcas: lo que se lee, se sube o se baja junto.
class HabitData {
  const HabitData({this.habits = const [], this.checks = const []});

  final List<Habit> habits;
  final List<HabitCheck> checks;

  bool get isEmpty => habits.isEmpty && checks.isEmpty;
  int get length => habits.length + checks.length;
}

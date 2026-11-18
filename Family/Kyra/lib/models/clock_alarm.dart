import '../util/format.dart' show weekdayLetters;

/// Una alarma del reloj. Vive **solo en el teléfono** (no se sincroniza con ningún servidor).
class ClockAlarm {
  const ClockAlarm({required this.id, required this.hour, required this.minute, this.label = '', this.days = 0, this.enabled = true, this.firesAt});

  /// Un número propio (de él salen los de sus notificaciones).
  final int id;

  /// La hora, en 24 h (0–23), y el minuto (0–59).
  final int hour;
  final int minute;

  /// Un nombre opcional («Gimnasio»).
  final String label;

  /// Los días que se repite: un bit por día, el 0 es el lunes y el 6 el domingo. Con 0 suena **una sola vez**.
  final int days;
  final bool enabled;

  /// Solo si suena una vez: cuándo sonará (hora local). Sirve para apagarla cuando ya sonó.
  final DateTime? firesAt;

  bool get repeats => days != 0;

  /// ¿Suena el día de la semana `weekday` (`DateTime.weekday`, 1 = lunes)?
  bool onDay(int weekday) => days & (1 << (weekday - 1)) != 0;

  /// Los minutos desde medianoche.
  int get minutes => hour * 60 + minute;

  /// Las alarmas de una sola vez que ya sonaron.
  bool rangBefore(DateTime now) => !repeats && firesAt != null && !firesAt!.isAfter(now);

  /// La próxima vez que suena (después de `now`), o `null` si está apagada o ya no sonará.
  DateTime? nextRing(DateTime now) {
    if (!enabled) return null;
    if (!repeats) {
      final at = firesAt ?? nextOnce(now, hour, minute);
      return at.isAfter(now) ? at : null;
    }
    DateTime? best;
    for (var d = 0; d < 8; d++) {
      final day = DateTime(now.year, now.month, now.day + d, hour, minute);
      if (day.isAfter(now) && onDay(day.weekday)) {
        best = day;
        break;
      }
    }
    return best;
  }

  /// La próxima vez que dan esa hora y minuto (hoy si todavía no llegó; si no, mañana).
  static DateTime nextOnce(DateTime now, int hour, int minute) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    return today.isAfter(now) ? today : DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  /// «Una vez», «Todos los días», «Lun a vie», «Fines de semana» o las letras de los días.
  String get daysLabel {
    if (!repeats) return 'Una vez';
    if (days == 127) return 'Todos los días';
    if (days == 31) return 'Lun a vie';
    if (days == 96) return 'Fines de semana';
    return [for (var i = 0; i < 7; i++) if (days & (1 << i) != 0) weekdayLetters[i]].join(' ');
  }

  ClockAlarm copyWith({int? hour, int? minute, String? label, int? days, bool? enabled, DateTime? firesAt, bool clearFiresAt = false}) => ClockAlarm(
        id: id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        label: label ?? this.label,
        days: days ?? this.days,
        enabled: enabled ?? this.enabled,
        firesAt: clearFiresAt ? null : (firesAt ?? this.firesAt),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'label': label,
        'days': days,
        'enabled': enabled,
        'firesAt': firesAt?.millisecondsSinceEpoch,
      };

  static ClockAlarm? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final hour = json['hour'];
    final minute = json['minute'];
    if (id is! int || hour is! int || minute is! int || hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    final fires = json['firesAt'];
    return ClockAlarm(
      id: id,
      hour: hour,
      minute: minute,
      label: json['label'] is String ? json['label'] as String : '',
      days: json['days'] is int ? (json['days'] as int) & 127 : 0,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      firesAt: fires is int ? DateTime.fromMillisecondsSinceEpoch(fires) : null,
    );
  }
}

/// Lo que guarda el cronómetro para seguir donde estaba aunque se cierre la app.
class StopwatchSnapshot {
  const StopwatchSnapshot({this.accumulated = Duration.zero, this.startedAt, this.laps = const []});

  /// Lo que ya contó antes de la última vez que se puso en marcha.
  final Duration accumulated;

  /// Cuándo se puso en marcha, si ahora mismo corre.
  final DateTime? startedAt;

  /// El tiempo total en cada vuelta, en orden.
  final List<Duration> laps;

  Map<String, Object?> toJson() => {
        'accumulated': accumulated.inMilliseconds,
        'startedAt': startedAt?.millisecondsSinceEpoch,
        'laps': [for (final l in laps) l.inMilliseconds],
      };

  static StopwatchSnapshot fromJson(Object? json) {
    if (json is! Map) return const StopwatchSnapshot();
    final acc = json['accumulated'];
    final started = json['startedAt'];
    final laps = json['laps'];
    return StopwatchSnapshot(
      accumulated: Duration(milliseconds: acc is int && acc > 0 ? acc : 0),
      startedAt: started is int ? DateTime.fromMillisecondsSinceEpoch(started) : null,
      laps: laps is List ? [for (final l in laps) if (l is int && l >= 0) Duration(milliseconds: l)] : const [],
    );
  }
}

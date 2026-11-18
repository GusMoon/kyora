import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/clock_alarm.dart';

/// Dónde guarda el reloj sus cosas: las alarmas y el estado del cronómetro. **Solo en el teléfono**: no toca ninguna base de datos.
abstract class ClockStore {
  Future<List<ClockAlarm>> loadAlarms();
  Future<void> saveAlarms(List<ClockAlarm> alarms);
  Future<StopwatchSnapshot> loadStopwatch();
  Future<void> saveStopwatch(StopwatchSnapshot snapshot);
}

/// En memoria (para las pruebas y como respaldo).
class MemoryClockStore implements ClockStore {
  MemoryClockStore({List<ClockAlarm> alarms = const [], StopwatchSnapshot snapshot = const StopwatchSnapshot()})
      : _alarms = List.of(alarms),
        _saved = snapshot;

  List<ClockAlarm> _alarms;
  StopwatchSnapshot _saved;

  @override
  Future<List<ClockAlarm>> loadAlarms() async => List.of(_alarms);

  @override
  Future<void> saveAlarms(List<ClockAlarm> alarms) async => _alarms = List.of(alarms);

  @override
  Future<StopwatchSnapshot> loadStopwatch() async => _saved;

  @override
  Future<void> saveStopwatch(StopwatchSnapshot snapshot) async => _saved = snapshot;
}

/// En `SharedPreferences`: claves `clock.alarms` y `clock.stopwatch`, en JSON. Un valor que no se entiende se ignora.
class PrefsClockStore implements ClockStore {
  PrefsClockStore._(this._prefs);

  final SharedPreferences _prefs;

  static const alarmsKey = 'clock.alarms';
  static const stopwatchKey = 'clock.stopwatch';

  static Future<PrefsClockStore> open() async => PrefsClockStore._(await SharedPreferences.getInstance());

  @override
  Future<List<ClockAlarm>> loadAlarms() async {
    final raw = _prefs.getString(alarmsKey);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final item in list) ?ClockAlarm.fromJson(item)];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveAlarms(List<ClockAlarm> alarms) => _prefs.setString(alarmsKey, jsonEncode([for (final a in alarms) a.toJson()]));

  @override
  Future<StopwatchSnapshot> loadStopwatch() async {
    final raw = _prefs.getString(stopwatchKey);
    if (raw == null) return const StopwatchSnapshot();
    try {
      return StopwatchSnapshot.fromJson(jsonDecode(raw));
    } catch (_) {
      return const StopwatchSnapshot();
    }
  }

  @override
  Future<void> saveStopwatch(StopwatchSnapshot snapshot) => _prefs.setString(stopwatchKey, jsonEncode(snapshot.toJson()));
}

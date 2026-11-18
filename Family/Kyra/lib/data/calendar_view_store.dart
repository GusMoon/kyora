import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/agenda.dart' show CalendarMode;

/// La vista con la que se abre el calendario (la semana o el mes), elegida en Configuración. Cambiarla avisa a quien la escucha (la ficha de
/// Configuración); el calendario la lee cada vez que se abre.
abstract class CalendarViewStore extends ChangeNotifier {
  /// La vista por defecto. Si nunca se eligió, la semana.
  CalendarMode get mode;

  Future<void> setMode(CalendarMode mode);
}

class MemoryCalendarViewStore extends CalendarViewStore {
  MemoryCalendarViewStore([CalendarMode mode = CalendarMode.week]) : _mode = mode;

  CalendarMode _mode;

  @override
  CalendarMode get mode => _mode;

  @override
  Future<void> setMode(CalendarMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }
}

class PrefsCalendarViewStore extends CalendarViewStore {
  PrefsCalendarViewStore._(this._prefs);

  static const _key = 'calendar.defaultView';

  final SharedPreferences _prefs;

  static Future<PrefsCalendarViewStore> open() async => PrefsCalendarViewStore._(await SharedPreferences.getInstance());

  /// Lo guardado como texto; lo que no se entienda (o nada) es la semana.
  static CalendarMode parse(String? value) => value == CalendarMode.month.name ? CalendarMode.month : CalendarMode.week;

  @override
  CalendarMode get mode => parse(_prefs.getString(_key));

  @override
  Future<void> setMode(CalendarMode mode) async {
    if (this.mode == mode && _prefs.containsKey(_key)) return;
    await _prefs.setString(_key, mode.name);
    notifyListeners();
  }
}

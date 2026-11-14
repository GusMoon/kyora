import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';
import 'sync_rows.dart';

/// Dónde se recuerdan los recordatorios en el teléfono (con los borrados y lo que falta por subir; ver [RowStore]).
typedef ReminderStore = RowStore<Reminder>;

class MemoryReminderStore extends MemoryRowStore<Reminder> {
  /// Lo que hay guardado (para las pruebas).
  List<Reminder> get items => rows;
  set items(List<Reminder> value) => rows = value;
}

class PrefsReminderStore extends PrefsRowStore<Reminder> {
  PrefsReminderStore._(SharedPreferences prefs, String key) : super(prefs, key, Reminder.fromJson, (r) => r.toLocalJson());

  /// Uno por cuenta: al cambiar de cuenta en el mismo teléfono no se mezclan. Lo guardado antes de sincronizar se lee igual y queda «por subir».
  static Future<PrefsReminderStore> open(String userId) async => PrefsReminderStore._(await SharedPreferences.getInstance(), 'reminders.$userId');
}

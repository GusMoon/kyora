import 'package:shared_preferences/shared_preferences.dart';

import '../models/event.dart';
import 'sync_rows.dart';

/// Dónde se recuerdan los eventos del calendario en el teléfono (con los borrados y lo que falta por subir; ver [RowStore]).
typedef EventStore = RowStore<CalendarEvent>;

class MemoryEventStore extends MemoryRowStore<CalendarEvent> {}

class PrefsEventStore extends PrefsRowStore<CalendarEvent> {
  PrefsEventStore._(SharedPreferences prefs, String key) : super(prefs, key, CalendarEvent.fromJson, (e) => e.toLocalJson());

  /// Uno por cuenta.
  static Future<PrefsEventStore> open(String userId) async => PrefsEventStore._(await SharedPreferences.getInstance(), 'events.$userId');
}

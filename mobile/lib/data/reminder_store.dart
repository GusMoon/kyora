import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';

/// Dónde se recuerdan los recordatorios (solo en el teléfono, no en Supabase).
abstract class ReminderStore {
  Future<List<Reminder>> load();
  Future<void> save(List<Reminder> items);
}

class MemoryReminderStore implements ReminderStore {
  List<Reminder> items = [];

  @override
  Future<List<Reminder>> load() async => List.of(items);

  @override
  Future<void> save(List<Reminder> value) async => items = List.of(value);
}

class PrefsReminderStore implements ReminderStore {
  PrefsReminderStore._(this._prefs, this._key);

  final SharedPreferences _prefs;
  final String _key;

  /// Uno por cuenta: al cambiar de cuenta en el mismo teléfono no se mezclan.
  static Future<PrefsReminderStore> open(String userId) async => PrefsReminderStore._(await SharedPreferences.getInstance(), 'reminders.$userId');

  @override
  Future<List<Reminder>> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      return [for (final item in jsonDecode(raw) as List<dynamic>) Reminder.fromJson(Map<String, Object?>.from(item as Map))];
    } catch (_) {
      return []; // lo guardado está dañado: se empieza de cero antes que fallar al abrir
    }
  }

  @override
  Future<void> save(List<Reminder> items) async {
    await _prefs.setString(_key, jsonEncode([for (final r in items) r.toJson()]));
  }
}

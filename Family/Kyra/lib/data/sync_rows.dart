import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

export 'task_store.dart' show remoteWins;

/// Una fila que se sincroniza con Supabase (recordatorios, eventos): mismo esquema que las tareas y los hábitos. Ids uuid del dispositivo,
/// horas en UTC, gana el `updatedAt` más reciente y el borrado es suave.
abstract class SyncRow {
  String get id;
  DateTime get updatedAt;
  DateTime? get deletedAt;

  /// Hay cambios hechos aquí que todavía no se subieron.
  bool get dirty;

  /// La hora del servidor en que se guardó por última vez (solo viene de Supabase).
  String? get syncedAt;

  bool get isDeleted => deletedAt != null;

  /// La misma fila con la marca «por subir» puesta o quitada.
  SyncRow withDirty(bool value);

  /// La misma fila, tal como llega de Supabase (limpia y con su hora de servidor).
  SyncRow get fromServer;
}

/// Lo que una tabla de Supabase necesita: subir lo que cambió aquí y bajar lo que cambió en otros sitios. Lanza `ChatException`.
abstract class RowBackend<T extends SyncRow> {
  Future<void> push(List<T> rows);

  /// Lo que cambió después de `since` (la `synced_at` de la última fila leída; `null` = todo).
  Future<List<T>> pull(String? since);
}

/// Avisa cuando algo cambia en Supabase (Realtime): sirve para ponerse al día sin esperar.
abstract class LiveBackend {
  /// Emite cada vez que cambia algo en esas tablas, y al (re)conectarse.
  Stream<void> changes(List<String> tables);
}

/// Dónde viven esas filas en el teléfono. Se guardan también las borradas (borrado suave): así el borrado llega a Supabase.
abstract class RowStore<T extends SyncRow> {
  Future<List<T>> load();
  Future<void> save(List<T> rows);
  Future<String?> cursor();
  Future<void> setCursor(String value);
}

class MemoryRowStore<T extends SyncRow> implements RowStore<T> {
  List<T> rows = [];
  String? _cursor;

  @override
  Future<List<T>> load() async => List.of(rows);

  @override
  Future<void> save(List<T> value) async => rows = List.of(value);

  @override
  Future<String?> cursor() async => _cursor;

  @override
  Future<void> setCursor(String value) async => _cursor = value;
}

/// Una lista en JSON dentro de las preferencias (son pocas filas). Lo dañado se ignora antes que fallar al abrir.
class PrefsRowStore<T extends SyncRow> implements RowStore<T> {
  PrefsRowStore(this._prefs, this._key, this._read, this._write);

  final SharedPreferences _prefs;
  final String _key;
  final T Function(Map<String, Object?> json) _read;
  final Map<String, Object?> Function(T row) _write;

  @override
  Future<List<T>> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      return [for (final item in jsonDecode(raw) as List<dynamic>) _read(Map<String, Object?>.from(item as Map))];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<T> rows) async {
    await _prefs.setString(_key, jsonEncode([for (final r in rows) _write(r)]));
  }

  @override
  Future<String?> cursor() async => _prefs.getString('$_key.cursor');

  @override
  Future<void> setCursor(String value) async {
    await _prefs.setString('$_key.cursor', value);
  }
}

DateTime? parseTime(Object? value) => value == null ? null : DateTime.parse(value as String).toUtc();

String? isoOf(DateTime? value) => value?.toUtc().toIso8601String();

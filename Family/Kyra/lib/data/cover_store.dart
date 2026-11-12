import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Dónde se recuerda la imagen que elegiste para cada canción enviada (solo en el teléfono: esas canciones viven en Supabase, no en tu
/// carpeta): `{id de la canción: ruta de la imagen}`.
abstract class CoverStore {
  Map<String, String> load();
  Future<void> save(Map<String, String> covers);
}

class MemoryCoverStore implements CoverStore {
  Map<String, String> covers = {};

  @override
  Map<String, String> load() => Map.of(covers);

  @override
  Future<void> save(Map<String, String> value) async => covers = Map.of(value);
}

class PrefsCoverStore implements CoverStore {
  PrefsCoverStore._(this._prefs);

  static const _key = 'music.covers';

  final SharedPreferences _prefs;

  static Future<PrefsCoverStore> open() async => PrefsCoverStore._(await SharedPreferences.getInstance());

  @override
  Map<String, String> load() {
    final text = _prefs.getString(_key);
    if (text == null) return {};
    try {
      return (jsonDecode(text) as Map<String, dynamic>).map((id, path) => MapEntry(id, path as String));
    } on FormatException {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, String> covers) async => _prefs.setString(_key, jsonEncode(covers));
}

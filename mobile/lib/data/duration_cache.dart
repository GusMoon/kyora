import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lo que duran las canciones, recordado en el teléfono (Supabase no lo guarda). Se llena con lo que lee Android de los .mp3
/// de la carpeta y con lo que el reproductor aprende al sonar una canción recibida.
abstract class DurationCache {
  /// La duración de esa canción, o `null` si aún no se sabe.
  Duration? of(String key);

  Future<void> putAll(Map<String, Duration> found);
}

/// Sin guardar nada en disco: para pruebas o cuando no hay dónde recordarlo.
class MemoryDurationCache implements DurationCache {
  final Map<String, Duration> _known = {};

  @override
  Duration? of(String key) => _known[key];

  @override
  Future<void> putAll(Map<String, Duration> found) async => _known.addAll(found);
}

/// En `shared_preferences`, todo junto en un solo texto JSON `{clave: milisegundos}`.
class PrefsDurationCache implements DurationCache {
  PrefsDurationCache._(this._prefs, this._known);

  static const _key = 'music.durations';

  final SharedPreferences _prefs;
  final Map<String, Duration> _known;

  static Future<PrefsDurationCache> open() async {
    final prefs = await SharedPreferences.getInstance();
    final known = <String, Duration>{};
    try {
      final raw = prefs.getString(_key);
      if (raw != null) {
        for (final entry in (jsonDecode(raw) as Map<String, dynamic>).entries) {
          known[entry.key] = Duration(milliseconds: (entry.value as num).toInt());
        }
      }
    } catch (_) {
      // un texto dañado: se empieza de cero, las duraciones se vuelven a leer
    }
    return PrefsDurationCache._(prefs, known);
  }

  @override
  Duration? of(String key) => _known[key];

  @override
  Future<void> putAll(Map<String, Duration> found) async {
    if (found.isEmpty) return;
    _known.addAll(found);
    await _prefs.setString(_key, jsonEncode({for (final e in _known.entries) e.key: e.value.inMilliseconds}));
  }
}

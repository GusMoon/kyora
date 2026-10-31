import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dónde se guardan las canciones en el teléfono. Android no deja escribir en cualquier ruta, así que la «carpeta
/// predeterminada» es una de las dos carpetas públicas (Música o Descargas) más una subcarpeta con el nombre que elijas.
enum MusicBase { music, download }

extension MusicBaseText on MusicBase {
  String get label => this == MusicBase.music ? 'Música' : 'Descargas';
}

class MusicSettings {
  const MusicSettings({this.base = MusicBase.music, this.folder = 'Kyora', this.auto = true});

  final MusicBase base;
  final String folder;

  /// Guardar solas las canciones nuevas que lleguen mientras la app está abierta.
  final bool auto;

  MusicSettings copyWith({MusicBase? base, String? folder, bool? auto}) =>
      MusicSettings(base: base ?? this.base, folder: folder ?? this.folder, auto: auto ?? this.auto);

  /// «Música/Kyora»: lo que se le enseña a la persona.
  String get where => folder.trim().isEmpty ? base.label : '${base.label}/${folder.trim()}';
}

/// Lo que recuerda la app de la música: los ajustes, qué canciones ya guardó y desde cuándo guardar solas.
abstract class MusicStore {
  Future<MusicSettings> loadSettings();
  Future<void> saveSettings(MusicSettings settings);
  Future<Set<String>> loadSaved();
  Future<void> markSaved(String trackId);

  /// Solo las canciones llegadas después de esta hora se guardan solas (las viejas, a mano: así instalar la app no baja
  /// de golpe toda la biblioteca). La primera vez que se pide, es ahora.
  Future<DateTime> autoSince();
}

class PrefsMusicStore implements MusicStore {
  PrefsMusicStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsMusicStore> open() async => PrefsMusicStore(await SharedPreferences.getInstance());

  @override
  Future<MusicSettings> loadSettings() async {
    final base = _prefs.getString('music.base') == 'download' ? MusicBase.download : MusicBase.music;
    return MusicSettings(base: base, folder: _prefs.getString('music.folder') ?? 'Kyora', auto: _prefs.getBool('music.auto') ?? true);
  }

  @override
  Future<void> saveSettings(MusicSettings settings) async {
    await _prefs.setString('music.base', settings.base.name);
    await _prefs.setString('music.folder', settings.folder.trim());
    await _prefs.setBool('music.auto', settings.auto);
  }

  @override
  Future<Set<String>> loadSaved() async => (_prefs.getStringList('music.saved') ?? const []).toSet();

  @override
  Future<void> markSaved(String trackId) async {
    final saved = await loadSaved()..add(trackId);
    await _prefs.setStringList('music.saved', saved.toList());
  }

  @override
  Future<DateTime> autoSince() async {
    final stored = _prefs.getInt('music.autoSince');
    if (stored != null) return DateTime.fromMillisecondsSinceEpoch(stored, isUtc: true);
    final now = DateTime.now().toUtc();
    await _prefs.setInt('music.autoSince', now.millisecondsSinceEpoch);
    return now;
  }
}

/// Deja un MP3 en la carpeta pública del teléfono.
abstract class TrackSaver {
  /// Devuelve la carpeta donde quedó (para enseñarla). Lanza `TrackSaveException` si no se pudo.
  Future<String> save({required String fileName, required Uint8List bytes, required MusicBase base, required String folder});
}

class TrackSaveException implements Exception {
  const TrackSaveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// El guardado real, con el código nativo de `MainActivity.kt` (MediaStore: la canción aparece en el reproductor del teléfono).
class AndroidTrackSaver implements TrackSaver {
  static const _channel = MethodChannel('kyora/music_saver');

  @override
  Future<String> save({required String fileName, required Uint8List bytes, required MusicBase base, required String folder}) async {
    try {
      final where = await _channel.invokeMethod<String>('save', {
        'name': fileName,
        'bytes': bytes,
        'base': base.name,
        'folder': folder.trim(),
      });
      return where ?? base.label;
    } on PlatformException catch (e) {
      throw TrackSaveException(e.message ?? 'No se pudo guardar la canción.');
    } on MissingPluginException {
      throw const TrackSaveException('Este teléfono no puede guardar canciones desde la app.');
    }
  }
}

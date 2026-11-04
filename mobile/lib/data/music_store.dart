import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// Dónde se guardan las canciones en el teléfono. La persona puede elegir cualquier carpeta con el selector de Android
/// (`treeUri`); si no ha elegido ninguna, es una de las dos carpetas públicas (Música o Descargas) más una subcarpeta con el
/// nombre que escriba (Android no deja escribir en cualquier ruta sin que la persona la elija).
enum MusicBase { music, download }

extension MusicBaseText on MusicBase {
  String get label => this == MusicBase.music ? 'Música' : 'Descargas';
}

class MusicSettings {
  const MusicSettings({this.base = MusicBase.music, this.folder = 'Kyora', this.auto = true, this.treeUri, this.treeName});

  final MusicBase base;
  final String folder;

  /// Guardar solas las canciones nuevas que lleguen mientras la app está abierta.
  final bool auto;

  /// La carpeta que la persona eligió con el selector de Android (dirección `content://`), o `null` si no eligió ninguna.
  /// Si hay una, manda sobre `base` y `folder`.
  final String? treeUri;

  /// El nombre de esa carpeta, para enseñarlo.
  final String? treeName;

  bool get hasTree => treeUri != null && treeUri!.isNotEmpty;

  MusicSettings copyWith({MusicBase? base, String? folder, bool? auto}) =>
      MusicSettings(base: base ?? this.base, folder: folder ?? this.folder, auto: auto ?? this.auto, treeUri: treeUri, treeName: treeName);

  /// Guardar en esa carpeta elegida.
  MusicSettings withTree(String uri, String name) =>
      MusicSettings(base: base, folder: folder, auto: auto, treeUri: uri, treeName: name);

  /// Volver a Música/Descargas + subcarpeta.
  MusicSettings withoutTree() => MusicSettings(base: base, folder: folder, auto: auto);

  /// «Música/Kyora» o el nombre de la carpeta elegida: lo que se le enseña a la persona.
  String get where {
    if (hasTree) return (treeName == null || treeName!.trim().isEmpty) ? 'la carpeta elegida' : treeName!.trim();
    return folder.trim().isEmpty ? base.label : '${base.label}/${folder.trim()}';
  }
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
    final tree = _prefs.getString('music.treeUri');
    return MusicSettings(
      base: base,
      folder: _prefs.getString('music.folder') ?? 'Kyora',
      auto: _prefs.getBool('music.auto') ?? true,
      treeUri: tree == null || tree.isEmpty ? null : tree,
      treeName: _prefs.getString('music.treeName'),
    );
  }

  @override
  Future<void> saveSettings(MusicSettings settings) async {
    await _prefs.setString('music.base', settings.base.name);
    await _prefs.setString('music.folder', settings.folder.trim());
    await _prefs.setBool('music.auto', settings.auto);
    if (settings.hasTree) {
      await _prefs.setString('music.treeUri', settings.treeUri!);
      await _prefs.setString('music.treeName', settings.treeName ?? '');
    } else {
      await _prefs.remove('music.treeUri');
      await _prefs.remove('music.treeName');
    }
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

/// Una carpeta elegida con el selector de Android.
class PickedFolder {
  const PickedFolder({required this.uri, required this.name});

  final String uri;
  final String name;
}

/// Deja un MP3 en la carpeta del teléfono y deja elegir esa carpeta.
abstract class TrackSaver {
  /// Devuelve la carpeta donde quedó (para enseñarla). Con `treeUri` lo deja en esa carpeta elegida; si no, en Música o
  /// Descargas + `folder`. Lanza `TrackSaveException` si no se pudo.
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
    required MusicBase base,
    required String folder,
    String? treeUri,
  });

  /// Abre el selector de carpetas de Android. `null` si la persona lo cierra sin elegir. Lanza `TrackSaveException` si no se pudo abrir.
  Future<PickedFolder?> pickFolder();

  /// Lo que hay en UNA carpeta de la elegida (`dirUri`; sin él, la raíz): sus subcarpetas y sus .mp3. Lanza `TrackSaveException` (con
  /// `folderLost` si la carpeta ya no sirve) si no se pudo leer.
  Future<FolderListing> listDir(String treeUri, {String? dirUri});

  /// Crea una carpeta de verdad dentro de `parentUri` (sin él, la raíz). Lanza `TrackSaveException` si no se pudo.
  Future<LocalFolder> createFolder(String treeUri, {String? parentUri, required String name});

  /// Mueve canciones de `fromUri` a `toUri` (sin ellos, la raíz) en el almacenamiento. Las que fallan salen en `failures` y el
  /// original no se toca. Lanza `TrackSaveException` solo si falla todo (la carpeta ya no sirve, etc.).
  Future<MoveResult> moveSongs(String treeUri, {required List<String> uris, String? fromUri, String? toUri});

  /// Lo que dura cada archivo (por su dirección `content://`). Los que no se puedan leer no salen en el resultado.
  Future<Map<String, Duration>> readDurations(List<String> uris);

  /// La carátula incrustada de cada .mp3, ya reducida y guardada en el teléfono: `{dirección: ruta de la imagen}`. Los que no
  /// traen carátula no salen en el resultado.
  Future<Map<String, String>> readArt(List<String> uris);

  /// La imagen de esa ruta lista para ser carátula (JPEG, derecha y de tamaño razonable). Lanza `TrackSaveException` si no se puede abrir.
  Future<Uint8List> prepareCover(String path);

  /// Guarda una carátula y devuelve su ruta, distinta cada vez. Con `keep` se conserva; si no, Android puede borrarla cuando le haga falta
  /// espacio (para lo que se puede volver a leer del .mp3). Reemplaza a la anterior de esa `key`.
  Future<String> storeCover(String key, Uint8List bytes, {required bool keep});

  /// El contenido de un archivo de la carpeta. Lanza `TrackSaveException` si no se pudo.
  Future<Uint8List> readFile(String uri);

  /// Reescribe un archivo de la carpeta. Si falla, el archivo se queda como estaba y lanza `TrackSaveException`.
  Future<void> writeFile(String uri, Uint8List bytes);
}

class TrackSaveException implements Exception {
  const TrackSaveException(this.message, {this.folderLost = false});

  final String message;

  /// La carpeta elegida ya no sirve (se borró o Android quitó el permiso): hay que elegirla otra vez.
  final bool folderLost;

  @override
  String toString() => message;
}

/// El guardado real, con el código nativo de `MainActivity.kt` (MediaStore: la canción aparece en el reproductor del teléfono).
class AndroidTrackSaver implements TrackSaver {
  static const _channel = MethodChannel('kyora/music_saver');

  @override
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
    required MusicBase base,
    required String folder,
    String? treeUri,
  }) async {
    try {
      final where = await _channel.invokeMethod<String>('save', {
        'name': fileName,
        'bytes': bytes,
        'base': base.name,
        'folder': folder.trim(),
        'treeUri': treeUri ?? '',
      });
      return where ?? base.label;
    } on PlatformException catch (e) {
      throw TrackSaveException(e.message ?? 'No se pudo guardar la canción.', folderLost: e.code == 'folder_lost');
    } on MissingPluginException {
      throw const TrackSaveException('Este teléfono no puede guardar canciones desde la app.');
    }
  }

  List<Map<Object?, Object?>> _rows(Object? value) =>
      [for (final row in (value as List<Object?>? ?? const [])) Map<Object?, Object?>.from(row! as Map)];

  @override
  Future<FolderListing> listDir(String treeUri, {String? dirUri}) async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('listDir', {'treeUri': treeUri, 'dirUri': dirUri ?? ''});
      return FolderListing(
        folders: [for (final row in _rows(map?['folders'])) LocalFolder.fromMap(row)],
        songs: [for (final row in _rows(map?['songs'])) LocalSong.fromMap(row)],
      );
    } on PlatformException catch (e) {
      throw TrackSaveException(e.message ?? 'No se pudo leer la carpeta.', folderLost: e.code == 'folder_lost');
    } on MissingPluginException {
      throw const TrackSaveException('Este teléfono no puede leer carpetas desde la app.');
    }
  }

  @override
  Future<LocalFolder> createFolder(String treeUri, {String? parentUri, required String name}) async {
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>('createFolder', {'treeUri': treeUri, 'parentUri': parentUri ?? '', 'name': name});
      return LocalFolder.fromMap(map!);
    } on PlatformException catch (e) {
      throw TrackSaveException(e.message ?? 'No se pudo crear la carpeta.', folderLost: e.code == 'folder_lost');
    } on MissingPluginException {
      throw const TrackSaveException('Este teléfono no puede crear carpetas desde la app.');
    }
  }

  @override
  Future<MoveResult> moveSongs(String treeUri, {required List<String> uris, String? fromUri, String? toUri}) async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('moveSongs', {
        'treeUri': treeUri,
        'uris': uris,
        'fromUri': fromUri ?? '',
        'toUri': toUri ?? '',
      });
      final failed = Map<Object?, Object?>.from((map?['failed'] as Map?) ?? const {});
      return MoveResult(moved: (map?['moved'] as num?)?.toInt() ?? 0, failures: {for (final e in failed.entries) e.key! as String: e.value as String});
    } on PlatformException catch (e) {
      throw TrackSaveException(e.message ?? 'No se pudo mover.', folderLost: e.code == 'folder_lost');
    } on MissingPluginException {
      throw const TrackSaveException('Este teléfono no puede mover canciones desde la app.');
    }
  }

  @override
  Future<Map<String, Duration>> readDurations(List<String> uris) async {
    if (uris.isEmpty) return const {};
    try {
      final rows = await _channel.invokeMapMethod<String, num>('readDurations', {'uris': uris});
      return {for (final e in (rows ?? const <String, num>{}).entries) e.key: Duration(milliseconds: e.value.toInt())};
    } on PlatformException {
      return const {}; // la duración es un adorno: sin ella la lista sigue funcionando
    } on MissingPluginException {
      return const {};
    }
  }

  @override
  Future<Map<String, String>> readArt(List<String> uris) async {
    if (uris.isEmpty) return const {};
    try {
      final rows = await _channel.invokeMapMethod<String, String>('readArt', {'uris': uris});
      return rows ?? const {};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  /// Una llamada que devuelve bytes o texto; sus fallos ya vienen explicados en español.
  Future<T> _call<T>(String method, Map<String, Object?> args, String fallback) async {
    try {
      final value = await _channel.invokeMethod<T>(method, args);
      if (value == null) throw TrackSaveException(fallback);
      return value;
    } on PlatformException catch (e) {
      throw TrackSaveException(e.message ?? fallback, folderLost: e.code == 'folder_lost');
    } on MissingPluginException {
      throw TrackSaveException(fallback);
    }
  }

  @override
  Future<Uint8List> prepareCover(String path) => _call('prepareCover', {'path': path}, 'No se pudo abrir esa imagen.');

  @override
  Future<String> storeCover(String key, Uint8List bytes, {required bool keep}) =>
      _call('storeCover', {'key': key, 'bytes': bytes, 'keep': keep}, 'No se pudo guardar la imagen.');

  @override
  Future<Uint8List> readFile(String uri) => _call('readFile', {'uri': uri}, 'No se pudo leer la canción.');

  @override
  Future<void> writeFile(String uri, Uint8List bytes) async {
    try {
      await _channel.invokeMethod<void>('writeFile', {'uri': uri, 'bytes': bytes});
    } on PlatformException catch (e) {
      throw TrackSaveException(e.message ?? 'No se pudo escribir en la canción.', folderLost: e.code == 'folder_lost');
    } on MissingPluginException {
      throw const TrackSaveException('Este teléfono no puede cambiar canciones desde la app.');
    }
  }

  @override
  Future<PickedFolder?> pickFolder() async {
    try {
      final picked = await _channel.invokeMapMethod<String, String>('pickFolder');
      if (picked == null || (picked['uri'] ?? '').isEmpty) return null;
      return PickedFolder(uri: picked['uri']!, name: picked['name'] ?? '');
    } on PlatformException catch (e) {
      throw TrackSaveException(e.message ?? 'No se pudo abrir el selector de carpetas.');
    } on MissingPluginException {
      throw const TrackSaveException('Este teléfono no puede elegir carpetas desde la app.');
    }
  }
}

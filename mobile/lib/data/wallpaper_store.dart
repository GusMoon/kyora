import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lo que se recuerda del fondo de pantalla: la ruta de la imagen (una copia dentro de la app) y sus 5 colores, como números ARGB.
class WallpaperState {
  const WallpaperState({this.path, this.palette = const []});

  final String? path;
  final List<int> palette;
}

/// Dónde se guarda el fondo de pantalla de Kyra y su paleta (solo en el teléfono).
abstract class WallpaperStore {
  WallpaperState load();
  Future<void> save(WallpaperState state);

  /// Copia la imagen elegida a un sitio propio de la app (así no depende de la galería) y devuelve la nueva ruta.
  Future<String> keep(String source);

  /// Borra una copia que ya no se usa.
  Future<void> discard(String path);
}

class MemoryWallpaperStore implements WallpaperStore {
  WallpaperState state = const WallpaperState();

  /// Lo que se copió, para las pruebas.
  final List<String> kept = [];
  final List<String> discarded = [];

  @override
  WallpaperState load() => state;

  @override
  Future<void> save(WallpaperState value) async => state = value;

  @override
  Future<String> keep(String source) async {
    kept.add(source);
    return source;
  }

  @override
  Future<void> discard(String path) async => discarded.add(path);
}

class PrefsWallpaperStore implements WallpaperStore {
  PrefsWallpaperStore._(this._prefs);

  static const _pathKey = 'wallpaper.path';
  static const _paletteKey = 'wallpaper.palette';

  final SharedPreferences _prefs;

  static Future<PrefsWallpaperStore> open() async => PrefsWallpaperStore._(await SharedPreferences.getInstance());

  @override
  WallpaperState load() {
    final path = _prefs.getString(_pathKey);
    if (path == null) return const WallpaperState();
    var palette = <int>[];
    try {
      palette = (jsonDecode(_prefs.getString(_paletteKey) ?? '[]') as List).cast<int>();
    } on Object {
      palette = [];
    }
    return WallpaperState(path: path, palette: palette);
  }

  @override
  Future<void> save(WallpaperState state) async {
    if (state.path == null) {
      await _prefs.remove(_pathKey);
      await _prefs.remove(_paletteKey);
      return;
    }
    await _prefs.setString(_pathKey, state.path!);
    await _prefs.setString(_paletteKey, jsonEncode(state.palette));
  }

  @override
  Future<String> keep(String source) async {
    final folder = await getApplicationDocumentsDirectory();
    // un nombre nuevo cada vez: así Flutter no enseña la imagen anterior que tiene en caché
    final target = p.join(folder.path, 'wallpaper-${DateTime.now().millisecondsSinceEpoch}${p.extension(source).isEmpty ? '.jpg' : p.extension(source)}');
    await File(source).copy(target);
    return target;
  }

  @override
  Future<void> discard(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // no pasa nada: queda un archivo de más
    }
  }
}

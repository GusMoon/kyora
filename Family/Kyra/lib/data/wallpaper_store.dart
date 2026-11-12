import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lo que se recuerda del fondo de pantalla: la ruta de una copia de la imagen dentro de la app y su color de acento (ARGB).
class WallpaperState {
  const WallpaperState({this.path, this.accent});

  final String? path;
  final int? accent;
}

/// Dónde se guarda el fondo de pantalla de Inicio y su color (solo en el teléfono).
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

  /// Lo que se copió y lo que se borró, para las pruebas.
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
  static const _accentKey = 'wallpaper.accent';

  final SharedPreferences _prefs;

  static Future<PrefsWallpaperStore> open() async => PrefsWallpaperStore._(await SharedPreferences.getInstance());

  @override
  WallpaperState load() {
    final path = _prefs.getString(_pathKey);
    // la copia pudo borrarse (limpiar datos): sin archivo no hay fondo
    if (path == null || !File(path).existsSync()) return const WallpaperState();
    return WallpaperState(path: path, accent: _prefs.getInt(_accentKey));
  }

  @override
  Future<void> save(WallpaperState state) async {
    if (state.path == null) {
      await _prefs.remove(_pathKey);
    } else {
      await _prefs.setString(_pathKey, state.path!);
    }
    if (state.accent == null) {
      await _prefs.remove(_accentKey);
    } else {
      await _prefs.setInt(_accentKey, state.accent!);
    }
  }

  @override
  Future<String> keep(String source) async {
    final folder = await getApplicationDocumentsDirectory();
    final extension = p.extension(source).isEmpty ? '.jpg' : p.extension(source);
    // un nombre nuevo cada vez: así Flutter no enseña la imagen anterior que tiene en caché
    final target = p.join(folder.path, 'wallpaper-${DateTime.now().millisecondsSinceEpoch}$extension');
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

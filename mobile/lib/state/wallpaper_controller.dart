import 'dart:async';

import 'package:flutter/material.dart';

import '../data/wallpaper_store.dart';
import '../util/palette.dart';

/// Cómo se sacan los colores de una imagen (en las pruebas, uno falso).
typedef PaletteLookup = Future<List<Color>?> Function(String path);

/// El fondo de pantalla de la app y sus 5 colores. Sin fondo, el gris oscuro de siempre. Al poner uno, la copia a la app, saca sus colores
/// y avisa: el fondo, el tema y las franjas de colores se actualizan a la vez.
class WallpaperController extends ChangeNotifier {
  WallpaperController(this._store, {this._lookup = paletteOfFile}) {
    final saved = _store.load();
    _path = saved.path;
    _palette = [for (final value in saved.palette) Color(value)];
    // se guardó la imagen pero no la paleta (se interrumpió): se calcula ahora
    if (_path != null && _palette.isEmpty) unawaited(_recompute(_path!));
  }

  final WallpaperStore _store;
  final PaletteLookup _lookup;
  String? _path;
  List<Color> _palette = const [];
  bool _busy = false;

  /// La imagen del fondo, o `null` si no hay.
  String? get path => _path;

  /// Los 5 colores del fondo, del que más ocupa al que menos. Vacía si no hay fondo.
  List<Color> get palette => _palette;

  bool get hasWallpaper => _path != null;

  /// Está leyendo una imagen nueva.
  bool get busy => _busy;

  /// El color con el que se viste la app, o `null` sin fondo.
  Color? get seed => _palette.isEmpty ? null : paletteSeed(_palette);

  /// Pone [source] (una imagen de la galería) de fondo. Devuelve `false` si la imagen no se pudo leer (se queda el fondo que había).
  Future<bool> set(String source) async {
    _busy = true;
    notifyListeners();
    try {
      final kept = await _store.keep(source);
      final colors = await _lookup(kept);
      if (colors == null || colors.isEmpty) {
        await _store.discard(kept);
        return false;
      }
      final old = _path;
      _path = kept;
      _palette = colors;
      await _store.save(WallpaperState(path: kept, palette: [for (final c in colors) c.toARGB32()]));
      if (old != null && old != kept) await _store.discard(old);
      return true;
    } on Object {
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Quita el fondo: vuelve el gris oscuro.
  Future<void> clear() async {
    final old = _path;
    _path = null;
    _palette = const [];
    await _store.save(const WallpaperState());
    if (old != null) await _store.discard(old);
    notifyListeners();
  }

  Future<void> _recompute(String path) async {
    final colors = await _lookup(path);
    if (colors == null || _path != path) return;
    _palette = colors;
    await _store.save(WallpaperState(path: path, palette: [for (final c in colors) c.toARGB32()]));
    notifyListeners();
  }
}

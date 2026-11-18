import 'dart:async';

import 'package:flutter/material.dart';

import '../data/wallpaper_store.dart';
import '../util/wallpaper_color.dart';

/// El fondo de pantalla de Inicio y **el color con el que se viste toda la app**, sacado de ese fondo. Sin fondo, el gris oscuro y el acento
/// de siempre. Al poner uno, se copia a la app, se saca su color y se avisa: el fondo y el tema cambian a la vez.
class WallpaperController extends ChangeNotifier {
  WallpaperController(this._store, {AccentLookup lookup = wallpaperAccent, ExtrasLookup extras = wallpaperExtras})
      : _lookup = lookup, // ignore: prefer_initializing_formals
        _extrasLookup = extras {
    final saved = _store.load();
    _path = saved.path;
    _accent = saved.accent == null ? null : Color(saved.accent!);
    _extras = [for (final v in saved.extras) Color(v)];
    // se guardó la imagen pero no su color (se interrumpió): se calcula ahora
    if (_path != null && saved.accent == null) {
      unawaited(_recompute(_path!));
    } else if (_path != null && _extras.isEmpty && _accent != null) {
      unawaited(_recomputeExtras(_path!, _accent!)); // un fondo de antes de que hubiera colores secundarios
    }
  }

  final WallpaperStore _store;
  final AccentLookup _lookup;
  final ExtrasLookup _extrasLookup;
  String? _path;
  Color? _accent;
  List<Color> _extras = const [];
  bool _busy = false;

  /// La imagen del fondo, o `null` si no hay.
  String? get path => _path;

  /// El color de acento que sale del fondo, o `null` (sin fondo, o un fondo casi gris): el de siempre.
  Color? get accent => _accent;

  /// Otros colores del fondo (que no son el predominante), para las tareas, los recordatorios y los hábitos. Vacío sin fondo.
  List<Color> get extras => _extras;

  bool get hasWallpaper => _path != null;

  /// Está copiando una imagen nueva.
  bool get busy => _busy;

  /// Pone [source] (una imagen de la galería) de fondo. Devuelve `false` si no se pudo (se queda el fondo que había).
  Future<bool> set(String source) async {
    _busy = true;
    notifyListeners();
    try {
      final kept = await _store.keep(source);
      final color = await _lookup(kept);
      final extras = color == null ? const <Color>[] : await _extrasLookup(kept, color);
      final old = _path;
      _path = kept;
      _accent = color;
      _extras = extras;
      await _store.save(WallpaperState(path: kept, accent: color?.toARGB32(), extras: [for (final e in extras) e.toARGB32()]));
      if (old != null && old != kept) await _store.discard(old);
      return true;
    } on Object {
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Quita el fondo: vuelven el gris oscuro y los colores de siempre.
  Future<void> clear() async {
    final old = _path;
    _path = null;
    _accent = null;
    _extras = const [];
    await _store.save(const WallpaperState());
    if (old != null) await _store.discard(old);
    notifyListeners();
  }

  Future<void> _recompute(String path) async {
    final color = await _lookup(path);
    if (color == null || _path != path) return;
    _accent = color;
    final extras = await _extrasLookup(path, color);
    if (_path != path) return;
    _extras = extras;
    await _store.save(WallpaperState(path: path, accent: color.toARGB32(), extras: [for (final e in extras) e.toARGB32()]));
    notifyListeners();
  }

  Future<void> _recomputeExtras(String path, Color accent) async {
    final extras = await _extrasLookup(path, accent);
    if (extras.isEmpty || _path != path) return;
    _extras = extras;
    await _store.save(WallpaperState(path: path, accent: accent.toARGB32(), extras: [for (final e in extras) e.toARGB32()]));
    notifyListeners();
  }
}

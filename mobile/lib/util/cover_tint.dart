import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pixel_art.dart';
import 'wallpaper_color.dart';

/// El **color de cada portada**, para teñir su disco (el plástico, el anillo de avance y la línea del sonido) como un vinilo de color.
///
/// Lo calcula el disco la primera vez que lee la portada (ya la tiene en pixel art para la etiqueta) y lo deja aquí; quien lo quiera lo
/// escucha por la portada (`file` o `url`). Una portada casi gris no tiene color: entonces vale `null` y se usa el acento de la app.
abstract final class CoverTints {
  static final Map<String, ValueNotifier<Color?>> _known = {};
  static final Map<String, ValueNotifier<CoverPalette?>> _palettes = {};

  /// El color de esa portada, que avisa cuando se sabe. Sin portada, siempre `null`.
  static ValueListenable<Color?> watch(String? source) {
    if (source == null) return _none;
    return _known.putIfAbsent(source, () => ValueNotifier<Color?>(null));
  }

  /// Los colores de esa portada (el principal, un segundo tono y el fondo hondo) para el jaspeado del vinilo; avisa cuando se saben. `null`
  /// mientras no se sepan o si la portada es gris.
  static ValueListenable<CoverPalette?> watchPalette(String? source) {
    if (source == null) return _noPalette;
    return _palettes.putIfAbsent(source, () => ValueNotifier<CoverPalette?>(null));
  }

  /// Lo que ya se sabe del color de esa portada (`null` si aún no o si es gris).
  static Color? of(String? source) => source == null ? null : _known[source]?.value;

  /// Apunta el color de esa portada, sacado de su pixel art.
  static void learn(String source, PixelArt art) {
    final notifier = _known.putIfAbsent(source, () => ValueNotifier<Color?>(null));
    final color = tintOf(art);
    if (notifier.value != color) notifier.value = color;
    final palette = paletteOf(art.rgba);
    final known = _palettes.putIfAbsent(source, () => ValueNotifier<CoverPalette?>(null));
    if (known.value != palette) known.value = palette;
  }

  /// Para las pruebas: pone a mano el color de una portada.
  @visibleForTesting
  static void set(String source, Color? color) => _known.putIfAbsent(source, () => ValueNotifier<Color?>(null)).value = color;

  /// Para las pruebas: pone a mano la paleta de una portada.
  @visibleForTesting
  static void setPalette(String source, CoverPalette? palette) => _palettes.putIfAbsent(source, () => ValueNotifier<CoverPalette?>(null)).value = palette;

  /// Para las pruebas: lo olvida todo.
  @visibleForTesting
  static void clear() {
    _known.clear();
    _palettes.clear();
  }

  static final ValueNotifier<Color?> _none = ValueNotifier<Color?>(null);
  static final ValueNotifier<CoverPalette?> _noPalette = ValueNotifier<CoverPalette?>(null);
}

/// El color de un pixel art: el tono con más presencia, con viveza y brillo de neón (`accentOf`). `null` si es casi gris.
Color? tintOf(PixelArt art) => accentOf(art.rgba);

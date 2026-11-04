import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui/widgets/app_backdrop.dart';

/// Los colores de la app, siempre en modo oscuro: el gris de Kyora y su dorado. Se leen con `context.colors`.
@immutable
class KyoraColors extends ThemeExtension<KyoraColors> {
  const KyoraColors({
    required this.background,
    required this.surface,
    required this.plate,
    required this.field,
    required this.pick,
    required this.edge,
    required this.ink,
    required this.dim,
    required this.accent,
    required this.onAccent,
    required this.warn,
    required this.ok,
  });

  /// El fondo de las pantallas.
  final Color background;

  /// Hojas, diálogos y tarjetas.
  final Color surface;

  /// Superficies algo más claras (barra del reproductor, avisos).
  final Color plate;

  /// Campos de escribir y carriles: más oscuros que el fondo.
  final Color field;

  /// Lo elegido o lo propio (el relleno de mis burbujas).
  final Color pick;

  /// El filo fino de campos y tarjetas.
  final Color edge;

  /// El texto normal y el atenuado.
  final Color ink;
  final Color dim;

  /// El color principal (botones, lo que suena, lo activo) y el del texto que va encima.
  final Color accent;
  final Color onAccent;

  /// Errores y requisitos cumplidos.
  final Color warn;
  final Color ok;

  /// Mis burbujas del chat.
  Color get mine => pick;

  static const _warn = Color(0xFFE07A5F);
  static const _ok = Color(0xFF5DBB63);

  // El gris oscuro de la app: de menos a más claro, cada capa se separa de la de abajo.
  static const _field = Color(0xFF17181A);
  static const _background = Color(0xFF1F2023);
  static const _surface = Color(0xFF2A2B2F);
  static const _plate = Color(0xFF33353A);
  static const _pick = Color(0xFF3B3D43);
  static const _ink = Color(0xFF141414); // el texto oscuro que va sobre el acento

  /// Los colores de siempre: el gris oscuro y el acento dorado de Kyora.
  factory KyoraColors.classic() => const KyoraColors(
        background: _background,
        surface: _surface,
        plate: _plate,
        field: _field,
        pick: _pick,
        edge: Color(0x1AFFFFFF),
        ink: Color(0xFFE8E8E8),
        dim: Color(0xFFB4B4B4),
        accent: Color(0xFFE3B25A),
        onAccent: Color(0xFF141414),
        warn: _warn,
        ok: _ok,
      );

  /// Los colores a partir del color de una carátula: todo sale de ella (el tono de los fondos y de los textos y el color principal), con la
  /// misma escalera de claridad que los de siempre, y con la claridad del acento y de los textos ajustada para que se lean (contraste de
  /// 4,5:1 como mínimo contra el fondo, la superficie y la placa). Una carátula gris da un juego neutro, sin color.
  factory KyoraColors.fromCover(Color seed) {
    final hsl = HSLColor.fromColor(seed);
    final gray = hsl.saturation < 0.12;
    final hue = hsl.hue;
    final tint = gray ? 0.03 : (hsl.saturation * 0.5).clamp(0.2, 0.5);
    Color tone(double lightness, [double? saturation]) => HSLColor.fromAHSL(1, hue, saturation ?? tint, lightness).toColor();

    final field = tone(0.09);
    final background = tone(0.12);
    final surface = tone(0.16);
    final plate = tone(0.195);
    final pick = tone(0.235);
    final darkest = [field, background, surface, plate, pick];

    /// Sube la claridad de un color hasta que se lea sobre las placas más claras.
    Color readable(double saturation, double lightness, double ratio) {
      var l = lightness;
      var color = HSLColor.fromAHSL(1, hue, saturation, l).toColor();
      while (l < 0.97 && darkest.any((back) => contrastRatio(color, back) < ratio)) {
        l += 0.02;
        color = HSLColor.fromAHSL(1, hue, saturation, l).toColor();
      }
      return color;
    }

    final accentSaturation = gray ? 0.0 : hsl.saturation.clamp(0.5, 0.9);
    var accent = readable(accentSaturation, gray ? 0.72 : 0.62, 4.5);
    // el texto de encima (oscuro o claro, el que más se lea): si ninguno llega, se aclara el acento hasta que el oscuro sí
    Color onAccentFor(Color color) => contrastRatio(_ink, color) >= contrastRatio(Colors.white, color) ? _ink : Colors.white;
    var accentLightness = HSLColor.fromColor(accent).lightness;
    while (contrastRatio(onAccentFor(accent), accent) < 4.5 && accentLightness < 0.97) {
      accentLightness += 0.02;
      accent = HSLColor.fromAHSL(1, hue, accentSaturation, accentLightness).toColor();
    }
    final onAccent = onAccentFor(accent);
    return KyoraColors(
      background: background,
      surface: surface,
      plate: plate,
      field: field,
      pick: pick,
      edge: const Color(0x1AFFFFFF),
      ink: readable(0.10, 0.93, 7),
      dim: readable(0.10, 0.74, 4.5),
      accent: accent,
      onAccent: onAccent,
      warn: _warn,
      ok: _ok,
    );
  }

  @override
  KyoraColors copyWith({
    Color? background,
    Color? surface,
    Color? plate,
    Color? field,
    Color? pick,
    Color? edge,
    Color? ink,
    Color? dim,
    Color? accent,
    Color? onAccent,
    Color? warn,
    Color? ok,
  }) =>
      KyoraColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        plate: plate ?? this.plate,
        field: field ?? this.field,
        pick: pick ?? this.pick,
        edge: edge ?? this.edge,
        ink: ink ?? this.ink,
        dim: dim ?? this.dim,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        warn: warn ?? this.warn,
        ok: ok ?? this.ok,
      );

  @override
  KyoraColors lerp(ThemeExtension<KyoraColors>? other, double t) {
    if (other is! KyoraColors) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return KyoraColors(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      plate: mix(plate, other.plate),
      field: mix(field, other.field),
      pick: mix(pick, other.pick),
      edge: mix(edge, other.edge),
      ink: mix(ink, other.ink),
      dim: mix(dim, other.dim),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      warn: mix(warn, other.warn),
      ok: mix(ok, other.ok),
    );
  }
}

/// El contraste entre dos colores (1 = ninguno, 21 = blanco sobre negro): 4,5 es lo mínimo para leer un texto.
double contrastRatio(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

extension KyoraColorsContext on BuildContext {
  /// Los colores de la app en este momento.
  KyoraColors get colors => Theme.of(this).extension<KyoraColors>() ?? KyoraColors.classic();
}

/// El tema (siempre oscuro) para esos colores.
ThemeData buildTheme([KyoraColors? colors]) {
  final c = colors ?? KyoraColors.classic();
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: Brightness.dark,
    surface: c.background,
  ).copyWith(
    primary: c.accent,
    onPrimary: c.onAccent,
    error: c.warn,
    onSurface: c.ink,
    onSurfaceVariant: c.dim,
    surfaceContainerHighest: c.pick,
    surfaceContainerHigh: c.plate,
    surfaceContainer: c.surface,
    surfaceContainerLowest: c.field,
  );
  final base = TextStyle(color: c.ink, fontSize: 16);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    extensions: [c],
    scaffoldBackgroundColor: Colors.transparent, // el fondo lo pinta `AppBackdrop`, detrás de todas las pantallas
    canvasColor: c.background,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: LayerPageTransitions(),
      TargetPlatform.iOS: LayerPageTransitions(),
      TargetPlatform.windows: LayerPageTransitions(),
      TargetPlatform.macOS: LayerPageTransitions(),
      TargetPlatform.linux: LayerPageTransitions(),
    }),
    textTheme: TextTheme(
      bodyLarge: base,
      bodyMedium: base,
      bodySmall: TextStyle(color: c.dim, fontSize: 13),
      titleMedium: TextStyle(color: c.ink, fontSize: 18, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.field,
      hintStyle: TextStyle(color: c.dim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: c.edge)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: c.edge)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide(color: c.accent)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.plate,
      contentTextStyle: base,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surface, modalBackgroundColor: c.surface),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.onAccent : c.dim),
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.accent : c.pick),
    ),
  );
}

/// Cómo se comportan los desplazamientos: sin el estiramiento en los extremos. Ese efecto de Material 3 pinta la lista a través de un
/// filtro de imagen, y mientras dura todas las tarjetas de cristal que lleva dentro pierden lo que tienen detrás (se quita el desenfoque).
class KyraScrollBehavior extends MaterialScrollBehavior {
  const KyraScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const ClampingScrollPhysics();
}

final _coverThemes = <int, ThemeData>{};
ThemeData? _classicTheme;

/// El tema de la app para el color de la carátula que suena (`null` = nada ha sonado: los colores de siempre). Se guarda lo ya
/// calculado: construir un tema no es barato y el mismo color sale muchas veces.
ThemeData buildCoverTheme(Color? tint) {
  if (tint == null) return _classicTheme ??= buildTheme();
  final cache = _coverThemes[tint.toARGB32()];
  if (cache != null) return cache;
  if (_coverThemes.length > 64) _coverThemes.clear();
  return _coverThemes[tint.toARGB32()] = buildTheme(KyoraColors.fromCover(tint));
}

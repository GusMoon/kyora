import 'package:flutter/material.dart';

import '../../theme.dart';
import 'neo_themes.dart';

/// El diseño **cyber-brutalista** de KyraFamily: fondo liso con una cuadrícula tenue, **filos finos**, etiquetas monoespaciadas en
/// mayúsculas con su número (`/01`), títulos grandes y condensados, botones llenos con la flecha en el color de acento y avisos en el color
/// «pop». Los colores salen de uno de los 10 temas (`neo_themes.dart`), en modo claro u oscuro, y se leen con `context.neo`. (El
/// administrador conserva el diseño sci-fi de siempre.)
class Neo {
  const Neo._();

  /// Los avisos (errores) y lo cumplido: iguales en todos los temas.
  static const warn = Color(0xFFE5173F);
  static const ok = Color(0xFF17B26A);

  /// El grosor de los filos finos y de los marcados (campos, botones secundarios).
  static const border = 1.0;
  static const strong = 1.5;

  /// El negro y el blanco de verdad (para elegir el texto que va sobre un color).
  static const black = Color(0xFF0A0A0D);
  static const white = Color(0xFFFFFFFF);
}

/// Todos los colores de KyraFamily en este momento: las superficies (que cambian con el modo oscuro) y los acentos (que cambian con el tema).
///  · `bg` el fondo, `paper` las tarjetas, `soft` lo de dentro de una tarjeta, `line` los filos finos;
///  · `ink` el texto (y el relleno de los botones principales), `dim` el texto secundario;
///  · `accent` lo activo, los números y las flechas; `accentDeep` el texto en color de acento; `pop` lo resaltado (etiquetas, lo elegido,
///    los mensajes propios). `onAccent` y `onPop` son los textos que van encima.
@immutable
class NeoScheme extends ThemeExtension<NeoScheme> {
  const NeoScheme({
    required this.dark,
    required this.bg,
    required this.paper,
    required this.soft,
    required this.line,
    required this.ink,
    required this.dim,
    required this.accent,
    required this.accentDeep,
    required this.pop,
    required this.onAccent,
    required this.onPop,
  });

  final bool dark;
  final Color bg;
  final Color paper;
  final Color soft;
  final Color line;
  final Color ink;
  final Color dim;
  final Color accent;
  final Color accentDeep;
  final Color pop;
  final Color onAccent;
  final Color onPop;

  /// El tema de siempre, en claro.
  static final standard = NeoScheme.of(NeoThemes.standard);

  /// Los colores de un tema, en claro u oscuro. Los acentos se ajustan lo justo para que se lean: el acento sobre el fondo y su texto encima,
  /// y el pop con su texto.
  factory NeoScheme.of(NeoThemeSpec spec, {bool dark = false}) {
    final bg = dark ? const Color(0xFF0B0B0E) : const Color(0xFFF4F4F5);
    final paper = dark ? const Color(0xFF141418) : Neo.white;
    final ink = dark ? const Color(0xFFF2F2F4) : Neo.black;
    final accent = readableOn(spec.accent, bg, 4.5);
    final deep = readableOn(dark ? spec.accent : _shade(spec.accent, 0.82), bg, 7);
    final pop = withReadableText(spec.pop, 4.5);
    return NeoScheme(
      dark: dark,
      bg: bg,
      paper: paper,
      soft: dark ? const Color(0xFF1E1E24) : const Color(0xFFE9E9EC),
      line: dark ? const Color(0xFF2E2E36) : const Color(0xFFC6C6CE),
      ink: ink,
      dim: dark ? const Color(0xFFA2A2AE) : const Color(0xFF55555F),
      accent: accent,
      accentDeep: deep,
      pop: pop,
      onAccent: textOn(accent),
      onPop: textOn(pop),
    );
  }

  /// El texto que mejor se lee sobre [fill]: casi negro o blanco.
  static Color textOn(Color fill) => contrastRatio(fill, Neo.black) >= contrastRatio(fill, Neo.white) ? Neo.black : Neo.white;

  /// El texto que va sobre un relleno cualquiera de la app (el acento, el pop, la tinta, una tarjeta…).
  Color onColor(Color fill) => fill == ink ? paper : (fill == paper || fill == bg || fill == soft ? ink : textOn(fill));

  /// [color] con el brillo justo para que se lea sobre [background] (contraste mínimo [min]): se oscurece sobre un fondo claro y se aclara
  /// sobre uno oscuro, sin perder su tono.
  static Color readableOn(Color color, Color background, double min) {
    final darkBg = background.computeLuminance() < 0.2;
    var c = color;
    for (var t = 0.0; contrastRatio(c, background) < min && t < 1; t += 0.04) {
      c = Color.lerp(color, darkBg ? Neo.white : Neo.black, t)!;
    }
    return c;
  }

  /// [color] ajustado para que su texto (negro o blanco, el que mejor vaya) se lea encima con contraste [min].
  static Color withReadableText(Color color, double min) {
    final text = textOn(color);
    var c = color;
    for (var t = 0.0; contrastRatio(c, text) < min && t < 1; t += 0.04) {
      c = Color.lerp(color, text == Neo.black ? Neo.white : Neo.black, t)!;
    }
    return c;
  }

  static Color _shade(Color c, double f) {
    final hsv = HSVColor.fromColor(c);
    return hsv.withValue((hsv.value * f).clamp(0.0, 1.0)).toColor();
  }

  /// Los mismos colores con los nombres de la app de siempre, para las piezas compartidas (cuadros de diálogo, campos…).
  KyoraColors get kyora => KyoraColors(
        background: bg,
        surface: paper,
        plate: soft,
        field: paper,
        pick: pop,
        edge: line,
        ink: ink,
        dim: dim,
        accent: accent,
        onAccent: onAccent,
        warn: Neo.warn,
        ok: Neo.ok,
        tasks: accent,
        reminders: pop,
        habits: Neo.ok,
      );

  @override
  bool operator ==(Object other) =>
      other is NeoScheme &&
      other.dark == dark &&
      other.bg == bg &&
      other.paper == paper &&
      other.ink == ink &&
      other.accent == accent &&
      other.accentDeep == accentDeep &&
      other.pop == pop;

  @override
  int get hashCode => Object.hash(dark, bg, paper, ink, accent, accentDeep, pop);

  @override
  NeoScheme copyWith({Color? accent, Color? pop}) => NeoScheme(
        dark: dark,
        bg: bg,
        paper: paper,
        soft: soft,
        line: line,
        ink: ink,
        dim: dim,
        accent: accent ?? this.accent,
        accentDeep: accentDeep,
        pop: pop ?? this.pop,
        onAccent: onAccent,
        onPop: onPop,
      );

  @override
  NeoScheme lerp(ThemeExtension<NeoScheme>? other, double t) {
    if (other is! NeoScheme) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return NeoScheme(
      dark: t < 0.5 ? dark : other.dark,
      bg: mix(bg, other.bg),
      paper: mix(paper, other.paper),
      soft: mix(soft, other.soft),
      line: mix(line, other.line),
      ink: mix(ink, other.ink),
      dim: mix(dim, other.dim),
      accent: mix(accent, other.accent),
      accentDeep: mix(accentDeep, other.accentDeep),
      pop: mix(pop, other.pop),
      onAccent: mix(onAccent, other.onAccent),
      onPop: mix(onPop, other.onPop),
    );
  }
}

extension NeoSchemeContext on BuildContext {
  /// Los colores de KyraFamily en este momento.
  NeoScheme get neo => Theme.of(this).extension<NeoScheme>() ?? NeoScheme.standard;
}

/// Un título grande: condensado (Bebas Neue), en mayúsculas (se escribe así). Sin `color`, el del texto del tema.
TextStyle neoHeading({double size = 22, Color? color}) =>
    TextStyle(fontFamily: neoDisplayFont, fontSize: size * 1.25, fontWeight: FontWeight.w400, letterSpacing: size * 0.01, height: 0.98, color: color);

/// El texto normal: monoespaciado. Sin `color`, el del texto del tema.
TextStyle neoBody({double size = 16, Color? color, FontWeight weight = FontWeight.w500}) =>
    TextStyle(fontFamily: monoFont, fontSize: size * 0.9, fontWeight: weight == FontWeight.w500 ? FontWeight.w400 : weight, height: 1.45, color: color);

/// Una etiqueta técnica: monoespaciada, en mayúsculas y con las letras separadas. Sin `color`, el del texto del tema.
TextStyle neoLabel({double size = 13, Color? color}) =>
    TextStyle(fontFamily: monoFont, fontSize: size, fontWeight: FontWeight.w500, letterSpacing: 1.0, color: color);

/// La letra de los títulos grandes.
const neoDisplayFont = 'Bebas Neue';

/// El tema de KyraFamily para esos colores: con filos finos y sin redondeos.
ThemeData neoTheme([NeoScheme? scheme]) {
  final s = scheme ?? NeoScheme.standard;
  final line = BorderSide(color: s.ink, width: Neo.border);
  final hair = BorderSide(color: s.line, width: Neo.border);
  final brightness = s.dark ? Brightness.dark : Brightness.light;
  final colors = ColorScheme.fromSeed(seedColor: s.accent, brightness: brightness).copyWith(
    primary: s.accent,
    onPrimary: s.onAccent,
    secondary: s.pop,
    onSecondary: s.onPop,
    error: Neo.warn,
    onError: Neo.white,
    surface: s.paper,
    onSurface: s.ink,
    onSurfaceVariant: s.dim,
    outline: s.ink,
    outlineVariant: s.line,
    surfaceTint: Colors.transparent,
    shadow: Colors.transparent,
  );
  final base = neoBody(color: s.ink);
  return ThemeData(
    useMaterial3: true,
    fontFamily: appFont,
    brightness: brightness,
    colorScheme: colors,
    extensions: [s.kyora, s],
    scaffoldBackgroundColor: Colors.transparent, // el fondo (liso con la cuadrícula) lo pinta `GuestShell`
    canvasColor: s.paper,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    hoverColor: Colors.transparent,
    textTheme: TextTheme(
      bodyLarge: base,
      bodyMedium: base,
      bodySmall: neoBody(size: 14, color: s.dim),
      titleMedium: neoHeading(size: 18, color: s.ink),
      labelLarge: neoLabel(size: 14, color: s.ink),
    ),
    iconTheme: IconThemeData(color: s.ink),
    dividerTheme: DividerThemeData(color: s.line, thickness: Neo.border, space: Neo.border),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.paper,
      hintStyle: neoBody(color: s.dim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: line),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: line),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: s.accent, width: Neo.strong * 1.5)),
      errorBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Neo.warn, width: Neo.border)),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: s.ink, selectionColor: s.pop.withValues(alpha: 0.6), selectionHandleColor: s.accent),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: s.pop,
      contentTextStyle: neoBody(weight: FontWeight.w700, color: s.onPop),
      actionTextColor: s.onPop,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(side: BorderSide(color: s.ink, width: Neo.border)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.paper,
      elevation: 0,
      shape: RoundedRectangleBorder(side: hair),
      titleTextStyle: neoHeading(color: s.ink),
      contentTextStyle: neoBody(color: s.ink),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.paper,
      modalBackgroundColor: s.paper,
      elevation: 0,
      modalElevation: 0,
      shape: Border(top: BorderSide(color: s.ink, width: Neo.border)),
      dragHandleColor: s.dim,
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: s.ink, shape: const RoundedRectangleBorder(), textStyle: neoLabel())),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(),
      side: BorderSide(color: s.ink, width: Neo.strong),
      fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? s.accent : Colors.transparent),
      checkColor: WidgetStatePropertyAll(s.onAccent),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: s.accent, inactiveTrackColor: s.soft, thumbColor: s.accent, overlayColor: Colors.transparent),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: s.accent, linearTrackColor: s.soft, circularTrackColor: Colors.transparent),
  );
}

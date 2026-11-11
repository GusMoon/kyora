import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui/widgets/cut_border.dart';

import 'ui/widgets/app_backdrop.dart';

/// El color de acento (un neón) con el que se viste la app y el texto que va encima. Sale del fondo de pantalla; sin fondo, [standard].
@immutable
class AppPalette {
  const AppPalette({required this.accent});

  /// El acento: el color de lo elegido, de los botones principales y de las tarjetas destacadas.
  final Color accent;

  /// El texto que va sobre el acento: casi negro, o blanco si el acento es muy oscuro.
  Color get onAccent => accent.computeLuminance() > 0.18 ? const Color(0xFF0A0B0D) : const Color(0xFFFFFFFF);

  /// El de siempre: un naranja.
  static const standard = AppPalette(accent: Color(0xFFFF5A1F));
}

/// Los colores de la app: un negro limpio con tarjetas en grises oscuros, texto claro y **un acento de neón** (el que sale del fondo de pantalla) para lo
/// activo y lo destacado. Se leen con `context.colors`.
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
    required this.reminders,
    required this.tasks,
    required this.habits,
  });

  /// El fondo de las pantallas.
  final Color background;

  /// Las tarjetas, otra más clara para lo que va dentro de ellas (`plate`), los campos de escribir (`field`) y lo elegido (`pick`).
  final Color surface;
  final Color plate;
  final Color field;
  final Color pick;

  /// El filo fino de las tarjetas y los separadores (blanco muy tenue).
  final Color edge;

  /// El texto normal y el secundario.
  final Color ink;
  final Color dim;

  /// Lo activo o elegido y el texto que va encima.
  final Color accent;
  final Color onAccent;

  /// Avisos (lo vencido, los errores) y lo cumplido.
  final Color warn;
  final Color ok;

  /// Los colores de los recordatorios, las tareas y los hábitos (en sus iconos y cifras).
  final Color reminders;
  final Color tasks;
  final Color habits;

  /// Mis burbujas del chat: claras, con texto oscuro.
  Color get mine => ink;

  /// El texto sobre `mine`.
  Color get onMine => background;

  /// Los colores con un acento.
  factory KyoraColors.of(AppPalette palette) => KyoraColors(
        background: const Color(0xFF08090B),
        surface: const Color(0xFF14161A),
        plate: const Color(0xFF1D2025),
        field: const Color(0xFF101216),
        pick: const Color(0xFF282C33),
        edge: const Color(0x1FFFFFFF),
        ink: const Color(0xFFF3F4F6),
        dim: const Color(0xFF9AA1AC),
        accent: palette.accent,
        onAccent: palette.onAccent,
        warn: const Color(0xFFFF6B6B),
        ok: const Color(0xFF7CE38B),
        reminders: const Color(0xFFFFD166),
        tasks: const Color(0xFF5BC8FF),
        habits: const Color(0xFF7CE38B),
      );

  /// Los de siempre (el naranja de acento).
  factory KyoraColors.classic() => KyoraColors.of(AppPalette.standard);

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
    Color? reminders,
    Color? tasks,
    Color? habits,
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
        reminders: reminders ?? this.reminders,
        tasks: tasks ?? this.tasks,
        habits: habits ?? this.habits,
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
      reminders: mix(reminders, other.reminders),
      tasks: mix(tasks, other.tasks),
      habits: mix(habits, other.habits),
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

/// La letra de toda la app: una grotesca moderna (títulos, cifras y texto) y, para lo técnico (etiquetas, códigos, datos), una monoespaciada.
const appFont = 'Space Grotesk';
const monoFont = 'IBM Plex Mono';

/// La misma dentro de las pantallas.
const screenFont = appFont;

/// Una etiqueta técnica: monoespaciada, en mayúsculas (se escriben así) y con las letras algo separadas.
TextStyle hudLabel({double size = 15, Color? color}) =>
    TextStyle(fontFamily: monoFont, fontSize: size, fontWeight: FontWeight.w500, letterSpacing: 1.1, color: color);

/// Un título o una cifra grande: la grotesca, en seminegrita y con las letras algo juntas.
TextStyle display({double size = 32, Color? color, FontWeight weight = FontWeight.w600}) =>
    TextStyle(fontFamily: appFont, fontSize: size, fontWeight: weight, letterSpacing: -size * 0.03, height: 1.05, color: color);

/// Títulos de un grupo y botones: seminegrita.
TextStyle lcdLabel({double size = 15, Color? color}) =>
    TextStyle(fontFamily: appFont, fontSize: size, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: color);

/// Un mensaje de estado («cargando…», «sin conexión»): atenuado (nunca por debajo de 15 px).
TextStyle lcdStatus({double size = 15, Color? color}) => TextStyle(fontFamily: appFont, fontSize: size, color: color);

/// El tema para esos colores: oscuro, con tarjetas de esquinas cortadas y el acento de la paleta.
ThemeData buildTheme([KyoraColors? colors]) {
  final c = colors ?? KyoraColors.classic();
  final scheme = ColorScheme.fromSeed(seedColor: c.accent, brightness: Brightness.dark, surface: c.background).copyWith(
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.warn,
    onError: c.background,
    surface: c.background,
    onSurface: c.ink,
    onSurfaceVariant: c.dim,
    outline: c.edge,
    outlineVariant: c.edge,
    surfaceTint: Colors.transparent,
    surfaceContainerHighest: c.pick,
    surfaceContainerHigh: c.plate,
    surfaceContainer: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainerLowest: c.field,
    inverseSurface: c.ink,
    onInverseSurface: c.background,
    shadow: Colors.transparent,
  );
  final base = TextStyle(fontFamily: appFont, color: c.ink, fontSize: 16);
  final line = BorderSide(color: c.edge, width: 1);
  const round = CutBorder(cut: 12);
  const pill = CutBorder(cut: 10);
  return ThemeData(
    useMaterial3: true,
    fontFamily: appFont,
    brightness: Brightness.dark,
    colorScheme: scheme,
    extensions: [c],
    scaffoldBackgroundColor: Colors.transparent, // el fondo lo pinta `AppBackdrop`
    canvasColor: c.background,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    hoverColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: display(size: 20, color: c.ink),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: LayerPageTransitions(),
        TargetPlatform.iOS: LayerPageTransitions(),
        TargetPlatform.windows: LayerPageTransitions(),
        TargetPlatform.macOS: LayerPageTransitions(),
        TargetPlatform.linux: LayerPageTransitions(),
      },
    ),
    textTheme: TextTheme(
      bodyLarge: base,
      bodyMedium: base,
      bodySmall: base.copyWith(color: c.dim, fontSize: 15),
      titleMedium: display(size: 18, color: c.ink),
      labelLarge: base.copyWith(fontWeight: FontWeight.w600),
    ),
    iconTheme: IconThemeData(color: c.ink),
    dividerTheme: DividerThemeData(color: c.edge, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.field,
      hintStyle: TextStyle(fontFamily: appFont, color: c.dim, fontSize: 16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: line),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: line),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: c.accent, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        disabledBackgroundColor: c.plate,
        disabledForegroundColor: c.dim,
        minimumSize: const Size.fromHeight(52),
        elevation: 0,
        shape: pill,
        textStyle: lcdLabel(size: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.accent, shape: pill, textStyle: lcdLabel(size: 16))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: c.ink, shape: pill, side: line, textStyle: lcdLabel(size: 16))),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: c.ink)),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.pick,
      contentTextStyle: base,
      actionTextColor: c.accent,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: round,
    ),
    dialogTheme: DialogThemeData(backgroundColor: c.surface, elevation: 0, shape: CutBorder(cut: 18, all: true, side: line)),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      elevation: 0,
      modalElevation: 0,
      shape: CutBorder(cut: 22, side: line),
      dragHandleColor: c.dim,
    ),
    popupMenuTheme: PopupMenuThemeData(color: c.plate, elevation: 0, shape: round),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.plate, circularTrackColor: Colors.transparent),
    checkboxTheme: CheckboxThemeData(
      shape: const RoundedRectangleBorder(),
      side: BorderSide(color: c.dim, width: 1.5),
      fillColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.accent : Colors.transparent),
      checkColor: WidgetStatePropertyAll(c.onAccent),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.onAccent : c.dim),
      trackColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected) ? c.accent : c.pick),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: c.accent, inactiveTrackColor: c.pick, thumbColor: c.accent, overlayColor: Colors.transparent),
  );
}

/// Cómo se comportan los desplazamientos: sin el estiramiento en los extremos.
class KyraScrollBehavior extends MaterialScrollBehavior {
  const KyraScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const ClampingScrollPhysics();
}

final _accentThemes = <int, ThemeData>{};

/// El tema de la app para un color de acento, el que sale del fondo de pantalla (`null` = el de siempre). Se guarda lo ya calculado.
ThemeData buildAccentTheme(Color? accent) {
  final palette = accent == null ? AppPalette.standard : AppPalette(accent: accent);
  return _accentThemes[palette.accent.toARGB32()] ??= buildTheme(KyoraColors.of(palette));
}

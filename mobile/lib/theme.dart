import 'package:flutter/material.dart';

/// Los colores de la app: oscuros y con el acento dorado de Kyora (en la PC el acento sale del fondo de pantalla; aquí es fijo).
class Palette {
  const Palette._();

  static const background = Color(0xFF151515);
  static const surface = Color(0xFF1D1D1D);
  static const plate = Color(0xFF262626);
  static const field = Color(0xFF0F0F0F);
  static const ink = Color(0xFFE8E8E8);
  static const dim = Color(0xFF9A9A9A);
  static const accent = Color(0xFFE3B25A);
  static const warn = Color(0xFFE07A5F);
  static const edge = Color(0x14FFFFFF);
  static const pick = Color(0xFF2E2E2E);

  /// El relleno de mis burbujas: un gris algo más claro, liso (como el mensaje del usuario en Claude, igual que en la PC).
  static Color get mine => pick;
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.accent,
    brightness: Brightness.dark,
    surface: Palette.background,
  ).copyWith(primary: Palette.accent, onPrimary: const Color(0xFF141414), error: Palette.warn);
  const base = TextStyle(color: Palette.ink, fontSize: 16);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.background,
    canvasColor: Palette.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.background,
      foregroundColor: Palette.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: const TextTheme(
      bodyLarge: base,
      bodyMedium: base,
      bodySmall: TextStyle(color: Palette.dim, fontSize: 13),
      titleMedium: TextStyle(color: Palette.ink, fontSize: 18, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.field,
      hintStyle: const TextStyle(color: Palette.dim),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Palette.edge)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Palette.edge)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: Palette.accent)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.accent,
        foregroundColor: const Color(0xFF141414),
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.plate,
      contentTextStyle: base,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: Palette.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Palette.surface, modalBackgroundColor: Palette.surface),
  );
}

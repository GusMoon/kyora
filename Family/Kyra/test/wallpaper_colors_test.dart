import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/wallpaper_store.dart';
import 'package:kyora_chat/state/wallpaper_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/util/wallpaper_color.dart';

/// Unos píxeles RGBA: cada par (color, cuántos) repite ese color.
Uint8List pixels(List<(Color, int)> parts) {
  final out = <int>[];
  for (final (color, count) in parts) {
    for (var i = 0; i < count; i++) {
      out.addAll([(color.r * 255).round(), (color.g * 255).round(), (color.b * 255).round(), 255]);
    }
  }
  return Uint8List.fromList(out);
}

double hueOf(Color c) => HSVColor.fromColor(c).hue;

double gap(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

void main() {
  final orange = HSVColor.fromAHSV(1, 20, 0.9, 0.9).toColor();
  final teal = HSVColor.fromAHSV(1, 180, 0.8, 0.8).toColor();
  final violet = HSVColor.fromAHSV(1, 280, 0.8, 0.8).toColor();
  final green = HSVColor.fromAHSV(1, 110, 0.8, 0.8).toColor();

  group('los colores secundarios del fondo', () {
    test('salen de otros tonos de la imagen, aunque pesen poco, y no del predominante', () {
      // casi todo naranja, y un poco de verde azulado, violeta y verde
      final rgba = pixels([(orange, 900), (teal, 60), (violet, 30), (green, 10), (const Color(0xFF101010), 200)]);
      final accent = accentOf(rgba)!;
      expect(gap(hueOf(accent), 20), lessThan(10)); // el predominante es el naranja
      final extras = secondaryColorsOf(rgba, accent);
      expect(extras, hasLength(3));
      final hues = extras.map(hueOf).toList();
      expect(hues.any((h) => gap(h, 180) < 12), isTrue, reason: 'el verde azulado del fondo'); // el de más peso va primero
      expect(hues.any((h) => gap(h, 280) < 12), isTrue, reason: 'el violeta del fondo');
      expect(hues.any((h) => gap(h, 110) < 12), isTrue, reason: 'el verde del fondo');
      expect(gap(hues.first, 180), lessThan(12)); // por peso: primero el verde azulado
      for (final h in hues) {
        expect(gap(h, hueOf(accent)), greaterThanOrEqualTo(45), reason: 'no se parecen al acento');
      }
    });

    test('son distintos entre sí y vivos (tonos de neón)', () {
      final rgba = pixels([(orange, 500), (teal, 200), (violet, 150), (green, 100)]);
      final extras = secondaryColorsOf(rgba, accentOf(rgba)!);
      for (var i = 0; i < extras.length; i++) {
        for (var j = i + 1; j < extras.length; j++) {
          expect(gap(hueOf(extras[i]), hueOf(extras[j])), greaterThanOrEqualTo(45));
        }
        final hsv = HSVColor.fromColor(extras[i]);
        expect(hsv.saturation, greaterThan(0.6));
        expect(hsv.value, greaterThan(0.85));
      }
    });

    test('un fondo de un solo color da igual tres tonos distintos del acento (girando el tono)', () {
      final rgba = pixels([(orange, 800)]);
      final accent = accentOf(rgba)!;
      final extras = secondaryColorsOf(rgba, accent);
      expect(extras, hasLength(3));
      final hues = [hueOf(accent), ...extras.map(hueOf)];
      for (var i = 0; i < hues.length; i++) {
        for (var j = i + 1; j < hues.length; j++) {
          expect(gap(hues[i], hues[j]), greaterThanOrEqualTo(45), reason: '$i y $j');
        }
      }
    });

    test('lo gris y lo casi negro no cuentan como colores', () {
      final rgba = pixels([(orange, 100), (const Color(0xFF888888), 900), (const Color(0xFF050505), 500)]);
      final extras = secondaryColorsOf(rgba, accentOf(rgba)!);
      expect(extras, hasLength(3)); // se completan girando el acento: nada sale del gris
      for (final e in extras) {
        expect(HSVColor.fromColor(e).saturation, greaterThan(0.6));
      }
    });
  });

  group('el tema', () {
    test('las tareas, los recordatorios y los hábitos toman los colores del fondo (en ese orden); los que falten, los de siempre', () {
      final a = const Color(0xFF11AA99);
      final b = const Color(0xFFAA1199);
      final c = const Color(0xFF9911AA);
      final full = KyoraColors.of(AppPalette(accent: orange, extras: [a, b, c]));
      expect((full.tasks, full.reminders, full.habits), (a, b, c));
      final partial = KyoraColors.of(AppPalette(accent: orange, extras: [a]));
      expect(partial.tasks, a);
      expect(partial.reminders, KyoraColors.classic().reminders);
      expect(partial.habits, KyoraColors.classic().habits);
      final none = KyoraColors.of(AppPalette(accent: orange));
      expect((none.tasks, none.reminders, none.habits), (KyoraColors.classic().tasks, KyoraColors.classic().reminders, KyoraColors.classic().habits));
    });

    test('el tema para un acento y unos colores secundarios se reutiliza, y con otros colores es otro', () {
      final one = buildAccentTheme(orange, [teal, violet, green]);
      expect(identical(buildAccentTheme(orange, [teal, violet, green]), one), isTrue);
      expect(identical(buildAccentTheme(orange, [violet, teal, green]), one), isFalse);
      expect(one.extension<KyoraColors>()!.tasks, teal);
      expect(buildAccentTheme(null, [teal]).extension<KyoraColors>()!.tasks, KyoraColors.classic().tasks); // sin acento, el de siempre
    });

    testWidgets('los campos de escribir son de cristal: un velo del acento, no un bloque negro', (tester) async {
      final colors = KyoraColors.classic();
      final theme = buildTheme(colors);
      final fill = theme.inputDecorationTheme.fillColor!;
      expect(fill, isNot(colors.field));
      expect(fill.a, lessThan(0.2)); // casi transparente: se ve lo de detrás
      expect(fill.computeLuminance(), greaterThan(Colors.black.computeLuminance()));
    });
  });

  group('el fondo de pantalla guarda sus colores', () {
    test('al poner un fondo se calculan y se guardan; al quitarlo, se van', () async {
      final store = MemoryWallpaperStore();
      final c = WallpaperController(store, lookup: (_) async => orange, extras: (path, accent) async => [teal, violet, green]);
      expect(c.extras, isEmpty);
      expect(await c.set('foto.jpg'), isTrue);
      expect(c.extras, [teal, violet, green]);
      expect(store.state.extras, [teal.toARGB32(), violet.toARGB32(), green.toARGB32()]);
      await c.clear();
      expect(c.extras, isEmpty);
      expect(store.state.extras, isEmpty);
    });

    test('al abrir con un fondo guardado, vuelven los colores guardados', () {
      final store = MemoryWallpaperStore()..state = WallpaperState(path: 'f.jpg', accent: orange.toARGB32(), extras: [teal.toARGB32(), violet.toARGB32()]);
      final c = WallpaperController(store, lookup: (_) async => null, extras: (_, _) async => throw StateError('no hace falta recalcular'));
      expect(c.extras, [teal, violet]);
    });

    test('un fondo de antes (con acento pero sin colores secundarios) los calcula y los guarda al abrir', () async {
      final store = MemoryWallpaperStore()..state = WallpaperState(path: 'f.jpg', accent: orange.toARGB32());
      final c = WallpaperController(store, lookup: (_) async => orange, extras: (_, _) async => [teal, violet, green]);
      var notified = 0;
      c.addListener(() => notified++);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.extras, [teal, violet, green]);
      expect(store.state.extras, hasLength(3));
      expect(notified, greaterThan(0));
    });

    test('si no se puede leer la imagen, sin colores secundarios (se quedan los de siempre)', () async {
      final store = MemoryWallpaperStore();
      final c = WallpaperController(store, lookup: (_) async => orange, extras: (_, _) async => const []);
      await c.set('foto.jpg');
      expect(c.extras, isEmpty);
      expect(KyoraColors.of(AppPalette(accent: orange, extras: c.extras)).tasks, KyoraColors.classic().tasks);
    });
  });
}

import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/util/palette.dart';

/// Píxeles RGBA: cada franja es `(color, cuántos píxeles)`.
Uint8List pixels(List<(Color, int)> bands) {
  final out = <int>[];
  for (final (color, count) in bands) {
    for (var i = 0; i < count; i++) {
      out.addAll([(color.r * 255).round(), (color.g * 255).round(), (color.b * 255).round(), 255]);
    }
  }
  return Uint8List.fromList(out);
}

void main() {
  group('extractPalette', () {
    test('una imagen de cinco franjas da esos cinco colores exactos, del que más ocupa al que menos', () {
      const red = Color(0xFFD62828), green = Color(0xFF2A9D4F), blue = Color(0xFF1D4ED8), yellow = Color(0xFFF2C94C), white = Color(0xFFF5F5F5);
      final palette = extractPalette(pixels([(green, 500), (blue, 400), (red, 300), (yellow, 200), (white, 100)]));
      expect(palette, [green, blue, red, yellow, white]);
    });

    test('no inventa colores: cada uno sale de píxeles que la imagen tiene', () {
      // un degradado de grises y un rojo: cada grupo es la media de sus píxeles reales
      final data = pixels([
        for (var g = 0; g < 40; g++) (Color.fromARGB(255, g * 6, g * 6, g * 6), 10),
        (const Color(0xFFCC0000), 300),
      ]);
      final palette = extractPalette(data);
      expect(palette, hasLength(5));
      expect(palette.first, const Color(0xFFCC0000)); // el que más ocupa
      for (final color in palette) {
        final isGray = (color.r - color.g).abs() < 0.01 && (color.g - color.b).abs() < 0.01;
        expect(isGray || color == const Color(0xFFCC0000), isTrue, reason: '$color no está en la imagen');
      }
    });

    test('con menos de cinco colores distintos repite el último hasta completar', () {
      const a = Color(0xFF102030), b = Color(0xFFE0D0C0);
      final palette = extractPalette(pixels([(a, 80), (b, 20)]));
      expect(palette, [a, b, b, b, b]);
    });

    test('una imagen de un solo gris da ese gris cinco veces', () {
      const grey = Color(0xFF808080);
      expect(extractPalette(pixels([(grey, 50)])), List.filled(5, grey));
    });

    test('ignora los píxeles transparentes y sin píxeles opacos no hay paleta', () {
      expect(extractPalette(Uint8List.fromList([10, 20, 30, 0, 40, 50, 60, 0])), isEmpty);
      expect(extractPalette(Uint8List(0)), isEmpty);
    });

    test('es determinista: la misma imagen da siempre lo mismo', () {
      final data = pixels([for (var i = 0; i < 60; i++) (Color.fromARGB(255, (i * 37) % 256, (i * 91) % 256, (i * 13) % 256), 7)]);
      expect(extractPalette(data), extractPalette(data));
    });
  });

  group('paletteSeed', () {
    test('el que más ocupa con color; si todo es gris, el primero', () {
      const grey = Color(0xFF808080), teal = Color(0xFF1B998B);
      expect(paletteSeed([grey, teal, grey, grey, grey]), teal);
      expect(paletteSeed([grey, const Color(0xFF909090), grey, grey, grey]), grey);
    });
  });

  test('hexOf escribe el código en mayúsculas', () {
    expect(hexOf(const Color(0xFF1B998B)), '#1B998B');
    expect(hexOf(const Color(0xFF000000)), '#000000');
  });
}

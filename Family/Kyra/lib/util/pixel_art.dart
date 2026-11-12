import 'dart:typed_data';

/// Una imagen de pocos píxeles (RGBA, 4 bytes cada uno) lista para pintarse a cuadros.
class PixelArt {
  const PixelArt(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;

  /// El color del píxel `(x, y)` como `0xAARRGGBB` (los de fuera de la imagen se quedan en el borde).
  int at(int x, int y) {
    final cx = x.clamp(0, width - 1);
    final cy = y.clamp(0, height - 1);
    final i = (cy * width + cx) * 4;
    return rgba[i + 3] << 24 | rgba[i] << 16 | rgba[i + 1] << 8 | rgba[i + 2];
  }

  /// Los colores distintos que lleva (los de la paleta, si ya pasó por [quantize]).
  Set<int> get colors => {for (var y = 0; y < height; y++) for (var x = 0; x < width; x++) at(x, y)};
}

/// Pasa unos píxeles a una **paleta corta de `k` colores** (k-medias sobre los colores de la propia imagen): así sale el aspecto del pixel art,
/// de colores planos con unos pocos tonos por zona, y no un degradado de miles de tintes. Es determinista (sin azar): los colores de
/// arranque se toman a intervalos regulares de los píxeles ordenados por luminosidad. Sobre lo transparente se pone `background`.
Uint8List quantize(Uint8List rgba, int width, int height, {int k = 10, int iterations = 8, int background = 0xFF000000}) {
  final count = width * height;
  if (count == 0) return Uint8List(0);
  // los píxeles como r, g, b (lo transparente, sobre el fondo)
  final px = Float64List(count * 3);
  final order = List<int>.generate(count, (i) => i);
  for (var i = 0; i < count; i++) {
    final a = rgba[i * 4 + 3] / 255;
    px[i * 3] = rgba[i * 4] * a + ((background >> 16) & 0xFF) * (1 - a);
    px[i * 3 + 1] = rgba[i * 4 + 1] * a + ((background >> 8) & 0xFF) * (1 - a);
    px[i * 3 + 2] = rgba[i * 4 + 2] * a + (background & 0xFF) * (1 - a);
  }
  double lum(int i) => 0.2126 * px[i * 3] + 0.7152 * px[i * 3 + 1] + 0.0722 * px[i * 3 + 2];
  order.sort((a, b) => lum(a).compareTo(lum(b)));
  final groups = k < count ? k : count;
  final centers = Float64List(groups * 3);
  for (var c = 0; c < groups; c++) {
    final i = order[((c + 0.5) * count / groups).floor().clamp(0, count - 1)];
    centers[c * 3] = px[i * 3];
    centers[c * 3 + 1] = px[i * 3 + 1];
    centers[c * 3 + 2] = px[i * 3 + 2];
  }
  final owner = Int32List(count);
  for (var it = 0; it < iterations; it++) {
    var moved = false;
    for (var i = 0; i < count; i++) {
      var best = 0;
      var bestD = double.infinity;
      for (var c = 0; c < groups; c++) {
        final dr = px[i * 3] - centers[c * 3], dg = px[i * 3 + 1] - centers[c * 3 + 1], db = px[i * 3 + 2] - centers[c * 3 + 2];
        final d = dr * dr + dg * dg + db * db;
        if (d < bestD) {
          bestD = d;
          best = c;
        }
      }
      if (owner[i] != best) {
        owner[i] = best;
        moved = true;
      }
    }
    final sum = Float64List(groups * 3);
    final n = Int32List(groups);
    for (var i = 0; i < count; i++) {
      final c = owner[i];
      sum[c * 3] += px[i * 3];
      sum[c * 3 + 1] += px[i * 3 + 1];
      sum[c * 3 + 2] += px[i * 3 + 2];
      n[c]++;
    }
    for (var c = 0; c < groups; c++) {
      if (n[c] == 0) continue;
      centers[c * 3] = sum[c * 3] / n[c];
      centers[c * 3 + 1] = sum[c * 3 + 1] / n[c];
      centers[c * 3 + 2] = sum[c * 3 + 2] / n[c];
    }
    if (!moved && it > 0) break;
  }
  final out = Uint8List(count * 4);
  for (var i = 0; i < count; i++) {
    final c = owner[i];
    out[i * 4] = centers[c * 3].round().clamp(0, 255);
    out[i * 4 + 1] = centers[c * 3 + 1].round().clamp(0, 255);
    out[i * 4 + 2] = centers[c * 3 + 2].round().clamp(0, 255);
    out[i * 4 + 3] = 255;
  }
  return out;
}

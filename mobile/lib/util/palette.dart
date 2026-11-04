import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'cover_color.dart';

/// Cuántos colores se sacan de un fondo de pantalla.
const paletteSize = 5;

/// Los 5 colores principales de un fondo de pantalla, del que más ocupa al que menos. Se analiza una miniatura (96 px de ancho).
/// Devuelve `null` si la imagen no se puede leer.
Future<List<Color>?> paletteOfFile(String path) async {
  try {
    final image = await loadImage(ResizeImage(FileImage(File(path)), width: 96));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final colors = extractPalette(data.buffer.asUint8List());
    return colors.isEmpty ? null : colors;
  } catch (_) {
    return null;
  }
}

/// Los colores principales de unos píxeles RGBA (los opacos), del que más ocupa al que menos.
///
/// Agrupa los píxeles con k-means (arranque determinista: primero el color más repetido y luego, cada vez, el que más pesa y más lejos
/// queda de los ya elegidos) y de cada grupo da la **media de sus píxeles más centrales** (reales: nunca un color que la imagen no tenga). Si la
/// imagen tiene menos de [count] colores distintos, se repiten los últimos hasta completar. Vacío si no hay píxeles opacos.
List<Color> extractPalette(Uint8List rgba, {int count = paletteSize, int iterations = 12}) {
  // un histograma: cada color distinto con las veces que sale (así, miles de píxeles iguales cuestan una sola cuenta)
  final histogram = <int, int>{};
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final key = (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
    histogram[key] = (histogram[key] ?? 0) + 1;
  }
  if (histogram.isEmpty) return const [];

  // más repetido primero; a igualdad, por valor, para que el resultado no dependa del orden del mapa
  final keys = histogram.keys.toList()
    ..sort((a, b) {
      final byCount = histogram[b]!.compareTo(histogram[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  final n = keys.length;
  final r = Float64List(n), g = Float64List(n), b = Float64List(n), w = Float64List(n);
  for (var i = 0; i < n; i++) {
    r[i] = ((keys[i] >> 16) & 0xFF).toDouble();
    g[i] = ((keys[i] >> 8) & 0xFF).toDouble();
    b[i] = (keys[i] & 0xFF).toDouble();
    w[i] = histogram[keys[i]]!.toDouble();
  }
  double dist(int i, double cr, double cg, double cb) {
    final dr = r[i] - cr, dg = g[i] - cg, db = b[i] - cb;
    return dr * dr + dg * dg + db * db;
  }

  final k = math.min(count, n);
  final cr = <double>[r[0]], cg = <double>[g[0]], cb = <double>[b[0]];
  final nearest = Float64List.fromList([for (var i = 0; i < n; i++) dist(i, cr[0], cg[0], cb[0])]);
  while (cr.length < k) {
    var pick = -1;
    var best = -1.0;
    for (var i = 0; i < n; i++) {
      final score = nearest[i] * w[i];
      if (score > best) {
        best = score;
        pick = i;
      }
    }
    if (pick < 0 || best <= 0) break;
    cr.add(r[pick]);
    cg.add(g[pick]);
    cb.add(b[pick]);
    for (var i = 0; i < n; i++) {
      nearest[i] = math.min(nearest[i], dist(i, r[pick], g[pick], b[pick]));
    }
  }

  final groups = cr.length;
  final owner = List<int>.filled(n, 0);
  for (var round = 0; round < iterations; round++) {
    var moved = false;
    for (var i = 0; i < n; i++) {
      var bestGroup = 0;
      var bestDist = double.infinity;
      for (var c = 0; c < groups; c++) {
        final d = dist(i, cr[c], cg[c], cb[c]);
        if (d < bestDist) {
          bestDist = d;
          bestGroup = c;
        }
      }
      if (owner[i] != bestGroup) {
        owner[i] = bestGroup;
        moved = true;
      }
    }
    final sr = List<double>.filled(groups, 0), sg = List<double>.filled(groups, 0), sb = List<double>.filled(groups, 0), sw = List<double>.filled(groups, 0);
    for (var i = 0; i < n; i++) {
      final c = owner[i];
      sr[c] += r[i] * w[i];
      sg[c] += g[i] * w[i];
      sb[c] += b[i] * w[i];
      sw[c] += w[i];
    }
    for (var c = 0; c < groups; c++) {
      if (sw[c] == 0) continue;
      cr[c] = sr[c] / sw[c];
      cg[c] = sg[c] / sw[c];
      cb[c] = sb[c] / sw[c];
    }
    if (!moved && round > 0) break;
  }

  final weight = List<double>.filled(groups, 0);
  for (var i = 0; i < n; i++) {
    weight[owner[i]] += w[i];
  }

  // el color de cada grupo es la media de su **núcleo**: la mitad de sus píxeles (por peso) más cercana al centro. Así los píxeles de
  // borde, mezclados con el color de al lado, no lo ensucian, y en una foto sale el color más denso del grupo, no uno aguado
  for (var c = 0; c < groups; c++) {
    final members = [for (var i = 0; i < n; i++) if (owner[i] == c) i]..sort((x, y) => dist(x, cr[c], cg[c], cb[c]).compareTo(dist(y, cr[c], cg[c], cb[c])));
    if (members.isEmpty) continue;
    final half = weight[c] / 2;
    var seen = 0.0;
    var sr = 0.0, sg = 0.0, sb = 0.0, sw = 0.0;
    for (final i in members) {
      sr += r[i] * w[i];
      sg += g[i] * w[i];
      sb += b[i] * w[i];
      sw += w[i];
      seen += w[i];
      if (seen >= half) break;
    }
    cr[c] = sr / sw;
    cg[c] = sg / sw;
    cb[c] = sb / sw;
  }
  final order = [for (var c = 0; c < groups; c++) if (weight[c] > 0) c]..sort((x, y) => weight[y].compareTo(weight[x]));
  final colors = [for (final c in order) Color.fromARGB(255, cr[c].round().clamp(0, 255), cg[c].round().clamp(0, 255), cb[c].round().clamp(0, 255))];
  while (colors.length < count) {
    colors.add(colors.last);
  }
  return colors;
}

/// El color con el que se viste la app a partir de la paleta: el que más ocupa **con color**; si todo el fondo es gris, el que más ocupa.
Color paletteSeed(List<Color> palette) {
  for (final color in palette) {
    if (HSLColor.fromColor(color).saturation >= 0.25) return color;
  }
  return palette.first;
}

/// El código de un color como `#RRGGBB`.
String hexOf(Color color) {
  String two(double channel) => (channel * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(color.r)}${two(color.g)}${two(color.b)}'.toUpperCase();
}

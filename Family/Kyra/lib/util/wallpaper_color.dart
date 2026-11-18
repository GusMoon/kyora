import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Cómo se saca el color de acento de un fondo de pantalla (en las pruebas, uno falso: analizar una imagen de verdad lleva tiempo).
typedef AccentLookup = Future<Color?> Function(String path);

/// El color de acento de una imagen del teléfono: el tono con más presencia (pesa más lo vivo y claro), ya con la viveza y el brillo que
/// necesita un acento sobre fondo oscuro. `null` si la imagen no se puede leer o es casi gris (ahí queda el acento de siempre).
Future<Color?> wallpaperAccent(String path) async {
  try {
    final image = await _load(ResizeImage(FileImage(File(path)), width: 64));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    return accentOf(data.buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

/// Cómo se sacan los colores secundarios de un fondo (en las pruebas, uno falso). Recibe la ruta y el acento ya calculado.
typedef ExtrasLookup = Future<List<Color>> Function(String path, Color accent);

/// Los colores **secundarios** de una imagen del teléfono: otros tonos del fondo que no son el predominante (ver [secondaryColorsOf]). Vacío si
/// la imagen no se puede leer.
Future<List<Color>> wallpaperExtras(String path, Color accent) async {
  try {
    final image = await _load(ResizeImage(FileImage(File(path)), width: 64));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return const [];
    return secondaryColorsOf(data.buffer.asUint8List(), accent);
  } catch (_) {
    return const [];
  }
}

/// Hasta [count] colores de unos píxeles RGBA que **no** son el tono principal: se agrupa por tono (24 grupos), se descartan los grupos
/// cercanos al del acento (menos de 45°) y de cada color ya elegido, y se toman los que más pesan (saturación × brillo), llevados a viveza y
/// brillo de neón. Aunque pesen poco (un detalle del fondo) valen mientras tengan algo de color. Si el fondo no da [count] tonos distintos, se
/// completa girando el tono del acento (distintos entre sí y del acento), así siempre salen [count] colores.
List<Color> secondaryColorsOf(Uint8List rgba, Color accent, {int count = 3}) {
  const buckets = 24;
  final weight = List<double>.filled(buckets, 0);
  final sinSum = List<double>.filled(buckets, 0);
  final cosSum = List<double>.filled(buckets, 0);
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final hsv = HSVColor.fromColor(Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]));
    if (hsv.saturation < 0.2 || hsv.value < 0.15) continue;
    final w = hsv.saturation * hsv.value;
    final bucket = (hsv.hue / 360 * buckets).floor() % buckets;
    final radians = hsv.hue * math.pi / 180;
    weight[bucket] += w;
    sinSum[bucket] += w * math.sin(radians);
    cosSum[bucket] += w * math.cos(radians);
  }
  final accentHue = HSVColor.fromColor(accent).hue;
  double gap(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  final hues = <double>[accentHue];
  final out = <Color>[];
  final order = List<int>.generate(buckets, (b) => b)..sort((a, b) => weight[b].compareTo(weight[a]));
  for (final b in order) {
    if (out.length >= count) break;
    if (weight[b] <= 0) break;
    var hue = math.atan2(sinSum[b], cosSum[b]) * 180 / math.pi;
    if (hue < 0) hue += 360;
    if (hues.any((h) => gap(h, hue) < 45)) continue;
    hues.add(hue);
    out.add(HSVColor.fromAHSV(1, hue, 0.72, 0.96).toColor());
  }
  // lo que falte: tonos girados desde el acento, lo más lejos posible de los ya elegidos
  const spread = [150.0, 210.0, 90.0, 270.0, 30.0, 330.0];
  for (final turn in spread) {
    if (out.length >= count) break;
    final hue = (accentHue + turn) % 360;
    if (hues.any((h) => gap(h, hue) < 45)) continue;
    hues.add(hue);
    out.add(HSVColor.fromAHSV(1, hue, 0.72, 0.96).toColor());
  }
  return out;
}

/// El acento de unos píxeles RGBA: agrupa por tono (24 grupos), elige el grupo que más pesa (saturación × brillo de cada píxel) y devuelve
/// su tono medio con saturación y brillo de neón. `null` si apenas hay color (una foto gris, negra o blanca).
Color? accentOf(Uint8List rgba) {
  const buckets = 24;
  final weight = List<double>.filled(buckets, 0);
  final sinSum = List<double>.filled(buckets, 0);
  final cosSum = List<double>.filled(buckets, 0);
  var colorful = 0.0;
  var total = 0.0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    total++;
    final hsv = HSVColor.fromColor(Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]));
    if (hsv.saturation < 0.25 || hsv.value < 0.2) continue; // lo gris y lo casi negro no dan color
    colorful++;
    final w = hsv.saturation * hsv.value;
    final bucket = (hsv.hue / 360 * buckets).floor() % buckets;
    final radians = hsv.hue * math.pi / 180;
    weight[bucket] += w;
    sinSum[bucket] += w * math.sin(radians);
    cosSum[bucket] += w * math.cos(radians);
  }
  if (total == 0 || colorful / total < 0.02) return null;
  var best = 0;
  for (var b = 1; b < buckets; b++) {
    if (weight[b] > weight[best]) best = b;
  }
  if (weight[best] <= 0) return null;
  var hue = math.atan2(sinSum[best], cosSum[best]) * 180 / math.pi;
  if (hue < 0) hue += 360;
  return HSVColor.fromAHSV(1, hue, 0.78, 1).toColor();
}

/// Los tres colores de una portada para teñir su vinilo: el principal (el tono que más pesa, vivo), un segundo tono (otro color de la portada, de
/// otra zona del círculo cromático; si la portada es de un solo color, un tono vecino) y el fondo hondo (lo más oscuro de la portada, casi negro).
@immutable
class CoverPalette {
  const CoverPalette({required this.main, required this.second, required this.deep});

  final Color main;
  final Color second;
  final Color deep;

  @override
  bool operator ==(Object other) => other is CoverPalette && other.main == main && other.second == second && other.deep == deep;

  @override
  int get hashCode => Object.hash(main, second, deep);

  /// Una paleta sacada de un solo color (una portada sin más tonos, o sin portada): el segundo tono es vecino y el fondo, casi negro.
  factory CoverPalette.fromColor(Color color) {
    final hsv = HSVColor.fromColor(color);
    return CoverPalette(
      main: color,
      second: hsv.withHue((hsv.hue + 38) % 360).withSaturation((hsv.saturation * 0.9).clamp(0.0, 1.0)).toColor(),
      deep: Color.lerp(color, Colors.black, 0.86)!,
    );
  }
}

/// La paleta de unos píxeles RGBA (ver [CoverPalette]); `null` si apenas hay color (una portada gris, negra o blanca).
CoverPalette? paletteOf(Uint8List rgba) {
  final main = accentOf(rgba);
  if (main == null) return null;
  const buckets = 24;
  final weight = List<double>.filled(buckets, 0);
  final sinSum = List<double>.filled(buckets, 0);
  final cosSum = List<double>.filled(buckets, 0);
  final lums = <double>[];
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final color = Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]);
    lums.add(color.computeLuminance());
    final hsv = HSVColor.fromColor(color);
    if (hsv.saturation < 0.25 || hsv.value < 0.2) continue;
    final w = hsv.saturation * hsv.value;
    final bucket = (hsv.hue / 360 * buckets).floor() % buckets;
    final radians = hsv.hue * math.pi / 180;
    weight[bucket] += w;
    sinSum[bucket] += w * math.sin(radians);
    cosSum[bucket] += w * math.cos(radians);
  }
  final mainBucket = (HSVColor.fromColor(main).hue / 360 * buckets).floor() % buckets;
  // el segundo tono: el grupo que más pesa entre los que están lejos del principal (al menos 45° de distancia)
  int? other;
  for (var b = 0; b < buckets; b++) {
    final gap = (b - mainBucket).abs();
    if (math.min(gap, buckets - gap) < 3) continue;
    if (weight[b] > 0 && (other == null || weight[b] > weight[other])) other = b;
  }
  Color second;
  if (other != null && weight[other] >= weight[mainBucket] * 0.2) {
    var hue = math.atan2(sinSum[other], cosSum[other]) * 180 / math.pi;
    if (hue < 0) hue += 360;
    second = HSVColor.fromAHSV(1, hue, 0.78, 0.95).toColor();
  } else {
    second = CoverPalette.fromColor(main).second;
  }
  // el fondo hondo: lo más oscuro de la portada (el quinto más oscuro por cien), llevado casi a negro
  lums.sort();
  final dark = lums.isEmpty ? 0.0 : lums[(lums.length * 0.05).floor().clamp(0, lums.length - 1)];
  final deep = Color.lerp(main, Colors.black, (0.8 + 0.18 * (1 - dark.clamp(0.0, 1.0))).clamp(0.0, 0.97))!;
  return CoverPalette(main: main, second: second, deep: deep);
}

Future<ui.Image> _load(ImageProvider provider) {
  final done = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (!done.isCompleted) done.complete(info.image);
    },
    onError: (error, stack) {
      stream.removeListener(listener);
      if (!done.isCompleted) done.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return done.future;
}

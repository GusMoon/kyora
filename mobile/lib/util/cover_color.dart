import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

final Map<String, Future<Color?>> _known = {};

/// La versión grande de una carátula de YouTube (`hqdefault` mide solo 480×360). Cualquier otra dirección queda igual.
String sharperCover(String url) => url.contains('i.ytimg.com') ? url.replaceFirst('/hqdefault.', '/maxresdefault.') : url;

/// El color que más se ve en una carátula, para teñir el reproductor y toda la app: una imagen de internet (`url`) o un archivo del teléfono
/// (`file`, que manda si están los dos). Sin carátula, o si no carga, `null`. Recuerda lo que ya calculó: cada una se analiza una vez.
Future<Color?> coverColor({String? url, String? file}) {
  final key = file != null ? 'file:$file' : url;
  if (key == null) return Future.value();
  return _known.putIfAbsent(key, () async {
    try {
      final ImageProvider source = file != null ? FileImage(File(file)) : NetworkImage(url!);
      // en miniatura: analizarla no frena la pantalla al cambiar de canción
      final image = await loadImage(ResizeImage(source, width: 32));
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      final pixels = data.buffer.asUint8List();
      return dominantColor(pixels) ?? meanColor(pixels); // una carátula gris da su gris: la app se tiñe de ese gris, sin color
    } catch (_) {
      return null;
    }
  });
}

/// Carga una imagen y devuelve ya decodificada.
Future<ui.Image> loadImage(ImageProvider provider) {
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

/// El color con más presencia de unos píxeles RGBA: agrupa por tono y pesa más lo vivo. Lo devuelve con brillo suficiente para usarlo de
/// luz. `null` si la imagen es casi gris (ahí queda mejor el color de la app).
Color? dominantColor(Uint8List rgba) {
  const buckets = 24;
  final weight = List<double>.filled(buckets, 0);
  final hueSum = List<double>.filled(buckets, 0);
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final hsv = HSVColor.fromColor(Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]));
    final w = hsv.saturation * hsv.value;
    if (w < 0.12) continue;
    final b = (hsv.hue / 360 * buckets).floor() % buckets;
    weight[b] += w;
    hueSum[b] += hsv.hue * w;
  }
  var best = 0;
  for (var b = 1; b < buckets; b++) {
    if (weight[b] > weight[best]) best = b;
  }
  final pixels = rgba.length / 4;
  if (pixels == 0 || weight[best] / pixels < 0.02) return null;
  return HSLColor.fromAHSL(1, hueSum[best] / weight[best], 0.75, 0.5).toColor();
}

/// El color medio de unos píxeles RGBA (los opacos). Para las carátulas casi grises, donde `dominantColor` no da ninguno: así también
/// ellas dan su tono (un gris más claro o más oscuro). `null` si no hay píxeles.
Color? meanColor(Uint8List rgba) {
  var r = 0, g = 0, b = 0, n = 0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    r += rgba[i];
    g += rgba[i + 1];
    b += rgba[i + 2];
    n++;
  }
  return n == 0 ? null : Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
}

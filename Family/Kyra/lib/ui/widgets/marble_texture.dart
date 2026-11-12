import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../util/wallpaper_color.dart';

/// La textura **jaspeada** de un vinilo de color: plástico translúcido del color de la portada con nubes de otros tonos de la portada y
/// **manchas de humo oscuro** que se retuercen en vetas, como un vinilo de edición especial. Se pinta una sola vez por portada (con curvas
/// difuminadas, a 512 px) y el disco la gira; cada portada sale distinta (las manchas salen de su nombre) pero siempre igual para ella.
abstract final class MarbleTexture {
  /// El lado de la imagen (px).
  static const side = 512;

  static final Map<String, ui.Image> _cache = {};

  /// La semilla de una portada: siempre la misma para el mismo nombre.
  static int seedOf(String text) {
    var h = 17;
    for (final unit in text.codeUnits) {
      h = (h * 31 + unit) & 0x3fffffff;
    }
    return h;
  }

  /// La textura de esa paleta y semilla (la pinta la primera vez y la guarda). `null` si no se pudo pintar.
  static ui.Image? of(CoverPalette palette, int seed) {
    final key = '${palette.main.toARGB32()}-${palette.second.toARGB32()}-${palette.deep.toARGB32()}-$seed';
    final known = _cache[key];
    if (known != null) return known;
    final made = render(palette, seed);
    if (made == null) return null;
    if (_cache.length >= 12) _cache.remove(_cache.keys.first); // guarda pocas
    return _cache[key] = made;
  }

  /// Pinta la textura: base, nubes, humo y vetas finas.
  static ui.Image? render(CoverPalette p, int seed) {
    try {
      final rnd = math.Random(seed);
      const s = side * 1.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const all = Rect.fromLTWH(0, 0, s, s);
      // la base: el color de la portada, vivo y profundo
      canvas.drawRect(all, Paint()..color = Color.lerp(p.main, p.deep, 0.12)!);

      Offset spot() => Offset(rnd.nextDouble() * s, rnd.nextDouble() * s);

      // nubes grandes y suaves de los otros tonos: unas claras (el plástico translúcido deja pasar la luz) y otras hondas
      final cloudColors = [p.second, Color.lerp(p.main, Colors.white, 0.22)!, p.main, Color.lerp(p.deep, p.main, 0.25)!];
      for (var i = 0; i < 12; i++) {
        final at = spot();
        final radius = s * (0.16 + rnd.nextDouble() * 0.26);
        final tone = cloudColors[i % cloudColors.length];
        canvas.drawCircle(
          at,
          radius,
          Paint()..shader = RadialGradient(colors: [tone.withValues(alpha: 0.5), tone.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: at, radius: radius)),
        );
      }

      // las manchas de humo grandes: vetas muy anchas y difuminadas que serpentean, casi negras (el humo del vinilo jaspeado), con alguna
      // del segundo tono entre ellas
      for (var i = 0; i < 24; i++) {
        final path = _swirl(rnd, s, 3 + rnd.nextInt(4));
        final dark = i % 6 != 0;
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = dark ? 14 + rnd.nextDouble() * 58 : 14 + rnd.nextDouble() * 40
            ..color = (dark ? p.deep : p.second).withValues(alpha: dark ? 0.7 + rnd.nextDouble() * 0.28 : 0.22 + rnd.nextDouble() * 0.2)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + rnd.nextDouble() * 6),
        );
      }

      // el color vuelve a asomar entre el humo: claros anchos del tono principal
      for (var i = 0; i < 9; i++) {
        canvas.drawPath(
          _swirl(rnd, s, 3),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 20 + rnd.nextDouble() * 50
            ..color = (i.isEven ? p.main : Color.lerp(p.main, Colors.white, 0.2)!).withValues(alpha: 0.35)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + rnd.nextDouble() * 8),
        );
      }

      // los hilos de humo: vetas medias, algo más nítidas, que salen de las manchas
      for (var i = 0; i < 24; i++) {
        final path = _swirl(rnd, s, 4 + rnd.nextInt(3));
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 5 + rnd.nextDouble() * 15
            ..color = p.deep.withValues(alpha: 0.4 + rnd.nextDouble() * 0.4)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 + rnd.nextDouble() * 3.5),
        );
      }

      // unas pocas vetas finas, apenas insinuadas
      for (var i = 0; i < 10; i++) {
        final path = _swirl(rnd, s, 5);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 0.7 + rnd.nextDouble() * 1.2
            ..color = p.deep.withValues(alpha: 0.18 + rnd.nextDouble() * 0.25)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1 + rnd.nextDouble()),
        );
      }

      final picture = recorder.endRecording();
      final image = picture.toImageSync(side, side);
      picture.dispose();
      return image;
    } catch (_) {
      return null;
    }
  }

  /// Una veta: un camino curvo que sigue un rumbo que va girando poco a poco, con `steps` tramos suaves.
  static Path _swirl(math.Random rnd, double s, int steps) {
    var at = Offset(rnd.nextDouble() * s, rnd.nextDouble() * s);
    var heading = rnd.nextDouble() * 2 * math.pi;
    final path = Path()..moveTo(at.dx, at.dy);
    for (var i = 0; i < steps; i++) {
      final length = s * (0.1 + rnd.nextDouble() * 0.16);
      final turn = (rnd.nextDouble() - 0.5) * 2.4;
      final mid = at + Offset.fromDirection(heading + turn / 2, length * 0.6);
      heading += turn;
      at = at + Offset.fromDirection(heading, length);
      path.quadraticBezierTo(mid.dx, mid.dy, at.dx, at.dy);
    }
    return path;
  }
}

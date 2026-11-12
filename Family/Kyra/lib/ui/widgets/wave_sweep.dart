import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'section_motion.dart';

/// La **ola** que acompaña al efecto de holograma al abrir (y cerrar) todas las apps: un frente ondulado que **barre la pantalla desde el
/// borde de arriba a la izquierda hasta el de abajo a la derecha**. Lo que la ola ya cruzó cambia de estado (el contenido se deshace, las apps
/// se materializan), con el parpadeo del holograma en la franja de después del frente.
///
/// Todo se mide en una coordenada `u` **de esquina a esquina**: 0 en la de arriba a la izquierda y 1 en la de abajo a la derecha (`x/ancho +
/// y/alto`, a la mitad). El frente es, pues, una línea paralela a la diagonal que une las otras dos esquinas, y llega a las cuatro esquinas
/// a la vez que a su `u`. La ola es un avance `t` de 0 a 1.
abstract final class WaveSweep {
  /// El ancho de la franja de transición (en fracción de la diagonal): lo que tarda un punto en pasar de «sin tocar» a «del todo cambiado».
  static const band = 0.42;

  /// Cuánto ondula el frente (px) y cuántas ondas lleva a lo ancho.
  static const amplitude = 20.0;
  static const waves = 3.0;

  /// La curva con la que corre la ola por la pantalla.
  static const curve = Curves.easeInOut;

  /// La coordenada `u` de un punto en una pantalla de ese tamaño: 0 arriba a la izquierda, 1 abajo a la derecha.
  static double along(Offset p, Size size) =>
      size.isEmpty ? 0 : (p.dx / size.width + p.dy / size.height) / 2;

  /// El final de un degradado que tiene 0 en la esquina de arriba a la izquierda y 1 en la de abajo a la derecha y cuyas líneas de igual valor
  /// son las de `u` (paralelas a la otra diagonal), en una pantalla de ese tamaño.
  static Offset gradientEnd(Size size) {
    final w = size.width, h = size.height;
    final k = 2 * w * h / (w * w + h * h);
    return Offset(h, w) * k;
  }

  /// Dónde está el frente (en `u`) con el avance `t`: empieza antes de la esquina y acaba pasada la otra, para barrer todo.
  static double lead(double t) => t * (1 + band);

  /// Cuánto ha cambiado el punto `u` con el avance `t`: 0 sin tocar, 1 del todo cambiado.
  static double passed(double t, double u) => ((lead(t) - u) / band).clamp(0.0, 1.0);

  /// Esa animación va hacia atrás: el contenido **se esconde** (la ola lo borra) en lugar de mostrarse.
  static bool hiding(Animation<double> shown) => shown.status == AnimationStatus.reverse;

  /// El avance de la ola (0 → 1) de un controlador que vale 1 con todo a la vista y 0 con todo quitado: al esconderse corre al revés, para que
  /// la ola vaya **siempre** de arriba a la izquierda a abajo a la derecha.
  static double timeFor(Animation<double> shown) {
    final v = shown.value.clamp(0.0, 1.0);
    return curve.transform(hiding(shown) ? 1 - v : v);
  }

  /// Lo visible que está el punto `u` ahora mismo (0 → 1) según esa animación y la ola.
  static double visibility(Animation<double> shown, double u) {
    final p = passed(timeFor(shown), u);
    return hiding(shown) ? 1 - p : p;
  }

  /// El degradado que usa de máscara el contenido: opaco donde se ve y transparente donde no, a lo largo de la diagonal del rectángulo.
  static ui.Shader mask(Rect rect, double t, {required bool hiding}) {
    final head = lead(t).clamp(0.0, 1.0);
    final tail = (lead(t) - band).clamp(0.0, 1.0);
    const white = Color(0xFFFFFFFF);
    const clear = Color(0x00FFFFFF);
    return ui.Gradient.linear(
      rect.topLeft,
      rect.topLeft + gradientEnd(rect.size),
      hiding ? const [clear, clear, white, white] : const [white, white, clear, clear],
      [0, tail, head, 1],
    );
  }
}

/// El frente de la ola dibujado: una **línea de luz ondulada** del acento, una estela suave detrás (la franja que se está transformando), una
/// segunda línea más tenue y unas rayitas de interferencia. Con `t` en 0 o en 1 no pinta nada. Es pintura: no recibe toques.
class WavePainter extends CustomPainter {
  const WavePainter({required this.t, required this.accent});

  /// El avance de la ola (0 → 1).
  final double t;
  final Color accent;

  /// Los puntos del frente `u` con una fase, de un extremo a otro de la pantalla (y un poco más).
  static List<Offset> front(Size size, double u, double phase, double envelope) {
    final d = Offset(size.width, size.height);
    final len = d.distance;
    // la línea de igual `u` va paralela a la diagonal de abajo a la izquierda a arriba a la derecha; su normal apunta de esquina a esquina
    final perp = Offset(size.width, -size.height) / len;
    final dir = Offset(size.height, size.width) / len;
    const k = 56;
    return [
      for (var i = 0; i <= k; i++)
        () {
          final s = ui.lerpDouble(-len * 0.6, len * 0.6, i / k)!;
          final wob = WaveSweep.amplitude * envelope * math.sin(s / len * WaveSweep.waves * 2 * math.pi - phase);
          return d * u + perp * s + dir * wob;
        }(),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1 || size.isEmpty) return;
    final len = Offset(size.width, size.height).distance;
    final dir = Offset(size.height, size.width) / len;
    final head = WaveSweep.lead(t);
    final envelope = math.sqrt(math.sin(math.pi * t).clamp(0.0, 1.0));
    final phase = t * 9 * math.pi;
    final line = front(size, head, phase, envelope);

    // la estela: todo lo de detrás del frente, desvanecido hacia atrás
    final trail = Path()..moveTo(line.first.dx, line.first.dy);
    for (final p in line.skip(1)) {
      trail.lineTo(p.dx, p.dy);
    }
    trail
      ..lineTo(line.last.dx - dir.dx * len * 2, line.last.dy - dir.dy * len * 2)
      ..lineTo(line.first.dx - dir.dx * len * 2, line.first.dy - dir.dy * len * 2)
      ..close();
    final tail = (head - WaveSweep.band).clamp(0.0, 1.0);
    final front0 = head.clamp(0.0, 1.0);
    if (front0 > tail) {
      canvas.drawPath(
        trail,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            WaveSweep.gradientEnd(size),
            [accent.withValues(alpha: 0), accent.withValues(alpha: 0.26 * envelope)],
            [tail, front0],
          ),
      );
    }

    // las interferencias: rayas horizontales cortas pegadas al frente, que saltan de sitio
    final tick = (t * 28).floor();
    final bars = Paint()..color = accent.withValues(alpha: 0.55 * envelope);
    final dark = Paint()..color = Colors.black.withValues(alpha: 0.45 * envelope);
    for (var i = 0; i < 7; i++) {
      final at = line[(SectionMotion.noise(i * 3 + 1, tick) * (line.length - 1)).floor()];
      final w = 30 + SectionMotion.noise(i * 5 + 2, tick) * 110;
      final h = 2 + SectionMotion.noise(i * 7 + 3, tick) * 4;
      final back = SectionMotion.noise(i * 11 + 4, tick) * WaveSweep.band * len * 0.7;
      canvas.drawRect(Rect.fromLTWH(at.dx - dir.dx * back - w / 2, at.dy - dir.dy * back, w, h), i.isEven ? bars : dark);
    }

    // la segunda línea, más atrás y más tenue
    final echo = front(size, head - WaveSweep.band * 0.45, phase + 1.4, envelope);
    canvas.drawPath(_polyline(echo), Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = accent.withValues(alpha: 0.35 * envelope));

    // el frente: un resplandor ancho y la línea nítida encima
    final path = _polyline(line);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..color = accent.withValues(alpha: 0.35 * envelope)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round..color = accent.withValues(alpha: 0.95 * envelope));
  }

  static Path _polyline(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant WavePainter old) => old.t != t || old.accent != accent;
}

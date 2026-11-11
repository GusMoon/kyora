import 'dart:math' as math;

import 'package:flutter/material.dart';

/// El centro ciberpunk del disco de Inicio (también el semicírculo de la lista alfabética): un núcleo oscuro con halo, un filo exterior, un aro
/// de tres tramos gruesos, un aro de marcas finas en sentido contrario, un aro de rayas que gira despacio, una mira y un punto con luz.
/// Todo gira a distinta velocidad con [angle]. Con [menu] (opciones abiertas) brilla más y lleva un aro extra.
///
/// Se dibuja con el centro en [center] y el radio [radius]; si [center] queda en el borde de la pantalla solo se ve la mitad (el semicírculo).
void paintCyberCore(Canvas canvas, Offset center, double radius, {required Color accent, required double angle, bool menu = false}) {
  final rc = radius;
  final o = center;
  Offset polar(double r, double a) => o + Offset(math.cos(a), math.sin(a)) * r;

  final glow = menu ? 0.5 : 0.28;
  final line = accent.withValues(alpha: menu ? 1 : 0.85);

  // el halo y el núcleo oscuro
  canvas.drawCircle(
    o,
    rc * 1.22,
    Paint()..shader = RadialGradient(colors: [accent.withValues(alpha: glow), accent.withValues(alpha: 0)], stops: const [0.7, 1]).createShader(Rect.fromCircle(center: o, radius: rc * 1.22)),
  );
  canvas.drawCircle(o, rc, Paint()..color = const Color(0xFF04060A).withValues(alpha: 0.82));

  // el filo exterior y un segundo aro fino por dentro
  canvas.drawCircle(o, rc, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = line);
  canvas.drawCircle(o, rc * 0.93, Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6..color = accent.withValues(alpha: 0.4));

  // el aro de tres tramos gruesos, que gira
  final seg = Paint()..style = PaintingStyle.stroke..strokeWidth = rc * 0.07..strokeCap = StrokeCap.butt..color = line;
  for (var k = 0; k < 3; k++) {
    canvas.drawArc(Rect.fromCircle(center: o, radius: rc * 0.82), angle * 0.8 + k * 2 * math.pi / 3, 0.95, false, seg);
  }

  // el aro de marcas finas, en sentido contrario
  final fine = Paint()..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.5);
  for (var i = 0; i < 36; i++) {
    final a = -angle * 1.4 + i * 2 * math.pi / 36;
    canvas.drawLine(polar(rc * (i % 3 == 0 ? 0.62 : 0.66), a), polar(rc * 0.7, a), fine);
  }

  // un aro de rayas más adentro, que gira despacio (en lugar del hexágono de antes)
  final dash = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = accent.withValues(alpha: 0.7);
  for (var i = 0; i < 12; i++) {
    canvas.drawArc(Rect.fromCircle(center: o, radius: rc * 0.5), angle * 0.5 + i * math.pi / 6, math.pi / 12, false, dash);
  }

  // la mira: cuatro rayitas en los puntos cardinales (no giran)
  final cross = Paint()..strokeWidth = 1.2..color = Colors.white.withValues(alpha: 0.75);
  for (var i = 0; i < 4; i++) {
    final a = i * math.pi / 2;
    canvas.drawLine(polar(rc * 0.16, a), polar(rc * 0.3, a), cross);
  }

  // el punto central con su luz; con las opciones abiertas, un aro más
  canvas.drawCircle(o, rc * 0.14, Paint()..color = accent.withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
  canvas.drawCircle(o, rc * 0.07, Paint()..color = menu ? Colors.white : accent);
  if (menu) canvas.drawCircle(o, rc * 0.2, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = Colors.white.withValues(alpha: 0.8));
}

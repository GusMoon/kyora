import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'glass_card.dart';

/// La forma de la tarjeta de Inicio: un rectángulo de esquinas redondeadas al que le falta una **muesca** en la esquina de arriba a la
/// derecha, con las esquinas de la muesca también redondeadas (las de dentro, cóncavas). En la muesca va otra tarjeta, un poco separada.
class NotchShape {
  const NotchShape._();

  /// El redondeo de las esquinas de la tarjeta y de la muesca.
  static const radius = 32.0;

  /// La separación entre la muesca y la tarjeta que va dentro.
  static const gap = 8.0;

  /// El alto de la muesca y su ancho (la parte del ancho de la tarjeta que ocupa).
  static const notchHeight = 172.0;
  static const notchFraction = 0.47;

  /// Dónde empieza la muesca por la izquierda para una tarjeta de ese ancho.
  static double notchLeft(double width) => width - width * notchFraction;

  /// El contorno de la tarjeta (con la muesca recortada).
  static Path pathFor(Size size) {
    final w = size.width, h = size.height, r = radius;
    final a = notchLeft(w), b = notchHeight;
    return Path()
      ..moveTo(r, 0)
      ..lineTo(a - r, 0)
      ..arcToPoint(Offset(a, r), radius: Radius.circular(r)) // esquina de arriba, a la izquierda de la muesca
      ..lineTo(a, b - r)
      ..arcToPoint(Offset(a + r, b), radius: Radius.circular(r), clockwise: false) // esquina cóncava de dentro
      ..lineTo(w - r, b)
      ..arcToPoint(Offset(w, b + r), radius: Radius.circular(r)) // el borde de la derecha, debajo de la muesca
      ..lineTo(w, h - r)
      ..arcToPoint(Offset(w - r, h), radius: Radius.circular(r))
      ..lineTo(r, h)
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();
  }

  /// Dónde va la tarjeta de la muesca: pegada arriba y a la derecha, con el hueco ([gap]) a su izquierda y debajo.
  static Rect tileRect(Size size) => Rect.fromLTRB(notchLeft(size.width) + gap, 0, size.width, notchHeight - gap);

  /// Las esquinas de esa tarjeta: las de dentro siguen el redondeo de la muesca y la de arriba a la derecha, el de la tarjeta grande.
  static const tileCorners = BorderRadius.only(
    topLeft: Radius.circular(radius - gap),
    topRight: Radius.circular(radius),
    bottomLeft: Radius.circular(radius - gap),
    bottomRight: Radius.circular(radius - gap),
  );
}

/// La tarjeta grande de Inicio: cristal sin color con la forma de [NotchShape]. [tile] va en la muesca y [content] ocupa la tarjeta entera
/// (se coloca con `Positioned`, sabiendo el tamaño con [NotchShape]).
class NotchedCard extends StatelessWidget {
  const NotchedCard({super.key, required this.tile, required this.content, this.height = 376});

  final Widget tile;
  final Widget Function(BuildContext context, Size size) content;
  final double height;

  @override
  Widget build(BuildContext context) {
    // el alto fijo por fuera: un `LayoutBuilder` no sabe decir su alto intrínseco (lo piden los `Spacer` de Inicio)
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, height);
          return Stack(
            children: [
              Positioned.fill(
                child: ClipPath(
                  clipper: _NotchClipper(),
                  child: BackdropFilter.grouped(
                    filter: ui.ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
                    child: CustomPaint(key: const Key('notched-card'), foregroundPainter: _NotchBorder(), child: const SizedBox.expand()),
                  ),
                ),
              ),
              Positioned.fill(child: content(context, size)),
              Positioned.fromRect(rect: NotchShape.tileRect(size), child: tile),
            ],
          );
        },
      ),
    );
  }
}

class _NotchClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => NotchShape.pathFor(size);

  @override
  bool shouldReclip(_NotchClipper oldClipper) => false;
}

class _NotchBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(NotchShape.pathFor(size), Paint()..color = glassEdge..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_NotchBorder oldDelegate) => false;
}

import 'dart:typed_data';

import 'package:flutter/material.dart';

/// El icono de una app (PNG del teléfono) **con sus colores de siempre** y las **líneas de barrido** de la pantalla por encima: una raya
/// horizontal fina cada pocos píxeles que borra un poco del icono (se ve el fondo a través), igual que la trama del resto de la app.
///
/// Las líneas van dentro de una capa propia (`ColorFiltered` con un filtro que no cambia nada) para que solo borren icono y nunca lo que hay
/// detrás de él. Se respeta la transparencia del PNG.
class ScanlineAppIcon extends StatelessWidget {
  const ScanlineAppIcon({super.key, required this.bytes, required this.size, this.lines = true, this.errorBuilder});

  final Uint8List bytes;
  final double size;

  /// Si lleva las líneas de barrido por encima.
  final bool lines;

  /// Qué se ve si el PNG no se puede leer.
  final ImageErrorWidgetBuilder? errorBuilder;

  /// Cada cuántos píxeles va una línea, y su grosor y cuánto borra del icono (0 a 1). Más finas que las del fondo: el icono es pequeño.
  static const pitch = 3.0;
  static const lineWidth = 1.2;
  static const lineAlpha = 0.55;

  /// Un filtro que deja el icono tal cual (el destino sin cambios): solo sirve para abrir la capa donde borran las líneas.
  static const sameColors = ColorFilter.mode(Color(0x00000000), BlendMode.dst);

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: sameColors,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, width: size, height: size, gaplessPlayback: true, errorBuilder: errorBuilder),
            if (lines) const CustomPaint(key: Key('icon-lines'), painter: IconLinesPainter()),
          ],
        ),
      ),
    );
  }
}

/// Las líneas de barrido de un icono: una raya horizontal cada [ScanlineAppIcon.pitch] píxeles que **borra** un poco del icono.
class IconLinesPainter extends CustomPainter {
  const IconLinesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final erase = Paint()
      ..blendMode = BlendMode.dstOut
      ..color = Colors.black.withValues(alpha: ScanlineAppIcon.lineAlpha);
    for (var y = 0.0; y < size.height; y += ScanlineAppIcon.pitch) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, ScanlineAppIcon.lineWidth), erase);
    }
  }

  @override
  bool shouldRepaint(covariant IconLinesPainter old) => false;
}

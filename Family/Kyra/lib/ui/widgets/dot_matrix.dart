import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Los glifos de 5×7 puntos: cada uno, siete filas de cinco columnas (`1` = punto encendido).
const Map<String, List<String>> dotGlyphs = {
  '0': ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
  '1': ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
  '2': ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
  '3': ['11110', '00001', '00001', '01110', '00001', '00001', '11110'],
  '4': ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
  '5': ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
  '6': ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
  '7': ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
  '8': ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
  '9': ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
  ':': ['00000', '00100', '00100', '00000', '00100', '00100', '00000'],
  '·': ['00000', '00000', '00000', '00100', '00000', '00000', '00000'],
  '.': ['00000', '00000', '00000', '00000', '00000', '00100', '00100'],
  '/': ['00001', '00010', '00010', '00100', '01000', '01000', '10000'],
  '-': ['00000', '00000', '00000', '11111', '00000', '00000', '00000'],
  ' ': ['00000', '00000', '00000', '00000', '00000', '00000', '00000'],
  'A': ['01110', '10001', '10001', '11111', '10001', '10001', '10001'],
  'B': ['11110', '10001', '10001', '11110', '10001', '10001', '11110'],
  'C': ['01110', '10001', '10000', '10000', '10000', '10001', '01110'],
  'D': ['11110', '10001', '10001', '10001', '10001', '10001', '11110'],
  'E': ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
  'F': ['11111', '10000', '10000', '11110', '10000', '10000', '10000'],
  'G': ['01110', '10001', '10000', '10111', '10001', '10001', '01111'],
  'H': ['10001', '10001', '10001', '11111', '10001', '10001', '10001'],
  'I': ['01110', '00100', '00100', '00100', '00100', '00100', '01110'],
  'J': ['00111', '00010', '00010', '00010', '00010', '10010', '01100'],
  'K': ['10001', '10010', '10100', '11000', '10100', '10010', '10001'],
  'L': ['10000', '10000', '10000', '10000', '10000', '10000', '11111'],
  'M': ['10001', '11011', '10101', '10101', '10001', '10001', '10001'],
  'N': ['10001', '10001', '11001', '10101', '10011', '10001', '10001'],
  'Ñ': ['01110', '00000', '10001', '11001', '10101', '10011', '10001'],
  'O': ['01110', '10001', '10001', '10001', '10001', '10001', '01110'],
  'P': ['11110', '10001', '10001', '11110', '10000', '10000', '10000'],
  'Q': ['01110', '10001', '10001', '10001', '10101', '10010', '01101'],
  'R': ['11110', '10001', '10001', '11110', '10100', '10010', '10001'],
  'S': ['01111', '10000', '10000', '01110', '00001', '00001', '11110'],
  'T': ['11111', '00100', '00100', '00100', '00100', '00100', '00100'],
  'U': ['10001', '10001', '10001', '10001', '10001', '10001', '01110'],
  'V': ['10001', '10001', '10001', '10001', '10001', '01010', '00100'],
  'W': ['10001', '10001', '10001', '10101', '10101', '10101', '01010'],
  'X': ['10001', '10001', '01010', '00100', '01010', '10001', '10001'],
  'Y': ['10001', '10001', '01010', '00100', '00100', '00100', '00100'],
  'Z': ['11111', '00001', '00010', '00100', '01000', '10000', '11111'],
};

/// Un texto en **matriz de puntos** (como un LCD de puntos): cada carácter es una rejilla de 5×7 puntos redondos, los encendidos en [color] con
/// un poco de brillo y los apagados muy tenues. Los caracteres que no están en [dotGlyphs] salen como un espacio.
class DotMatrixText extends StatelessWidget {
  const DotMatrixText(this.text, {super.key, required this.height, this.color, this.glow = true, this.dimOff = true, this.square = false});

  final String text;

  /// La altura del texto (siete filas de puntos).
  final double height;
  final Color? color;

  /// Un halo alrededor de los puntos encendidos.
  final bool glow;

  /// Pintar también los puntos apagados, muy tenues.
  final bool dimOff;

  /// Puntos **cuadrados** en lugar de redondos (y sin halo): para quien no quiere círculos.
  final bool square;

  /// Lo que ocupa un texto de [length] caracteres con esa altura.
  static Size sizeFor(int length, double height) {
    final pitch = height / 7;
    return Size(length == 0 ? 0 : (length * 6 - 1) * pitch, height);
  }

  @override
  Widget build(BuildContext context) {
    final upper = text.toUpperCase();
    return Semantics(
      label: text,
      child: CustomPaint(
        size: sizeFor(upper.runes.length, height),
        painter: _DotPainter(upper, color ?? Colors.white, glow: glow, dimOff: dimOff, square: square),
      ),
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter(this.text, this.color, {required this.glow, required this.dimOff, required this.square});

  final String text;
  final Color color;
  final bool glow;
  final bool dimOff;
  final bool square;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = size.height / 7;
    final r = math.max(0.6, pitch * 0.38);
    final on = Paint()..color = color;
    final off = Paint()..color = color.withValues(alpha: 0.08);
    final halo = Paint()..color = color.withValues(alpha: 0.35)..maskFilter = MaskFilter.blur(BlurStyle.normal, pitch * 0.6);
    var x0 = 0.0;
    for (final rune in text.runes) {
      final rows = dotGlyphs[String.fromCharCode(rune)] ?? dotGlyphs[' ']!;
      for (var row = 0; row < 7; row++) {
        for (var col = 0; col < 5; col++) {
          final center = Offset(x0 + col * pitch + pitch / 2, row * pitch + pitch / 2);
          if (square) {
            // cuadrados casi pegados (queda un hilo de espacio entre ellos)
            final cell = Rect.fromCenter(center: center, width: pitch * 0.86, height: pitch * 0.86);
            if (rows[row][col] == '1') {
              canvas.drawRect(cell, on);
            } else if (dimOff) {
              canvas.drawRect(cell, off);
            }
          } else if (rows[row][col] == '1') {
            if (glow) canvas.drawCircle(center, r * 1.4, halo);
            canvas.drawCircle(center, r, on);
          } else if (dimOff) {
            canvas.drawCircle(center, r, off);
          }
        }
      }
      x0 += pitch * 6;
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) => old.text != text || old.color != color || old.glow != glow || old.dimOff != dimOff || old.square != square;
}

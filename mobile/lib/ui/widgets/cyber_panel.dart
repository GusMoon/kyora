import 'package:flutter/material.dart';

import '../../theme.dart';

/// El panel ciberpunk de una ficha: un cristal oscuro con **degradado** (más negro arriba, más ligero abajo; sin desenfoque ni líneas de
/// barrido, que ya trae el fondo), de **esquinas rectas**, con un filo del acento y marcas en dos esquinas. Con [active] (la ficha
/// expandida) el filo se enciende y brilla.
class CyberPanel extends StatelessWidget {
  const CyberPanel({super.key, required this.child, this.active = 0});

  final Widget child;

  /// De 0 (cerrada) a 1 (expandida).
  final double active;

  @override
  Widget build(BuildContext context) {
    final accent = context.colors.accent;
    return CustomPaint(
      painter: _PanelPainter(accent: accent, active: active),
      foregroundPainter: _BracketsPainter(accent: accent, active: active),
      child: child,
    );
  }
}

Path _panelShape(Size s) => Path()..addRect(Offset.zero & s);

class _PanelPainter extends CustomPainter {
  const _PanelPainter({required this.accent, required this.active});

  final Color accent;
  final double active;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _panelShape(size);
    final bounds = Offset.zero & size;
    if (active > 0) {
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = accent.withValues(alpha: 0.28 * active)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
    // el cristal: un degradado de negro, más cerrado arriba, con un poco del acento
    canvas.drawPath(
      path,
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.alphaBlend(accent.withValues(alpha: 0.10), Colors.black.withValues(alpha: 0.9)), Colors.black.withValues(alpha: 0.66)],
      ).createShader(bounds),
    );
    // el filo
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = active > 0 ? 1.6 : 1..color = accent.withValues(alpha: 0.28 + 0.6 * active));
  }

  @override
  bool shouldRepaint(covariant _PanelPainter old) => old.accent != accent || old.active != active;
}

class _BracketsPainter extends CustomPainter {
  const _BracketsPainter({required this.accent, required this.active});

  final Color accent;
  final double active;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.square..color = accent.withValues(alpha: 0.65 + 0.35 * active);
    const l = 12.0;
    const m = 5.0;
    // en dos esquinas opuestas
    canvas.drawPath(Path()..moveTo(m, m + l)..lineTo(m, m)..lineTo(m + l, m), p);
    canvas.drawPath(Path()..moveTo(size.width - m, size.height - m - l)..lineTo(size.width - m, size.height - m)..lineTo(size.width - m - l, size.height - m), p);
  }

  @override
  bool shouldRepaint(covariant _BracketsPainter old) => old.accent != accent || old.active != active;
}

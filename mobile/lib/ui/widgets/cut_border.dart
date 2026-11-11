
import 'package:flutter/material.dart';

/// La forma de los componentes de Kyra: un **rectángulo de esquinas rectas** (sin redondeos ni cortes). Se llama «CutBorder» por historia:
/// `cut` y `all` se conservan para no tocar a quien la usa, pero ya no cortan nada. Sirve de `shape` de botones, tarjetas, campos y hojas, y
/// también de `ShapeDecoration`.
class CutBorder extends OutlinedBorder {
  const CutBorder({this.cut = 0, this.all = false, super.side});

  /// Sin efecto: las esquinas son rectas.
  final double cut;

  /// Sin efecto: las esquinas son rectas.
  final bool all;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRect(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(getOuterPath(rect.deflate(side.width / 2), textDirection: textDirection), side.toPaint());
  }

  @override
  CutBorder copyWith({BorderSide? side, double? cut, bool? all}) => CutBorder(cut: cut ?? this.cut, all: all ?? this.all, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => CutBorder(cut: cut * t, all: all, side: side.scale(t));

  @override
  bool operator ==(Object other) => other is CutBorder && other.cut == cut && other.all == all && other.side == side;

  @override
  int get hashCode => Object.hash(cut, all, side);
}

/// Un recuadro de esquinas rectas con contorno y relleno opcionales: lo que antes era un `BoxDecoration` con esquinas redondas.
ShapeDecoration cutDecoration({Color? color, Color? edge, double width = 1, double cut = 10, bool all = false}) =>
    ShapeDecoration(color: color, shape: CutBorder(cut: cut, all: all, side: edge == null ? BorderSide.none : BorderSide(color: edge, width: width)));

/// El marco de una portada: esquinas rectas, el filo del acento y una marca en dos esquinas. Sin líneas de barrido (las pone el fondo de la
/// app): la imagen se ve entera, con sus colores, sin pixelar.
class CoverFrame extends StatelessWidget {
  const CoverFrame({super.key, required this.child, this.cut = 14, this.focused = false});

  final Widget child;
  final double cut;

  /// La portada enfocada: el filo del acento más vivo.
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final shape = CutBorder(cut: cut);
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: CustomPaint(foregroundPainter: _FramePainter(accent: accent, cut: cut, focused: focused), child: child),
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter({required this.accent, required this.cut, required this.focused});

  final Color accent;
  final double cut;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    // el filo
    final path = CutBorder(cut: cut).getOuterPath((Offset.zero & size).deflate(0.8));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = focused ? 1.8 : 1.2..color = accent.withValues(alpha: focused ? 0.95 : 0.55));
    // las marcas de las dos esquinas rectas
    final l = (size.shortestSide * 0.12).clamp(6.0, 16.0);
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.square..color = accent;
    canvas.drawPath(Path()..moveTo(1, l)..lineTo(1, 1)..lineTo(l, 1), p);
    canvas.drawPath(Path()..moveTo(size.width - 1, size.height - l)..lineTo(size.width - 1, size.height - 1)..lineTo(size.width - l, size.height - 1), p);
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.accent != accent || old.cut != cut || old.focused != focused;
}

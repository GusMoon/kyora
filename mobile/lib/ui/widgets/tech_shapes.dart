import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'cut_border.dart';

/// Un rectángulo redondeado al que le falta una **esquina cortada en curva** (como en las tarjetas de referencia): la esquina que se elige
/// se hunde en un cuarto de círculo del tamaño de `notch`, y ahí suele ir un botón pequeño redondo.
class NotchedBorder extends ShapeBorder {
  const NotchedBorder({this.radius = 26, this.notch = 44, this.corner = NotchCorner.topRight, this.side = BorderSide.none});

  final double radius;
  final double notch;
  final NotchCorner corner;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = math.min(radius, math.min(rect.width, rect.height) / 2);
    final n = math.min(notch, math.min(rect.width, rect.height) - r);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));
    final base = Path()..addRRect(rrect);
    if (n <= 0) return base;
    // el círculo que se resta: de diámetro `n`, algo metido hacia dentro desde la esquina elegida
    final k = n * 0.2;
    final center = switch (corner) {
      NotchCorner.topRight => rect.topRight + Offset(-k, k),
      NotchCorner.topLeft => rect.topLeft + Offset(k, k),
      NotchCorner.bottomRight => rect.bottomRight + Offset(-k, -k),
      NotchCorner.bottomLeft => rect.bottomLeft + Offset(k, -k),
    };
    final hole = Path()..addOval(Rect.fromCircle(center: center, radius: n * 0.5));
    return Path.combine(PathOperation.difference, base, hole);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(getOuterPath(rect, textDirection: textDirection), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => NotchedBorder(radius: radius * t, notch: notch * t, corner: corner, side: side.scale(t));
}

enum NotchCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Una tarjeta del tablero: fondo gris oscuro, filo fino, esquinas redondeadas y, si se quiere, la esquina cortada con un botón redondo
/// (flecha) en el hueco. Con `accent` va rellena con el color de la paleta (y el texto de dentro debe ir en `onAccent`).
class TechCard extends StatelessWidget {
  const TechCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.accent = false,
    this.color,
    this.radius = 26,
    this.notch,
    this.corner = NotchCorner.topRight,
    this.onTap,
    this.onNotchTap,
    this.notchIcon = Icons.arrow_outward_rounded,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool accent;
  final Color? color;
  final double radius;

  /// El tamaño de la esquina cortada (sin esto, la tarjeta no la lleva).
  final double? notch;
  final NotchCorner corner;
  final VoidCallback? onTap;
  final VoidCallback? onNotchTap;
  final IconData notchIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = color ?? (accent ? c.accent : c.surface);
    final shape = notch == null
        ? CutBorder(cut: math.min(radius * 0.5, 16), side: accent ? BorderSide.none : BorderSide(color: c.edge))
        : NotchedBorder(radius: radius, notch: notch!, corner: corner);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) content = GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: content);
    Widget card = Material(color: fill, shape: shape, clipBehavior: Clip.antiAlias, child: content);
    if (notch != null) {
      final n = notch!;
      final k = n * 0.2 - (n * 0.62 + 12) / 2;
      final top = corner == NotchCorner.topLeft || corner == NotchCorner.topRight;
      final left = corner == NotchCorner.topLeft || corner == NotchCorner.bottomLeft;
      final dot = Positioned(
        top: top ? k : null,
        bottom: top ? null : k,
        left: left ? k : null,
        right: left ? null : k,
        child: NotchButton(size: n * 0.62, icon: notchIcon, onTap: onNotchTap ?? onTap, inverse: accent),
      );
      card = Stack(clipBehavior: Clip.none, children: [card, dot]);
    }
    return DecoratedBox(key: const Key('tech-card'), decoration: const BoxDecoration(), child: card);
  }
}

/// El botón redondo del hueco de una tarjeta.
class NotchButton extends StatelessWidget {
  const NotchButton({super.key, this.size = 30, required this.icon, this.onTap, this.inverse = false});

  final double size;
  final IconData icon;
  final VoidCallback? onTap;
  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.square(
        dimension: size + 12,
        child: Center(
          child: Container(
            width: size,
            height: size,
            color: c.ink,
            child: Icon(icon, size: size * 0.6, color: c.background),
          ),
        ),
      ),
    );
  }
}

/// Una píldora pequeña con un texto técnico (mayúsculas, mono): una etiqueta de la tarjeta.
class HudChip extends StatelessWidget {
  const HudChip(this.text, {super.key, this.filled = false, this.color, this.icon});

  final String text;

  /// Rellena con el acento (si no, solo el filo).
  final bool filled;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = filled ? c.onAccent : (color ?? c.ink);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: filled ? c.accent : null,
        shape: CutBorder(cut: 7, side: filled ? BorderSide.none : BorderSide(color: color ?? c.edge)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 16, color: fg), const SizedBox(width: 6)],
            Flexible(child: Text(text.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: hudLabel(size: 15, color: fg))),
          ],
        ),
      ),
    );
  }
}

/// Un par de pequeñas marcas en cruz en las esquinas (los detalles técnicos de los pósters de referencia).
class CornerMarks extends StatelessWidget {
  const CornerMarks({super.key, this.color, this.inset = 10, this.arm = 8});

  final Color? color;
  final double inset;
  final double arm;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _MarksPainter(color ?? context.colors.dim.withValues(alpha: 0.6), inset, arm), size: Size.infinite));
}

class _MarksPainter extends CustomPainter {
  _MarksPainter(this.color, this.inset, this.arm);

  final Color color;
  final double inset;
  final double arm;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    void cross(Offset o) {
      canvas.drawLine(o.translate(-arm / 2, 0), o.translate(arm / 2, 0), p);
      canvas.drawLine(o.translate(0, -arm / 2), o.translate(0, arm / 2), p);
    }

    cross(Offset(inset, inset));
    cross(Offset(size.width - inset, inset));
    cross(Offset(inset, size.height - inset));
    cross(Offset(size.width - inset, size.height - inset));
  }

  @override
  bool shouldRepaint(_MarksPainter old) => old.color != color;
}

/// Un código de barras decorativo (barras finas y gruesas, determinista según `seed`).
class Barcode extends StatelessWidget {
  const Barcode({super.key, this.seed = 7, this.color, this.height = 22, this.width = 80});

  final int seed;
  final Color? color;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: width, height: height, child: CustomPaint(painter: _BarcodePainter(color ?? context.colors.ink, seed)));
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.color, this.seed);

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final p = Paint()..color = color;
    var x = 0.0;
    while (x < size.width) {
      final w = 1.0 + rnd.nextInt(3);
      if (x + w > size.width) break;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), p);
      x += w + 1.0 + rnd.nextInt(3);
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.color != color || old.seed != seed;
}

/// Barras de nivel (como un ecualizador fijo): `values` de 0 a 1.
class HudBars extends StatelessWidget {
  const HudBars({super.key, required this.values, this.color, this.height = 40, this.barWidth = 5, this.gap = 4});

  final List<double> values;
  final Color? color;
  final double height;
  final double barWidth;
  final double gap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: values.length * (barWidth + gap) - gap,
        child: CustomPaint(painter: _BarsPainter(values, color ?? context.colors.accent, barWidth, gap)),
      );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.values, this.color, this.barWidth, this.gap);

  final List<double> values;
  final Color color;
  final double barWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final h = math.max(3.0, size.height * values[i].clamp(0.0, 1.0));
      canvas.drawRect(Rect.fromLTWH(i * (barWidth + gap), size.height - h, barWidth, h), p);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.color != color || !_same(old.values, values);

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Una banda de rayas en diagonal (aviso) de color `color`.
class HazardStripe extends StatelessWidget {
  const HazardStripe({super.key, this.color, this.height = 8});

  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, child: CustomPaint(painter: _StripePainter(color ?? context.colors.accent), size: Size.infinite));
}

class _StripePainter extends CustomPainter {
  _StripePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final p = Paint()
      ..color = color
      ..strokeWidth = size.height * 0.45
      ..isAntiAlias = true;
    for (var x = -size.height; x < size.width + size.height; x += size.height * 1.1) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_StripePainter old) => old.color != color;
}

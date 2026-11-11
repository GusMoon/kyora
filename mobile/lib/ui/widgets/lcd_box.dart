import 'package:flutter/material.dart';

import '../../theme.dart';
import 'cut_border.dart';

/// Un recuadro: filo fino, esquinas cortadas y, si es `inverse`, relleno con el acento.
class LcdBox extends StatelessWidget {
  const LcdBox({super.key, required this.child, this.padding = EdgeInsets.zero, this.width = 1, this.inverse = false, this.radius = 18});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double width;
  final bool inverse;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      key: const Key('lcd-box'),
      decoration: cutDecoration(color: inverse ? c.accent : null, edge: inverse ? null : c.edge, width: width, cut: radius * 0.5),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Un texto corto que tiene que llamar la atención (lo vencido, un error, lo elegido): una píldora de acento. Sin `inverse`, va normal.
class LcdTag extends StatelessWidget {
  const LcdTag(this.text, {super.key, this.inverse = true, this.size = 15, this.bold = false, this.maxLines = 1});

  final String text;
  final bool inverse;
  final double size;
  final bool bold;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(fontFamily: appFont, fontSize: size, color: inverse ? c.onAccent : c.ink, fontWeight: bold ? FontWeight.w600 : FontWeight.w500);
    final label = Text(text, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
    if (!inverse) return label;
    return DecoratedBox(
      key: const Key('lcd-tag-inverse'),
      decoration: ShapeDecoration(color: c.accent, shape: const CutBorder(cut: 6)),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2), child: label),
    );
  }
}

/// Un velo: negro translúcido (antes era una trama punteada). Es pintura y no recibe toques.
class LcdDither extends StatelessWidget {
  const LcdDither({super.key, this.pitch = 2, this.density = 0.5});

  final double pitch;

  /// Cuánto oscurece: 0,5 = bastante, 0,25 = poco.
  final double density;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: ColoredBox(key: const Key('lcd-dither'), color: context.colors.background.withValues(alpha: density * 1.4), child: const SizedBox.expand()));
}

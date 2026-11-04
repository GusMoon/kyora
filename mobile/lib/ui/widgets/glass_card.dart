import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Lo que difumina el cristal lo que tiene detrás (sigma del desenfoque).
const glassBlur = 18.0;

/// El borde fino del cristal: un blanco muy suave.
const glassEdge = Color(0x24FFFFFF);

/// Una tarjeta de Kyra: **esquinas redondeadas**, **sin color de relleno** (solo difumina lo de detrás) y un borde fino de luz.
/// Es el único sitio donde se ajusta el desenfoque y el borde de todas las tarjetas.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 28, this.corners, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// El redondeo de las esquinas (un círculo: la mitad del lado).
  final double radius;

  /// Esquinas distintas una de otra (si se da, manda sobre [radius]).
  final BorderRadius? corners;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = corners ?? BorderRadius.circular(radius);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = Material(type: MaterialType.transparency, child: InkWell(borderRadius: shape, onTap: onTap, child: content));
    }
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
        // el borde va por encima del contenido; sin relleno: nada de color
        child: DecoratedBox(
          key: const Key('glass-card'),
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(borderRadius: shape, border: Border.all(color: glassEdge)),
          child: content,
        ),
      ),
    );
  }
}

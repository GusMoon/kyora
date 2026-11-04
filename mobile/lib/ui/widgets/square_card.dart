import 'package:flutter/material.dart';

import '../../theme.dart';

/// Una tarjeta de Kyra: **esquinas rectas**, un borde fino y el color de las placas algo transparente, para que deje ver el fondo.
/// Sin desenfoques en vivo (el fondo ya va suavizado): así no cuesta nada al desplazar.
class SquareCard extends StatelessWidget {
  const SquareCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Cuánto se ve el color de la placa (el resto deja ver el fondo).
  static const opacity = 0.6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = DecoratedBox(
      decoration: BoxDecoration(color: c.plate.withValues(alpha: opacity), border: Border.all(color: c.edge)),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(borderRadius: BorderRadius.zero, onTap: onTap, child: card),
    );
  }
}

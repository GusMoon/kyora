import 'package:flutter/material.dart';

import 'tech_shapes.dart';

/// Una tarjeta de Kyra: la tarjeta del tablero (fondo gris oscuro, filo fino, esquinas redondeadas). Se conserva el nombre.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 24, this.corners, this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final BorderRadius? corners;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TechCard(key: const Key('glass-card'), padding: padding, radius: radius, onTap: onTap, child: child);
}

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Un icono sobre un círculo de vidrio esmerilado: difumina lo que tiene detrás, con un velo claro y un borde fino.
class GlassCircle extends StatelessWidget {
  const GlassCircle({super.key, required this.child, this.size = 42});

  /// El botón: normalmente un `IconButton`.
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: DecoratedBox(
            key: const Key('glass-circle'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

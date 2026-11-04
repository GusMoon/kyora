import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../util/palette.dart';

/// Los 5 colores del fondo de pantalla en fila: cuadraditos de esquina suave. Con [showHex], el código de cada uno debajo.
class PaletteStrip extends StatelessWidget {
  const PaletteStrip({super.key, required this.colors, this.height = 28, this.showHex = false});

  final List<Color> colors;
  final double height;
  final bool showHex;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      key: const Key('palette-strip'),
      children: [
        for (var i = 0; i < colors.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  key: Key('palette-$i'),
                  height: height,
                  decoration: BoxDecoration(color: colors[i], borderRadius: BorderRadius.circular(10), border: Border.all(color: c.edge)),
                ),
                if (showHex)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(hexOf(colors[i]), textAlign: TextAlign.center, style: TextStyle(color: c.dim, fontSize: 12, letterSpacing: 0.2)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

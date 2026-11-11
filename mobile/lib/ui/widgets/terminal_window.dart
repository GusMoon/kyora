import 'package:flutter/material.dart';

import '../../theme.dart';
import 'cut_border.dart';
import 'hack_text.dart';

/// Una ventana de terminal sci-fi: un recuadro **de esquinas rectas** con el filo del acento, una cabecera con tres marcas
/// cuadradas y un título en letra monoespaciada, y el cuerpo en un degradado de negro translúcido (sin desenfoque ni líneas: se ve el fondo de
/// pantalla detrás). Con [footer] lleva abajo, dentro de la ventana, una línea más (el prompt para escribir).
class TerminalWindow extends StatelessWidget {
  const TerminalWindow({super.key, required this.title, required this.child, this.trailing, this.footer});

  /// El título de la cabecera, tipo `KYORA :: TERMINAL`.
  final String title;

  /// Algo a la derecha de la cabecera (el estado de la conexión, por ejemplo).
  final Widget? trailing;

  /// Lo que va abajo del todo, separado del registro por un filo fino.
  final Widget? footer;

  final Widget child;

  static const cut = 20.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomPaint(
      painter: _WindowPainter(accent: c.accent),
      child: ClipPath(
        clipper: const ShapeBorderClipper(shape: CutBorder(cut: cut)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const Key('terminal-header'),
              padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.accent.withValues(alpha: 0.35)))),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(width: 9, height: 9, margin: const EdgeInsets.only(right: 7), color: i == 2 ? c.accent : c.accent.withValues(alpha: 0.35)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: HackText(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: c.accent),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            Expanded(child: child),
            if (footer != null)
              DecoratedBox(
                key: const Key('terminal-footer'),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.accent.withValues(alpha: 0.35)))),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

class _WindowPainter extends CustomPainter {
  const _WindowPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final path = const CutBorder(cut: TerminalWindow.cut).getOuterPath(Offset.zero & size);
    // el cuerpo: un degradado de negro, más cerrado arriba, con un toque del acento
    canvas.drawPath(
      path,
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.alphaBlend(accent.withValues(alpha: 0.06), Colors.black.withValues(alpha: 0.9)), Colors.black.withValues(alpha: 0.7)],
      ).createShader(Offset.zero & size),
    );
    // el filo
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = accent.withValues(alpha: 0.8));
    // las marcas de dos esquinas opuestas
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.4..strokeCap = StrokeCap.square..color = accent;
    const l = 14.0;
    canvas.drawPath(Path()..moveTo(0, l)..lineTo(0, 0)..lineTo(l, 0), p);
    canvas.drawPath(Path()..moveTo(size.width, size.height - l)..lineTo(size.width, size.height)..lineTo(size.width - l, size.height), p);
  }

  @override
  bool shouldRepaint(covariant _WindowPainter old) => old.accent != accent;
}

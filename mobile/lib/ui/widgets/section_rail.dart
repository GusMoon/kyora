import 'package:flutter/material.dart';

import '../../theme.dart';

/// Una sección de la app: su icono y su nombre (lo que enseña la barra) y la pantalla que se ve.
class AppSection {
  const AppSection({required this.id, required this.icon, required this.label, required this.builder});

  /// Con esto se encuentra su botón en la barra (`section-<id>`).
  final String id;
  final IconData icon;
  final String label;
  final WidgetBuilder builder;
}

/// La barra del borde derecho, como los paneles del escritorio: una pieza plana que **sale del borde de la pantalla**, con dos
/// pestañitas curvas que la ensanchan justo donde toca el borde, las esquinas de fuera redondeadas y una sombra sutil. Lleva solo los
/// iconos de todas las secciones en vertical; el de la sección a la que se va (la más cercana a `page`) se resalta (color y tamaño) al
/// ritmo del dedo. Tocar un icono salta a esa sección.
class SectionRail extends StatelessWidget {
  const SectionRail({super.key, required this.sections, required this.page, required this.onSelect});

  final List<AppSection> sections;

  /// La posición fraccionaria del `PageView` (1,5 = a mitad de camino entre la segunda y la tercera sección).
  final double page;
  final ValueChanged<int> onSelect;

  /// Lo que miden las pestañitas con las que la pieza nace del borde y el redondeo de sus esquinas (como `dock_tab` y `dock_corner`
  /// del escritorio).
  static const tab = 12.0;
  static const corner = 10.0;

  /// Cuánto pesa la sección `i` ahora: 1 si está del todo a la vista, 0 si está a una sección o más de distancia.
  static double weightOf(int i, double page) => (1 - (page - i).abs()).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomPaint(
      key: const Key('section-rail'),
      painter: _RailPainter(fill: c.surface, line: c.edge),
      child: Padding(
        // arriba y abajo cabe la pestañita; a la derecha, un respiro frente al borde; a la izquierda, el redondeo
        padding: const EdgeInsets.fromLTRB(6, tab + 6, 6, tab + 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < sections.length; i++) _Item(section: sections[i], weight: weightOf(i, page), onTap: () => onSelect(i)),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.section, required this.weight, required this.onTap});

  final AppSection section;
  final double weight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // solo el icono: al deslizar, el resaltado (color y tamaño) pasa de un icono al siguiente al ritmo del dedo
    return Semantics(
      label: section.label,
      button: true,
      child: GestureDetector(
        key: Key('section-${section.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(section.icon, size: 21 + 4 * weight, color: Color.lerp(c.dim, c.accent, weight)),
        ),
      ),
    );
  }
}

/// La forma de la pieza, la misma que `hanging_paths` del escritorio girada al borde derecho: cuerpo de esquinas redondeadas a la
/// izquierda y, donde toca el borde, una pestañita cóncava arriba y otra abajo que la ensanchan como si saliera de él.
class _RailPainter extends CustomPainter {
  const _RailPainter({required this.fill, required this.line});

  final Color fill;
  final Color line;

  /// El contorno (sin el lado del borde de la pantalla) para una pieza de ese tamaño; la pieza ocupa todo el alto menos las pestañitas.
  static Path outline(Size size) {
    const j = SectionRail.tab;
    const r = SectionRail.corner;
    final w = size.width;
    final length = size.height - 2 * j;
    return Path()
      ..moveTo(w, 0)
      ..arcToPoint(Offset(w - j, j), radius: const Radius.circular(j)) // pestañita de arriba (curva cóncava)
      ..lineTo(r, j)
      ..arcToPoint(const Offset(0, j + r), radius: const Radius.circular(r), clockwise: false) // esquina de arriba a la izquierda
      ..lineTo(0, j + length - r)
      ..arcToPoint(Offset(r, j + length), radius: const Radius.circular(r), clockwise: false) // esquina de abajo a la izquierda
      ..lineTo(w - j, j + length)
      ..arcToPoint(Offset(w, j + length + j), radius: const Radius.circular(j)); // pestañita de abajo
  }

  @override
  void paint(Canvas canvas, Size size) {
    final open = outline(size);
    final body = Path.from(open)..close();
    canvas.drawPath(body.shift(const Offset(-1, 1)), Paint()..color = const Color(0x4D000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)); // la sombra
    canvas.drawPath(body, Paint()..color = fill);
    canvas.drawPath(open, Paint()..color = line..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_RailPainter old) => old.fill != fill || old.line != line;
}

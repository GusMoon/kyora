import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Una opción del menú circular.
class RadialEntry {
  const RadialEntry({required this.id, required this.icon, required this.label});

  final String id;
  final IconData icon;
  final String label;
}

/// Dónde cae cada opción del menú circular. Es solo geometría (sin widgets) para poder probarla: un **círculo completo** alrededor del dedo,
/// con la primera opción arriba y las demás en el sentido del reloj. Cada opción cae **siempre en la misma dirección**, se toque donde se
/// toque, para poder memorizarla; cerca de un borde el círculo entero se corre lo justo hacia dentro, sin girar. Se elige por el **ángulo**
/// en que está el dedo visto desde el centro.
class RadialGeometry {
  RadialGeometry({required this.count, required this.bounds, required this.touch}) : step = 2 * math.pi / math.max(1, count) {
    // las posiciones se mueven todas juntas, así que basta una vez: lo que más se sale por un lado se compensa
    final minX = bounds.left + item / 2 + margin;
    final maxX = bounds.right - item / 2 - margin;
    final minY = bounds.top + item / 2 + margin;
    final maxY = bounds.bottom - item / 2 - margin;
    var left = 0.0, right = 0.0, up = 0.0, down = 0.0;
    for (var i = 0; i < count; i++) {
      final p = touch + Offset.fromDirection(angleOf(i), radius);
      left = math.max(left, minX - p.dx);
      right = math.max(right, p.dx - maxX);
      up = math.max(up, minY - p.dy);
      down = math.max(down, p.dy - maxY);
    }
    center = touch + Offset(left > 0 ? left : -right, up > 0 ? up : -down);
  }

  /// Cuántas opciones hay.
  final int count;

  /// La zona de la pantalla donde caben (sin las barras del sistema).
  final Rect bounds;

  /// Donde se puso el dedo.
  final Offset touch;

  /// El centro del menú (el del dedo, corrido si hacía falta para que todo se vea).
  late final Offset center;

  /// El ángulo entre una opción y la siguiente (rad): la vuelta entera repartida entre todas.
  final double step;

  /// La distancia del centro a cada opción, el lado de cada círculo, el aire con el borde de la pantalla y el radio sin selección en el
  /// centro.
  static const radius = 112.0;
  static const item = 52.0;
  static const margin = 8.0;
  static const deadZone = 40.0;

  /// El ángulo (rad) de la primera opción: arriba.
  static const first = -math.pi / 2;

  /// El ángulo (rad) de la opción `i`. No depende de dónde se ponga el dedo.
  double angleOf(int i) => first + step * i;

  /// El centro del círculo de la opción `i`.
  Offset positionOf(int i) => center + Offset.fromDirection(angleOf(i), radius);

  /// La opción a la que apunta el dedo, o nada si está en el centro.
  int? pick(Offset finger) {
    final v = finger - center;
    if (v.distance < deadZone) return null;
    return ((v.direction - first) / step).round() % count;
  }
}

/// El menú circular a la vista: todo lo de debajo borroso y más oscuro, el círculo de opciones y, en el centro, el nombre de la opción que
/// se tiene bajo el dedo. Nada se anima con opacidad (los círculos crecen de golpe con una curva) para no tocar el cristal de debajo.
class RadialMenuView extends StatelessWidget {
  const RadialMenuView({super.key, required this.geometry, required this.entries, required this.selected, required this.currentId, required this.opening});

  /// Lo borroso que queda lo de debajo con el menú abierto, y el velo que lo oscurece.
  static const backdropBlur = 16.0;
  static const veil = Color(0xA6000000);

  final RadialGeometry geometry;
  final List<RadialEntry> entries;
  final int? selected;

  /// El `id` de la sección que se ve (va marcada).
  final String currentId;

  /// 0 → 1 al abrirse.
  final Animation<double> opening;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = selected == null ? null : entries[selected!].label;
    return IgnorePointer(
      child: Stack(
        key: const Key('radial-menu'),
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: opening,
            builder: (context, _) => BackdropFilter(
              key: const Key('radial-blur'),
              filter: ui.ImageFilter.blur(sigmaX: backdropBlur * opening.value, sigmaY: backdropBlur * opening.value),
              child: ColoredBox(color: Color.lerp(const Color(0x00000000), veil, opening.value)!),
            ),
          ),
          CustomPaint(painter: _TicksPainter(geometry: geometry, color: const Color(0x38FFFFFF))),
          // el punto donde se puso el dedo
          Positioned(left: geometry.touch.dx - 4, top: geometry.touch.dy - 4, width: 8, height: 8, child: const DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0x66FFFFFF)))),
          // el nombre de la opción elegida, en el centro
          Positioned(
            left: geometry.center.dx - 60,
            top: geometry.center.dy - 14,
            width: 120,
            height: 28,
            child: Center(
              child: label == null
                  ? const SizedBox.shrink()
                  : FittedBox(fit: BoxFit.scaleDown, child: Text(label, key: const Key('radial-label'), style: TextStyle(color: c.ink, fontSize: 18, fontWeight: FontWeight.w600))),
            ),
          ),
          for (var i = 0; i < entries.length; i++)
            Positioned(
              left: geometry.positionOf(i).dx - RadialGeometry.item / 2,
              top: geometry.positionOf(i).dy - RadialGeometry.item / 2,
              width: RadialGeometry.item,
              height: RadialGeometry.item,
              child: _Bubble(
                entry: entries[i],
                index: i,
                of: entries.length,
                opening: opening,
                selected: selected == i,
                current: entries[i].id == currentId,
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry, required this.index, required this.of, required this.opening, required this.selected, required this.current});

  final RadialEntry entry;
  final int index;
  final int of;
  final Animation<double> opening;
  final bool selected;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // cada círculo sale un poco después del anterior
    final start = 0.5 * index / math.max(1, of);
    final grow = CurvedAnimation(parent: opening, curve: Interval(start, math.min(1, start + 0.5), curve: Curves.easeOutBack));
    return ScaleTransition(
      scale: grow,
      child: AnimatedScale(
        scale: selected ? 1.28 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Semantics(
          label: entry.label,
          selected: current,
          child: DecoratedBox(
            key: Key('radial-${entry.id}'),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? c.ink : const Color(0x40FFFFFF),
              border: Border.all(color: current ? c.accent : const Color(0x4DFFFFFF), width: current ? 2.4 : 1),
            ),
            child: Icon(entry.icon, size: 24, color: selected ? const Color(0xFF141414) : c.ink),
          ),
        ),
      ),
    );
  }
}

/// Las marcas finas de reloj, una vuelta entera dentro del círculo de opciones.
class _TicksPainter extends CustomPainter {
  _TicksPainter({required this.geometry, required this.color});

  final RadialGeometry geometry;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry.count < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const ticks = 5; // entre una opción y la siguiente
    final total = geometry.count * ticks;
    final from = geometry.angleOf(0) - geometry.step / 2;
    for (var k = 0; k < total; k++) {
      final angle = from + 2 * math.pi * k / total;
      final major = k % ticks == 0;
      final inner = RadialGeometry.radius - (major ? 50 : 46);
      final outer = RadialGeometry.radius - 40;
      canvas.drawLine(geometry.center + Offset.fromDirection(angle, inner), geometry.center + Offset.fromDirection(angle, outer), paint);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) => old.geometry != geometry || old.color != color;
}

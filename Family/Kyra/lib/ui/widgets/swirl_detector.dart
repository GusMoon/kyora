import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Un giro del dedo ya reconocido: dónde está el centro del círculo y hacia dónde giró.
class Swirl {
  const Swirl({required this.center, required this.clockwise});

  final Offset center;

  /// A la derecha (en el sentido del reloj) o a la izquierda.
  final bool clockwise;
}

/// Reconoce que un dedo **dibuja un círculo** (un giro). Es solo cuentas, sin widgets, para poder probarlo: se le dan los puntos del dedo con su
/// instante y avisa cuando los últimos describen una vuelta bastante redonda y bastante larga.
///
/// El giro se mide alrededor del **centro de masa** de los últimos puntos: se suman los ángulos que recorre el dedo visto desde ahí. Una raya
/// recta (desplazarse por una lista) no da vueltas, y un zigzag tampoco: no es redondo (hay puntos pegados al centro) ni suma en un solo
/// sentido.
class SwirlTracker {
  /// Lo que hay que girar (rad) para que cuente, medido alrededor del centro de masa (que en un arco queda hacia dentro y exagera un poco el
  /// giro): equivale a unos tres cuartos de vuelta.
  static const needed = 5.2;

  /// Solo cuentan los últimos instantes: un giro es un gesto rápido.
  static const window = Duration(milliseconds: 1800);

  /// El radio medio permitido (px): ni un temblor ni un círculo de pantalla entera.
  static const minRadius = 22.0;
  static const maxRadius = 190.0;

  /// Lo «redondo» que debe ser: ningún punto más cerca del centro que esta parte del radio medio ni más lejos que la otra.
  static const nearest = 0.62;
  static const farthest = 1.55;

  /// Cuántos puntos se guardan como máximo (por velocidad del dedo).
  static const maxPoints = 140;

  final List<(Offset, Duration)> _points = [];

  /// Se olvida todo (el dedo se levantó o empezó otro).
  void reset() => _points.clear();

  /// Añade el punto `at` visto en el instante `time`. Devuelve el giro si con él ya está completo.
  Swirl? add(Offset at, Duration time) {
    _points.add((at, time));
    while (_points.length > maxPoints || (_points.isNotEmpty && time - _points.first.$2 > window)) {
      _points.removeAt(0);
    }
    return _check();
  }

  Swirl? _check() {
    if (_points.length < 12) return null;
    var sum = Offset.zero;
    for (final (p, _) in _points) {
      sum += p;
    }
    final c = sum / _points.length.toDouble();
    var mean = 0.0;
    for (final (p, _) in _points) {
      mean += (p - c).distance;
    }
    mean /= _points.length;
    if (mean < minRadius || mean > maxRadius) return null;
    var sweep = 0.0;
    var previous = (_points.first.$1 - c).direction;
    for (final (p, _) in _points) {
      final v = p - c;
      final r = v.distance;
      if (r < mean * nearest || r > mean * farthest) return null; // no es redondo
      var d = v.direction - previous;
      while (d > math.pi) {
        d -= 2 * math.pi;
      }
      while (d < -math.pi) {
        d += 2 * math.pi;
      }
      sweep += d;
      previous = v.direction;
    }
    if (sweep.abs() < needed) return null;
    return Swirl(center: c, clockwise: sweep > 0); // la pantalla crece hacia abajo: ángulo positivo = sentido del reloj
  }
}

/// Mira, sin quitarle los toques a nadie (solo escucha), si un dedo dibuja un círculo sobre [child] y avisa con [onSwirl]. Se avisa una sola
/// vez por dedo; con más de un dedo en la pantalla (un pellizco) no se mira. Con [enabled] en `false` no hace nada.
class SwirlDetector extends StatefulWidget {
  const SwirlDetector({super.key, required this.child, required this.onSwirl, this.enabled = true});

  final Widget child;
  final ValueChanged<Swirl> onSwirl;
  final bool enabled;

  @override
  State<SwirlDetector> createState() => _SwirlDetectorState();
}

class _SwirlDetectorState extends State<SwirlDetector> {
  final _tracker = SwirlTracker();
  final _down = <int>{};
  int? _following;
  bool _done = false;

  void _start(PointerDownEvent e) {
    _down.add(e.pointer);
    if (_down.length == 1 && widget.enabled) {
      _following = e.pointer;
      _done = false;
      _tracker
        ..reset()
        ..add(e.position, e.timeStamp);
    } else {
      _following = null; // dos dedos: no es un giro
      _tracker.reset();
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _following || _done || !widget.enabled) return;
    final swirl = _tracker.add(e.position, e.timeStamp);
    if (swirl != null) {
      _done = true;
      widget.onSwirl(swirl);
    }
  }

  void _end(PointerEvent e) {
    _down.remove(e.pointer);
    if (e.pointer == _following) {
      _following = null;
      _tracker.reset();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: _start,
    onPointerMove: _move,
    onPointerUp: _end,
    onPointerCancel: _end,
    child: widget.child,
  );
}

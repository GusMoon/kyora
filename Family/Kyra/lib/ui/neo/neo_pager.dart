import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// El cambio de pantalla que está en marcha, para los bloques (`NeoSlide`) de una pantalla de KyraFamily: los de la que se va **se desplazan
/// uno por uno hacia el lado del gesto**, borrosos y apagándose, y los de la que llega **entran desde el otro lado**, uno tras otro, de
/// borrosos a nítidos. Rápido: menos de medio segundo.
class NeoSlideMotion extends InheritedWidget {
  const NeoSlideMotion({super.key, required this.animation, required this.leaving, required this.moving, required this.forward, required super.child});

  /// El avance del cambio, de 0 a 1 y sin curva: cada bloque aplica su propio tiempo.
  final Animation<double> animation;

  /// Esta pantalla es la que se va.
  final bool leaving;

  /// Hay un cambio en curso.
  final bool moving;

  /// Se va a la pantalla siguiente (el contenido corre hacia la izquierda); si no, a la anterior (hacia la derecha).
  final bool forward;

  /// Lo que dura el cambio entero, y los tiempos de cada bloque (en milisegundos).
  static const total = Duration(milliseconds: 430);
  static const exitMs = 150.0;
  static const exitStep = 30.0;
  static const enterDelayMs = 100.0;
  static const enterMs = 180.0;
  static const enterStep = 30.0;
  static const maxOrder = 5;

  /// El desenfoque más fuerte (en px) mientras un bloque corre.
  static const maxBlur = 14.0;

  static double _phase(double t, double start, double length) => ((t * total.inMilliseconds - start) / length).clamp(0.0, 1.0);

  /// Cuánto ha salido un bloque (0 en su sitio → 1 ido).
  static double exitProgress(double t, int order) => Curves.easeIn.transform(_phase(t, exitStep * order.clamp(0, maxOrder), exitMs));

  /// Cuánto ha llegado un bloque (0 fuera → 1 en su sitio).
  static double enterProgress(double t, int order) =>
      Curves.easeOutCubic.transform(_phase(t, enterDelayMs + enterStep * order.clamp(0, maxOrder), enterMs));

  static NeoSlideMotion? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<NeoSlideMotion>();

  @override
  bool updateShouldNotify(NeoSlideMotion old) => old.animation != animation || old.leaving != leaving || old.moving != moving || old.forward != forward;
}

/// Un bloque de una pantalla (el título, una ventana, la cuadrícula, el reproductor…): en el cambio de pantalla se desplaza en su turno
/// (`order`) con un desenfoque horizontal, y al quedar en su sitio se ve nítido (sin filtro). Fuera de un cambio se queda quieto.
class NeoSlide extends StatelessWidget {
  const NeoSlide({super.key, this.order = 0, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = NeoSlideMotion.maybeOf(context);
    final width = MediaQuery.sizeOf(context).width;
    // siempre la misma estructura (si cambiara a mitad, el bloque perdería su estado)
    return AnimatedBuilder(
      animation: motion?.animation ?? kAlwaysCompleteAnimation,
      child: child,
      builder: (context, body) {
        var dx = 0.0;
        var blur = 0.0;
        var opacity = 1.0;
        if (motion != null && motion.moving) {
          final t = motion.animation.value;
          final away = motion.forward ? -1.0 : 1.0; // hacia dónde corre el contenido
          if (motion.leaving) {
            final p = NeoSlideMotion.exitProgress(t, order);
            dx = away * width * 0.55 * p;
            blur = NeoSlideMotion.maxBlur * math.sin(math.pi * math.min(p * 1.4, 1) / 2);
            opacity = 1 - p;
          } else {
            final p = NeoSlideMotion.enterProgress(t, order);
            dx = -away * width * 0.4 * (1 - p);
            blur = NeoSlideMotion.maxBlur * (1 - p);
            opacity = p;
          }
        }
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: ImageFiltered(
              enabled: blur > 0.05,
              imageFilter: ui.ImageFilter.blur(sigmaX: math.max(blur, 0.001), sigmaY: 0, tileMode: TileMode.decal),
              child: body,
            ),
          ),
        );
      },
    );
  }
}

/// Las pantallas de KyraFamily, una a la vez: **deslizar a los lados cambia de pantalla** (a la izquierda, la siguiente; a la derecha, la
/// anterior). En el cambio, los bloques de la que se va corren borrosos hacia un lado y los de la nueva llegan desde el otro (`NeoSlide`).
/// Todas las pantallas siguen vivas (nada se pierde al cambiar); la que no se ve no se pinta ni recibe toques. Con «menos animaciones» el
/// cambio es inmediato.
class NeoPager extends StatefulWidget {
  const NeoPager({super.key, required this.index, required this.onChanged, required this.children});

  final int index;

  /// Pide cambiar a otra pantalla (al deslizar); quien manda decide y, si cambia `index`, el pager hace el efecto.
  final ValueChanged<int> onChanged;

  final List<Widget> children;

  /// Cuánto hay que arrastrar de lado (px) para pasar de pantalla.
  static const swipeDistance = 56.0;

  @override
  State<NeoPager> createState() => _NeoPagerState();
}

class _NeoPagerState extends State<NeoPager> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: NeoSlideMotion.total, value: 1)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() => _from = null);
    });

  int? _from;
  bool _forward = true;
  double _drag = 0;
  bool _fired = false;

  @override
  void didUpdateWidget(NeoPager old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _from = null;
      _controller.value = 1;
    } else {
      _from = old.index;
      _forward = widget.index > old.index;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    if (_fired) return;
    _drag += d.primaryDelta ?? 0;
    if (_drag.abs() < NeoPager.swipeDistance) return;
    final next = widget.index + (_drag < 0 ? 1 : -1);
    _fired = true;
    if (next >= 0 && next < widget.children.length) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final moving = _from != null;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _drag = 0;
        _fired = false;
      },
      onHorizontalDragUpdate: _update,
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            KeyedSubtree(
              key: ValueKey('neo-page-$i'),
              child: Offstage(
                offstage: i != widget.index && i != _from,
                child: TickerMode(
                  enabled: i == widget.index || i == _from,
                  child: IgnorePointer(
                    ignoring: i != widget.index,
                    child: NeoSlideMotion(
                      animation: _controller,
                      leaving: i == _from,
                      moving: moving && (i == widget.index || i == _from),
                      forward: _forward,
                      child: widget.children[i],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

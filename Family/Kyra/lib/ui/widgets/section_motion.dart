import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Por qué borde de la pantalla sale y entra un bloque.
enum MotionEdge { top, bottom, left, right }

/// El cambio de sección que está en marcha, para los bloques (`FlyIn`) de una sección. Es un efecto de **glitch / holograma**: los bloques de
/// la sección que se va se rompen y desaparecen muy rápido, todos a la vez, y los de la que llega se materializan uno tras otro (escalonados),
/// con saltos, parpadeo y franjas de interferencia hasta quedar nítidos en su sitio.
class SectionMotion extends InheritedWidget {
  const SectionMotion({super.key, required this.animation, required this.leaving, required this.moving, required super.child});

  /// El avance del cambio, de 0 a 1 y sin curva: cada bloque le aplica su propio tiempo. Lo dura `total`.
  final Animation<double> animation;

  /// Esta sección es la que se va.
  final bool leaving;

  /// Hay un cambio en curso.
  final bool moving;

  /// Lo que tarda un bloque en irse y en aparecer, la espera entre que empieza la salida y empieza la entrada, y la separación entre un
  /// bloque y el siguiente de la misma sección.
  static const exitTime = Duration(milliseconds: 210);
  static const enterTime = Duration(milliseconds: 240);
  static const enterDelay = Duration(milliseconds: 120);
  static const step = Duration(milliseconds: 45);

  /// El `order` más alto que se tiene en cuenta.
  static const maxOrder = 5;

  /// Lo que dura el cambio entero.
  static const total = Duration(milliseconds: 585);

  /// Cuánto salta como mucho un bloque (px) mientras se materializa o se rompe, y lo que se desplaza desde su borde.
  static const jitter = 14.0;
  static const drift = 10.0;

  /// Cuántos saltos da el glitch a lo largo de una aparición.
  static const ticks = 9;

  static double _phase(double t, Duration start, Duration length) =>
      ((t * total.inMilliseconds - start.inMilliseconds) / length.inMilliseconds).clamp(0.0, 1.0);

  /// Lo que lleva recorrido de su salida un bloque: 0 en su sitio, 1 ido. Salen todos a la vez (`order` no cuenta).
  static double exitProgress(double t, [int order = 0]) => _phase(t, Duration.zero, exitTime);

  /// Lo que lleva recorrido de su aparición un bloque: 0 oculto, 1 en su sitio.
  static double enterProgress(double t, int order) => Curves.easeOut.transform(_phase(t, enterDelay + step * order.clamp(0, maxOrder), enterTime));

  /// La espera (en milisegundos) que le queda a un bloque de turno `order` para empezar a aparecer, estando el cambio en `t`; 0 si ya empezó.
  static double waitFor(double t, int order) => math.max(0.0, (enterDelay + step * order.clamp(0, maxOrder)).inMilliseconds - t * total.inMilliseconds);

  /// Un número «al azar» entre 0 y 1, siempre el mismo para la misma semilla y el mismo paso (así el glitch salta a saltos, no a cada cuadro).
  static double noise(int seed, int tick) {
    var x = (seed * 374761393 + tick * 668265263) & 0x7fffffff;
    x = ((x ^ (x >> 13)) * 1274126177) & 0x7fffffff;
    return (x & 0xffff) / 0xffff;
  }

  /// Lo visible que está un bloque con el avance `shown` (0 oculto → 1 entero): sube con el avance pero **parpadea** (en algunos saltos casi se
  /// apaga).
  static double glitchOpacity(double shown, int seed) {
    if (shown <= 0) return 0;
    if (shown >= 1) return 1;
    final tick = (shown * ticks).floor();
    return noise(seed, tick) < 0.3 ? shown * 0.3 : shown;
  }

  /// Lo visible que está algo que **se apaga** (un panel que se cierra) con el avance `shown` (1 entero → 0 ido): baja de forma continua, sin
  /// parpadeo. Es la versión sutil del glitch para las salidas: rápida y limpia.
  static double quietOpacity(double shown) => Curves.easeIn.transform(shown.clamp(0.0, 1.0));

  /// Dónde está algo que se apaga: un temblor leve de lado a lado (3 px como mucho) que se acaba al quedar entero.
  static Offset quietShift(double shown, int seed) {
    if (shown >= 1) return Offset.zero;
    final g = 1 - shown.clamp(0.0, 1.0);
    return Offset((noise(seed, (shown * 6).floor()) - 0.5) * 6 * g, 0);
  }

  /// Dónde está un bloque con el avance `shown`: salta de lado a saltos (más cuanto menos se ve) y viene un poco desde su borde.
  static Offset glitchShift(double shown, int seed, MotionEdge edge) {
    if (shown >= 1) return Offset.zero;
    final g = 1 - shown;
    final tick = (shown * ticks).floor();
    final jump = (noise(seed + 11, tick) - 0.5) * 2 * jitter * g;
    return Offset(jump, 0) + FlyIn.driftFor(edge) * g;
  }

  static SectionMotion? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SectionMotion>();

  /// ¿Hay un cambio de sección en curso? Fuera de una sección, nunca.
  static bool movingOf(BuildContext context) => maybeOf(context)?.moving ?? false;

  @override
  bool updateShouldNotify(SectionMotion oldWidget) => oldWidget.animation != animation || oldWidget.leaving != leaving || oldWidget.moving != moving;
}

/// Un bloque de una sección (un título, una tarjeta, una lista, una barra…): en la sección nueva **se materializa** en su turno (`order`) con
/// un efecto de glitch / holograma —salta de lado, parpadea y lo cruzan franjas de interferencia del color de la app— hasta quedar nítido; al
/// cambiar de sección se rompe igual y desaparece en un instante. Se pinta una vez en su propia capa. Fuera de una sección (pantallas
/// empujadas, pruebas sueltas) se queda quieto.
class FlyIn extends StatelessWidget {
  const FlyIn({super.key, required this.edge, this.order = 0, required this.child});

  /// El borde desde el que llega (un poco) y hacia el que se va.
  final MotionEdge edge;

  /// Su turno dentro de la sección (de 0 a `maxOrder`): cada turno empieza un poco después del anterior.
  final int order;

  final Widget child;

  /// De dónde viene el bloque al aparecer (y adonde se va), por su borde.
  static Offset driftFor(MotionEdge edge) => switch (edge) {
    MotionEdge.top => const Offset(0, -SectionMotion.drift),
    MotionEdge.bottom => const Offset(0, SectionMotion.drift),
    MotionEdge.left => const Offset(-SectionMotion.drift, 0),
    MotionEdge.right => const Offset(SectionMotion.drift, 0),
  };

  @override
  Widget build(BuildContext context) {
    final motion = SectionMotion.maybeOf(context);
    final accent = Theme.of(context).colorScheme.primary;
    final seed = order * 7 + edge.index * 3 + 1;
    // siempre la misma estructura, también sin sección alrededor: si cambiara a mitad, el bloque perdería su estado
    return AnimatedBuilder(
      animation: motion?.animation ?? kAlwaysCompleteAnimation,
      child: RepaintBoundary(child: child),
      builder: (context, body) {
        var shown = 1.0; // 0 oculto, 1 en su sitio
        if (motion != null) {
          final t = motion.animation.value;
          shown = motion.leaving ? 1 - SectionMotion.exitProgress(t, order) : SectionMotion.enterProgress(t, order);
        }
        return Opacity(
          opacity: SectionMotion.glitchOpacity(shown, seed),
          child: Transform.translate(
            offset: SectionMotion.glitchShift(shown, seed, edge),
            child: CustomPaint(
              foregroundPainter: _GlitchPainter(amount: shown >= 1 ? 0 : 1 - shown, seed: seed, tick: (shown * SectionMotion.ticks).floor(), color: accent),
              child: body,
            ),
          ),
        );
      },
    );
  }
}

/// El efecto de holograma de un cambio **dentro de una pantalla** (de una vista a otra, o al abrir una pantalla empujada): lo de dentro se
/// materializa con saltos, parpadeo y franjas de interferencia del color de la app según el avance de [animation] (0 oculto → 1 nítido), y al
/// revés al irse. Es el mismo glitch que el de los bloques de una sección (`FlyIn`), pero movido por la animación que se le da. Se pinta una vez
/// en su propia capa; con la animación completa no hace nada.
class HologramReveal extends StatelessWidget {
  const HologramReveal({super.key, required this.animation, this.edge = MotionEdge.bottom, this.seed = 3, required this.child});

  final Animation<double> animation;
  final MotionEdge edge;
  final int seed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: child),
      builder: (context, body) {
        final shown = Curves.easeOut.transform(animation.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: SectionMotion.glitchOpacity(shown, seed),
          child: Transform.translate(
            offset: SectionMotion.glitchShift(shown, seed, edge),
            child: CustomPaint(
              foregroundPainter: _GlitchPainter(amount: shown >= 1 ? 0 : 1 - shown, seed: seed, tick: (shown * SectionMotion.ticks).floor(), color: accent),
              child: body,
            ),
          ),
        );
      },
    );
  }
}

/// Las franjas de interferencia del holograma: unas cuantas bandas horizontales del color de la app y otras oscuras, de alto y sitio al azar
/// (cambian a saltos), y líneas de barrido. Sin glitch (`amount` 0) no pinta nada.
class _GlitchPainter extends CustomPainter {
  const _GlitchPainter({required this.amount, required this.seed, required this.tick, required this.color});

  final double amount;
  final int seed;
  final int tick;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (amount <= 0 || size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final band = Paint()..color = color.withValues(alpha: 0.35 * amount);
    final cut = Paint()..color = Colors.black.withValues(alpha: 0.55 * amount);
    for (var i = 0; i < 4; i++) {
      final y = SectionMotion.noise(seed + i * 5, tick) * size.height;
      final h = 2 + SectionMotion.noise(seed + i * 9, tick) * size.height * 0.08;
      final x = (SectionMotion.noise(seed + i * 13, tick) - 0.5) * size.width * 0.3 * amount;
      canvas.drawRect(Rect.fromLTWH(x, y, size.width, h), i.isEven ? band : cut);
    }
    final scan = Paint()..strokeWidth = 1..color = color.withValues(alpha: 0.18 * amount);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scan);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlitchPainter old) => old.amount != amount || old.tick != tick || old.color != color || old.seed != seed;
}

/// Un `FlyIn` para la barra de arriba de un `Scaffold`: aparece y se va por el borde de arriba.
class FlyInBar extends StatelessWidget implements PreferredSizeWidget {
  const FlyInBar({super.key, required this.child});

  final PreferredSizeWidget child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) => FlyIn(edge: MotionEdge.top, child: child);
}

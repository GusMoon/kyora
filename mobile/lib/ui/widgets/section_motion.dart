import 'package:flutter/material.dart';

/// Por qué borde de la pantalla sale y entra un bloque.
enum MotionEdge { top, bottom, left, right }

/// El cambio de sección que está en marcha, para los bloques (`FlyIn`) de una sección: los de la sección que se va salen por su borde y,
/// con una espera mínima, los de la que llega entran por el suyo. Nada se funde: desaparecer es salir de la pantalla, así el cristal de las
/// tarjetas nunca pierde lo que tiene detrás.
class SectionMotion extends InheritedWidget {
  const SectionMotion({super.key, required this.animation, required this.leaving, required this.moving, required super.child});

  /// El avance del cambio, de 0 a 1 y sin curva: cada bloque le aplica su propio tiempo. Lo dura `total`.
  final Animation<double> animation;

  /// Esta sección es la que se va.
  final bool leaving;

  /// Hay un cambio en curso (mientras dura, las listas no recortan a los bloques que las atraviesan).
  final bool moving;

  /// Lo que tarda un bloque en salir y en entrar, la espera entre que empieza la salida y empieza la entrada, y la separación entre un
  /// bloque y el siguiente de la misma sección.
  static const exitTime = Duration(milliseconds: 200);
  static const enterTime = Duration(milliseconds: 300);
  static const enterDelay = Duration(milliseconds: 70);
  static const step = Duration(milliseconds: 25);

  /// El `order` más alto que se tiene en cuenta.
  static const maxOrder = 2;

  /// Lo que dura el cambio entero.
  static const total = Duration(milliseconds: 420);

  static double _phase(double t, Duration start, Duration length) =>
      ((t * total.inMilliseconds - start.inMilliseconds) / length.inMilliseconds).clamp(0.0, 1.0);

  /// Lo que lleva recorrido de su salida un bloque: 0 en su sitio, 1 fuera de la pantalla.
  static double exitProgress(double t, int order) => Curves.easeInCubic.transform(_phase(t, step * order.clamp(0, maxOrder), exitTime));

  /// Lo que lleva recorrido de su entrada un bloque: 0 fuera de la pantalla, 1 en su sitio.
  static double enterProgress(double t, int order) => Curves.easeOutCubic.transform(_phase(t, enterDelay + step * order.clamp(0, maxOrder), enterTime));

  static SectionMotion? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SectionMotion>();

  /// ¿Hay un cambio de sección en curso? Fuera de una sección, nunca.
  static bool movingOf(BuildContext context) => maybeOf(context)?.moving ?? false;

  @override
  bool updateShouldNotify(SectionMotion oldWidget) => oldWidget.animation != animation || oldWidget.leaving != leaving || oldWidget.moving != moving;
}

/// Un bloque de una sección (un título, una tarjeta, una lista, una barra…): al cambiar de sección sale por su `edge` y, en la sección
/// nueva, entra por él. Se pinta una vez en su propia capa y solo se mueve esa capa. Fuera de una sección (pantallas empujadas, pruebas
/// sueltas) se queda quieto.
///
/// El bloque no debe pintar fuera de su rectángulo: solo se desplaza un ancho o un alto de pantalla, y lo que sobresalga seguiría a la vista
/// (por eso la ruleta de álbumes recorta en su propio rectángulo).
class FlyIn extends StatelessWidget {
  const FlyIn({super.key, required this.edge, this.order = 0, required this.child});

  /// El borde por el que sale y entra: el más cercano a donde está el bloque.
  final MotionEdge edge;

  /// Su turno dentro de la sección (0, 1 o 2): cada turno empieza un poco después del anterior.
  final int order;

  final Widget child;

  /// El desplazamiento que lo deja fuera de una pantalla de `size`.
  static Offset awayFor(MotionEdge edge, Size size) => switch (edge) {
        MotionEdge.top => Offset(0, -size.height),
        MotionEdge.bottom => Offset(0, size.height),
        MotionEdge.left => Offset(-size.width, 0),
        MotionEdge.right => Offset(size.width, 0),
      };

  @override
  Widget build(BuildContext context) {
    final motion = SectionMotion.maybeOf(context);
    final away = awayFor(edge, MediaQuery.sizeOf(context));
    // siempre la misma estructura, también sin sección alrededor: si cambiara a mitad, el bloque perdería su estado
    return AnimatedBuilder(
      animation: motion?.animation ?? kAlwaysCompleteAnimation,
      child: RepaintBoundary(child: child),
      builder: (context, body) {
        var offset = Offset.zero;
        if (motion != null) {
          final t = motion.animation.value;
          offset = motion.leaving ? away * SectionMotion.exitProgress(t, order) : away * (1 - SectionMotion.enterProgress(t, order));
        }
        return Transform.translate(offset: offset, child: body);
      },
    );
  }
}

/// Un `FlyIn` para la barra de arriba de un `Scaffold`: sale y entra por el borde de arriba.
class FlyInBar extends StatelessWidget implements PreferredSizeWidget {
  const FlyInBar({super.key, required this.child});

  final PreferredSizeWidget child;

  @override
  Size get preferredSize => child.preferredSize;

  @override
  Widget build(BuildContext context) => FlyIn(edge: MotionEdge.top, child: child);
}

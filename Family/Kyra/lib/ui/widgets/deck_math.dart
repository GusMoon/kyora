import 'dart:math' as math;

/// La matemática de las ruletas (el abanico de favoritas y la ruleta de discos del reproductor): cuánto hay que arrastrar
/// para pasar de uno al siguiente, dónde se detiene al soltar y cómo se reparten en un anillo.
abstract final class DeckMath {
  /// Cuánto hay que arrastrar el dedo (px) para pasar de un elemento al siguiente, con la sensibilidad normal.
  static const basePixels = 220.0;

  /// Lo mismo con una sensibilidad dada (1 es lo normal; menos es más lenta).
  static double pixelsFor(double speed) => basePixels / speed;

  /// Lo más que avanza por la inercia al soltar, en elementos.
  static const maxFling = 3.0;

  /// El aire entre dos tarjetas vecinas con el anillo abierto, del ancho de la tarjeta.
  static const gap = 0.14;

  /// Lo que encoge cada tarjeta con el anillo abierto.
  static const openScale = 0.70;

  /// El ángulo entre dos elementos seguidos de un anillo (rad): la vuelta entera repartida entre todos, salvo si son muchos (entonces no da la
  /// vuelta entera a la vista).
  static double stepFor(int n) => n < 2 ? 0 : math.max(2 * math.pi / n, math.pi / 6);

  /// El ángulo del elemento `index` cuando enfrente está la posición `pos` (0 = de frente; positivo = a la derecha), por el lado más corto.
  static double angleOf(int index, double pos, int n) {
    if (n < 2) return 0;
    var away = (index - pos) % n;
    if (away > n / 2) away -= n;
    return away * stepFor(n);
  }

  /// El elemento de enfrente en la posición `pos` (el anillo no tiene tope).
  static int frontOf(double pos, int n) => n == 0 ? 0 : pos.round() % n;

  /// El radio del anillo para que `n` tarjetas de lado `side` no se pisen: cuantas más, más grande. Nunca menos de lo que luce con pocas.
  static double radiusFor(int n, double side) {
    final least = side * 0.78;
    if (n < 3) return least;
    final card = side * openScale;
    return math.max(least, card * (1 + gap) / (2 * math.sin(stepFor(n) / 2)));
  }

  /// A qué posición llega si se suelta en `pos` con esta velocidad del dedo (px/s), con `pixels` por elemento.
  static double settleAt(double pos, double velocity, {double pixels = basePixels}) =>
      (pos - (velocity / pixels * 0.35).clamp(-maxFling, maxFling)).roundToDouble();
}

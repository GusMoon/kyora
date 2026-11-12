import 'package:flutter/material.dart';


/// Los colores de un degradado negro **suave**: la opacidad baja de [peak] a 0 con una curva (smoothstep) en lugar de una recta, para que no
/// se note dónde empieza ni dónde acaba (sin el borde brusco ni las bandas de un degradado de dos colores).
List<Color> softFade(double peak, {int steps = 12}) => [
  for (var i = 0; i <= steps; i++)
    Colors.black.withValues(alpha: peak * (1 - _smooth(i / steps))),
];

/// Las paradas que acompañan a [softFade].
List<double> softStops({int steps = 12}) => [for (var i = 0; i <= steps; i++) i / steps];

double _smooth(double t) => t * t * (3 - 2 * t);

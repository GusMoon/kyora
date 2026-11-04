import 'package:flutter/material.dart';

/// La ruta del álbum: no pinta ninguna transición por su cuenta. La pantalla recibe la `animation` (0 → 1 al abrir, de vuelta al
/// cerrar) y la usa para sacar el disco de la placa, teñir el fondo y hacer entrar las canciones. Mientras
/// se anima se sigue viendo la pantalla de música debajo.
Route<T> albumRoute<T>({required Widget Function(BuildContext context, Animation<double> animation) builder}) => PageRouteBuilder<T>(
      opaque: true, // mientras dura la animación se ve la música debajo; al terminar ya no se construye
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (context, animation, secondaryAnimation) => builder(context, animation),
      transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
    );

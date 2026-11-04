import 'dart:io';

import 'package:flutter/material.dart';

import '../../state/wallpaper_controller.dart';
import '../../theme.dart';

/// El gris más claro que llega a tener el fondo (arriba) y el más oscuro (abajo), a partir del gris de la app: un gris **muy oscuro**.
(Color, Color) backdropGreys(Color base) => (Color.lerp(base, Colors.black, 0.30)!, Color.lerp(base, Colors.black, 0.58)!);

/// El fondo de toda la app. Sin fondo de pantalla, un gris muy oscuro (un poco más claro arriba para que no se vea plano). Con uno, esa
/// imagen **muy suavizada y oscurecida**, para que se vea moderno y limpio sea cual sea la imagen y el texto claro se lea siempre.
/// Va detrás del navegador, así que no se mueve al cambiar de pantalla.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child, this.wallpaper});

  final Widget child;

  /// El fondo de pantalla elegido; sin él (o sin imagen) queda el gris.
  final WallpaperController? wallpaper;

  /// El ancho al que se decodifica: tan pequeño que al estirarla a toda la pantalla queda borrosa, y casi sin coste de memoria.
  static const decodeWidth = 96;

  @override
  Widget build(BuildContext context) {
    final (top, bottom) = backdropGreys(context.colors.background);
    final gray = DecoratedBox(
      key: const Key('app-backdrop'),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom])),
    );
    final source = wallpaper;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (source == null)
          gray
        else
          ListenableBuilder(
            listenable: source,
            builder: (context, _) {
              final path = source.path;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child: path == null ? KeyedSubtree(key: const ValueKey('no-wallpaper'), child: gray) : _Wallpaper(key: ValueKey(path), path: path),
              );
            },
          ),
        child,
      ],
    );
  }
}

/// La imagen de fondo, suavizada y oscurecida.
class _Wallpaper extends StatelessWidget {
  const _Wallpaper({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(path),
            key: const Key('wallpaper-image'),
            fit: BoxFit.cover,
            cacheWidth: AppBackdrop.decodeWidth,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            errorBuilder: (context, _, _) => const ColoredBox(color: Color(0xFF111112)),
          ),
          // el velo: un poco más oscuro abajo, donde van las tarjetas
          const DecoratedBox(
            key: Key('wallpaper-veil'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x80000000), Color(0xA6000000)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una pantalla que aparece casi al instante: para abrir carpetas, donde la animación solo hace esperar.
class QuickPageRoute<T> extends MaterialPageRoute<T> {
  QuickPageRoute({required super.builder});

  @override
  Duration get transitionDuration => const Duration(milliseconds: 90);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 90);
}

/// Las pantallas son transparentes para que se vea el fondo: al cambiar de una a otra se funden, así no se ven una encima de la otra.
class FadePageTransitions extends PageTransitionsBuilder {
  const FadePageTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext? context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final entering = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    return FadeTransition(
      opacity: entering,
      child: FadeTransition(
        opacity: ReverseAnimation(secondaryAnimation),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(entering),
          child: child,
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';

import '../../state/wallpaper_controller.dart';
import '../../theme.dart';

/// El gris más claro que llega a tener el fondo (arriba) y el más oscuro (abajo), a partir del gris de la app: un gris **muy oscuro**.
(Color, Color) backdropGreys(Color base) => (Color.lerp(base, Colors.black, 0.30)!, Color.lerp(base, Colors.black, 0.58)!);

/// Quién tiene el fondo de pantalla: las pantallas que se empujan encima (y que deben taparlo todo mientras se deslizan) lo leen de aquí
/// para pintar sus propias capas del fondo, en vez de fundirse con opacidad (que dejaría sin desenfoque a las tarjetas de cristal).
class BackdropScope extends InheritedWidget {
  const BackdropScope({super.key, required this.wallpaper, required super.child});

  final WallpaperController? wallpaper;

  static BackdropScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<BackdropScope>();

  @override
  bool updateShouldNotify(BackdropScope oldWidget) => oldWidget.wallpaper != wallpaper;
}

/// El fondo de toda la app. Sin fondo de pantalla, un gris muy oscuro (un poco más claro arriba para que no se vea plano). Con uno, esa
/// imagen **muy suavizada y oscurecida**, para que se vea moderno y limpio sea cual sea la imagen y el texto claro se lea siempre.
/// Va detrás del navegador, así que no se mueve al cambiar de pantalla. Este es el fondo de Inicio; las demás secciones ponen encima el
/// efecto completo (`BackdropLayers` con `full`).
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child, this.wallpaper});

  final Widget child;

  /// El fondo de pantalla elegido; sin él (o sin imagen) queda el gris.
  final WallpaperController? wallpaper;

  /// El ancho al que se decodifica: tan pequeño que al estirarla a toda la pantalla queda borrosa, y casi sin coste de memoria.
  static const decodeWidth = 96;

  /// La parte de arriba, del alto de la pantalla, donde la foto se ve del todo nítida (el efecto cubre el 70 % de abajo).
  static const sharpUntil = 0.30;

  /// Cómo se va perdiendo la nitidez de la foto hacia abajo: la opacidad de la foto nítida en cada parada (de 1 en [sharpUntil] a 0 en
  /// el borde de abajo, con una curva suave).
  static const sharpStops = [0.0, sharpUntil, 0.45, 0.60, 0.80, 1.0];
  static const sharpAlphas = [1.0, 1.0, 0.72, 0.40, 0.12, 0.0];

  /// El velo del efecto completo (arriba y abajo): un poco más oscuro que el de Inicio.
  static const fullVeil = [Color(0xA6000000), Color(0xBF000000)];

  @override
  Widget build(BuildContext context) {
    return BackdropScope(
      wallpaper: wallpaper,
      child: Stack(fit: StackFit.expand, children: [BackdropLayers(wallpaper: wallpaper), child]),
    );
  }
}

/// Las capas del fondo (el gris, o la imagen suavizada con su velo), sin nada encima. Con `full`, el efecto ocupa el 100 %: toda la pantalla
/// borrosa, sin la foto nítida de arriba, y un poco más oscura. Así se ve el fondo fuera de Inicio.
class BackdropLayers extends StatelessWidget {
  const BackdropLayers({super.key, this.wallpaper, this.full = false});

  final WallpaperController? wallpaper;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final (top, bottom) = backdropGreys(context.colors.background);
    final plain = DecoratedBox(
      key: full ? null : const Key('app-backdrop'),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom])),
    );
    final Widget gray = full ? Stack(fit: StackFit.expand, children: [plain, const _FullVeil()]) : plain;
    final source = wallpaper;
    if (source == null) return gray;
    return ListenableBuilder(
      listenable: source,
      builder: (context, _) {
        final path = source.path;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: path == null ? KeyedSubtree(key: const ValueKey('no-wallpaper'), child: gray) : _Wallpaper(key: ValueKey(path), path: path, full: full),
        );
      },
    );
  }
}

/// El velo del efecto completo.
class _FullVeil extends StatelessWidget {
  const _FullVeil();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        key: Key('backdrop-full-veil'),
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: AppBackdrop.fullVeil)),
      );
}

/// La imagen de fondo. La de Inicio: suavizada y oscurecida en el 70 % de abajo y, arriba, la foto nítida que se va desvaneciendo hacia
/// abajo. Con `full`: solo la imagen suavizada, con el velo más oscuro.
class _Wallpaper extends StatelessWidget {
  const _Wallpaper({super.key, required this.path, required this.full});

  final String path;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final soft = Image.file(
      File(path),
      key: Key(full ? 'backdrop-full-image' : 'wallpaper-image'),
      fit: BoxFit.cover,
      cacheWidth: AppBackdrop.decodeWidth,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, _, _) => const ColoredBox(color: Color(0xFF111112)),
    );
    if (full) return RepaintBoundary(child: Stack(fit: StackFit.expand, children: [soft, const _FullVeil()]));
    final media = MediaQuery.of(context);
    // la nítida, al ancho real de la pantalla: aquí sí se ve la foto sin suavizar
    final sharpWidth = (media.size.width * media.devicePixelRatio).round().clamp(200, 1080);
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          soft,
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
          // la foto nítida de arriba, que se desvanece hacia abajo (dejando ver el fondo ya suavizado)
          ShaderMask(
            key: const Key('backdrop-sharp'),
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [for (final alpha in AppBackdrop.sharpAlphas) Colors.white.withValues(alpha: alpha)],
              stops: AppBackdrop.sharpStops,
            ).createShader(rect),
            child: Image.file(
              File(path),
              key: const Key('backdrop-sharp-image'),
              fit: BoxFit.cover,
              cacheWidth: sharpWidth,
              gaplessPlayback: true,
              errorBuilder: (context, _, _) => const SizedBox.expand(),
            ),
          ),
          // un velo fino arriba asegura que el texto claro se lea sobre cualquier foto
          const DecoratedBox(
            key: Key('backdrop-sharp-veil'),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66000000), Color(0x00000000)], stops: [0.0, 0.28]),
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

/// Cómo llegan las pantallas empujadas (detalle de tarea, reproductor, registro…): suben desde el borde de abajo **tapando** la anterior,
/// con su propio fondo detrás, el del efecto completo (la foto nítida es solo de Inicio). Sin ningún efecto de opacidad: una tarjeta de cristal dentro de una capa con opacidad deja de ver lo que
/// tiene detrás y pierde el desenfoque mientras dura el fundido.
class LayerPageTransitions extends PageTransitionsBuilder {
  const LayerPageTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext? context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (route.isFirst) return child;
    final scope = context == null ? null : BackdropScope.maybeOf(context);
    final entering = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(entering),
      child: Stack(fit: StackFit.expand, children: [BackdropLayers(wallpaper: scope?.wallpaper, full: true), child]),
    );
  }
}

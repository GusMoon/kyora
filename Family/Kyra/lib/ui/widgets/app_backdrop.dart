import 'dart:io';

import 'package:flutter/material.dart';

import '../../state/now_playing_backdrop.dart';
import '../../state/wallpaper_controller.dart';

import '../../theme.dart';
import 'cover_backdrop.dart';
import 'device_shell.dart';

/// El fondo de pantalla elegido, para quien lo pinte (`BackdropLayers`): se pone una vez, encima de toda la app, y cambia cuando se cambia.
class WallpaperScope extends InheritedNotifier<WallpaperController> {
  const WallpaperScope({super.key, super.notifier, required super.child});

  /// El fondo, o `null` si no hay un `WallpaperScope` encima o no se dio ninguno.
  static WallpaperController? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<WallpaperScope>()?.notifier;
}

/// La portada de lo que suena, para el fondo de toda la app (`BackdropLayers`): mientras suena una canción el fondo es su portada.
class NowPlayingScope extends InheritedNotifier<NowPlayingBackdrop> {
  const NowPlayingScope({super.key, super.notifier, required super.child});

  /// La portada que suena, o `null` si no suena nada, no hay `NowPlayingScope` encima o lo que suena no tiene portada.
  static ({String? file, String? url})? sourceOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<NowPlayingScope>()?.notifier?.source;
}

/// Lo que se oscurece el fondo (el de pantalla o la portada que suena): **plano**, igual en toda la pantalla y en todas las secciones; lo justo
/// para que la información se lea.
const kBackdropDim = 0.42;

/// La capa de «pantalla de hacker» que va sobre cualquier fondo: el oscurecido plano ([dim]) y encima las **líneas de barrido** bien marcadas
/// (una raya oscura cada pocos píxeles y un hilo de luz entre ellas). Es pintura: no recibe toques.
class HackerScreen extends StatelessWidget {
  const HackerScreen({super.key, this.dim = kBackdropDim});

  /// El oscurecido (0 = sin oscurecer, solo las líneas).
  final double dim;

  /// Cada cuántos píxeles va una línea, y su grosor y opacidad.
  static const pitch = 4.0;
  static const lineWidth = 1.6;
  static const lineAlpha = 0.38;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (dim > 0) ColoredBox(key: const Key('backdrop-dim'), color: Colors.black.withValues(alpha: dim)),
        const RepaintBoundary(child: CustomPaint(key: Key('backdrop-lines'), painter: ScanLinesPainter(), size: Size.infinite)),
      ],
    ),
  );
}

/// Las líneas de barrido del fondo: una raya oscura bien marcada cada [HackerScreen.pitch] píxeles y un hilo de luz tenue entre ellas.
class ScanLinesPainter extends CustomPainter {
  const ScanLinesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dark = Paint()..strokeWidth = HackerScreen.lineWidth..color = Colors.black.withValues(alpha: HackerScreen.lineAlpha);
    final light = Paint()..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.05);
    for (var y = 1.0; y < size.height; y += HackerScreen.pitch) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), dark);
      canvas.drawLine(Offset(0, y + HackerScreen.pitch / 2), Offset(size.width, y + HackerScreen.pitch / 2), light);
    }
  }

  @override
  bool shouldRepaint(covariant ScanLinesPainter old) => false;
}

/// Toda la app dentro del aparato: el bisel, la pantalla LCD y lo de dentro (el acceso, las secciones y lo que se abra encima). Con el fondo
/// de pantalla, que lo ven todas las secciones.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child, this.wallpaper, this.nowPlaying});

  final Widget child;

  /// El fondo de pantalla. Sin esto (o sin imagen puesta) el fondo es el gris oscuro de siempre.
  final WallpaperController? wallpaper;

  /// La portada de lo que suena: mientras suena algo, el fondo de toda la app pasa a ser su portada. Sin esto no cambia nunca.
  final NowPlayingBackdrop? nowPlaying;

  @override
  Widget build(BuildContext context) =>
      NowPlayingScope(notifier: nowPlaying, child: WallpaperScope(notifier: wallpaper, child: DeviceShell(key: const Key('app-backdrop'), screen: child)));
}

/// El fondo de una pantalla: el gris oscuro de siempre o, si hay un fondo de pantalla, esa imagen a pantalla completa; mientras suena una
/// canción, su portada por encima. Sobre todo ello, el **oscurecido plano** (sin degradados) y las **líneas de barrido** (`HackerScreen`).
class BackdropLayers extends StatelessWidget {
  const BackdropLayers({super.key});

  /// Lo que tarda el fondo en pasar a la portada que suena y en volver.
  static const coverFade = Duration(milliseconds: 600);

  @override
  Widget build(BuildContext context) {
    final path = WallpaperScope.maybeOf(context)?.path;
    final playing = NowPlayingScope.sourceOf(context);
    final base = ColoredBox(key: const Key('screen-backdrop'), color: context.colors.background);
    final media = MediaQuery.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        base,
        if (path != null)
          Image.file(
            File(path),
            key: ValueKey(path),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: (media.size.width * media.devicePixelRatio).round(),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        // mientras suena algo, su portada cubre el fondo; al pausar o parar se funde y vuelve el de siempre
        AnimatedSwitcher(
          duration: coverFade,
          child: playing == null
              ? const SizedBox.shrink(key: Key('now-playing-none'))
              : KeyedSubtree(key: ValueKey('now-playing-${playing.file ?? playing.url}'), child: CoverBackdrop(file: playing.file, url: playing.url)),
        ),
        // el oscurecido plano (solo si hay una imagen que oscurecer) y las líneas, siempre
        HackerScreen(dim: path != null || playing != null ? kBackdropDim : 0),
      ],
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

/// Cómo llegan las pantallas empujadas (detalle de tarea, álbum, registro…): suben desde el borde de abajo, con suavidad, tapando la
/// anterior con su propio fondo detrás.
class LayerPageTransitions extends PageTransitionsBuilder {
  const LayerPageTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext? context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    if (route.isFirst) return child;
    final entering = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(entering),
      child: Stack(fit: StackFit.expand, children: [const BackdropLayers(), child]),
    );
  }
}

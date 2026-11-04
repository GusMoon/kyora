import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/audio_engine.dart';
import '../state/player_controller.dart';
import '../theme.dart';
import '../util/cover_color.dart';
import '../util/format.dart';
import 'widgets/cover.dart';
import 'widgets/glass_button.dart';
import 'widgets/queue_disc.dart';

export '../util/format.dart' show clock;

/// El reproductor a pantalla completa: la carátula de fondo, y abajo un disco con las canciones que ya pasaron y las que siguen en
/// el aro, la que suena en la cuña, anterior · pausa · siguiente al centro y la barra de avance. Aleatorio y repetir, arriba.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key, required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final p = player;
        final c = context.colors;
        final width = MediaQuery.sizeOf(context).width;
        final inset = MediaQuery.paddingOf(context).bottom;
        final file = p.coverFileOf(p.current);
        return _CoverTint(
          url: p.current?.coverUrl,
          file: file,
          builder: (context, tint) => Stack(
            children: [
              Positioned.fill(
                child: _Backdrop(
                  coverUrl: p.current?.coverUrl,
                  coverFile: file,
                  tint: tint,
                  coverBottom: QueueDisc.coverBottomFor(width, inset),
                  discFromBottom: QueueDisc.centerFromBottom(width, inset),
                  discRadius: width * QueueDisc.radiusFactor,
                ),
              ),
              Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  leading: Center(
                    child: GlassCircle(
                      child: IconButton(
                        key: const Key('player-close'),
                        tooltip: 'Cerrar',
                        color: Colors.white,
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  ),
                  title: Text('Reproduciendo', style: TextStyle(fontSize: 16, color: c.ink)),
                  centerTitle: true,
                  actions: [
                    GlassCircle(
                      child: IconButton(
                        key: const Key('player-shuffle'),
                        tooltip: p.shuffle ? 'Aleatorio: activado' : 'Aleatorio: apagado',
                        color: p.shuffle ? c.accent : Colors.white,
                        padding: EdgeInsets.zero,
                        iconSize: 21,
                        icon: const Icon(Icons.shuffle_rounded),
                        onPressed: p.toggleShuffle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GlassCircle(
                      child: IconButton(
                        key: const Key('player-repeat'),
                        tooltip: switch (p.repeat) {
                          RepeatKind.off => 'Repetir: apagado',
                          RepeatKind.all => 'Repetir toda la lista',
                          RepeatKind.one => 'Repetir esta canción',
                        },
                        color: p.repeat == RepeatKind.off ? Colors.white : c.accent,
                        padding: EdgeInsets.zero,
                        iconSize: 21,
                        icon: Icon(p.repeat == RepeatKind.one ? Icons.repeat_one_rounded : Icons.repeat_rounded),
                        onPressed: p.cycleRepeat,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
                body: Stack(
                  children: [
                    if (p.error != null)
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: QueueDisc.heightFor(width, inset) + 12,
                        child: Text(p.error!, key: const Key('player-error'), textAlign: TextAlign.center, style: TextStyle(color: c.warn, fontWeight: FontWeight.w600)),
                      ),
                    Positioned(
                      left: 0,
                      bottom: 0,
                      // el color pasa suave de una carátula a otra
                      child: TweenAnimationBuilder<Color?>(
                        tween: ColorTween(end: tint ?? c.accent),
                        duration: const Duration(milliseconds: 450),
                        builder: (context, color, _) => QueueDisc(player: p, width: width, tint: color, bottomInset: inset),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Busca el color de la carátula y se lo da al `builder` cuando lo tiene (antes y sin carátula, `null`).
class _CoverTint extends StatefulWidget {
  const _CoverTint({required this.url, required this.file, required this.builder});

  final String? url;
  final String? file;
  final Widget Function(BuildContext context, Color? tint) builder;

  @override
  State<_CoverTint> createState() => _CoverTintState();
}

class _CoverTintState extends State<_CoverTint> {
  Color? _tint;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_CoverTint old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.file != widget.file) _load();
  }

  Future<void> _load() async {
    final url = widget.url;
    final file = widget.file;
    if (url == null && file == null) {
      if (_tint != null) setState(() => _tint = null);
      return;
    }
    final found = await coverColor(url: url, file: file);
    if (mounted && url == widget.url && file == widget.file) setState(() => _tint = found);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _tint);
}

/// El fondo: la carátula a pantalla completa con un velo oscuro que se cierra hacia abajo (para que se lea el disco). Sin carátula,
/// un degradado con su color.
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.coverUrl,
    required this.coverFile,
    required this.tint,
    required this.coverBottom,
    required this.discFromBottom,
    required this.discRadius,
  });

  final String? coverUrl;

  /// La carátula de una canción del teléfono (imagen incrustada en el .mp3); si hay, manda sobre la de internet.
  final String? coverFile;
  final Color? tint;

  /// Hasta dónde llega la carátula, desde el borde de abajo: solo ocupa lo que se ve por encima del disco, para no estirarse de más.
  final double coverBottom;

  /// Dónde está el disco, para oscurecer muy levemente la carátula justo por fuera de su borde.
  final double discFromBottom;
  final double discRadius;

  /// Hasta dónde llega lo oscuro, más allá del borde del disco.
  static const haloReach = 34.0;

  /// La carátula, de internet o del teléfono. `null` si no hay. Al cambiar de canción la anterior sigue a la vista hasta que la nueva
  /// está lista.
  Widget? _picture({Key? key, required int width}) {
    final url = coverUrl;
    if (coverFile != null) {
      return Image.file(
        File(coverFile!),
        key: key,
        cacheWidth: width,
        gaplessPlayback: true,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      );
    }
    if (url == null) return null;
    return Image.network(
      sharperCover(url),
      key: key,
      cacheWidth: width,
      gaplessPlayback: true,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      // no todos los videos tienen la versión grande: entonces, la normal
      errorBuilder: (context, error, stack) =>
          Image.network(url, cacheWidth: width, fit: BoxFit.cover, filterQuality: FilterQuality.high, errorBuilder: (context, error, stack) => const SizedBox.shrink()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final screen = MediaQuery.sizeOf(context);
    final discCenter = Offset(screen.width / 2, screen.height - discFromBottom);
    final reach = discRadius + haloReach;
    // decodificada al ancho de la pantalla (en píxeles), no al de la imagen original
    final width = (screen.width * MediaQuery.devicePixelRatioOf(context)).round().clamp(200, 1080);
    final sharp = _picture(key: Key(coverFile != null ? 'cover-file-bg' : 'cover-image'), width: width);
    final top = Color.lerp(c.background, tint ?? c.accent, tint == null ? 0.18 : 0.55)!;
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedContainer(
          key: const Key('player-backdrop'),
          duration: const Duration(milliseconds: 500),
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, c.background])),
        ),
        if (sharp != null) Positioned(left: 0, right: 0, top: 0, bottom: coverBottom, child: sharp),
        // un velo suave arriba (para la barra) y que se cierra abajo, donde va el disco; en medio la carátula se ve limpia
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x59000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
              stops: [0.0, 0.14, 0.62, 1.0],
            ),
          ),
        ),
        // se oscurece apenas junto al disco
        CustomPaint(key: const Key('disc-dark'), painter: _HaloPainter(center: discCenter, radius: discRadius, reach: reach)),
      ],
    );
  }
}

/// La sombra alrededor del disco: oscura junto a su borde y desapareciendo al alejarse.
class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.center, required this.radius, required this.reach});

  final Offset center;
  final double radius;
  final double reach;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          reach,
          const [Color(0x33000000), Color(0x33000000), Color(0x00000000)],
          [0, radius / reach, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) => old.center != center || old.radius != radius || old.reach != reach;
}

/// La barra de abajo de la pantalla de música con lo que suena: carátula, título, pausa y siguiente. Al tocarla se abre el
/// reproductor completo. No se dibuja si no hay nada cargado.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final track = player.current;
        if (track == null) return const SizedBox.shrink();
        final total = player.duration.inMilliseconds;
        return Material(
          color: context.colors.plate,
          child: InkWell(
            key: const Key('mini-player'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlayerPage(player: player))),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // el avance se repinta solo, sin reconstruir el resto de la mini-barra
                  ValueListenableBuilder<Duration>(
                    valueListenable: player.positionListenable,
                    builder: (context, position, _) => LinearProgressIndicator(
                      value: total > 0 ? (position.inMilliseconds / total).clamp(0.0, 1.0) : 0.0,
                      minHeight: 2,
                      backgroundColor: context.colors.field,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Row(
                      children: [
                        Cover(url: track.coverUrl, file: player.coverFileOf(track), size: 44, radius: 8),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(splitArtistTitle(track.title).title, key: const Key('mini-title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                player.error ?? (player.loading ? 'Cargando…' : (splitArtistTitle(track.title).artist ?? track.playlist ?? 'Kyora')),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: player.error != null ? context.colors.warn : context.colors.dim),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: const Key('mini-toggle'),
                          tooltip: player.playing ? 'Pausa' : 'Reproducir',
                          iconSize: 30,
                          icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                          onPressed: player.toggle,
                        ),
                        IconButton(
                          key: const Key('mini-next'),
                          tooltip: 'Siguiente',
                          iconSize: 30,
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: player.next,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

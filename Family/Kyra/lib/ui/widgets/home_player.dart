import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/audio_levels.dart';
import '../../data/favorites_store.dart';
import '../../state/player_controller.dart';
import '../../data/audio_engine.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'cover.dart';
import 'cyber_panel.dart';
import 'hack_text.dart';
import 'section_motion.dart';

/// El reproductor de **Inicio**, a todo lo ancho, cuando hay una canción cargada: arriba la portada, el nombre y el artista y, a la derecha, el
/// ecualizador que late con el sonido; debajo la barra de avance con el tiempo que lleva y lo que dura (se toca o se arrastra para adelantar);
/// y abajo los controles —repetir, aleatorio, anterior, **pausa/reproducir** en grande, siguiente, **detener** (el reproductor desaparece), abrir
/// el álbum de la canción y el corazón— entre dos
/// rejillas de puntos como altavoces. Todo en el estilo de Kyra: panel oscuro cuadrado, filos del acento y letra de terminal.
class HomePlayer extends StatelessWidget {
  const HomePlayer({super.key, required this.player, this.favorites, this.onOpenMusic});

  final PlayerController player;

  /// Las favoritas (el corazón). Sin esto no hay corazón.
  final FavoritesController? favorites;

  /// Lleva a la sección de música, al álbum de la canción que suena. Sin esto no hay botón.
  final VoidCallback? onOpenMusic;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([player, ?favorites]),
      builder: (context, _) {
        final track = player.current;
        if (track == null) return const SizedBox.shrink();
        final c = context.colors;
        final named = splitArtistTitle(track.title);
        final status = player.error ?? (player.loading ? 'cargando…' : null);
        final favorite = favorites?.isFavorite(track.durationKey) ?? false;
        return FlyIn(
          edge: MotionEdge.bottom,
          order: 4,
          child: CyberPanel(
            key: const Key('home-player'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Cover(url: track.coverUrl, file: player.coverFileOf(track), size: 64, radius: 0),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            HackText(
                              named.title,
                              textKey: const Key('home-player-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: appFont, fontSize: 18, fontWeight: FontWeight.w700, color: c.ink),
                            ),
                            const SizedBox(height: 2),
                            HackText(
                              (status ?? named.artist ?? track.playlist ?? 'Kyra').toUpperCase(),
                              textKey: const Key('home-player-artist'),
                              order: 1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: monoFont, fontSize: 15, letterSpacing: 1, color: status != null ? c.warn : c.dim),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _Equalizer(player: player),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Progress(player: player),
                  const SizedBox(height: 10),
                  _Controls(player: player, favorite: favorite, hasHeart: favorites != null, onHeart: () => unawaited(favorites?.toggle(track.durationKey)), onOpenMusic: onOpenMusic),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// La barra de avance con los tiempos: se repinta sola con la posición, sin reconstruir el resto de la tarjeta.
class _Progress extends StatelessWidget {
  const _Progress({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = player.duration;
    return ValueListenableBuilder<Duration>(
      valueListenable: player.positionListenable,
      builder: (context, position, _) {
        final value = total.inMilliseconds > 0 ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0) : 0.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                void seekTo(double dx) {
                  if (total <= Duration.zero) return;
                  unawaited(player.seek(total * (dx / box.maxWidth).clamp(0.0, 1.0)));
                }

                return GestureDetector(
                  key: const Key('home-player-bar'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => seekTo(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => seekTo(d.localPosition.dx),
                  child: SizedBox(height: 26, child: CustomPaint(painter: _BarPainter(value: value, accent: c.accent, track: c.edge))),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(clock(position), key: const Key('home-player-position'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.ink)),
                Text(clock(total), key: const Key('home-player-duration'), style: TextStyle(fontFamily: monoFont, fontSize: 15, color: c.dim)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  const _BarPainter({required this.value, required this.accent, required this.track});

  final double value;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final x = (size.width * value).clamp(0.0, size.width);
    canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()..strokeWidth = 2..color = track);
    // las marcas de la regla
    final tick = Paint()..strokeWidth = 1..color = track.withValues(alpha: 0.7);
    for (var i = 0; i <= 20; i++) {
      final tx = size.width * i / 20;
      canvas.drawLine(Offset(tx, y + 4), Offset(tx, y + (i % 5 == 0 ? 9 : 6)), tick);
    }
    canvas.drawLine(Offset(0, y), Offset(x, y), Paint()..strokeWidth = 3..color = accent);
    // la marca de lo que lleva: un bloque cuadrado
    canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: 10, height: 18), Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.value != value || old.accent != accent || old.track != track;
}

/// Los controles, entre dos rejillas de puntos (altavoces): repetir, aleatorio, anterior, pausa/reproducir, siguiente, abrir la música y el corazón.
class _Controls extends StatelessWidget {
  const _Controls({required this.player, required this.favorite, required this.hasHeart, required this.onHeart, this.onOpenMusic});

  final PlayerController player;
  final bool favorite;
  final bool hasHeart;
  final VoidCallback onHeart;
  final VoidCallback? onOpenMusic;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final repeat = player.repeat;
    Widget button(Key key, IconData icon, String label, VoidCallback? onTap, {bool lit = false}) => _Square(key: key, icon: icon, label: label, onTap: onTap, lit: lit);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dots(color: c.edge),
          const SizedBox(width: 8),
          button(const Key('hp-repeat'), repeat == RepeatKind.one ? Icons.repeat_one_rounded : Icons.repeat_rounded, 'Repetir', () => unawaited(player.cycleRepeat()), lit: repeat != RepeatKind.off),
          const SizedBox(width: 6),
          button(const Key('hp-shuffle'), Icons.shuffle_rounded, 'Aleatorio', () => unawaited(player.toggleShuffle()), lit: player.shuffle),
          const SizedBox(width: 6),
          button(const Key('hp-prev'), Icons.skip_previous_rounded, 'Anterior', () => unawaited(player.previous())),
          const SizedBox(width: 6),
          _Square(key: const Key('hp-toggle'), icon: player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, label: player.playing ? 'Pausa' : 'Reproducir', onTap: () => unawaited(player.toggle()), big: true),
          const SizedBox(width: 6),
          button(const Key('hp-next'), Icons.skip_next_rounded, 'Siguiente', () => unawaited(player.next())),
          const SizedBox(width: 6),
          button(const Key('hp-stop'), Icons.stop_rounded, 'Detener', () => unawaited(player.stop())),
          if (onOpenMusic != null) ...[const SizedBox(width: 6), button(const Key('hp-open'), Icons.album_outlined, 'Abrir el álbum de la canción', onOpenMusic)],
          if (hasHeart) ...[const SizedBox(width: 6), button(const Key('hp-heart'), favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, favorite ? 'Quitar de favoritas' : 'Añadir a favoritas', onHeart, lit: favorite)],
          const SizedBox(width: 8),
          _Dots(color: c.edge),
        ],
      ),
    );
  }
}

/// Un botón cuadrado: de contorno fino; encendido (o el principal) va relleno con el acento.
class _Square extends StatelessWidget {
  const _Square({super.key, required this.icon, required this.label, required this.onTap, this.lit = false, this.big = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool lit;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final filled = big || lit;
    final side = big ? 52.0 : 40.0;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(color: filled ? c.accent : Colors.black.withValues(alpha: 0.35), border: Border.all(color: filled ? c.accent : c.edge, width: big ? 1.6 : 1)),
          child: Icon(icon, size: big ? 32 : 22, color: filled ? c.onAccent : c.ink),
        ),
      ),
    );
  }
}

/// Una rejilla de puntitos, como la de un altavoz.
class _Dots extends StatelessWidget {
  const _Dots({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(width: 26, height: 44, child: CustomPaint(painter: _DotsPainter(color)));
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 2.0; x < size.width; x += 5) {
      for (var y = 2.0; y < size.height; y += 5) {
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) => old.color != color;
}

/// El ecualizador: columnas de segmentos cuadrados que suben y bajan con el sonido (la onda que lee `AudioLevels`). Sin sonido, o en pausa,
/// quedan en reposo. Solo escucha mientras suena.
class _Equalizer extends StatefulWidget {
  const _Equalizer({required this.player});

  final PlayerController player;

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer> {
  static const columns = 12;

  final _bars = ValueNotifier<List<double>>(List.filled(columns, 0));
  StreamSubscription<SoundFrame>? _sound;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(_Equalizer old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      old.player.removeListener(_sync);
      _stop(old.player);
      widget.player.addListener(_sync);
      _sync();
    }
  }

  /// Escucha el sonido mientras suena; en pausa lo suelta (y las columnas bajan).
  void _sync() {
    final p = widget.player;
    final levels = p.levels;
    if (p.playing && !_listening && levels != null) {
      _listening = true;
      _sound = levels.frames.listen(_onFrame, onError: (Object _) {});
      p.listenToSound();
    } else if (!p.playing && _listening) {
      _stop(p);
      _bars.value = List.filled(columns, 0);
    }
  }

  void _stop(PlayerController p) {
    if (!_listening) return;
    _listening = false;
    unawaited(_sound?.cancel());
    p.stopListeningToSound();
  }

  void _onFrame(SoundFrame frame) {
    final wave = frame.wave;
    final old = _bars.value;
    final next = List<double>.generate(columns, (i) {
      var v = frame.level * 0.6;
      if (wave.isNotEmpty) {
        final from = i * wave.length ~/ columns;
        final to = ((i + 1) * wave.length ~/ columns).clamp(from + 1, wave.length);
        var sum = 0.0;
        for (var k = from; k < to; k++) {
          sum += wave[k].abs();
        }
        v += sum / (to - from) * 1.6;
      }
      return v.clamp(0.0, 1.0) > old[i] ? v.clamp(0.0, 1.0) : old[i] * 0.8; // sube de golpe, baja con suavidad
    });
    _bars.value = next;
  }

  @override
  void dispose() {
    widget.player.removeListener(_sync);
    _stop(widget.player);
    _bars.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      key: const Key('home-player-eq'),
      width: 86,
      height: 56,
      child: RepaintBoundary(child: CustomPaint(painter: _EqPainter(bars: _bars, on: c.accent, off: c.edge))),
    );
  }
}

class _EqPainter extends CustomPainter {
  _EqPainter({required this.bars, required this.on, required this.off}) : super(repaint: bars);

  final ValueNotifier<List<double>> bars;
  final Color on;
  final Color off;

  static const rows = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final values = bars.value;
    final w = size.width / values.length;
    final h = size.height / rows;
    final lit = Paint()..color = on;
    final idle = Paint()..color = off.withValues(alpha: 0.55);
    final unlit = Paint()..color = off.withValues(alpha: 0.25);
    for (var i = 0; i < values.length; i++) {
      final level = (values[i] * rows).ceil().clamp(0, rows);
      for (var r = 0; r < rows; r++) {
        // en reposo, solo el segmento de abajo, tenue
        final paint = r < level ? lit : (r == 0 && level == 0 ? idle : unlit);
        canvas.drawRect(Rect.fromLTWH(i * w + 1, size.height - (r + 1) * h + 1, w - 2, h - 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EqPainter old) => old.on != on || old.off != off;
}

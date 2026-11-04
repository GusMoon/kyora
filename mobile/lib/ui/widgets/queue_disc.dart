import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/player_controller.dart';
import '../../theme.dart';
import '../../util/format.dart';
import 'sound_rings.dart';

/// El disco de abajo del reproductor, metido por el borde de la pantalla. Arriba, dentro del disco, una luz difuminada que sale del
/// botón de pausa lleva el título de la que suena. En el centro, anterior · pausa · siguiente, con aros que reaccionan al sonido, y
/// abajo la barra de avance, que se mueve a voluntad. Deslizar la parte de arriba pasa a la siguiente o a la anterior.
class QueueDisc extends StatefulWidget {
  const QueueDisc({super.key, required this.player, required this.width, this.tint, this.bottomInset = 0});

  final PlayerController player;

  /// El ancho de la pantalla: el disco es más ancho que ella.
  final double width;

  /// El color de la carátula, para teñir el disco y su luz. Sin él, el color principal de la app.
  final Color? tint;

  /// Lo que tapa la barra de gestos del teléfono por abajo: el disco sube sus controles esa distancia.
  final double bottomInset;

  /// El espacio que queda encima del disco, para su sombra.
  static const band = 16.0;

  /// Lo que mide todo desde el borde de abajo de la pantalla hacia arriba, para colocarle encima lo demás.
  static double heightFor(double width, double bottomInset) => band + width * radiusFactor + 120 + bottomInset;

  /// El radio del disco respecto al ancho de la pantalla.
  static const radiusFactor = 0.675;

  /// A qué altura queda el centro del disco, medida desde el borde de abajo de la pantalla.
  static double centerFromBottom(double width, double bottomInset) => heightFor(width, bottomInset) - band - width * radiusFactor;

  /// Dónde termina el fondo visible, medido desde el borde de abajo: la altura a la que el disco toca los lados. Lo que queda más abajo
  /// lo tapa el disco, así que la carátula no necesita estirarse hasta ahí.
  static double coverBottomFor(double width, double bottomInset) {
    final r = width * radiusFactor;
    return heightFor(width, bottomInset) - band - r + math.sqrt(r * r - width * width / 4);
  }

  @override
  State<QueueDisc> createState() => _QueueDiscState();
}

class _QueueDiscState extends State<QueueDisc> {
  /// Mientras se arrastra la barra, manda el dedo y no lo que llega del motor (de 0 a 1).
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    final c = context.colors;
    final w = widget.width;
    final r = w * QueueDisc.radiusFactor;
    final height = QueueDisc.heightFor(w, widget.bottomInset);
    final cx = w / 2;
    final discCy = QueueDisc.band + r;
    final controlsY = discCy - 8;
    final track = p.current;
    final named = splitArtistTitle(track?.title ?? 'Nada suena');
    final artist = named.artist ?? track?.playlist;
    final totalMs = p.duration.inMilliseconds;
    const timeStyle = TextStyle(color: Colors.white70, fontSize: 12.5, fontFeatures: [FontFeature.tabularFigures()]);
    final tint = widget.tint ?? c.accent;
    final glow = Color.lerp(tint, Colors.white, 0.12)!;
    return SizedBox(
      width: w,
      height: height,
      child: ClipRect(
        child: Stack(
          children: [
            // el cuerpo del disco, su borde iluminado y la luz que sale del botón
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const Key('player-disc'),
                  painter: _DiscPainter(center: Offset(cx, discCy), radius: r, controlsY: controlsY, top: QueueDisc.band, tint: tint, glow: glow),
                ),
              ),
            ),
            // los aros que siguen al sonido
            Positioned(
              left: cx - SoundRings.size / 2,
              top: controlsY - SoundRings.size / 2,
              child: SoundRings(player: p, color: glow),
            ),
            // la canción que suena, en la luz de arriba
            Positioned(
              left: cx - 95,
              top: QueueDisc.band + 34,
              width: 190,
              child: Column(
                children: [
                  Text(
                    named.title,
                    key: const Key('player-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                  ),
                  if (artist != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ),
                ],
              ),
            ),
            // deslizar por arriba cambia de canción (encima de lo escrito, que no tiene gestos; los botones quedan debajo)
            Positioned(
              left: 0,
              top: 0,
              width: w,
              height: QueueDisc.band + 110,
              child: GestureDetector(
                key: const Key('disc-swipe'),
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v < -250) unawaited(p.next());
                  if (v > 250) unawaited(p.previous());
                },
              ),
            ),
            // anterior · pausa · siguiente
            Positioned(
              left: cx - 124 - 24,
              top: controlsY - 24,
              child: IconButton(
                key: const Key('player-previous'),
                tooltip: 'Anterior',
                iconSize: 30,
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.35), fixedSize: const Size(48, 48)),
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: track == null ? null : p.previous,
              ),
            ),
            Positioned(left: cx - 34, top: controlsY - 34, child: _PlayButton(player: p, loadingColor: glow)),
            Positioned(
              left: cx + 124 - 24,
              top: controlsY - 24,
              child: IconButton(
                key: const Key('player-next'),
                tooltip: 'Siguiente',
                iconSize: 30,
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.35), fixedSize: const Size(48, 48)),
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: track == null ? null : p.next,
              ),
            ),
            // la barra de avance
            Positioned(
              left: 18,
              right: 18,
              bottom: 14 + widget.bottomInset,
              // solo esta barra se reconstruye con el avance (unas 5 veces por segundo), no todo el disco
              child: ValueListenableBuilder<Duration>(
                valueListenable: p.positionListenable,
                builder: (context, position, _) {
                  final fraction = totalMs > 0 ? (_dragging ?? position.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;
                  final shown = Duration(milliseconds: (fraction * totalMs).round());
                  return Row(
                children: [
                  Text(clock(shown), key: const Key('player-position'), style: timeStyle),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                        activeTrackColor: glow,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        key: const Key('player-seek'),
                        value: fraction,
                        onChanged: totalMs > 0 ? (value) => setState(() => _dragging = value) : null,
                        onChangeEnd: (value) {
                          setState(() => _dragging = null);
                          unawaited(p.seek(Duration(milliseconds: (value * totalMs).round())));
                        },
                      ),
                    ),
                  ),
                  Text(clock(p.duration), key: const Key('player-duration'), style: timeStyle),
                ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.player, required this.loadingColor});

  final PlayerController player;
  final Color loadingColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 68,
      child: player.loading
          ? Padding(padding: const EdgeInsets.all(20), child: CircularProgressIndicator(key: const Key('player-loading'), strokeWidth: 3, color: loadingColor))
          : IconButton.filled(
              key: const Key('player-toggle'),
              tooltip: player.playing ? 'Pausa' : 'Reproducir',
              iconSize: 38,
              style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              icon: Icon(player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              onPressed: player.hasCurrent ? player.toggle : null,
            ),
    );
  }
}

/// El disco, quieto: su cuerpo oscuro teñido con la carátula, el borde con su iluminación arriba y la luz difuminada que sube del botón.
class _DiscPainter extends CustomPainter {
  _DiscPainter({required this.center, required this.radius, required this.controlsY, required this.top, required this.tint, required this.glow});

  final Offset center;
  final double radius;
  final double controlsY;
  final double top;
  final Color tint;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final disc = Rect.fromCircle(center: center, radius: radius);
    canvas.drawShadow(Path()..addOval(disc), Colors.black, 20, false);
    final body = Color.lerp(Colors.black, tint, 0.30)!;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [Color.lerp(body, Colors.white, 0.06)!.withValues(alpha: 0.97), Colors.black.withValues(alpha: 0.97)], stops: const [0.2, 1.0]).createShader(disc),
    );
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.2),
    );
    canvas.save();
    canvas.clipPath(Path()..addOval(disc));
    // la iluminación del borde superior, por dentro del disco: fuerte arriba y apagándose hacia los lados
    const rimStart = math.pi * 7 / 6;
    const rimEnd = math.pi * 11 / 6;
    final rim = SweepGradient(
      startAngle: rimStart,
      endAngle: rimEnd,
      colors: [glow.withValues(alpha: 0), glow, glow.withValues(alpha: 0)],
    ).createShader(disc);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      rimStart,
      rimEnd - rimStart,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 22
        ..shader = rim
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 1.5),
      rimStart,
      rimEnd - rimStart,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..shader = rim,
    );
    // la luz que sale del botón y se abre hacia arriba, difuminada, hasta donde está el título
    final beam = Path()
      ..moveTo(center.dx - 30, controlsY - 20)
      ..lineTo(center.dx - 108, top + 6)
      ..lineTo(center.dx + 108, top + 6)
      ..lineTo(center.dx + 30, controlsY - 20)
      ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..shader = LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [glow.withValues(alpha: 0.62), glow.withValues(alpha: 0.30)])
            .createShader(Rect.fromLTRB(center.dx - 108, top, center.dx + 108, controlsY))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DiscPainter old) =>
      old.center != center || old.radius != radius || old.controlsY != controlsY || old.top != top || old.tint != tint || old.glow != glow;
}

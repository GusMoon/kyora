import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../state/player_controller.dart';
import '../../theme.dart';
import 'cut_border.dart';
import '../../util/format.dart';
import 'sound_circle.dart';
import '../../util/cover_tint.dart';
import 'vinyl_disc.dart';

/// El disco como reproductor. Un toque reproduce o pausa, y mientras suena gira (más rápido o más lento si se cambió la velocidad). Girarlo con
/// el dedo adelanta o retrocede la canción, y al soltar salta ahí. Mantenerlo presionado sin moverlo abre sus opciones. Por el contorno, la línea
/// blanca del avance; en el centro, el círculo que reacciona al sonido.
///
/// Los toques solo cuentan dentro del círculo: fuera de él pasan a lo que haya debajo.
class DiscPlayer extends StatefulWidget {
  const DiscPlayer({
    super.key,
    required this.id,
    required this.file,
    required this.url,
    required this.icon,
    required this.size,
    required this.active,
    required this.onTap,
    this.onLongPress,
    this.player,
    this.touchKey,
  });

  /// El álbum.
  final String id;
  final String? file;
  final String? url;
  final IconData icon;

  /// El lado de todo el conjunto, con la línea del avance.
  final double size;

  /// La canción que suena es de este álbum: solo entonces gira, avanza la línea y se puede mover la canción.
  final bool active;
  final VoidCallback onTap;

  /// Mantener el dedo quieto sobre el disco (abre sus opciones).
  final VoidCallback? onLongPress;
  final PlayerController? player;

  /// La clave de la zona que se toca.
  final Key? touchKey;

  /// Lo que hay entre el borde del conjunto y el del disco: ahí va la línea del avance.
  static const inset = 10.0;

  /// Lo que se mueve la canción por cada vuelta completa del disco.
  static const perTurn = Duration(seconds: 30);

  /// A cuánto gira mientras suena: 33⅓ vueltas por minuto, en radianes por segundo.
  static const speed = 2 * math.pi * (100 / 3) / 60;

  /// Lo que tarda en coger o perder la velocidad (s).
  static const inertia = 0.35;

  /// A cuánto gira con la velocidad de la canción en `rate` (1 = normal): radianes por segundo.
  static double spinFor(double rate) => speed * rate;

  /// La diferencia entre dos ángulos, por el camino corto: de -π a π. Al cruzar el lado izquierdo del disco `atan2` salta una vuelta entera.
  static double wrapAngle(double difference) => difference - 2 * math.pi * (difference / (2 * math.pi)).roundToDouble();

  /// Dónde cae la canción tras girar el disco `radians` desde `start`: hacia delante (positivo) adelanta, hacia atrás retrocede. Sin salirse
  /// de la canción.
  static Duration seekTarget(Duration start, double radians, Duration length) {
    final moved = perTurn.inMicroseconds * radians / (2 * math.pi);
    final at = start.inMicroseconds + moved.round();
    return Duration(microseconds: at.clamp(0, math.max(0, length.inMicroseconds)));
  }

  @override
  State<DiscPlayer> createState() => _DiscPlayerState();
}

class _DiscPlayerState extends State<DiscPlayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _angle = ValueNotifier(0);
  final ValueNotifier<double> _fraction = ValueNotifier(0);

  /// Dónde caerá la canción si se suelta (mientras se gira con el dedo).
  final ValueNotifier<Duration?> _preview = ValueNotifier(null);

  double _speed = 0;
  Duration _last = Duration.zero;
  bool _held = false;
  double _fingerAngle = 0;
  double _turned = 0;
  Duration _start = Duration.zero;

  PlayerController? get _p => widget.player;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  bool get _spinning => widget.active && (_p?.playing ?? false) && !_held && !_still;

  @override
  void initState() {
    super.initState();
    _listenTo(_p);
  }

  void _listenTo(PlayerController? player) {
    player?.addListener(_sync);
    player?.positionListenable.addListener(_updateFraction);
  }

  void _stopListeningTo(PlayerController? player) {
    player?.removeListener(_sync);
    player?.positionListenable.removeListener(_updateFraction);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(DiscPlayer old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      _stopListeningTo(old.player);
      _listenTo(widget.player);
    }
    _sync();
  }

  void _sync() {
    _updateFraction();
    if ((_spinning || _speed > 0.02) && !_ticker.isActive) {
      _last = Duration.zero;
      unawaited(_ticker.start());
    }
  }

  void _updateFraction() {
    if (_held) return;
    final p = _p;
    _fraction.value = !widget.active || p == null ? 0 : _fractionOf(p.position, p.duration);
  }

  static double _fractionOf(Duration at, Duration length) => length <= Duration.zero ? 0 : (at.inMicroseconds / length.inMicroseconds).clamp(0.0, 1.0);

  void _onTick(Duration elapsed) {
    // tras estar en pausa (la lista abierta) el reloj trae un salto enorme: se acota
    final dt = math.min((elapsed - _last).inMicroseconds / 1e6, 0.25);
    _last = elapsed;
    final goal = _spinning ? DiscPlayer.spinFor(_p?.rate ?? 1) : 0.0;
    _speed += (goal - _speed) * (1 - math.exp(-dt / DiscPlayer.inertia));
    if (!_held) _angle.value += _speed * dt;
    if (goal == 0 && _speed <= 0.02) {
      _speed = 0;
      _ticker.stop();
    }
  }

  // ---- girarlo con el dedo ----

  Offset _centerOf(BuildContext context) => (context.findRenderObject()! as RenderBox).size.center(Offset.zero);

  void _grab(Offset local, Offset center) {
    final p = _p;
    _held = true;
    _speed = 0;
    _turned = 0;
    _fingerAngle = (local - center).direction;
    _start = widget.active && p != null ? p.position : Duration.zero;
    _sync();
  }

  void _turn(Offset local, Offset center) {
    final v = local - center;
    if (v.distance < 12) return; // junto al centro el ángulo da saltos
    final delta = DiscPlayer.wrapAngle(v.direction - _fingerAngle);
    _fingerAngle = v.direction;
    _turned += delta;
    _angle.value += delta;
    final p = _p;
    if (widget.active && p != null && p.duration > Duration.zero) {
      final target = DiscPlayer.seekTarget(_start, _turned, p.duration);
      _preview.value = target;
      _fraction.value = _fractionOf(target, p.duration);
    }
  }

  void _release() {
    final target = _preview.value;
    _held = false;
    _preview.value = null;
    if (target != null) unawaited(_p?.seek(target));
    _sync();
  }

  void _cancel() {
    _held = false;
    _preview.value = null;
    _sync();
  }

  @override
  void dispose() {
    _stopListeningTo(_p);
    _ticker.dispose();
    _angle.dispose();
    _fraction.dispose();
    _preview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vinyl = widget.size - 2 * DiscPlayer.inset;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Stack(
              alignment: Alignment.center,
              children: [
                VinylDisc(id: widget.id, file: widget.file, url: widget.url, icon: widget.icon, size: vinyl, angle: _angle),
                // el sonido y el avance, del color de la portada (como el disco)
                ValueListenableBuilder<Color?>(
                  valueListenable: CoverTints.watch(widget.file ?? widget.url),
                  builder: (context, tint, _) => Stack(
                    alignment: Alignment.center,
                    children: [
                      SoundCircle(player: _p, active: widget.active, size: vinyl * VinylDisc.label * 0.92, color: tint),
                      Positioned.fill(
                        child: RepaintBoundary(child: CustomPaint(key: const Key('disc-progress'), painter: ProgressRingPainter(fraction: _fraction, ink: tint ?? context.colors.accent))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // la zona que se toca: solo el círculo del disco
          Padding(
            padding: const EdgeInsets.all(DiscPlayer.inset),
            child: ClipOval(
              child: Builder(
                builder: (context) => GestureDetector(
                  key: widget.touchKey,
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onTap: widget.onTap,
                  onLongPress: widget.onLongPress,
                  onPanStart: (d) => _grab(d.localPosition, _centerOf(context)),
                  onPanUpdate: (d) => _turn(d.localPosition, _centerOf(context)),
                  onPanEnd: (_) => _release(),
                  onPanCancel: _cancel,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          // el tiempo adonde se va a saltar, mientras se gira
          ValueListenableBuilder<Duration?>(
            valueListenable: _preview,
            builder: (context, at, _) => at == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: const Alignment(0, 0.66),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: ShapeDecoration(color: context.colors.accent, shape: const CutBorder(cut: 7)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          child: Text(
                            '${clock(at)} / ${clock(_p?.duration ?? Duration.zero)}',
                            key: const Key('disc-time'),
                            style: TextStyle(fontFamily: monoFont, color: context.colors.onAccent, fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// La línea del avance, en tinta: un aro de puntos y, encima, el tramo ya sonado (un trazo grueso), desde arriba y en el sentido del reloj,
/// con un cuadro al final. Sin suavizado.
class ProgressRingPainter extends CustomPainter {
  ProgressRingPainter({required this.fraction, this.ink = const Color(0xFF000000)}) : super(repaint: fraction);

  final ValueNotifier<double> fraction;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final rect = Rect.fromCircle(center: c, radius: r);
    // el aro de fondo: una línea fina y tenue
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ink.withValues(alpha: 0.22),
    );
    final f = fraction.value;
    if (f <= 0) return;
    final sweep = f * 2 * math.pi;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = ink,
    );
    canvas.drawCircle(c + Offset.fromDirection(-math.pi / 2 + sweep, r), 6, Paint()..color = ink);
  }

  @override
  bool shouldRepaint(ProgressRingPainter old) => old.fraction != fraction || old.ink != ink;
}

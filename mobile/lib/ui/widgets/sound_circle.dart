import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../data/audio_levels.dart';
import '../../state/player_controller.dart';
import '../../util/sound_shape.dart';

/// El círculo del centro del disco: una línea blanca que se hincha con los bajos y se altera con los golpes (`SoundShape`). En pausa queda
/// lisa. Si no se puede leer el sonido (sin permiso, o el teléfono no lo deja) late suavemente mientras suena; con las animaciones del
/// teléfono desactivadas, quieta. El permiso se pide la primera vez que suena algo aquí, no al abrir el álbum.
class SoundCircle extends StatefulWidget {
  const SoundCircle({super.key, required this.player, required this.active, required this.size});

  final PlayerController? player;

  /// La canción que suena es de este disco.
  final bool active;
  final double size;

  @override
  State<SoundCircle> createState() => _SoundCircleState();
}

class _SoundCircleState extends State<SoundCircle> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker = createTicker(_onTick);
  final SoundShape _shape = SoundShape();
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  StreamSubscription<SoundFrame>? _sound;
  Duration _last = Duration.zero;
  bool _listening = false;

  PlayerController? get _p => widget.player;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  bool get _sounding => widget.active && (_p?.playing ?? false) && !_still;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _p?.addListener(_sync);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(SoundCircle old) {
    super.didUpdateWidget(old);
    if (old.player != widget.player) {
      old.player?.removeListener(_sync);
      _stopListening(old.player);
      widget.player?.addListener(_sync);
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_listening) return;
    if (state == AppLifecycleState.resumed) {
      _p?.resumeSound();
    } else {
      _p?.pauseSound();
    }
  }

  void _sync() {
    if (_sounding && !_listening) {
      final levels = _p?.levels;
      if (levels != null) {
        _listening = true;
        _sound = levels.frames.listen(_shape.add, onError: (Object _) {});
        _p!.listenToSound();
      }
    }
    if ((_sounding || !_shape.atRest) && !_ticker.isActive) {
      _last = Duration.zero;
      unawaited(_ticker.start());
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _shape.tick(dt, active: _sounding, seconds: elapsed.inMicroseconds / 1e6);
    _repaint.value++;
    if (!_sounding && _shape.atRest) _ticker.stop();
  }

  void _stopListening(PlayerController? player) {
    if (!_listening) return;
    _listening = false;
    unawaited(_sound?.cancel());
    player?.stopListeningToSound();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _p?.removeListener(_sync);
    _stopListening(_p);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(key: const Key('sound-circle'), size: Size.square(widget.size), painter: SoundCirclePainter(shape: _shape, repaint: _repaint)),
    );
  }
}

class SoundCirclePainter extends CustomPainter {
  SoundCirclePainter({required this.shape, required Listenable repaint}) : super(repaint: repaint);

  final SoundShape shape;

  /// Lo que ocupa la línea en reposo, del lado del cuadrado: deja sitio para hincharse sin salirse.
  static const rest = 0.34;

  /// Cuántos tramos tiene la línea.
  static const segments = 96;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide * rest;
    final path = Path();
    for (var i = 0; i <= segments; i++) {
      final angle = i / segments * 2 * math.pi;
      final point = c + Offset.fromDirection(angle, shape.radiusAt(angle, base));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    // una sombra debajo, para que la línea se lea sobre cualquier portada
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2
        ..color = const Color(0x59000000),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.9
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(SoundCirclePainter old) => old.shape != shape;
}

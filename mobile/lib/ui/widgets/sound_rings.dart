import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/player_controller.dart';

/// Los aros luminosos alrededor del botón de pausa, que se abren y brillan con el sonido. Si no se puede leer el sonido (sin permiso,
/// o el teléfono no lo deja) laten suavemente mientras suena. En pausa se apagan; con las animaciones del teléfono desactivadas, quietos.
class SoundRings extends StatefulWidget {
  const SoundRings({super.key, required this.player, required this.color});

  final PlayerController player;
  final Color color;

  /// El lado del cuadrado que ocupan.
  static const size = 190.0;

  @override
  State<SoundRings> createState() => _SoundRingsState();
}

class _SoundRingsState extends State<SoundRings> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _ticker = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..addListener(_onTick);
  final ValueNotifier<double> _level = ValueNotifier(0);
  StreamSubscription<double>? _sound;
  double _target = 0;

  /// El sonido más fuerte reciente: la fuerza se mide contra él, para que se mueva igual en canciones suaves y fuertes.
  double _peak = 0;

  /// Menos que esto no es sonido: el teléfono da ceros porque no deja leerlo.
  static const _silent = 0.005;

  PlayerController get _p => widget.player;

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _p.addListener(_apply);
    final levels = _p.levels;
    if (levels != null) {
      _sound = levels.levels.listen(_onSound, onError: (Object _) {});
      unawaited(levels.start());
    }
  }

  /// En segundo plano el sonido no se puede leer (Android lo calla) y medirlo solo gasta batería: se apaga y al volver se enciende.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final levels = _p.levels;
    if (levels == null) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(levels.start());
    } else {
      unawaited(levels.stop());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apply();
  }

  /// Solo se anima cuando hace falta: sonando, o mientras se apaga tras la pausa.
  void _apply() {
    if (_still) {
      _ticker.stop();
      _level.value = 0;
    } else if ((_p.playing || _level.value > 0.01) && !_ticker.isAnimating) {
      _ticker.repeat();
    }
  }

  void _onSound(double value) {
    _peak = math.max(value, _peak * 0.995);
    _target = _peak < _silent ? 0 : (value / math.max(_peak, 0.04)).clamp(0.0, 1.0);
  }

  void _onTick() {
    final double goal;
    if (!_p.playing) {
      goal = 0;
    } else if (_peak >= _silent) {
      goal = _target;
    } else {
      goal = 0.28 + 0.16 * math.sin(_ticker.value * 2 * math.pi); // sin sonido que leer: un latido suave
    }
    final now = _level.value;
    _level.value = now + (goal - now) * (goal > now ? 0.45 : 0.12); // sube rápido y baja despacio
    if (!_p.playing && _level.value <= 0.01) {
      _level.value = 0;
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _p.removeListener(_apply);
    unawaited(_sound?.cancel());
    unawaited(_p.levels?.stop());
    _ticker.dispose();
    _level.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const Key('sound-rings'),
          size: const Size.square(SoundRings.size),
          painter: SoundRingsPainter(level: _level, color: widget.color),
        ),
      ),
    );
  }
}

class SoundRingsPainter extends CustomPainter {
  SoundRingsPainter({required this.level, required this.color}) : super(repaint: level);

  /// La fuerza con que se dibujan, de 0 a 1.
  final ValueNotifier<double> level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final l = level.value;
    canvas.drawCircle(c, size.shortestSide / 2 - 4, Paint()..color = Colors.black.withValues(alpha: 0.55));
    // el resplandor
    canvas.drawCircle(
      c,
      46 + l * 16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12 + l * 10
        ..color = color.withValues(alpha: 0.22 + l * 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    // los aros, cada uno se abre un poco más que el anterior
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(
        c,
        42 + i * 10 + l * (3 + i * 4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6 - i * 0.4
          ..color = color.withValues(alpha: (0.9 - i * 0.2) * (0.5 + 0.5 * l)),
      );
    }
  }

  @override
  bool shouldRepaint(SoundRingsPainter old) => old.level != level || old.color != color;
}

import 'dart:math' as math;
import 'dart:typed_data';

import '../data/audio_levels.dart';

/// La forma que toma el círculo del centro del disco según lo que suena. Los **bajos** lo hinchan, despacio y con amplitud; los **golpes**
/// (cuando la fuerza salta sobre su media reciente) alteran la línea de repente con la onda real, y se calma enseguida. Todo se mide contra
/// lo más fuerte que ha sonado hace poco, para que reaccione igual en una canción suave que en una fuerte.
class SoundShape {
  /// Cuántos puntos de la onda se usan.
  static const points = 48;

  /// Menos que esto no es sonido: el teléfono da ceros porque no deja leerlo.
  static const silent = 0.005;

  /// Lo que se hincha con los bajos (del radio), lo que se altera la línea con un golpe y lo que se mueve solo con los bajos.
  static const swellSize = 0.16;
  static const joltSize = 0.30;
  static const swellRipple = 0.10;

  /// Lo hinchado (0 a 1).
  double swell = 0;

  /// Lo alterado por un golpe (0 a 1).
  double jolt = 0;

  final Float64List _wave = Float64List(points);
  final Float64List _waveGoal = Float64List(points);
  double _peak = 0;
  double _peakBass = 0;
  double _average = 0;
  double _swellGoal = 0;

  /// ¿Se ha podido leer el sonido? Si no, el círculo late sin más.
  bool get heard => _peak >= silent;

  /// ¿Está liso y quieto?
  bool get atRest => swell < 0.005 && jolt < 0.005;

  /// Un nuevo trozo de sonido.
  void add(SoundFrame frame) {
    _peak = math.max(frame.level, _peak * 0.995);
    _peakBass = math.max(frame.bass, _peakBass * 0.99);
    if (!heard) {
      _swellGoal = 0;
      _waveGoal.fillRange(0, points, 0);
      return;
    }
    final strength = (frame.level / math.max(_peak, 0.04)).clamp(0.0, 1.0);
    // sin bajos que leer (hay teléfonos que no dan la FFT) se hincha con la fuerza
    _swellGoal = _peakBass >= silent ? (frame.bass / math.max(_peakBass, 0.02)).clamp(0.0, 1.0) : strength * 0.6;
    // el golpe se mide en crudo contra la media reciente y luego contra el pico: medido ya normalizado, un salto que marca un pico nuevo no se notaría
    final hit = (frame.level - _average * 1.25) / math.max(_peak, 0.04);
    if (hit > 0) jolt = math.max(jolt, math.min(1.0, hit * 2.2));
    _average += (frame.level - _average) * 0.12;

    if (frame.wave.isEmpty) {
      _waveGoal.fillRange(0, points, 0);
      return;
    }
    var top = 0.02;
    for (final sample in frame.wave) {
      top = math.max(top, sample.abs());
    }
    for (var i = 0; i < points; i++) {
      _waveGoal[i] = (frame.wave[i * frame.wave.length ~/ points] / top).clamp(-1.0, 1.0);
    }
  }

  /// Avanza `dt` segundos. `active`: está sonando; `seconds`: el reloj del latido cuando no se puede leer el sonido.
  void tick(double dt, {required bool active, required double seconds}) {
    double rate(double tau) => 1 - math.exp(-dt / tau);
    final double goal;
    if (!active) {
      goal = 0;
    } else if (heard) {
      goal = _swellGoal;
    } else {
      goal = 0.32 + 0.22 * math.sin(seconds * 2 * math.pi / 1.6);
    }
    swell += (goal - swell) * rate(goal > swell ? 0.06 : 0.35);
    jolt *= math.exp(-dt / 0.16);
    final follow = rate(0.05);
    for (var i = 0; i < points; i++) {
      final target = active && heard ? _waveGoal[i] : 0.0;
      _wave[i] += (target - _wave[i]) * follow;
    }
  }

  /// La onda en el ángulo `angle` (rad), de -1 a 1. Va y vuelve (el lado izquierdo es el espejo del derecho), así la línea se cierra sin salto.
  double waveAt(double angle) {
    final turn = (angle / (2 * math.pi)) % 1.0;
    final there = (turn < 0.5 ? turn * 2 : 2 - turn * 2) * (points - 1);
    final i = there.floor();
    final j = math.min(i + 1, points - 1);
    return _wave[i] + (_wave[j] - _wave[i]) * (there - i);
  }

  /// El radio de la línea en ese ángulo, para un círculo de radio `base`.
  double radiusAt(double angle, double base) {
    final hinchado = base * (1 + swellSize * swell);
    return hinchado + base * (swellRipple * swell + joltSize * jolt) * waveAt(angle);
  }
}

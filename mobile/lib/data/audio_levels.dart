import 'package:flutter/services.dart';

/// Un trozo de lo que suena: lo que el disco y los aros del reproductor necesitan para reaccionar.
class SoundFrame {
  const SoundFrame({required this.level, this.bass = 0, this.wave = const []});

  /// Lo que manda `MainActivity.kt`: `[fuerza, bajos, ...la onda]`. Un número suelto es solo la fuerza.
  factory SoundFrame.fromEvent(Object? event) {
    if (event is List) {
      final values = [for (final value in event) (value as num).toDouble()];
      if (values.length < 2) return SoundFrame(level: values.isEmpty ? 0 : values.first);
      return SoundFrame(level: values[0], bass: values[1], wave: values.sublist(2));
    }
    return SoundFrame(level: event is num ? event.toDouble() : 0);
  }

  /// La fuerza del sonido, de 0 a 1.
  final double level;

  /// La fuerza de los bajos (unos 45–190 Hz), sin normalizar.
  final double bass;

  /// La forma de la onda, de -1 a 1, en pocos puntos.
  final List<double> wave;
}

/// Qué tan fuerte suena el audio en cada momento, para que la pantalla reaccione al sonido.
abstract class AudioLevels {
  /// La fuerza del sonido (de 0 a 1), unas 20 veces por segundo, mientras esté encendido.
  Stream<double> get levels;

  /// Fuerza, bajos y onda, con el mismo ritmo.
  Stream<SoundFrame> get frames;

  /// Empieza a escuchar. `false` si no se puede (sin permiso, o el teléfono no lo permite).
  Future<bool> start();

  Future<void> stop();
}

/// El real, con el `Visualizer` de Android (`MainActivity.kt`). Android lo trata como grabar audio y pide ese permiso, pero solo mide
/// lo que suena: no usa el micrófono ni guarda nada.
class AndroidAudioLevels implements AudioLevels {
  static const _channel = MethodChannel('kyora/audio_levels');
  static const _stream = EventChannel('kyora/audio_levels/stream');

  /// Uno solo y compartido: pedir otro al canal dejaría sin datos al que ya estaba escuchando.
  static final Stream<SoundFrame> _frames = _stream.receiveBroadcastStream().map(SoundFrame.fromEvent);

  @override
  Stream<SoundFrame> get frames => _frames;

  @override
  Stream<double> get levels => _frames.map((frame) => frame.level);

  @override
  Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // ya estaba apagado
    } on MissingPluginException {
      // sin código nativo no había nada encendido
    }
  }
}

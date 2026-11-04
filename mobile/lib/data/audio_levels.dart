import 'package:flutter/services.dart';

/// Qué tan fuerte suena el audio en cada momento, para que el reproductor reaccione al sonido.
abstract class AudioLevels {
  /// La fuerza del sonido (de 0 a 1), unas 20 veces por segundo, mientras esté encendido.
  Stream<double> get levels;

  /// Empieza a escuchar. `false` si no se puede (sin permiso, o el teléfono no lo permite).
  Future<bool> start();

  Future<void> stop();
}

/// El real, con el `Visualizer` de Android (`MainActivity.kt`). Android lo trata como grabar audio y pide ese permiso, pero solo mide
/// la fuerza de lo que suena: no usa el micrófono ni guarda nada.
class AndroidAudioLevels implements AudioLevels {
  static const _channel = MethodChannel('kyora/audio_levels');
  static const _stream = EventChannel('kyora/audio_levels/stream');

  @override
  Stream<double> get levels => _stream.receiveBroadcastStream().map((value) => (value as num).toDouble());

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

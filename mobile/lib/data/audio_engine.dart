/// Una canción lista para sonar: su dirección ya firmada y lo que enseñan la pantalla y la notificación.
class QueueItem {
  const QueueItem({required this.id, required this.title, required this.url, this.subtitle, this.artUrl});

  final String id;
  final String title;
  final String url;
  final String? subtitle;
  final String? artUrl;
}

/// Qué hacer al terminar una canción: nada (al final de la cola se detiene), repetir toda la cola o repetir solo esa.
enum RepeatKind { off, all, one }

/// En qué punto está el motor con la canción actual.
enum EngineStatus { idle, loading, buffering, ready, completed }

/// Lo que el reproductor necesita de un motor de audio. El real (`JustAudioEngine`) usa `just_audio` y deja los controles en
/// la notificación; los tests usan uno falso, sin plugins.
abstract class AudioEngine {
  /// La posición de la canción actual dentro de la cola (con el aleatorio activado sigue siendo su lugar en la lista original).
  Stream<int?> get index;

  Stream<bool> get playing;
  Stream<Duration> get position;
  Stream<Duration?> get duration;
  Stream<EngineStatus> get status;

  /// Mensajes de fallo ya explicados (sin red, enlace caducado, archivo roto…).
  Stream<String> get errors;

  /// Carga la cola y se prepara para sonar la de `startIndex` (no empieza hasta `play`).
  Future<void> setQueue(List<QueueItem> items, int startIndex);

  Future<void> play();
  Future<void> pause();

  /// Para del todo y suelta lo que estuviera leyendo. Para volver a sonar hace falta `setQueue`.
  Future<void> stop();

  /// La siguiente de la cola (no hace nada si no hay).
  Future<void> next();

  /// La anterior de la cola. `false` (y no hace nada) si no hay.
  Future<bool> previous();

  Future<void> seek(Duration position);

  /// Activa o desactiva el aleatorio: la canción actual sigue sonando y el resto se mezcla.
  Future<void> setShuffle(bool on);

  /// Cambia lo que pasa al terminar una canción.
  Future<void> setRepeat(RepeatKind mode);

  Future<void> dispose();
}

import 'dart:typed_data';

import '../models/track.dart';

/// Lo que la app necesita de Supabase para la música. La implementación real es `ChatRepository`; los tests usan una falsa.
abstract class MusicBackend {
  /// Las canciones de la cuenta, de la más nueva a la más antigua.
  Future<List<Track>> listTracks({int limit = 200});

  /// Los bytes del MP3 (bucket privado de Storage).
  Future<Uint8List> downloadTrack(String storagePath);

  /// Direcciones temporales (válidas `expiresIn` segundos) para reproducir los MP3: `{ruta de Storage: dirección}`. Las rutas que
  /// no existen se omiten.
  Future<Map<String, String>> signedUrls(List<String> storagePaths, int expiresIn);

  /// Avisa a Supabase de que la canción ya está guardada en este teléfono («Recibido»). Solo después de esto puede borrarse de allí.
  Future<void> confirmReceived(String trackId);

  /// Avisa cada vez que la tabla de canciones cambia (y al conectarse): hay que volver a pedir la lista.
  Stream<void> trackChanges();
}

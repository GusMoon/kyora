import 'dart:typed_data';

import '../models/track.dart';

/// Lo que la app necesita de Supabase para la música. La implementación real es `ChatRepository`; los tests usan una falsa.
abstract class MusicBackend {
  /// Las canciones de la cuenta, de la más nueva a la más antigua.
  Future<List<Track>> listTracks({int limit = 200});

  /// Los bytes del MP3 (bucket privado de Storage).
  Future<Uint8List> downloadTrack(String storagePath);

  /// Avisa cada vez que la tabla de canciones cambia (y al conectarse): hay que volver a pedir la lista.
  Stream<void> trackChanges();
}

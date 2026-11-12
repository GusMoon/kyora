import 'package:flutter/foundation.dart';

import '../models/track.dart';

/// De dónde sale la carátula de las canciones del teléfono (la imagen incrustada en el .mp3). Avisa cuando aparece una nueva.
abstract class ArtSource implements Listenable {
  /// La ruta de la imagen en el teléfono, o `null` si aún no se leyó o no trae.
  String? artOf(Track track);

  /// Se asegura de haber leído la carátula de esa canción (por ejemplo, la que va a sonar).
  Future<void> load(Track track);
}

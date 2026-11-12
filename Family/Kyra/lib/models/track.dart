/// Un .mp3 que hay en la carpeta que elegiste en el teléfono (lo lee el selector de carpetas de Android).
class LocalSong {
  const LocalSong({required this.uri, required this.name, required this.sizeBytes, required this.modified});

  /// La dirección `content://` del archivo (vale mientras Android conserve el permiso de la carpeta).
  final String uri;

  /// El nombre del archivo, con su «.mp3».
  final String name;
  final int sizeBytes;
  final DateTime modified;

  /// El nombre sin la extensión: lo que se enseña como título.
  String get title => name.toLowerCase().endsWith('.mp3') ? name.substring(0, name.length - 4) : name;

  factory LocalSong.fromMap(Map<Object?, Object?> map) => LocalSong(
        uri: map['uri'] as String,
        name: (map['name'] as String?) ?? 'canción.mp3',
        sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
        modified: DateTime.fromMillisecondsSinceEpoch((map['modified'] as num?)?.toInt() ?? 0, isUtc: true),
      );
}

/// Una carpeta dentro de la que elegiste en el teléfono.
class LocalFolder {
  const LocalFolder({required this.uri, required this.name, this.count = 0});

  /// La dirección `content://` de la carpeta.
  final String uri;
  final String name;

  /// Cuántos .mp3 tiene directamente (sin contar sus subcarpetas).
  final int count;

  factory LocalFolder.fromMap(Map<Object?, Object?> map) => LocalFolder(
        uri: map['uri'] as String,
        name: (map['name'] as String?) ?? 'carpeta',
        count: (map['count'] as num?)?.toInt() ?? 0,
      );
}

/// Lo que hay dentro de una carpeta: sus subcarpetas y sus .mp3 (solo los de ese nivel).
class FolderListing {
  const FolderListing({this.folders = const [], this.songs = const []});

  final List<LocalFolder> folders;
  final List<LocalSong> songs;
}

/// El resultado de mover canciones: cuántas se movieron y, de las que no, el motivo (por dirección).
class MoveResult {
  const MoveResult({required this.moved, this.failures = const {}});

  final int moved;
  final Map<String, String> failures;
}

/// Una canción: la que te mandaron (tabla `music_tracks`, se escucha por internet) o un archivo de tu carpeta del teléfono
/// (`localUri`, se escucha directo del archivo).
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.fileName,
    required this.storagePath,
    required this.sizeBytes,
    required this.createdAt,
    this.mimeType = 'audio/mpeg',
    this.playlist,
    this.coverUrl,
    this.localUri,
    this.receivedAt,
  });

  final String id;
  final String title;
  final String fileName;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final String? playlist;

  /// La carátula (una dirección de internet), si la PC la mandó.
  final String? coverUrl;
  final DateTime createdAt;

  /// Si es un archivo del teléfono, su dirección `content://`; si no, `null` (se escucha desde Supabase).
  final String? localUri;

  /// Cuándo confirmaste con «Recibido» que ya la tienes guardada en el teléfono. `null` = aún no.
  final DateTime? receivedAt;

  bool get isLocal => localUri != null;

  /// La misma canción, ya confirmada como recibida.
  Track withReceived(DateTime at) => Track(
        id: id,
        title: title,
        fileName: fileName,
        storagePath: storagePath,
        sizeBytes: sizeBytes,
        createdAt: createdAt,
        mimeType: mimeType,
        playlist: playlist,
        coverUrl: coverUrl,
        localUri: localUri,
        receivedAt: at,
      );

  /// Con qué se recuerda su duración. Un archivo del teléfono, por dirección + tamaño + fecha (si lo cambian, se vuelve a leer);
  /// una recibida, por su id.
  String get durationKey => isLocal ? '$localUri|$sizeBytes|${createdAt.millisecondsSinceEpoch}' : id;

  /// Un archivo de la carpeta del teléfono como canción reproducible.
  factory Track.local(LocalSong song) => Track(
        id: 'local:${song.uri}',
        title: song.title,
        fileName: song.name,
        storagePath: '',
        sizeBytes: song.sizeBytes,
        createdAt: song.modified,
        localUri: song.uri,
      );

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        title: (json['title'] as String?)?.trim().isNotEmpty == true ? json['title'] as String : json['file_name'] as String,
        fileName: json['file_name'] as String,
        storagePath: json['storage_path'] as String,
        mimeType: (json['mime_type'] as String?) ?? 'audio/mpeg',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        playlist: json['playlist'] as String?,
        coverUrl: (json['cover_url'] as String?)?.trim().isEmpty == true ? null : json['cover_url'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        receivedAt: json['received_at'] == null ? null : DateTime.parse(json['received_at'] as String),
      );
}

/// Una canción que la PC bajó con «Descargar» y subió a tu cuenta (tabla `music_tracks`).
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
  });

  final String id;
  final String title;
  final String fileName;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final String? playlist;
  final DateTime createdAt;

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        title: (json['title'] as String?)?.trim().isNotEmpty == true ? json['title'] as String : json['file_name'] as String,
        fileName: json['file_name'] as String,
        storagePath: json['storage_path'] as String,
        mimeType: (json['mime_type'] as String?) ?? 'audio/mpeg',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        playlist: json['playlist'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

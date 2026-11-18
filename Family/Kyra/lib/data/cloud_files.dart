import 'dart:typed_data';

// La nube: los archivos que se han compartido por medio de Supabase y están ahora mismo en el servidor (bucket `chat-files`). Salen de dos
// tablas, que la limpieza automática borra junto con sus archivos (lo mismo que `src/data/cloud.ts` de Merida):
//  - `attachments`: lo que se mandó por el chat (fotos, documentos…), con el dispositivo que lo mandó;
//  - `music_tracks`: las canciones que la PC subió (para ti o para un pasante).

enum CloudKind { image, audio, video, doc, other }

const cloudKindLabel = {
  CloudKind.image: 'Fotos',
  CloudKind.audio: 'Música',
  CloudKind.video: 'Vídeos',
  CloudKind.doc: 'Documentos',
  CloudKind.other: 'Otros',
};

enum CloudSource { chat, music, upload }

final _docExt = RegExp(r'\.(pdf|docx?|xlsx?|pptx?|txt|md|csv|rtf|odt|zip|rar|7z)$', caseSensitive: false);

CloudKind kindOf(String mime, [String name = '']) {
  final m = mime.toLowerCase();
  if (m.startsWith('image/')) return CloudKind.image;
  if (m.startsWith('audio/')) return CloudKind.audio;
  if (m.startsWith('video/')) return CloudKind.video;
  if (m.startsWith('text/') || m == 'application/pdf' || m.contains('officedocument') || m.contains('msword') || m.contains('zip') || _docExt.hasMatch(name)) return CloudKind.doc;
  return CloudKind.other;
}

class CloudFile {
  const CloudFile({
    required this.id,
    required this.source,
    required this.path,
    required this.name,
    required this.mime,
    required this.size,
    required this.at,
    required this.from,
    required this.kind,
    this.messageId,
    this.thumbPath,
  });

  /// `chat:<id>` o `music:<id>`: el mismo archivo no se repite.
  final String id;
  final CloudSource source;
  final String path;
  final String name;
  final String mime;
  final int size;

  /// Cuándo llegó al servidor.
  final DateTime at;

  /// Quién lo mandó o a quién va: «PC», «móvil», «web», «para ti»…
  final String from;
  final CloudKind kind;

  /// Si vino por el chat: el mensaje al que pertenece, y su miniatura si tiene.
  final String? messageId;
  final String? thumbPath;

  CloudFile withFrom(String value) => CloudFile(id: id, source: source, path: path, name: name, mime: mime, size: size, at: at, from: value, kind: kind, messageId: messageId, thumbPath: thumbPath);
}

/// Dónde se guarda lo que se sube a la nube desde el teléfono (el Vault): `<usuario>/cloud/<hora>-<nombre>`. La hora delante evita pisar un
/// archivo con otro del mismo nombre.
String uploadPath(String uid, String name, DateTime now) {
  final safe = name.replaceAll(RegExp(r'[^\w.\- áéíóúÁÉÍÓÚñÑüÜ()]'), '_').trim();
  return '$uid/cloud/${now.toUtc().millisecondsSinceEpoch}-${safe.isEmpty ? 'archivo' : safe}';
}

/// Un archivo subido desde el teléfono, a partir de lo que dice Storage de él (`name`, `id`, `created_at` y `metadata` con `size` y
/// `mimetype`). `uid` es la carpeta del usuario.
CloudFile cloudFileFromUpload(String uid, Map<String, Object?> object) {
  final stored = (object['name'] as String?) ?? 'archivo';
  final dash = stored.indexOf('-');
  final shown = dash > 0 && int.tryParse(stored.substring(0, dash)) != null ? stored.substring(dash + 1) : stored;
  final meta = object['metadata'] is Map ? Map<String, Object?>.from(object['metadata']! as Map) : const <String, Object?>{};
  final mime = (meta['mimetype'] as String?) ?? 'application/octet-stream';
  return CloudFile(
    id: 'upload:${object['id'] ?? stored}',
    source: CloudSource.upload,
    path: '$uid/cloud/$stored',
    name: shown,
    mime: mime,
    size: _int(meta['size']),
    at: _time(object['created_at']),
    from: 'mi nube',
    kind: kindOf(mime, shown),
  );
}

/// El dispositivo que mandó algo, en palabras.
String deviceName(String device) => switch (device) {
      'pc' => 'PC',
      'mobile' || 'phone' || 'kyra' => 'móvil',
      'web' || 'merida' => 'web',
      _ => device,
    };

DateTime _time(Object? v) => DateTime.tryParse('${v ?? ''}')?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

int _int(Object? v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

/// Une las dos listas: un archivo por ruta (una canción para varios pasantes es un solo MP3), lo más nuevo primero. `chat` son las filas de
/// `attachments` (con su `message` anidado) y `tracks` las de `music_tracks`.
List<CloudFile> mergeCloud(List<Map<String, Object?>> chat, List<Map<String, Object?>> tracks, String? me, [Map<String, String> names = const {}, List<CloudFile> uploads = const []]) {
  final byPath = <String, CloudFile>{for (final u in uploads) u.path: u};
  for (final a in chat) {
    final raw = a['message'];
    final msg = raw is List ? (raw.isEmpty ? null : raw.first) : raw;
    final message = msg is Map ? msg : null;
    if (message?['deleted_at'] != null) continue; // un mensaje borrado ya no cuenta
    final path = a['storage_path'] as String?;
    if (path == null) continue;
    final name = (a['file_name'] as String?) ?? 'archivo';
    final mime = (a['mime_type'] as String?) ?? 'application/octet-stream';
    final device = message?['sender_device'] as String?;
    byPath[path] = CloudFile(
      id: 'chat:${a['id']}',
      source: CloudSource.chat,
      path: path,
      name: name,
      mime: mime,
      size: _int(a['size_bytes']),
      at: _time(a['created_at']),
      from: device == null ? 'chat' : deviceName(device),
      kind: kindOf(mime, name),
      messageId: a['message_id'] as String?,
      thumbPath: a['thumb_path'] as String?,
    );
  }
  for (final t in tracks) {
    final recipient = t['recipient_id'] as String?;
    final to = recipient == me ? 'para ti' : (names[recipient] != null ? 'para ${names[recipient]}' : 'para un pasante');
    final path = t['storage_path'] as String?;
    if (path == null) continue;
    final prev = byPath[path];
    if (prev != null) {
      // el mismo MP3 para varios: se muestra una vez, a quién va se junta
      if (!prev.from.contains(to)) byPath[path] = prev.withFrom('${prev.from}, $to');
      continue;
    }
    final fileName = t['file_name'] as String?;
    byPath[path] = CloudFile(
      id: 'music:${t['id']}',
      source: CloudSource.music,
      path: path,
      name: fileName == null || fileName.isEmpty ? '${t['title'] ?? 'canción'}.mp3' : fileName,
      mime: (t['mime_type'] as String?) ?? 'audio/mpeg',
      size: _int(t['size_bytes']),
      at: _time(t['created_at']),
      from: to,
      kind: CloudKind.audio,
    );
  }
  return byPath.values.toList()..sort((a, b) => a.at != b.at ? b.at.compareTo(a.at) : a.id.compareTo(b.id));
}

class CloudTotals {
  const CloudTotals({required this.count, required this.bytes, required this.byKind});

  final int count;
  final int bytes;
  final Map<CloudKind, int> byKind;
}

CloudTotals cloudTotals(List<CloudFile> files) {
  final byKind = {for (final k in CloudKind.values) k: 0};
  var bytes = 0;
  for (final f in files) {
    byKind[f.kind] = byKind[f.kind]! + 1;
    bytes += f.size;
  }
  return CloudTotals(count: files.length, bytes: bytes, byKind: byKind);
}

/// Cuánto hace que llegó, en palabras cortas: «ahora», «hace 5 min», «hace 3 h», «ayer», «12 nov».
String agoLabel(DateTime at, DateTime now) {
  final min = now.difference(at).inMinutes;
  if (min < 1) return 'ahora';
  if (min < 60) return 'hace $min min';
  if (min < 60 * 24) return 'hace ${min ~/ 60} h';
  if (min < 60 * 48) return 'ayer';
  const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  final local = at.toLocal();
  return '${local.day} ${months[local.month - 1]}';
}

/// Lo que pasó al borrar un archivo de la nube.
class CloudDeleteResult {
  const CloudDeleteResult({this.messageDeleted = false});

  /// Si al quitar el archivo el mensaje del chat se quedó vacío (sin texto ni más adjuntos), el mensaje también se borró.
  final bool messageDeleted;
}

/// Lo que la Nube necesita de Supabase. Lanza `ChatException`.
abstract class CloudBackend {
  /// Los archivos que hay ahora en el servidor.
  Future<List<CloudFile>> listCloud();

  /// Una dirección temporal para abrir un archivo (o, con [download], para bajarlo con ese nombre).
  Future<String> cloudUrl(String path, {String? download});

  /// Borra un archivo del servidor **de verdad**: primero el archivo en Storage y luego su fila (así, si algo falla a medias, se puede volver
  /// a intentar). Una canción se quita para todos los que la tenían.
  Future<CloudDeleteResult> deleteCloudFile(CloudFile file);

  /// Sube un archivo a **tu nube** (desde el Vault): queda en tu carpeta del servidor y sale en la lista de la Nube hasta que lo borres.
  Future<void> uploadCloudFile(String name, String mime, Uint8List bytes);
}

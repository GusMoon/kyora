import '../util/format.dart';

/// Cómo va un mensaje: en espera (aún no salió), enviado (Supabase confirmó) o con un error sin remedio.
enum SendState { pending, sent, failed }

/// Un archivo o foto de un mensaje. El formato del servidor es el de `message_json` (supabase/schema.sql).
class Attachment {
  const Attachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.storagePath,
    this.width,
    this.height,
    this.durationMs,
    this.thumbPath,
    this.localPath,
    this.uploaded = false,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int sizeBytes;

  /// `<id_de_usuario>/<conversación>/<mensaje>/<nombre_seguro>` en el bucket `chat-files`.
  final String? storagePath;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? thumbPath;

  /// El archivo en el teléfono (el que se va a subir, o el ya enviado desde aquí).
  final String? localPath;

  /// Ya está subido a Storage (para no volver a subirlo si se reintenta el envío).
  final bool uploaded;

  bool get isImage => mimeType.toLowerCase().startsWith('image/');

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: json['id'] as String,
        fileName: (json['file_name'] as String?) ?? 'archivo',
        mimeType: (json['mime_type'] as String?) ?? 'application/octet-stream',
        sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
        storagePath: json['storage_path'] as String?,
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        durationMs: (json['duration_ms'] as num?)?.toInt(),
        thumbPath: json['thumb_path'] as String?,
        uploaded: json['storage_path'] != null,
      );

  Attachment copyWith({String? storagePath, String? localPath, bool? uploaded}) => Attachment(
        id: id,
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        storagePath: storagePath ?? this.storagePath,
        width: width,
        height: height,
        durationMs: durationMs,
        thumbPath: thumbPath,
        localPath: localPath ?? this.localPath,
        uploaded: uploaded ?? this.uploaded,
      );

  /// Lo que `send_message` espera de cada adjunto (`p_attachments`).
  Map<String, dynamic> toRpc() => {
        'storage_path': storagePath,
        'file_name': fileName,
        'mime_type': mimeType,
        'size_bytes': sizeBytes,
        'width': width,
        'height': height,
        'duration_ms': durationMs,
        'thumb_path': thumbPath,
      };
}

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.device,
    required this.kind,
    required this.state,
    required this.sentAt,
    this.body,
    this.createdAt,
    this.attachments = const [],
    this.error,
  });

  final String id;
  final String conversationId;

  /// El dispositivo que lo mandó (`pc`, `movil`...): decide de qué lado se ve.
  final String device;
  final String kind;
  final String? body;
  final SendState state;

  /// La hora de envío, según el dispositivo que lo mandó.
  final DateTime sentAt;

  /// La hora en que llegó al servidor (null si aún no salió de este teléfono).
  final DateTime? createdAt;
  final List<Attachment> attachments;
  final String? error;

  bool get hasText => (body ?? '').trim().isNotEmpty;
  bool get isPending => state == SendState.pending;

  /// Un mensaje del servidor (`message_json`): ya enviado, salvo que traiga `status: pending`.
  factory Message.fromJson(Map<String, dynamic> json) {
    final created = json['created_at'] as String?;
    return Message(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      device: (json['sender_device'] as String?) ?? 'unknown',
      kind: (json['kind'] as String?) ?? 'text',
      body: json['body'] as String?,
      state: json['status'] == 'pending' ? SendState.pending : SendState.sent,
      sentAt: DateTime.parse((json['sent_at'] ?? json['created_at']) as String).toUtc(),
      createdAt: created == null ? null : DateTime.parse(created).toUtc(),
      attachments: [
        for (final item in (json['attachments'] as List<dynamic>? ?? const []))
          Attachment.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }

  /// Un mensaje nuevo escrito aquí: nace en espera.
  factory Message.draft({
    required String id,
    required String conversationId,
    required String device,
    required DateTime sentAt,
    String? body,
    List<Attachment> attachments = const [],
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        device: device,
        kind: attachments.isEmpty ? 'text' : kindOfMime(attachments.first.mimeType),
        body: (body ?? '').trim().isEmpty ? null : body!.trim(),
        state: SendState.pending,
        sentAt: sentAt.toUtc(),
        attachments: attachments,
      );

  Message copyWith({
    String? conversationId,
    SendState? state,
    List<Attachment>? attachments,
    String? error,
    bool clearError = false,
  }) =>
      Message(
        id: id,
        conversationId: conversationId ?? this.conversationId,
        device: device,
        kind: kind,
        body: body,
        state: state ?? this.state,
        sentAt: sentAt,
        createdAt: createdAt,
        attachments: attachments ?? this.attachments,
        error: clearError ? null : (error ?? this.error),
      );
}

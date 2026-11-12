import 'dart:typed_data';

import '../models/message.dart';

/// Un fallo del chat ya explicado en español. `retryable`: tiene sentido volver a intentarlo (sin conexión, error del
/// servidor...); si no (credenciales mal, archivo rechazado...), el mensaje se queda con su error hasta que se reintente a mano.
class ChatException implements Exception {
  const ChatException(this.message, {this.retryable = false, this.code});

  final String message;
  final bool retryable;
  final String? code;

  @override
  String toString() => message;
}

/// Lo que avisa Realtime: se conectó (o se reconectó), algo cambió en la base de datos, un mensaje se borró o se cortó.
enum SignalKind { connected, changed, deleted, disconnected }

class BackendSignal {
  const BackendSignal(this.kind, [this.messageId]);

  final SignalKind kind;
  final String? messageId;
}

/// Todo lo que la app necesita de Supabase. La implementación real es `ChatRepository`; los tests usan una falsa.
abstract class ChatBackend {
  /// El id del usuario con sesión (la primera carpeta de la ruta de Storage).
  String? get userId;

  /// La conversación «General» (se crea la primera vez). Devuelve su id.
  Future<String> ensureConversation();

  /// El historial, del más antiguo al más nuevo. `before`: solo lo enviado antes de esa hora; `after`: solo lo que llegó
  /// al servidor después de esa hora (para ponerse al día).
  Future<List<Message>> listMessages(String conversationId, {DateTime? before, DateTime? after, int limit = 50});

  /// Envía un mensaje (con sus adjuntos ya subidos). El `id` lo crea el dispositivo: repetir la llamada no duplica.
  Future<Message> sendMessage({
    required String id,
    required String conversationId,
    required DateTime sentAt,
    required String device,
    String? body,
    List<Attachment> attachments = const [],
  });

  /// Sube un archivo a `chat-files/<storagePath>`.
  Future<void> upload(String storagePath, Uint8List bytes, String mime);

  Future<void> deleteMessage(String id);

  /// Una dirección temporal para ver o bajar un archivo del bucket privado.
  Future<String> signedUrl(String storagePath);

  /// Los avisos de Realtime de la conversación. Se conecta al escuchar y se desconecta al cancelar.
  Stream<BackendSignal> signals(String conversationId);
}

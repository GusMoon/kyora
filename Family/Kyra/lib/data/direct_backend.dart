import '../models/message.dart';
import '../models/profile.dart';
import 'chat_backend.dart';

/// Una persona a la que se le puede escribir: su id, nombre de usuario, rol y si está en línea.
class ChatUser {
  const ChatUser({required this.id, required this.username, this.role = Role.intern, this.online = false});

  final String id;
  final String username;
  final Role role;
  final bool online;

  factory ChatUser.fromJson(Map<String, dynamic> json) => ChatUser(
        id: json['id'] as String,
        username: (json['username'] as String?) ?? 'alguien',
        role: roleFromName(json['role'] as String?),
        online: (json['online'] as bool?) ?? false,
      );
}

/// Un mensaje del chat privado (`dm_messages`). Permanente en el servidor; cada quien puede ocultarlo solo para sí.
class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.body,
    required this.sentAt,
    this.createdAt,
    this.state = SendState.sent,
    this.error,
    this.senderName,
  });

  final String id;
  final String threadId;
  final String senderId;
  final String body;
  final DateTime sentAt;

  /// Cuándo llegó al servidor (`null` mientras sale de este teléfono).
  final DateTime? createdAt;
  final SendState state;
  final String? error;

  /// El nombre de quien lo envió (solo en la supervisión del administrador).
  final String? senderName;

  bool get isPending => state == SendState.pending;

  factory DirectMessage.fromJson(Map<String, dynamic> json) {
    final created = json['created_at'] as String?;
    return DirectMessage(
      id: json['id'] as String,
      threadId: json['thread_id'] as String,
      senderId: json['sender_id'] as String,
      body: (json['body'] as String?) ?? '',
      sentAt: DateTime.parse((json['sent_at'] ?? json['created_at']) as String).toUtc(),
      createdAt: created == null ? null : DateTime.parse(created).toUtc(),
      senderName: json['sender_name'] as String?,
    );
  }

  DirectMessage copyWith({SendState? state, String? error, bool clearError = false}) => DirectMessage(
        id: id,
        threadId: threadId,
        senderId: senderId,
        body: body,
        sentAt: sentAt,
        createdAt: createdAt,
        state: state ?? this.state,
        error: clearError ? null : (error ?? this.error),
        senderName: senderName,
      );
}

/// Una conversación vista por quien la tiene: con quién es, el último mensaje que se le enseña y cuántos no ha leído.
class DirectThread {
  const DirectThread({required this.id, required this.other, this.last, this.unread = 0});

  final String id;
  final ChatUser other;
  final DirectMessage? last;
  final int unread;

  factory DirectThread.fromJson(Map<String, dynamic> json) {
    final last = json['last'];
    return DirectThread(
      id: json['id'] as String,
      other: ChatUser.fromJson(Map<String, dynamic>.from(json['other'] as Map)),
      last: last is Map ? DirectMessage.fromJson(Map<String, dynamic>.from(last)) : null,
      unread: (json['unread'] as num?)?.toInt() ?? 0,
    );
  }

  DirectThread copyWith({DirectMessage? last, int? unread}) => DirectThread(id: id, other: other, last: last ?? this.last, unread: unread ?? this.unread);
}

/// Una conversación en la supervisión del administrador: entre quiénes, cuántos mensajes tiene y cuándo fue el último.
class AdminThread {
  const AdminThread({required this.id, required this.a, required this.b, required this.count, this.lastMessageAt});

  final String id;
  final ChatUser a;
  final ChatUser b;
  final int count;
  final DateTime? lastMessageAt;

  factory AdminThread.fromJson(Map<String, dynamic> json) {
    final last = json['last_message_at'] as String?;
    return AdminThread(
      id: json['id'] as String,
      a: ChatUser.fromJson(Map<String, dynamic>.from(json['a'] as Map)),
      b: ChatUser.fromJson(Map<String, dynamic>.from(json['b'] as Map)),
      count: (json['count'] as num?)?.toInt() ?? 0,
      lastMessageAt: last == null ? null : DateTime.parse(last).toUtc(),
    );
  }
}

/// Un aviso de Realtime del chat privado: qué pasó y, si es un mensaje, de qué conversación, de quién y qué dice.
class DirectSignal {
  const DirectSignal(this.kind, {this.messageId, this.threadId, this.senderId, this.body});

  final SignalKind kind;
  final String? messageId;
  final String? threadId;
  final String? senderId;
  final String? body;
}

/// El chat privado 1 a 1 en Supabase (`Server/supabase/schema.sql` §19). La implementación real es `ChatRepository`; los tests usan una
/// falsa. Los errores llegan como `ChatException` (en español).
abstract class DirectBackend {
  /// El id de quien tiene la sesión.
  String? get userId;

  /// A quién se le puede escribir: todas las cuentas verificadas menos la propia.
  Future<List<ChatUser>> directory();

  /// Abre (o crea) la conversación con esa persona.
  Future<DirectThread> openThread(String userId);

  /// Las conversaciones propias con algo que enseñar, la más reciente primero.
  Future<List<DirectThread>> listThreads();

  /// Los mensajes de una conversación (sin lo oculto ni lo vaciado), del más antiguo al más nuevo.
  Future<List<DirectMessage>> listDirectMessages(String threadId, {DateTime? before, DateTime? after, int limit = 100});

  /// Envía un mensaje. El `id` lo crea el teléfono: repetir la llamada no duplica.
  Future<DirectMessage> sendDirect({required String id, required String threadId, required String body, required DateTime sentAt, required String device});

  /// «Borrar para mí» un mensaje.
  Future<void> hideMessage(String id);

  /// «Vaciar chat» solo para quien llama.
  Future<void> clearThread(String threadId);

  /// Marca como leída la conversación.
  Future<void> markRead(String threadId);

  /// Los avisos de Realtime de los mensajes. Se conecta al escuchar y se desconecta al cancelar.
  Stream<DirectSignal> directSignals();

  // ---------- supervisión: solo el administrador ----------

  Future<List<AdminThread>> adminThreads();
  Future<List<DirectMessage>> adminMessages(String threadId);
  Future<void> adminDeleteMessage(String id);
  Future<void> adminDeleteThread(String threadId);
}

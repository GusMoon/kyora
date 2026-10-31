import 'dart:async';
import 'dart:typed_data';

import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/models/message.dart';

/// Un Supabase de mentira: guarda los mensajes, no duplica por `id`, se puede dejar sin red y manda avisos de Realtime.
class FakeBackend implements ChatBackend {
  FakeBackend({this.uid = 'user-1'});

  final String uid;
  bool offline = false;

  /// El servidor guarda el mensaje pero la respuesta se pierde (la app cree que falló).
  bool loseReplyOnce = false;
  ChatException? sendError;
  ChatException? uploadError;
  ChatException? deleteError;

  final Map<String, Message> remote = {};
  final Set<String> deleted = {};
  final Map<String, Uint8List> uploads = {};
  final List<String> calls = [];
  final List<Map<String, Object?>> listCalls = [];
  final _signals = StreamController<BackendSignal>.broadcast();
  int _tick = 0;

  @override
  String? get userId => uid;

  void emit(BackendSignal signal) => _signals.add(signal);

  /// Un mensaje que "llegó" al servidor desde otro dispositivo (por defecto, la PC).
  Message add(String id, {String? body, String device = 'pc', List<Attachment> attachments = const [], DateTime? sentAt}) {
    _tick++;
    final stamp = DateTime.utc(2026, 10, 30, 10, 0, _tick % 60, _tick ~/ 60);
    final message = Message(
      id: id,
      conversationId: 'conv-1',
      device: device,
      kind: attachments.isEmpty ? 'text' : 'file',
      body: body,
      state: SendState.sent,
      sentAt: sentAt ?? stamp,
      createdAt: stamp,
      attachments: attachments,
    );
    remote[id] = message;
    return message;
  }

  void _needNetwork() {
    if (offline) throw const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
  }

  @override
  Future<String> ensureConversation() async {
    calls.add('ensure');
    _needNetwork();
    return 'conv-1';
  }

  @override
  Future<List<Message>> listMessages(String conversationId, {DateTime? before, DateTime? after, int limit = 50}) async {
    calls.add('list');
    listCalls.add({'before': before, 'after': after, 'limit': limit});
    _needNetwork();
    var rows = remote.values.where((m) => !deleted.contains(m.id)).toList()
      ..sort((a, b) {
        final byTime = a.sentAt.compareTo(b.sentAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    if (before != null) rows = rows.where((m) => m.sentAt.isBefore(before)).toList();
    if (after != null) rows = rows.where((m) => m.createdAt!.isAfter(after)).toList();
    return rows.length > limit ? rows.sublist(rows.length - limit) : rows;
  }

  @override
  Future<Message> sendMessage({
    required String id,
    required String conversationId,
    required DateTime sentAt,
    required String device,
    String? body,
    List<Attachment> attachments = const [],
  }) async {
    calls.add('send:$id');
    _needNetwork();
    final error = sendError;
    if (error != null) {
      sendError = null;
      throw error;
    }
    final existing = remote[id];
    final stored = existing ??
        add(id, body: body, device: device, sentAt: sentAt, attachments: [
          for (var i = 0; i < attachments.length; i++)
            Attachment(
              id: 'att-$id-$i',
              fileName: attachments[i].fileName,
              mimeType: attachments[i].mimeType,
              sizeBytes: attachments[i].sizeBytes,
              storagePath: attachments[i].storagePath,
            ),
        ]);
    if (loseReplyOnce) {
      loseReplyOnce = false;
      throw const ChatException('Se cortó la respuesta', retryable: true, code: 'offline');
    }
    return stored;
  }

  @override
  Future<void> upload(String storagePath, Uint8List bytes, String mime) async {
    calls.add('upload:$storagePath');
    _needNetwork();
    final error = uploadError;
    if (error != null) throw error;
    uploads[storagePath] = bytes;
  }

  @override
  Future<void> deleteMessage(String id) async {
    calls.add('delete:$id');
    _needNetwork();
    final error = deleteError;
    if (error != null) throw error;
    deleted.add(id);
  }

  @override
  Future<String> signedUrl(String storagePath) async {
    calls.add('url:$storagePath');
    return 'https://files.test/$storagePath';
  }

  @override
  Stream<BackendSignal> signals(String conversationId) {
    calls.add('signals');
    return _signals.stream;
  }
}

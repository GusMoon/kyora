import 'dart:async';

import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/direct_backend.dart';
import 'package:kyora_chat/models/profile.dart';

/// El chat privado en memoria, para las pruebas. Guarda los mensajes «del servidor» (que nunca se borran salvo con las funciones del
/// administrador) y, aparte, lo que cada quien ocultó o vació, como el servidor de verdad.
class FakeDirectBackend implements DirectBackend {
  FakeDirectBackend({this.uid = 'user-1', List<ChatUser>? people})
      : everyone = people ??
            const [
              ChatUser(id: 'user-1', username: 'ana'),
              ChatUser(id: 'admin-1', username: 'gustavo', role: Role.admin, online: true),
              ChatUser(id: 'user-2', username: 'luis'),
            ];

  String uid;
  final List<ChatUser> everyone;

  /// Las conversaciones (id → los dos), los mensajes del servidor y lo que ocultó/vació quien llama.
  final Map<String, (String, String)> threads = {};
  final List<DirectMessage> server = [];
  final Set<String> hidden = {};
  final Map<String, DateTime> clearedBefore = {};
  final Map<String, DateTime> readAt = {};

  final List<String> calls = [];
  final List<String> sent = [];
  ChatException? sendError;
  ChatException? listError;
  final _signals = StreamController<DirectSignal>.broadcast();

  @override
  String? get userId => uid;

  void emit(DirectSignal signal) => _signals.add(signal);

  String _threadFor(String a, String b) {
    final pair = a.compareTo(b) < 0 ? (a, b) : (b, a);
    for (final e in threads.entries) {
      if (e.value == pair) return e.key;
    }
    final id = 'th-${pair.$1}-${pair.$2}';
    threads[id] = pair;
    return id;
  }

  ChatUser _person(String id) => everyone.firstWhere((p) => p.id == id, orElse: () => ChatUser(id: id, username: 'alguien'));

  /// Un mensaje que llegó de otra persona (por omisión, de gustavo a quien llama).
  DirectMessage receive(String id, {String body = 'hola', String from = 'admin-1', DateTime? at}) {
    final thread = _threadFor(uid, from);
    final when = at ?? DateTime.now().toUtc();
    final m = DirectMessage(id: id, threadId: thread, senderId: from, body: body, sentAt: when, createdAt: when);
    server.add(m);
    return m;
  }

  Iterable<DirectMessage> _visible(String thread) => server.where(
        (m) => m.threadId == thread && !hidden.contains(m.id) && (clearedBefore[thread] == null || m.createdAt!.isAfter(clearedBefore[thread]!)),
      );

  DirectThread _summary(String id) {
    final pair = threads[id]!;
    final other = pair.$1 == uid ? pair.$2 : pair.$1;
    final visible = _visible(id).toList()..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final read = readAt[id];
    return DirectThread(
      id: id,
      other: _person(other),
      last: visible.lastOrNull,
      unread: visible.where((m) => m.senderId != uid && (read == null || m.createdAt!.isAfter(read))).length,
    );
  }

  @override
  Future<List<ChatUser>> directory() async {
    calls.add('directory');
    return everyone.where((p) => p.id != uid).toList();
  }

  @override
  Future<DirectThread> openThread(String userId) async {
    calls.add('open:$userId');
    return _summary(_threadFor(uid, userId));
  }

  @override
  Future<List<DirectThread>> listThreads() async {
    calls.add('threads');
    final error = listError;
    if (error != null) throw error;
    return [
      for (final id in threads.keys)
        if (threads[id]!.$1 == uid || threads[id]!.$2 == uid)
          if (_summary(id).last != null) _summary(id),
    ];
  }

  @override
  Future<List<DirectMessage>> listDirectMessages(String threadId, {DateTime? before, DateTime? after, int limit = 100}) async {
    calls.add('messages:$threadId');
    final error = listError;
    if (error != null) throw error;
    return _visible(threadId).toList()..sort((a, b) => a.sentAt.compareTo(b.sentAt));
  }

  @override
  Future<DirectMessage> sendDirect({required String id, required String threadId, required String body, required DateTime sentAt, required String device}) async {
    calls.add('send');
    final error = sendError;
    if (error != null) throw error;
    sent.add(body);
    final existing = server.where((m) => m.id == id).firstOrNull;
    if (existing != null) return existing;
    final m = DirectMessage(id: id, threadId: threadId, senderId: uid, body: body, sentAt: sentAt, createdAt: DateTime.now().toUtc());
    server.add(m);
    return m;
  }

  @override
  Future<void> hideMessage(String id) async {
    calls.add('hide:$id');
    hidden.add(id);
  }

  @override
  Future<void> clearThread(String threadId) async {
    calls.add('clear:$threadId');
    clearedBefore[threadId] = DateTime.now().toUtc().add(const Duration(milliseconds: 1));
  }

  @override
  Future<void> markRead(String threadId) async {
    calls.add('read:$threadId');
    readAt[threadId] = DateTime.now().toUtc().add(const Duration(milliseconds: 1));
  }

  @override
  Stream<DirectSignal> directSignals() {
    calls.add('signals');
    return _signals.stream;
  }

  @override
  Future<List<AdminThread>> adminThreads() async {
    calls.add('admin-threads');
    return [
      for (final e in threads.entries)
        AdminThread(id: e.key, a: _person(e.value.$1), b: _person(e.value.$2), count: server.where((m) => m.threadId == e.key).length),
    ];
  }

  @override
  Future<List<DirectMessage>> adminMessages(String threadId) async {
    calls.add('admin-messages:$threadId');
    return server.where((m) => m.threadId == threadId).toList();
  }

  @override
  Future<void> adminDeleteMessage(String id) async {
    calls.add('admin-delete:$id');
    server.removeWhere((m) => m.id == id);
  }

  @override
  Future<void> adminDeleteThread(String threadId) async {
    calls.add('admin-delete-thread:$threadId');
    server.removeWhere((m) => m.threadId == threadId);
    threads.remove(threadId);
  }
}

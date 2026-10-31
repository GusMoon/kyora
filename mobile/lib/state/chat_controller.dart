import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../data/chat_backend.dart';
import '../models/message.dart';
import '../util/format.dart';

enum Connection { connecting, online, offline }

/// Un archivo elegido en el teléfono (foto, archivo...) que sale con el próximo mensaje.
class OutgoingFile {
  OutgoingFile({required this.path, required this.name, required this.size, String? mime})
      : mime = mime ?? lookupMimeType(name) ?? 'application/octet-stream';

  final String path;
  final String name;
  final int size;
  final String mime;
}

class _SignedUrl {
  _SignedUrl(this.future) : created = DateTime.now();

  final Future<String> future;
  final DateTime created;
}

/// El estado del chat: los mensajes (ordenados), la conexión y la bandeja de salida.
///
/// Un mensaje escrito aquí nace «en espera» con su `uuid`; sube sus archivos a Storage y llama a `send_message`. Si no hay
/// red se queda en espera y se reintenta solo (el `uuid` hace que repetir el envío no lo duplique). Lo que llega de la PC
/// entra por Realtime: cada aviso dispara una puesta al día con `list_messages(p_after = última llegada)`, que también
/// recupera lo perdido si se cortó la conexión.
class ChatController extends ChangeNotifier {
  ChatController(
    this.backend, {
    this.device = AppConfig.deviceName,
    this.retryDelay = const Duration(seconds: 5),
    this.catchUpDelay = const Duration(milliseconds: 250),
    this.maxFileBytes = AppConfig.maxFileBytes,
    this.pageSize = AppConfig.pageSize,
    Uuid? uuid,
    DateTime Function()? clock,
  })  : _uuid = uuid ?? const Uuid(),
        _clock = clock ?? DateTime.now;

  final ChatBackend backend;
  final String device;
  final Duration retryDelay;
  final Duration catchUpDelay;
  final int maxFileBytes;
  final int pageSize;
  final Uuid _uuid;
  final DateTime Function() _clock;

  final List<Message> _messages = [];
  final _notices = StreamController<String>.broadcast();
  final Map<String, _SignedUrl> _urls = {};

  String? _conversation;
  DateTime? _lastCreatedAt;
  StreamSubscription<BackendSignal>? _signals;
  Timer? _retryTimer;
  Timer? _catchUpTimer;
  bool _flushing = false;
  bool _catching = false;
  bool _catchAgain = false;
  bool _disposed = false;

  Connection connection = Connection.connecting;
  String? detail;
  bool loadingOlder = false;
  bool hasOlder = true;

  /// Los mensajes, del más antiguo al más nuevo.
  List<Message> get messages => List.unmodifiable(_messages);

  /// Avisos cortos para mostrar al usuario (un archivo rechazado, un borrado que falló...).
  Stream<String> get notices => _notices.stream;

  bool get hasPending => _messages.any((m) => m.state == SendState.pending);

  // ---------- arrancar ----------

  /// Abre la conversación, carga el historial y se queda escuchando lo que llegue.
  Future<void> start() async {
    _setConnection(Connection.connecting);
    try {
      final conversation = await backend.ensureConversation();
      _conversation = conversation;
      final first = await backend.listMessages(conversation, limit: pageSize);
      hasOlder = first.length >= pageSize;
      _merge(first, advance: true);
      await _signals?.cancel();
      _signals = backend.signals(conversation).listen(_onSignal, onError: (_) => _goOffline('Sin conexión con Supabase'));
      _setConnection(Connection.online);
      unawaited(_flush());
    } on ChatException catch (e) {
      _fail(e);
    }
  }

  void _fail(ChatException e) {
    if (e.retryable) {
      _goOffline(e.message);
    } else {
      _setConnection(Connection.offline, e.message);
      _notice(e.message);
    }
  }

  void _goOffline(String why) {
    _setConnection(Connection.offline, why);
    _scheduleRetry();
  }

  void _setConnection(Connection value, [String? why]) {
    if (_disposed) return;
    connection = value;
    detail = value == Connection.offline ? why : null;
    notifyListeners();
  }

  void _scheduleRetry() {
    if (_disposed || (_retryTimer?.isActive ?? false)) return;
    _retryTimer = Timer(retryDelay, () async {
      if (_disposed) return;
      if (_conversation == null) {
        await start();
      } else {
        await _catchUp();
        unawaited(_flush());
      }
    });
  }

  // ---------- lo que llega ----------

  void _onSignal(BackendSignal signal) {
    switch (signal.kind) {
      case SignalKind.connected:
        _setConnection(Connection.online);
        unawaited(_catchUp()); // lo que llegó mientras no se estaba conectado
        unawaited(_flush());
      case SignalKind.changed:
        _catchUpTimer?.cancel();
        _catchUpTimer = Timer(catchUpDelay, () => unawaited(_catchUp()));
      case SignalKind.deleted:
        if (signal.messageId != null) _remove(signal.messageId!);
      case SignalKind.disconnected:
        _goOffline('Sin conexión con Supabase');
    }
  }

  /// Pide al servidor lo que aún no se tiene (todo lo posterior a la última llegada).
  Future<void> _catchUp() async {
    final conversation = _conversation;
    if (conversation == null || _disposed) return;
    if (_catching) {
      _catchAgain = true;
      return;
    }
    _catching = true;
    try {
      do {
        _catchAgain = false;
        for (var round = 0; round < 20; round++) {
          final page = await backend.listMessages(conversation, after: _lastCreatedAt, limit: 200);
          _merge(page, advance: true);
          if (page.length < 200) break;
        }
      } while (_catchAgain);
      if (connection != Connection.online) _setConnection(Connection.online);
    } on ChatException catch (e) {
      _fail(e);
    } finally {
      _catching = false;
    }
  }

  /// Sube a leer lo anterior: pide los mensajes enviados antes del más antiguo que se tiene.
  Future<void> loadOlder() async {
    final conversation = _conversation;
    if (conversation == null || loadingOlder || !hasOlder) return;
    final oldest = _messages.where((m) => m.state == SendState.sent).firstOrNull;
    if (oldest == null) return;
    loadingOlder = true;
    notifyListeners();
    try {
      final page = await backend.listMessages(conversation, before: oldest.sentAt, limit: pageSize);
      hasOlder = page.length >= pageSize;
      _merge(page, advance: false);
    } on ChatException catch (e) {
      _notice(e.message);
    } finally {
      loadingOlder = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Une mensajes del servidor a la lista: los nuevos se añaden, los que ya estaban se sustituyen (un mensaje propio en
  /// espera pasa a enviado) y los borrados se quitan. `advance`: si su hora de llegada mueve el punto de la puesta al día
  /// (no para los envíos propios ni para el historial antiguo: podrían saltarse mensajes de la PC).
  void _merge(List<Message> incoming, {required bool advance}) {
    for (final message in incoming) {
      final index = _messages.indexWhere((m) => m.id == message.id);
      final merged = index >= 0 ? _withLocalFiles(message, _messages[index]) : message;
      if (index >= 0) {
        _messages[index] = merged;
      } else {
        _messages.add(merged);
      }
      final created = message.createdAt;
      if (advance && created != null && (_lastCreatedAt == null || created.isAfter(_lastCreatedAt!))) {
        _lastCreatedAt = created;
      }
    }
    _sort();
    notifyListeners();
  }

  /// El mensaje del servidor, pero conservando el archivo local de cada adjunto (para no volver a bajar lo que se mandó).
  Message _withLocalFiles(Message server, Message local) {
    if (local.attachments.isEmpty) return server;
    final byPath = {for (final a in local.attachments) if (a.storagePath != null) a.storagePath!: a.localPath};
    return server.copyWith(attachments: [
      for (final a in server.attachments) byPath[a.storagePath] == null ? a : a.copyWith(localPath: byPath[a.storagePath]),
    ]);
  }

  void _sort() {
    _messages.sort((a, b) {
      final byTime = a.sentAt.compareTo(b.sentAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
  }

  void _remove(String id) {
    final before = _messages.length;
    _messages.removeWhere((m) => m.id == id);
    if (_messages.length != before) notifyListeners();
  }

  void _replace(Message message) {
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    _messages[index] = message;
    notifyListeners();
  }

  // ---------- enviar ----------

  /// Escribe un mensaje: aparece al instante «en espera» y sale en cuanto se pueda. Lanza `ChatException` si algún archivo
  /// no vale (demasiado grande): en ese caso no se crea nada.
  Message send({String? text, List<OutgoingFile> files = const []}) {
    final body = (text ?? '').trim();
    if (body.isEmpty && files.isEmpty) throw const ChatException('Escribe algo o adjunta un archivo', code: 'empty');
    for (final file in files) {
      if (file.size > maxFileBytes) {
        throw ChatException('«${file.name}» pesa ${humanSize(file.size)}; el máximo es ${maxFileBytes ~/ 1000000} MB',
            code: 'too_big');
      }
    }
    final draft = Message.draft(
      id: _uuid.v4(),
      conversationId: _conversation ?? '',
      device: device,
      sentAt: _clock(),
      body: body,
      attachments: [
        for (final file in files)
          Attachment(
            id: _uuid.v4(),
            fileName: file.name,
            mimeType: file.mime,
            sizeBytes: file.size,
            localPath: file.path,
          ),
      ],
    );
    _messages.add(draft);
    _sort();
    notifyListeners();
    unawaited(_flush());
    return draft;
  }

  /// Vuelve a intentar un mensaje que se quedó con error.
  void retry(String id) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index < 0 || _messages[index].state != SendState.failed) return;
    _messages[index] = _messages[index].copyWith(state: SendState.pending, clearError: true);
    notifyListeners();
    unawaited(_flush());
  }

  /// La bandeja de salida: manda los mensajes en espera, de uno en uno y en orden.
  Future<void> _flush() async {
    if (_flushing || _disposed) return;
    _flushing = true;
    try {
      while (!_disposed) {
        final next = _messages.where((m) => m.state == SendState.pending).firstOrNull;
        if (next == null) break;
        final outcome = await _sendOne(next);
        if (outcome == _Outcome.later) break;
      }
    } finally {
      _flushing = false;
    }
  }

  Future<_Outcome> _sendOne(Message message) async {
    final conversation = _conversation;
    final user = backend.userId;
    if (conversation == null || (message.attachments.isNotEmpty && user == null)) return _Outcome.later;
    try {
      final ready = <Attachment>[];
      for (final att in message.attachments) {
        var current = att;
        if (!att.uploaded) {
          final path = att.storagePath ?? '$user/$conversation/${message.id}/${safeName(att.fileName)}';
          final local = att.localPath;
          if (local == null) throw const ChatException('No encuentro el archivo', code: 'missing_file');
          final Uint8List bytes;
          try {
            bytes = await File(local).readAsBytes();
          } on FileSystemException {
            throw ChatException('No encuentro el archivo «${att.fileName}»', code: 'missing_file');
          }
          await backend.upload(path, bytes, att.mimeType);
          current = att.copyWith(storagePath: path, uploaded: true);
          _replace(message.copyWith(attachments: [
            for (final a in message.attachments) a.id == att.id ? current : a,
          ]));
        }
        ready.add(current);
      }
      final sent = await backend.sendMessage(
        id: message.id,
        conversationId: conversation,
        sentAt: message.sentAt,
        device: device,
        body: message.body,
        attachments: ready,
      );
      final local = _messages.where((m) => m.id == message.id).firstOrNull ?? message;
      _replace(_withLocalFiles(sent, local.copyWith(attachments: ready)));
      if (connection == Connection.offline) _setConnection(Connection.online);
      return _Outcome.sent;
    } on ChatException catch (e) {
      if (e.retryable) {
        _goOffline(e.message);
        return _Outcome.later;
      }
      _replace(message.copyWith(state: SendState.failed, error: e.message));
      return _Outcome.failed;
    }
  }

  // ---------- borrar ----------

  /// Borra un mensaje. Uno que no llegó a salir se quita sin más; uno enviado se borra también en Supabase (y desaparece de
  /// la PC). Si Supabase falla, vuelve a aparecer.
  Future<void> delete(String id) async {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index < 0) return;
    final message = _messages.removeAt(index);
    notifyListeners();
    if (message.state != SendState.sent) return;
    try {
      await backend.deleteMessage(id);
    } on ChatException catch (e) {
      _messages.add(message);
      _sort();
      notifyListeners();
      _notice('No se pudo borrar: ${e.message}');
    }
  }

  // ---------- archivos ----------

  /// La dirección temporal de un adjunto del servidor (se guarda un rato para no pedirla en cada repintado).
  Future<String> urlFor(Attachment attachment) {
    final path = attachment.storagePath;
    if (path == null) return Future.error(const ChatException('El archivo aún no está en Supabase'));
    final cached = _urls[path];
    if (cached != null && DateTime.now().difference(cached.created) < const Duration(minutes: 50)) return cached.future;
    final fresh = _SignedUrl(backend.signedUrl(path));
    _urls[path] = fresh;
    fresh.future.catchError((Object _) {
      _urls.remove(path);
      return '';
    });
    return fresh.future;
  }

  void _notice(String text) {
    if (!_disposed) _notices.add(text);
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _catchUpTimer?.cancel();
    unawaited(_signals?.cancel());
    unawaited(_notices.close());
    super.dispose();
  }
}

enum _Outcome { sent, failed, later }

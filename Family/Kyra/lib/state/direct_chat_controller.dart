import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../data/chat_backend.dart';
import '../data/chat_notifier.dart';
import '../data/direct_backend.dart';
import '../models/message.dart';

/// El chat privado de quien tiene la sesión: sus conversaciones (con los no leídos), a quién puede escribir, y el tiempo real. Abre cada
/// conversación con su propio controlador (`DirectThreadController`) y le pasa lo que llega. Si llega un mensaje con la app en segundo plano
/// (o con otra conversación abierta) avisa con una notificación del teléfono.
class DirectChatsController extends ChangeNotifier {
  DirectChatsController(this._backend, {this.notifier, bool Function()? appInForeground, DateTime Function()? now, String Function()? newId})
      : _foreground = appInForeground ?? _isResumed,
        _now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4());

  final DirectBackend _backend;
  final ChatNotifier? notifier;
  final bool Function() _foreground;
  final DateTime Function() _now;
  final String Function() _newId;

  static bool _isResumed() {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  /// Las conversaciones, la más reciente primero.
  List<DirectThread> threads = const [];

  /// A quién se le puede escribir (se lee al abrir «Nuevo chat»).
  List<ChatUser> people = const [];
  bool loading = true;
  bool loadingPeople = false;
  String? error;
  bool live = false;

  StreamSubscription<DirectSignal>? _signals;
  final Map<String, DirectThreadController> _open = {};

  /// La conversación que está a la vista (sus mensajes no se avisan con notificación).
  String? visibleThread;
  bool _disposed = false;
  bool _refreshing = false;

  String? get userId => _backend.userId;

  /// Todos los no leídos (para el puntito de la barra).
  int get unread => threads.fold(0, (sum, t) => sum + t.unread);

  Future<void> start() async {
    await refresh(first: true);
    _signals ??= _backend.directSignals().listen(_onSignal);
  }

  Future<void> refresh({bool first = false}) async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    if (first) {
      loading = true;
      notifyListeners();
    }
    try {
      threads = await _backend.listThreads();
      error = null;
    } on ChatException catch (e) {
      if (threads.isEmpty) error = e.message;
    } finally {
      _refreshing = false;
      loading = false;
      notifyListeners();
    }
  }

  /// Lee a quién se le puede escribir.
  Future<void> loadPeople() async {
    loadingPeople = true;
    notifyListeners();
    try {
      people = await _backend.directory();
    } on ChatException catch (e) {
      error = e.message;
    } finally {
      loadingPeople = false;
      notifyListeners();
    }
  }

  /// Abre (o crea) la conversación con esa persona y devuelve su controlador.
  Future<DirectThreadController> openWith(ChatUser person) async {
    final existing = threads.where((t) => t.other.id == person.id).firstOrNull;
    final thread = existing ?? await _backend.openThread(person.id);
    return controllerFor(thread);
  }

  /// El controlador de una conversación (uno por conversación, vivo mientras viva este).
  DirectThreadController controllerFor(DirectThread thread) =>
      _open[thread.id] ??= DirectThreadController(_backend, thread, now: _now, newId: _newId, onChanged: _onThreadChanged)..start().ignore();

  /// Algo cambió dentro de una conversación (se leyó, se vació…): se vuelve a leer la lista.
  void _onThreadChanged() => unawaited(refresh());

  void _onSignal(DirectSignal signal) {
    switch (signal.kind) {
      case SignalKind.connected:
        live = true;
        notifyListeners();
        unawaited(refresh());
        for (final c in _open.values) {
          unawaited(c.refresh());
        }
      case SignalKind.disconnected:
        live = false;
        notifyListeners();
      case SignalKind.deleted:
        unawaited(refresh());
        for (final c in _open.values) {
          c.removeLocally(signal.messageId);
        }
      case SignalKind.changed:
        final threadId = signal.threadId;
        if (threadId != null) unawaited(_open[threadId]?.refresh());
        unawaited(refresh());
        _maybeNotify(signal);
    }
  }

  /// Un mensaje ajeno que llega con la app en segundo plano, o de otra conversación que la que se ve: aviso del teléfono.
  void _maybeNotify(DirectSignal signal) {
    final notifier = this.notifier;
    final sender = signal.senderId;
    if (notifier == null || sender == null || sender == userId || signal.body == null) return;
    if (_foreground() && visibleThread == signal.threadId) return;
    final name = threads.where((t) => t.other.id == sender).firstOrNull?.other.username ??
        people.where((p) => p.id == sender).firstOrNull?.username ??
        'Alguien';
    unawaited(notifier.show(threadId: signal.threadId ?? sender, sender: name, body: signal.body!));
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_signals?.cancel());
    for (final c in _open.values) {
      c.dispose();
    }
    _open.clear();
    super.dispose();
  }
}

/// Una conversación: sus mensajes (del más antiguo al más nuevo), enviar (sale en espera al instante y se manda; si falla, se reintenta),
/// «borrar para mí» un mensaje, «vaciar chat» solo para mí y marcar como leída.
class DirectThreadController extends ChangeNotifier {
  DirectThreadController(this._backend, this.thread, {DateTime Function()? now, String Function()? newId, VoidCallback? onChanged})
      : _now = now ?? DateTime.now,
        _newId = newId ?? (() => const Uuid().v4()),
        _onChanged = onChanged; // ignore: prefer_initializing_formals

  final DirectBackend _backend;
  final DirectThread thread;
  final DateTime Function() _now;
  final String Function() _newId;
  final VoidCallback? _onChanged;

  List<DirectMessage> messages = const [];
  bool loading = true;
  String? error;
  bool _disposed = false;
  bool _refreshing = false;

  String? get userId => _backend.userId;
  bool isMine(DirectMessage m) => m.senderId == userId;

  Future<void> start() async {
    loading = true;
    notifyListeners();
    await refresh();
    loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    try {
      final history = await _backend.listDirectMessages(thread.id);
      final serverIds = history.map((m) => m.id).toSet();
      // lo que ya no viene del servidor (lo ocultaste o lo borró el administrador) sale; lo que está en espera se queda
      final kept = messages.where((m) => m.state != SendState.sent || serverIds.contains(m.id)).toList();
      _set(_merge(kept, history));
      error = null;
    } on ChatException catch (e) {
      if (messages.isEmpty) error = e.message;
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  List<DirectMessage> _merge(List<DirectMessage> current, List<DirectMessage> incoming) {
    final byId = <String, DirectMessage>{for (final m in current) m.id: m};
    for (final m in incoming) {
      byId[m.id] = m;
    }
    return byId.values.toList()
      ..sort((a, b) {
        final byTime = a.sentAt.compareTo(b.sentAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
  }

  void _set(List<DirectMessage> next) {
    messages = next;
    notifyListeners();
  }

  /// Escribe un mensaje. Devuelve `false` si no había nada que mandar.
  Future<bool> send(String text) async {
    final body = text.trim();
    final me = userId;
    if (body.isEmpty || me == null) return false;
    final draft = DirectMessage(id: _newId(), threadId: thread.id, senderId: me, body: body, sentAt: _now().toUtc(), state: SendState.pending);
    _set(_merge(messages, [draft]));
    await _deliver(draft);
    return true;
  }

  Future<void> retry(String id) async {
    final m = messages.where((x) => x.id == id).firstOrNull;
    if (m == null || m.state != SendState.failed) return;
    final again = m.copyWith(state: SendState.pending, clearError: true);
    _set(_merge(messages, [again]));
    await _deliver(again);
  }

  Future<void> _deliver(DirectMessage draft) async {
    try {
      final sent = await _backend.sendDirect(id: draft.id, threadId: thread.id, body: draft.body, sentAt: draft.sentAt, device: AppConfig.deviceName);
      _set(_merge(messages, [sent]));
      _onChanged?.call();
    } on ChatException catch (e) {
      _set([for (final m in messages) m.id == draft.id ? m.copyWith(state: SendState.failed, error: e.message) : m]);
    }
  }

  /// «Borrar para mí»: el mensaje deja de verse aquí (el otro lo sigue viendo). Uno en espera o fallido solo se quita de la pantalla.
  Future<void> hide(String id) async {
    final m = messages.where((x) => x.id == id).firstOrNull;
    if (m == null) return;
    final before = messages;
    _set(messages.where((x) => x.id != id).toList());
    if (m.state != SendState.sent) return;
    try {
      await _backend.hideMessage(id);
      _onChanged?.call();
    } on ChatException catch (e) {
      messages = before;
      error = e.message;
      notifyListeners();
    }
  }

  /// «Vaciar chat» solo para mí: todo lo de hasta ahora deja de verse aquí.
  Future<void> clear() async {
    final before = messages;
    _set(messages.where((m) => m.state != SendState.sent).toList());
    try {
      await _backend.clearThread(thread.id);
      _onChanged?.call();
    } on ChatException catch (e) {
      messages = before;
      error = e.message;
      notifyListeners();
    }
  }

  /// La conversación se está viendo: lo que hay se da por leído.
  Future<void> markRead() async {
    try {
      await _backend.markRead(thread.id);
      _onChanged?.call();
    } on ChatException {
      // sin red: se marcará la próxima vez
    }
  }

  /// El administrador borró un mensaje: se quita sin esperar a volver a leer.
  void removeLocally(String? id) {
    if (id == null || !messages.any((m) => m.id == id)) return;
    _set(messages.where((m) => m.id != id).toList());
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// La supervisión del administrador: todas las conversaciones, sus mensajes (también los ocultos) y borrar de verdad.
class DirectSupervisionController extends ChangeNotifier {
  DirectSupervisionController(this._backend);

  final DirectBackend _backend;

  List<AdminThread> threads = const [];
  bool loading = false;
  String? error;
  bool _disposed = false;

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    try {
      threads = await _backend.adminThreads();
      error = null;
    } on ChatException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<List<DirectMessage>> messagesOf(String threadId) => _backend.adminMessages(threadId);

  Future<void> deleteMessage(String id) => _backend.adminDeleteMessage(id);

  Future<void> deleteThread(String threadId) async {
    await _backend.adminDeleteThread(threadId);
    threads = threads.where((t) => t.id != threadId).toList();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

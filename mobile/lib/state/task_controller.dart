import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/chat_backend.dart';
import '../data/task_backend.dart';
import '../data/task_store.dart';
import '../models/task.dart';

/// Cómo va la sincronización con Supabase.
enum SyncState { idle, syncing, offline, error }

/// Las tareas del teléfono. Todo cambio se guarda al instante en la base local (SQLite) y de ahí sube a Supabase cuando hay
/// internet: sin conexión nada se pierde, se sube solo al volver (se reintenta cada 30 s mientras haya algo por subir, y al abrir
/// la pantalla). Lo que cambió en otros dispositivos se baja en la misma pasada; si dos cambian lo mismo, gana el más reciente.
class TaskController extends ChangeNotifier {
  TaskController(
    this._store,
    this._backend, {
    DateTime Function()? now,
    String Function()? newId,
    Duration retry = const Duration(seconds: 30),
  })  : _now = now ?? (() => DateTime.now().toUtc()),
        _newId = newId ?? (() => const Uuid().v4()),
        _retry = retry; // ignore: prefer_initializing_formals

  final TaskStore _store;
  final TaskBackend _backend;
  final DateTime Function() _now;
  final String Function() _newId;
  final Duration _retry;

  List<TaskItem> _tasks = const [];
  List<Tag> _tags = const [];
  List<TaskTag> _links = const [];
  Timer? _timer;
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;

  SyncState syncState = SyncState.idle;

  /// El motivo de la última falla de sincronización, o `null`.
  String? syncError;

  /// Cuántas filas faltan por subir a Supabase.
  int pending = 0;

  /// La última vez que la sincronización terminó bien.
  DateTime? lastSync;
  bool loaded = false;

  /// Las que ya llevan una subtarea no se anidan más: solo hay un nivel.
  static const maxDepth = 1;

  Future<void> start() async {
    await _reload();
    loaded = true;
    _tell();
    _timer = Timer.periodic(_retry, (_) {
      if (pending > 0 || syncState == SyncState.offline || syncState == SyncState.error) unawaited(sync());
    });
    unawaited(sync()); // sin esperarla: las tareas ya se ven del teléfono mientras se ponen al día
  }

  // ---------- lo que se ve ----------

  /// Las tareas de primer nivel: las sin finalizar primero, con entrega la más cercana antes y luego por creación. Con `status`, solo
  /// las de ese estado; con `active`, las que no están finalizadas.
  List<TaskItem> roots({TaskStatus? status, bool active = false, String? tagId}) {
    final out = [
      for (final t in _tasks)
        if (!t.isSub && (status == null || t.status == status) && (!active || !t.isDone) && (tagId == null || _hasTag(t.id, tagId))) t,
    ];
    out.sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      if ((a.due == null) != (b.due == null)) return a.due == null ? 1 : -1;
      if (a.due != null && b.due != null) {
        final byDue = a.due!.compareTo(b.due!);
        if (byDue != 0) return byDue;
      }
      return a.createdAt.compareTo(b.createdAt);
    });
    return out;
  }

  /// Las subtareas de una tarea, en su orden.
  List<TaskItem> subtasksOf(String id) => [for (final t in _tasks) if (t.parentId == id) t]..sort((a, b) => a.position != b.position ? a.position.compareTo(b.position) : a.createdAt.compareTo(b.createdAt));

  TaskItem? byId(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Cuántas subtareas hay y cuántas están finalizadas.
  ({int done, int total}) progress(TaskItem task) {
    final subs = subtasksOf(task.id);
    return (done: subs.where((s) => s.isDone).length, total: subs.length);
  }

  /// Cuántas tareas hay por estado (`null` = las que no están finalizadas).
  int count(TaskStatus? status) => _tasks.where((t) => !t.isSub && (status == null ? !t.isDone : t.status == status)).length;

  List<Tag> get tags => [..._tags]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<Tag> tagsOf(String taskId) {
    final ids = {for (final l in _links) if (l.taskId == taskId) l.tagId};
    return tags.where((t) => ids.contains(t.id)).toList();
  }

  bool _hasTag(String taskId, String tagId) => _links.any((l) => l.taskId == taskId && l.tagId == tagId);

  // ---------- cambios ----------

  /// Una hora nueva para un cambio: siempre posterior a la que ya tenía, para que Supabase no lo tome por viejo.
  DateTime _stamp(DateTime? previous) {
    final now = _now();
    return previous != null && !now.isAfter(previous) ? previous.add(const Duration(milliseconds: 1)) : now;
  }

  Future<void> _put(TaskData changes) async {
    await _store.put(changes);
    await _reload();
    _tell();
    unawaited(sync());
  }

  /// Una tarea nueva (o una subtarea, con `parentId`). Un nombre vacío no crea nada. Lanza `StateError` si se quiere anidar más
  /// de un nivel.
  Future<TaskItem?> add(String name, {String? parentId, String description = '', DateTime? due, int? expectedMin}) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    if (parentId != null && byId(parentId)?.isSub != false) throw StateError('Solo hay un nivel de subtareas.');
    final at = _now();
    final siblings = [for (final t in _tasks) if (t.parentId == parentId) t.position];
    final task = TaskItem(
      id: _newId(),
      parentId: parentId,
      position: siblings.isEmpty ? 0 : siblings.reduce((a, b) => a > b ? a : b) + 1,
      name: clean,
      description: description.trim(),
      due: due,
      expectedMin: expectedMin,
      createdAt: at,
      updatedAt: at,
    );
    await _put(TaskData(tasks: [task]));
    return task;
  }

  /// Guarda lo que se cambió de una tarea (nombre, descripción, entrega, tiempo esperado). Si no cambió nada, no hace nada.
  Future<void> update(TaskItem task, {String? name, String? description, Object? due = _unchanged, Object? expectedMin = _unchanged}) async {
    final current = byId(task.id);
    if (current == null) return;
    final nextName = name?.trim() ?? current.name;
    if (nextName.isEmpty) return; // el nombre no puede quedar vacío
    final next = current.copyWith(
      name: nextName,
      description: description?.trim() ?? current.description,
      due: identical(due, _unchanged) ? current.due : due as DateTime?,
      expectedMin: identical(expectedMin, _unchanged) ? current.expectedMin : expectedMin as int?,
    );
    if (next.name == current.name && next.description == current.description && next.due == current.due && next.expectedMin == current.expectedMin) return;
    await _put(TaskData(tasks: [next.copyWith(updatedAt: _stamp(current.updatedAt))]));
  }

  /// Cambia el estado. «Finalizada» pone la hora de fin y para el cronómetro; salir de ahí la quita (como en el escritorio).
  Future<void> setStatus(TaskItem task, TaskStatus status) async {
    final current = byId(task.id);
    if (current == null || current.status == status) return;
    final at = _now();
    var next = current.copyWith(status: status);
    if (status == TaskStatus.done) {
      final started = current.timerStarted;
      next = next.copyWith(
        finished: at,
        timerStarted: null,
        realS: started == null ? current.realS : current.realS + at.difference(started).inSeconds.clamp(0, 1 << 31).toInt(),
      );
    } else {
      next = next.copyWith(finished: null);
    }
    await _put(TaskData(tasks: [next.copyWith(updatedAt: _stamp(current.updatedAt))]));
  }

  /// Alterna entre finalizada y pendiente (la casilla de la lista).
  Future<void> toggleDone(TaskItem task) => setStatus(task, task.isDone ? TaskStatus.pending : TaskStatus.done);

  /// Borra la tarea y sus subtareas (borrado suave: el borrado también llega a Supabase y a los demás dispositivos).
  Future<void> delete(TaskItem task) async {
    final at = _now();
    final victims = [task, ...subtasksOf(task.id)];
    await _put(TaskData(
      tasks: [for (final t in victims) (byId(t.id) ?? t).copyWith(deletedAt: at, updatedAt: _stamp((byId(t.id) ?? t).updatedAt))],
      links: [for (final l in _links) if (victims.any((t) => t.id == l.taskId)) l.copyWith(deletedAt: at, updatedAt: _stamp(l.updatedAt))],
    ));
  }

  /// Una etiqueta nueva; si ya hay una con ese nombre (sin distinguir mayúsculas) devuelve esa.
  Future<Tag?> createTag(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return null;
    for (final t in _tags) {
      if (t.name.toLowerCase() == clean.toLowerCase()) return t;
    }
    final tag = Tag(id: _newId(), name: clean, color: tagColors[_tags.length % tagColors.length], updatedAt: _now());
    await _put(TaskData(tags: [tag]));
    return tag;
  }

  /// Borra la etiqueta y la quita de todas las tareas.
  Future<void> deleteTag(Tag tag) async {
    final at = _now();
    await _put(TaskData(
      tags: [tag.copyWith(deletedAt: at, updatedAt: _stamp(tag.updatedAt))],
      links: [for (final l in _links) if (l.tagId == tag.id) l.copyWith(deletedAt: at, updatedAt: _stamp(l.updatedAt))],
    ));
  }

  /// Le pone la etiqueta a la tarea, o se la quita si ya la tenía.
  Future<void> toggleTag(String taskId, Tag tag) async {
    final existing = _links.where((l) => l.taskId == taskId && l.tagId == tag.id).firstOrNull;
    if (existing != null) {
      await _put(TaskData(links: [existing.copyWith(deletedAt: _now(), updatedAt: _stamp(existing.updatedAt))]));
      return;
    }
    // puede haber una marca borrada antes: se revive con la hora nueva
    final old = (await _store.dirty()).links.where((l) => l.taskId == taskId && l.tagId == tag.id).firstOrNull;
    await _put(TaskData(links: [TaskTag(taskId: taskId, tagId: tag.id, updatedAt: _stamp(old?.updatedAt))]));
  }

  // ---------- sincronizar ----------

  /// Sube lo pendiente y baja las novedades. Si ya hay una en marcha, pide otra pasada al terminar y espera a la misma (así
  /// `await sync()` siempre vuelve con todo al día). No lanza: el motivo queda en `syncState` y `syncError`.
  Future<void> sync() {
    if (_disposed) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _runSync().whenComplete(() => _running = null);
  }

  Future<void> _runSync() async {
    syncState = SyncState.syncing;
    _tell();
    try {
      do {
        _again = false;
        final dirty = await _store.dirty();
        if (!dirty.isEmpty) {
          await _backend.push(dirty);
          await _store.markClean(dirty);
        }
        await _pull();
      } while (_again && !_disposed);
      syncState = SyncState.idle;
      syncError = null;
      lastSync = _now();
    } on ChatException catch (e) {
      syncState = e.retryable ? SyncState.offline : SyncState.error;
      syncError = e.message;
    } finally {
      if (!_disposed) {
        pending = await _store.dirtyCount();
        await _reload();
        _tell();
      }
    }
  }

  Future<void> _pull() async {
    final remote = await _backend.pull(
      tasksSince: await _store.cursor('tasks'),
      tagsSince: await _store.cursor('tags'),
      linksSince: await _store.cursor('task_tags'),
    );
    if (!remote.isEmpty) await _store.applyRemote(remote);
    Future<void> advance(String table, Iterable<String?> stamps) async {
      DateTime? best;
      for (final raw in stamps) {
        if (raw == null) continue;
        final at = DateTime.tryParse(raw);
        if (at != null && (best == null || at.isAfter(best))) best = at;
      }
      if (best != null) await _store.setCursor(table, best.toUtc().toIso8601String());
    }

    await advance('tasks', remote.tasks.map((t) => t.syncedAt));
    await advance('tags', remote.tags.map((t) => t.syncedAt));
    await advance('task_tags', remote.links.map((l) => l.syncedAt));
  }

  Future<void> _reload() async {
    final data = await _store.load();
    _tasks = data.tasks;
    _tags = data.tags;
    _links = data.links;
    pending = await _store.dirtyCount();
  }

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_store.close());
    super.dispose();
  }
}

const _unchanged = Object();

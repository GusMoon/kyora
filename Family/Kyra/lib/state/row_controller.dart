import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/chat_backend.dart';
import '../data/sync_rows.dart';
import 'task_controller.dart' show SyncState;

/// Una lista de filas (recordatorios, eventos) que vive en el teléfono y se sincroniza con Supabase como las tareas y los hábitos: todo
/// cambio se guarda al instante y de ahí sube cuando hay internet (se reintenta cada 30 s mientras haya algo por subir); lo que cambió en
/// otros dispositivos se baja en la misma pasada y gana el más reciente. Sin [backend] (sin Supabase) solo es local.
abstract class RowController<T extends SyncRow> extends ChangeNotifier {
  RowController(this.store, this.backend, {DateTime Function()? now, Duration retry = const Duration(seconds: 30)})
      : now = now ?? (() => DateTime.now().toUtc()),
        _retry = retry; // ignore: prefer_initializing_formals

  final RowStore<T> store;
  final RowBackend<T>? backend;
  final DateTime Function() now;
  final Duration _retry;

  List<T> _all = const [];
  Timer? _timer;
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;

  SyncState syncState = SyncState.idle;
  String? syncError;
  int pending = 0;
  bool loaded = false;

  /// Cuándo terminó la última puesta al día con Supabase (UTC), o `null` si todavía no hubo ninguna.
  DateTime? lastSync;

  /// Todo lo guardado, también lo borrado (el borrado suave tiene que llegar a Supabase).
  @protected
  List<T> get everything => _all;

  /// Lo que se ve: lo que no está borrado.
  @protected
  List<T> get rows => [for (final r in _all) if (!r.isDeleted) r];

  T? rowById(String id) {
    for (final r in _all) {
      if (r.id == id && !r.isDeleted) return r;
    }
    return null;
  }

  Future<void> start() async {
    _all = await store.load();
    pending = _all.where((r) => r.dirty).length;
    await onRowsChanged();
    loaded = true;
    tell();
    if (backend != null) {
      _timer = Timer.periodic(_retry, (_) {
        if (pending > 0 || syncState == SyncState.offline || syncState == SyncState.error) unawaited(sync());
      });
      unawaited(sync());
    }
  }

  /// Un hook para quien herede: se llama cada vez que cambió la lista (aquí se programan los avisos).
  @protected
  Future<void> onRowsChanged() async {}

  /// Cómo queda una fila que llega de Supabase sobre la local (por defecto, la de Supabase tal cual).
  @protected
  T adopt(T? local, T remote) => remote.fromServer as T;

  /// Una hora de cambio siempre mayor que la anterior de esa fila: Supabase ignora un cambio que no sea más reciente.
  @protected
  DateTime stamp(DateTime? previous) {
    final t = now();
    return previous != null && !t.isAfter(previous) ? previous.add(const Duration(milliseconds: 1)) : t;
  }

  /// Guarda cambios hechos aquí (nuevos, editados o borrados suaves), los deja «por subir» y empieza a subirlos.
  @protected
  Future<void> put(List<T> changes) async {
    final byId = {for (final r in _all) r.id: r};
    for (final c in changes) {
      byId[c.id] = c.withDirty(true) as T;
    }
    _all = byId.values.toList();
    pending = _all.where((r) => r.dirty).length;
    await store.save(_all);
    await onRowsChanged();
    tell();
    unawaited(sync());
  }

  /// Sube lo pendiente y baja las novedades. Pedirla mientras hay una pasada en curso encadena otra al terminar.
  Future<void> sync() {
    final backend = this.backend;
    if (backend == null || _disposed) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _runSync(backend).whenComplete(() => _running = null);
  }

  Future<void> _runSync(RowBackend<T> backend) async {
    do {
      _again = false;
      syncState = SyncState.syncing;
      tell();
      try {
        final dirty = [for (final r in _all) if (r.dirty) r];
        if (dirty.isNotEmpty) {
          await backend.push(dirty);
          // lo que cambió mientras subía (su hora ya es otra) sigue «por subir»
          final current = {for (final r in _all) r.id: r};
          for (final up in dirty) {
            final now = current[up.id];
            if (now != null && now.updatedAt == up.updatedAt) current[up.id] = now.withDirty(false) as T;
          }
          _all = current.values.toList();
        }
        final remote = await backend.pull(await store.cursor());
        if (remote.isNotEmpty) {
          final byId = {for (final r in _all) r.id: r};
          for (final r in remote) {
            final local = byId[r.id];
            if (remoteWins(local: local?.updatedAt, localDirty: local?.dirty ?? false, remote: r.updatedAt)) byId[r.id] = adopt(local, r);
          }
          _all = byId.values.toList();
          DateTime? best;
          for (final r in remote) {
            final at = r.syncedAt == null ? null : DateTime.tryParse(r.syncedAt!);
            if (at != null && (best == null || at.isAfter(best))) best = at;
          }
          if (best != null) await store.setCursor(best.toUtc().toIso8601String());
        }
        await store.save(_all);
        syncState = SyncState.idle;
        syncError = null;
        lastSync = now();
      } on ChatException catch (e) {
        syncState = e.retryable ? SyncState.offline : SyncState.error;
        syncError = e.message;
      } finally {
        pending = _all.where((r) => r.dirty).length;
        if (!_disposed) {
          await onRowsChanged();
          tell();
        }
      }
    } while (_again && !_disposed && syncState == SyncState.idle);
  }

  @protected
  void tell() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

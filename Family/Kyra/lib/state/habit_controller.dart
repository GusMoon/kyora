import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/chat_backend.dart';
import '../data/habit_backend.dart';
import '../data/habit_store.dart';
import '../data/reminder_scheduler.dart';
import '../models/habit.dart';
import 'task_controller.dart' show SyncState;

/// El número del aviso de un hábito un día de la semana. Va en su propio rango (desde 2³⁰), lejos de los recordatorios (que cuentan desde 1), y
/// siempre es el mismo para el mismo hábito y día, así se puede cancelar sin haberlo guardado.
int habitNotifId(String habitId, int weekday) {
  var hash = 0x811C9DC5; // FNV-1a de 32 bits
  for (final unit in habitId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return (1 << 30) + ((hash & 0x3FFFFFF) << 3) + weekday;
}

/// Los hábitos del teléfono. Como las tareas: todo cambio se guarda al instante en la base local y de ahí sube a Supabase cuando hay internet
/// (se reintenta cada 30 s mientras haya algo por subir); lo que cambió en otros dispositivos se baja en la misma pasada y gana el más reciente.
/// Cada hábito con aviso programa una notificación semanal por cada día que toca.
class HabitController extends ChangeNotifier {
  HabitController(
    this._store,
    this._backend, {
    ReminderScheduler? scheduler,
    DateTime Function()? now,
    String Function()? newId,
    Duration retry = const Duration(seconds: 30),
  })  : _scheduler = scheduler, // ignore: prefer_initializing_formals
        _now = now ?? (() => DateTime.now().toUtc()),
        _newId = newId ?? (() => const Uuid().v4()),
        _retry = retry; // ignore: prefer_initializing_formals

  final HabitStore _store;
  final HabitBackend _backend;
  final ReminderScheduler? _scheduler;
  final DateTime Function() _now;
  final String Function() _newId;
  final Duration _retry;

  List<Habit> _all = const [];
  Map<String, HabitCheck> _checks = const {};
  Timer? _timer;
  Future<void>? _running;
  bool _again = false;
  bool _disposed = false;

  /// Lo que hay programado ahora mismo: número del aviso → «título|hora|minuto».
  final Map<int, String> _planned = {};
  bool _plannedOnce = false;

  SyncState syncState = SyncState.idle;
  String? syncError;
  int pending = 0;
  bool loaded = false;

  /// `true` si el teléfono no deja mostrar avisos.
  bool notificationsBlocked = false;

  Future<void> start() async {
    await _reload();
    loaded = true;
    _tell();
    _timer = Timer.periodic(_retry, (_) {
      if (pending > 0 || syncState == SyncState.offline || syncState == SyncState.error) unawaited(sync());
    });
    unawaited(sync());
  }

  // ---------- lo que se ve ----------

  /// Los hábitos sin borrar, en su orden.
  List<Habit> get habits => [for (final h in _all) if (!h.isDeleted) h]..sort((a, b) => a.position != b.position ? a.position.compareTo(b.position) : a.createdAt.compareTo(b.createdAt));

  Habit? byId(String id) {
    for (final h in _all) {
      if (h.id == id && !h.isDeleted) return h;
    }
    return null;
  }

  /// Los hábitos que tocan ese día (por el día de la semana), sin los que se crearon después.
  List<Habit> habitsFor(DateTime day) {
    final local = day.toLocal();
    final date = DateTime(local.year, local.month, local.day);
    return [
      for (final h in habits)
        if (h.on(local.weekday) && !DateTime(h.createdAt.toLocal().year, h.createdAt.toLocal().month, h.createdAt.toLocal().day).isAfter(date)) h,
    ];
  }

  bool isDone(Habit habit, DateTime day) => _checks['${habit.id}|${dayKey(day)}']?.done ?? false;

  /// ¿Es un día que todavía no llega? Esos no se pueden marcar.
  bool isFuture(DateTime day) => dayKey(day).compareTo(dayKey(_now())) > 0;

  // ---------- cambios ----------

  DateTime _stamp(DateTime? previous) {
    final now = _now();
    return previous != null && !now.isAfter(previous) ? previous.add(const Duration(milliseconds: 1)) : now;
  }

  Future<void> _put(HabitData changes) async {
    await _store.put(changes);
    await _reload();
    _tell();
    unawaited(sync());
  }

  /// Un hábito nuevo. Un nombre vacío o sin ningún día no crea nada. Con aviso, pide el permiso de notificaciones.
  Future<Habit?> add(String name, {int weekdays = Habit.everyDay, int? remindAt}) async {
    final clean = name.trim();
    if (clean.isEmpty || weekdays & Habit.everyDay == 0) return null;
    final now = _now();
    final last = _all.isEmpty ? -1 : _all.map((h) => h.position).reduce((a, b) => a > b ? a : b);
    final habit = Habit(id: _newId(), name: clean, weekdays: weekdays & Habit.everyDay, remindAt: remindAt, position: last + 1, createdAt: now, updatedAt: now);
    if (remindAt != null) await _askPermission();
    await _put(HabitData(habits: [habit]));
    return habit;
  }

  Future<void> update(Habit habit, {String? name, int? weekdays, Object? remindAt = _unchanged}) async {
    final current = byId(habit.id) ?? habit;
    final clean = name?.trim();
    if (clean != null && clean.isEmpty) return;
    if (weekdays != null && weekdays & Habit.everyDay == 0) return;
    final next = identical(remindAt, _unchanged)
        ? current.copyWith(name: clean, weekdays: weekdays, updatedAt: _stamp(current.updatedAt))
        : current.copyWith(name: clean, weekdays: weekdays, remindAt: remindAt, updatedAt: _stamp(current.updatedAt));
    if (next.remindAt != null && current.remindAt == null) await _askPermission();
    await _put(HabitData(habits: [next]));
  }

  /// Borra el hábito (borrado suave: llega también a Supabase y a los demás dispositivos) y cancela sus avisos.
  Future<void> delete(Habit habit) async {
    final current = byId(habit.id) ?? habit;
    await _put(HabitData(habits: [current.copyWith(deletedAt: _now(), updatedAt: _stamp(current.updatedAt))]));
  }

  /// Lo marca como hecho ese día, o lo desmarca. Un día que todavía no llega no se marca. Devuelve si cambió.
  Future<bool> toggle(Habit habit, DateTime day) async {
    if (isFuture(day)) return false;
    final key = dayKey(day);
    final previous = _checks['${habit.id}|$key'];
    await _put(HabitData(checks: [HabitCheck(habitId: habit.id, day: key, done: !(previous?.done ?? false), updatedAt: _stamp(previous?.updatedAt))]));
    return true;
  }

  Future<void> _askPermission() async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    try {
      notificationsBlocked = !await scheduler.ensurePermissions();
    } catch (_) {
      notificationsBlocked = true;
    }
  }

  // ---------- avisos ----------

  /// Deja programado exactamente lo que toca: un aviso semanal por cada día de cada hábito con aviso; lo demás se cancela. Solo llama al
  /// teléfono para lo que cambió.
  Future<void> _plan() async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    try {
      for (final h in _all) {
        for (var weekday = 1; weekday <= 7; weekday++) {
          final id = habitNotifId(h.id, weekday);
          final at = h.remindAt;
          final wanted = !h.isDeleted && at != null && h.on(weekday) ? '${h.name}|${at ~/ 60}|${at % 60}' : null;
          if (_plannedOnce && _planned[id] == wanted) continue;
          if (wanted == null) {
            if (_planned.containsKey(id) || !_plannedOnce) await scheduler.cancel(id);
            _planned.remove(id);
          } else {
            await scheduler.scheduleWeekly(id: id, title: h.name, weekday: weekday, hour: at! ~/ 60, minute: at % 60);
            _planned[id] = wanted;
          }
        }
      }
      _plannedOnce = true;
    } catch (_) {
      notificationsBlocked = true; // sin notificaciones los hábitos se siguen viendo y marcando
    }
  }

  // ---------- sincronización ----------

  Future<void> sync() {
    if (_disposed) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _runSync().whenComplete(() => _running = null);
  }

  /// Pasadas hasta que no quede nada pedido. Lo que se pide mientras una pasada recarga (al final) también cuenta: si no, un cambio hecho
  /// justo entonces esperaría al siguiente reintento.
  Future<void> _runSync() async {
    do {
      _again = false;
      syncState = SyncState.syncing;
      _tell();
      try {
        final dirty = await _store.dirty();
        if (!dirty.isEmpty) {
          await _backend.pushHabits(dirty);
          await _store.markClean(dirty);
        }
        await _pull();
        syncState = SyncState.idle;
        syncError = null;
      } on ChatException catch (e) {
        syncState = e.retryable ? SyncState.offline : SyncState.error;
        syncError = e.message;
      } finally {
        if (!_disposed) {
          await _reload();
          _tell();
        }
      }
    } while (_again && !_disposed && syncState == SyncState.idle);
  }

  Future<void> _pull() async {
    final remote = await _backend.pullHabits(habitsSince: await _store.cursor('habits'), checksSince: await _store.cursor('habit_checks'));
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

    await advance('habits', remote.habits.map((h) => h.syncedAt));
    await advance('habit_checks', remote.checks.map((c) => c.syncedAt));
  }

  Future<void> _reload() async {
    final data = await _store.load();
    _all = data.habits;
    _checks = {for (final c in data.checks) c.key: c};
    pending = await _store.dirtyCount();
    if (!_disposed) await _plan();
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

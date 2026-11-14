import 'package:uuid/uuid.dart';

import '../data/reminder_scheduler.dart';
import '../data/reminder_store.dart';
import '../data/sync_rows.dart';
import '../models/reminder.dart';
import 'row_controller.dart';

/// Los recordatorios: se guardan en el teléfono y se sincronizan con Supabase (ver [RowController]), y cada uno programa su aviso en Android
/// para que suene a su hora aunque la app esté cerrada. Al abrir la app se vuelven a programar los pendientes, por si el sistema los perdió.
class ReminderController extends RowController<Reminder> {
  ReminderController(ReminderStore store, this._scheduler, {RowBackend<Reminder>? backend, super.now, super.retry, String Function()? newId})
      : _newId = newId ?? (() => const Uuid().v4()),
        super(store, backend);

  final ReminderScheduler _scheduler;
  final String Function() _newId;

  /// Lo que hay programado ahora mismo: número del aviso → «título|hora».
  final Map<int, String> _planned = {};
  bool _plannedOnce = false;

  /// `true` si el teléfono no deja mostrar avisos (permiso negado): los recordatorios se guardan pero no sonarán.
  bool notificationsBlocked = false;

  /// Los pendientes por hora (el más próximo primero) y luego los hechos (el más reciente primero).
  List<Reminder> get items {
    final all = rows;
    final pending = [for (final r in all) if (!r.done) r]..sort((a, b) => a.at.compareTo(b.at));
    final done = [for (final r in all) if (r.done) r]..sort((a, b) => b.at.compareTo(a.at));
    return [...pending, ...done];
  }

  bool isOverdue(Reminder r) => !r.done && !r.at.isAfter(now());

  @override
  Future<void> start() async {
    try {
      await _scheduler.init();
    } catch (_) {
      // sin notificaciones los recordatorios siguen viéndose y editándose
    }
    await super.start();
  }

  @override
  Reminder adopt(Reminder? local, Reminder remote) {
    final server = remote.fromServer;
    return server.withNotifId(local?.notifId ?? reminderNotifIdFor(server.id));
  }

  /// Deja programado exactamente lo que toca: el aviso de cada recordatorio pendiente que todavía no pasó; lo demás se cancela. Solo llama al
  /// teléfono para lo que cambió.
  @override
  Future<void> onRowsChanged() async {
    try {
      for (final r in everything) {
        final wanted = !r.isDeleted && !r.done && r.at.isAfter(now()) ? '${r.title}|${r.at.millisecondsSinceEpoch}' : null;
        if (_plannedOnce && _planned[r.notifId] == wanted) continue;
        if (wanted == null) {
          if (_planned.containsKey(r.notifId) || !_plannedOnce) await _scheduler.cancel(r.notifId);
          _planned.remove(r.notifId);
        } else {
          await _scheduler.schedule(r);
          _planned[r.notifId] = wanted;
        }
      }
      _plannedOnce = true;
    } catch (_) {
      notificationsBlocked = true; // sin notificaciones los recordatorios se guardan igual
    }
  }

  /// Un recordatorio nuevo. Pide el permiso de notificaciones la primera vez. Un título vacío no crea nada.
  Future<Reminder?> add(String title, DateTime at, {String notes = ''}) async {
    final clean = title.trim();
    if (clean.isEmpty) return null;
    try {
      notificationsBlocked = !await _scheduler.ensurePermissions();
    } catch (_) {
      notificationsBlocked = true;
    }
    final t = now();
    final id = _newId();
    final r = Reminder(id: id, notifId: reminderNotifIdFor(id), title: clean, notes: notes.trim(), at: at.toUtc(), createdAt: t, updatedAt: t);
    await put([r]);
    return r;
  }

  Future<void> update(Reminder r, {String? title, String? notes, DateTime? at}) async {
    final current = rowById(r.id) ?? r;
    final nextTitle = title?.trim() ?? current.title;
    if (nextTitle.isEmpty) return;
    await put([current.copyWith(title: nextTitle, notes: notes?.trim(), at: at?.toUtc(), updatedAt: stamp(current.updatedAt))]);
  }

  /// Marca como hecho (su aviso se cancela) o lo vuelve a poner pendiente (se programa otra vez si todavía no pasó).
  Future<void> toggleDone(Reminder r) async {
    final current = rowById(r.id) ?? r;
    await put([current.copyWith(done: !current.done, updatedAt: stamp(current.updatedAt))]);
  }

  /// Lo mueve a otro momento (arrastrándolo en el calendario).
  Future<void> moveTo(Reminder r, DateTime at) => update(r, at: at);

  /// Borra el recordatorio (borrado suave: llega también a Supabase y a la web) y cancela su aviso.
  Future<void> delete(Reminder r) async {
    final current = rowById(r.id) ?? r;
    await put([current.copyWith(deletedAt: now(), updatedAt: stamp(current.updatedAt))]);
  }
}

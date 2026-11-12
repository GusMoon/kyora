import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/reminder_scheduler.dart';
import '../data/reminder_store.dart';
import '../models/reminder.dart';

/// Los recordatorios del teléfono: se guardan aquí (sin Supabase por ahora) y cada uno programa su aviso en Android para que
/// suene a su hora aunque la app esté cerrada. Al abrir la app se vuelven a programar los pendientes, por si el sistema los perdió.
class ReminderController extends ChangeNotifier {
  ReminderController(this._store, this._scheduler, {DateTime Function()? now, String Function()? newId})
      : _now = now ?? (() => DateTime.now().toUtc()),
        _newId = newId ?? (() => const Uuid().v4());

  final ReminderStore _store;
  final ReminderScheduler _scheduler;
  final DateTime Function() _now;
  final String Function() _newId;

  List<Reminder> _items = const [];
  bool _disposed = false;
  bool loaded = false;

  /// `true` si el teléfono no deja mostrar avisos (permiso negado): los recordatorios se guardan pero no sonarán.
  bool notificationsBlocked = false;

  /// Los pendientes por hora (el más próximo primero) y luego los hechos (el más reciente primero).
  List<Reminder> get items {
    final pending = [for (final r in _items) if (!r.done) r]..sort((a, b) => a.at.compareTo(b.at));
    final done = [for (final r in _items) if (r.done) r]..sort((a, b) => b.at.compareTo(a.at));
    return [...pending, ...done];
  }

  bool isOverdue(Reminder r) => !r.done && !r.at.isAfter(_now());

  Future<void> start() async {
    _items = await _store.load();
    try {
      await _scheduler.init();
      for (final r in _items) {
        if (!r.done && r.at.isAfter(_now())) await _scheduler.schedule(r);
      }
    } catch (_) {
      // sin notificaciones los recordatorios siguen viéndose y editándose
    }
    loaded = true;
    _tell();
  }

  Future<void> _schedule(Reminder r) async {
    try {
      await _scheduler.cancel(r.notifId);
      if (!r.done && r.at.isAfter(_now())) await _scheduler.schedule(r);
    } catch (_) {
      notificationsBlocked = true;
    }
  }

  Future<void> _persist() async {
    await _store.save(_items);
    _tell();
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
    final nextNotif = _items.isEmpty ? 1 : _items.map((r) => r.notifId).reduce((a, b) => a > b ? a : b) + 1;
    final r = Reminder(id: _newId(), notifId: nextNotif, title: clean, notes: notes.trim(), at: at.toUtc(), createdAt: _now());
    _items = [..._items, r];
    await _schedule(r);
    await _persist();
    return r;
  }

  Future<void> update(Reminder r, {String? title, String? notes, DateTime? at}) async {
    final nextTitle = title?.trim() ?? r.title;
    if (nextTitle.isEmpty) return;
    final next = r.copyWith(title: nextTitle, notes: notes?.trim(), at: at?.toUtc());
    _items = [for (final x in _items) x.id == r.id ? next : x];
    await _schedule(next);
    await _persist();
  }

  /// Marca como hecho (su aviso se cancela) o lo vuelve a poner pendiente (se programa otra vez si todavía no pasó).
  Future<void> toggleDone(Reminder r) async {
    final next = r.copyWith(done: !r.done);
    _items = [for (final x in _items) x.id == r.id ? next : x];
    await _schedule(next);
    await _persist();
  }

  Future<void> delete(Reminder r) async {
    _items = [for (final x in _items) if (x.id != r.id) x];
    try {
      await _scheduler.cancel(r.notifId);
    } catch (_) {}
    await _persist();
  }

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

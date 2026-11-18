import 'package:flutter/foundation.dart';

import '../data/alarm_scheduler.dart';
import '../data/clock_store.dart';
import '../models/clock_alarm.dart';
import '../util/agenda.dart' show hourParts;

/// El número de la notificación de una alarma en un «hueco» (0 = una sola vez; 1–7 = ese día de la semana). Van por encima de los de los
/// recordatorios (que llegan a 2^30) para no pisarse.
int alarmNotifId(int alarmId, int slot) => alarmNotifBase + alarmId * 8 + slot;

const alarmNotifBase = 1500000000;

/// Las alarmas: una lista que se guarda en el teléfono y se programa en Android. Todo local.
class AlarmController extends ChangeNotifier {
  AlarmController(this._store, this._scheduler, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ClockStore _store;
  final AlarmScheduler? _scheduler;
  final DateTime Function() _now;

  List<ClockAlarm> _alarms = const [];
  bool _permissionDenied = false;
  bool _started = false;

  /// Por hora del día.
  List<ClockAlarm> get alarms => _alarms;

  /// El teléfono no dejó mostrar avisos: las alarmas se guardan pero no sonarán.
  bool get permissionDenied => _permissionDenied;

  ClockAlarm? byId(int id) => _alarms.where((a) => a.id == id).firstOrNull;

  /// Lee las alarmas, apaga las de una sola vez que ya sonaron y vuelve a programar las que siguen activas (por si Android las perdió).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _scheduler?.init();
    } catch (_) {
      // sin notificaciones las alarmas se ven y se editan, pero no suenan
    }
    _alarms = _sorted(await _store.loadAlarms());
    final now = _now();
    var changed = false;
    _alarms = [
      for (final a in _alarms)
        if (a.enabled && a.rangBefore(now)) () {
          changed = true;
          return a.copyWith(enabled: false, clearFiresAt: true);
        }() else a,
    ];
    if (changed) await _store.saveAlarms(_alarms);
    for (final a in _alarms) {
      await _plan(a);
    }
    notifyListeners();
  }

  List<ClockAlarm> _sorted(List<ClockAlarm> list) => [...list]..sort((a, b) {
      final byTime = a.minutes.compareTo(b.minutes);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

  int _nextId() => _alarms.isEmpty ? 1 : _alarms.map((a) => a.id).reduce((a, b) => a > b ? a : b) + 1;

  /// La próxima vez que suena alguna alarma activa: cuál y cuándo.
  (ClockAlarm, DateTime)? next() {
    final now = _now();
    (ClockAlarm, DateTime)? best;
    for (final a in _alarms) {
      final at = a.nextRing(now);
      if (at != null && (best == null || at.isBefore(best.$2))) best = (a, at);
    }
    return best;
  }

  /// Crea una alarma (activa) y la programa. Con `days` en 0 suena una sola vez, la próxima vez que den esa hora.
  Future<ClockAlarm> add({required int hour, required int minute, String label = '', int days = 0}) async {
    final alarm = ClockAlarm(id: _nextId(), hour: hour, minute: minute, label: label.trim(), days: days & 127, firesAt: days == 0 ? ClockAlarm.nextOnce(_now(), hour, minute) : null);
    _alarms = _sorted([..._alarms, alarm]);
    await _store.saveAlarms(_alarms);
    await _plan(alarm);
    notifyListeners();
    return alarm;
  }

  /// Cambia la hora, el nombre y los días de una alarma. Al editarla vuelve a quedar activa.
  Future<void> update(int id, {required int hour, required int minute, String label = '', int days = 0}) async {
    final old = byId(id);
    if (old == null) return;
    await _unplan(old);
    final alarm = old.copyWith(hour: hour, minute: minute, label: label.trim(), days: days & 127, enabled: true, firesAt: days == 0 ? ClockAlarm.nextOnce(_now(), hour, minute) : null, clearFiresAt: days != 0);
    _alarms = _sorted([for (final a in _alarms) a.id == id ? alarm : a]);
    await _store.saveAlarms(_alarms);
    await _plan(alarm);
    notifyListeners();
  }

  /// La enciende o la apaga.
  Future<void> setEnabled(int id, bool enabled) async {
    final old = byId(id);
    if (old == null || old.enabled == enabled) return;
    final alarm = old.copyWith(enabled: enabled, firesAt: !old.repeats && enabled ? ClockAlarm.nextOnce(_now(), old.hour, old.minute) : null, clearFiresAt: old.repeats || !enabled);
    _alarms = [for (final a in _alarms) a.id == id ? alarm : a];
    await _store.saveAlarms(_alarms);
    await (enabled ? _plan(alarm) : _unplan(old));
    notifyListeners();
  }

  Future<void> remove(int id) async {
    final old = byId(id);
    if (old == null) return;
    await _unplan(old);
    _alarms = [for (final a in _alarms) if (a.id != id) a];
    await _store.saveAlarms(_alarms);
    notifyListeners();
  }

  /// El texto del aviso: el nombre, o «Alarma».
  static String titleOf(ClockAlarm a) => a.label.isEmpty ? 'Alarma' : a.label;

  static String bodyOf(ClockAlarm a) {
    final (h, ampm) = hourParts(a.minutes);
    return '$h:${a.minute.toString().padLeft(2, '0')} $ampm';
  }

  Future<void> _plan(ClockAlarm a) async {
    final scheduler = _scheduler;
    if (scheduler == null || !a.enabled) return;
    try {
      if (!_permissionAsked) {
        _permissionAsked = true;
        _permissionDenied = !await scheduler.ensurePermissions();
      }
      if (a.repeats) {
        for (var weekday = 1; weekday <= 7; weekday++) {
          if (a.onDay(weekday)) {
            await scheduler.scheduleWeekly(id: alarmNotifId(a.id, weekday), title: titleOf(a), body: bodyOf(a), weekday: weekday, hour: a.hour, minute: a.minute);
          } else {
            await scheduler.cancel(alarmNotifId(a.id, weekday)); // un día que se quitó al editar
          }
        }
        await scheduler.cancel(alarmNotifId(a.id, 0));
      } else {
        await scheduler.scheduleOnce(id: alarmNotifId(a.id, 0), title: titleOf(a), body: bodyOf(a), at: a.firesAt ?? ClockAlarm.nextOnce(_now(), a.hour, a.minute));
        for (var weekday = 1; weekday <= 7; weekday++) {
          await scheduler.cancel(alarmNotifId(a.id, weekday));
        }
      }
    } catch (_) {
      _permissionDenied = true; // no se pudo programar: se avisa en la pantalla
    }
  }

  bool _permissionAsked = false;

  Future<void> _unplan(ClockAlarm a) async {
    final scheduler = _scheduler;
    if (scheduler == null) return;
    try {
      for (var slot = 0; slot <= 7; slot++) {
        await scheduler.cancel(alarmNotifId(a.id, slot));
      }
    } catch (_) {
      // si no se pudo cancelar, el aviso ya no tiene alarma que lo respalde: Android lo mostrará una vez como mucho
    }
  }
}

/// El cronómetro: cuenta mientras está en marcha (con la hora del reloj, así sigue contando aunque la pantalla no se dibuje), marca vueltas y
/// se guarda en el teléfono para seguir donde estaba.
class StopwatchController extends ChangeNotifier {
  StopwatchController(this._store, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final ClockStore _store;
  final DateTime Function() _now;

  Duration _accumulated = Duration.zero;
  DateTime? _startedAt;
  List<Duration> _laps = const [];

  bool get running => _startedAt != null;

  /// ¿Hay algo que reiniciar (corre, o se paró con tiempo contado)?
  bool get hasTime => running || _accumulated > Duration.zero;

  /// Lo contado hasta ahora.
  Duration get elapsed => _accumulated + (_startedAt == null ? Duration.zero : _now().difference(_startedAt!).abs());

  /// El tiempo total en cada vuelta (la primera marcada primero).
  List<Duration> get laps => _laps;

  /// Lo que duró cada vuelta (el total menos el de la anterior), en el mismo orden que [laps].
  List<Duration> get lapTimes => [for (var i = 0; i < _laps.length; i++) _laps[i] - (i == 0 ? Duration.zero : _laps[i - 1])];

  Future<void> start() async {
    final snap = await _store.loadStopwatch();
    _accumulated = snap.accumulated;
    _startedAt = snap.startedAt;
    _laps = snap.laps;
    notifyListeners();
  }

  Future<void> toggle() async {
    if (running) {
      _accumulated = elapsed;
      _startedAt = null;
    } else {
      _startedAt = _now();
    }
    await _save();
  }

  /// Marca una vuelta (solo si corre).
  Future<void> lap() async {
    if (!running) return;
    _laps = [..._laps, elapsed];
    await _save();
  }

  Future<void> reset() async {
    _accumulated = Duration.zero;
    _startedAt = null;
    _laps = const [];
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await _store.saveStopwatch(StopwatchSnapshot(accumulated: _accumulated, startedAt: _startedAt, laps: _laps));
  }
}

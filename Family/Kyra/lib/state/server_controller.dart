import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/chat_backend.dart';
import '../data/reminder_scheduler.dart';
import '../data/server_stats.dart';

/// Cuánto ocupa tu proyecto de Supabase frente al plan gratuito. Mide al empezar, al volver a la app y cada 30 minutos; al llegar al 80 % de un
/// límite avisa con una notificación (una vez al día por límite). Lo que se ve en la Nube y los límites de Configuración salen de aquí.
class ServerController extends ChangeNotifier {
  ServerController(this._backend, this._store, {ReminderScheduler? scheduler, DateTime Function()? now, Duration every = const Duration(minutes: 30)})
      : _scheduler = scheduler, // ignore: prefer_initializing_formals
        _now = now ?? (() => DateTime.now().toUtc()),
        _every = every; // ignore: prefer_initializing_formals

  final ServerBackend _backend;
  final ServerStore _store;
  final ReminderScheduler? _scheduler;
  final DateTime Function() _now;
  final Duration _every;

  /// El número de la notificación de cada límite (propio, lejos de los recordatorios y los hábitos).
  static const notifIdBase = 0x3F000000;

  Timer? _timer;
  bool _disposed = false;
  bool _permissionAsked = false;

  ServerStats? stats;

  /// Lo que salió mal al medir (por ejemplo, que falta la función en Supabase), o `null`.
  String? error;
  bool measuring = false;
  QuotaLimits limits = const QuotaLimits();
  bool loaded = false;

  /// Los dos límites con lo que llevas usado; vacío mientras no se haya medido.
  List<Quota> get quotaList => stats == null ? const [] : quotas(stats!, limits);

  /// Los que están en el 80 % o más.
  List<Quota> get warnings => [for (final q in quotaList) if (q.level != QuotaLevel.ok) q];

  Future<void> start() async {
    limits = await _store.loadLimits();
    loaded = true;
    _tell();
    _timer = Timer.periodic(_every, (_) => unawaited(measure()));
    unawaited(measure());
  }

  /// Mide ahora. Si ya hay una medición en curso no empieza otra.
  Future<void> measure() async {
    if (measuring || _disposed) return;
    measuring = true;
    _tell();
    try {
      stats = await _backend.serverStats();
      error = null;
      await _notifyIfNeeded();
    } on ChatException catch (e) {
      error = e.message;
    } finally {
      measuring = false;
      _tell();
    }
  }

  /// Cambia los límites (por si cambias de plan) y vuelve a comprobar con ellos.
  Future<void> setLimits(QuotaLimits next) async {
    final clean = QuotaLimits(dbMb: validMb(next.dbMb, limits.dbMb), filesMb: validMb(next.filesMb, limits.filesMb));
    if (clean == limits) return;
    limits = clean;
    await _store.saveLimits(clean);
    _tell();
    if (stats != null) await _notifyIfNeeded();
  }

  /// Avisa de lo que esté en el 80 % o más, si hace más de un día del último aviso de ese límite. Lo que bajó del 80 % olvida su aviso, así
  /// que si vuelve a llegar se avisa otra vez.
  Future<void> _notifyIfNeeded() async {
    final warned = await _store.loadWarned();
    final over = warnings;
    var changed = false;
    for (final q in quotaList) {
      if (q.level == QuotaLevel.ok && warned.remove(q.id) != null) changed = true;
    }
    final scheduler = _scheduler;
    for (final q in over) {
      if (!shouldRenotify(warned[q.id], _now())) continue;
      warned[q.id] = _now();
      changed = true;
      if (scheduler == null) continue;
      try {
        if (!_permissionAsked) {
          _permissionAsked = true;
          await scheduler.ensurePermissions();
        }
        await scheduler.showNow(id: notifIdBase + q.id.index, title: 'Tu servidor de Supabase se está llenando', body: warningText(q));
      } catch (_) {
        // sin notificaciones el aviso sigue saliendo dentro de la app
      }
    }
    if (changed) await _store.saveWarned(warned);
  }

  void _tell() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

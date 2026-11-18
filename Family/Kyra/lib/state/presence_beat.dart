import 'dart:async';

import '../data/admin_backend.dart';

/// El latido de presencia: mientras haya sesión y la app esté abierta, cada 30 segundos le dice al servidor «sigo aquí»
/// (`touch_presence`). Así el administrador ve quién está en línea (visto en los últimos 90 s). Un fallo (sin internet) no hace nada:
/// el siguiente latido lo intenta otra vez.
class PresenceBeat {
  PresenceBeat(this._backend, {this.every = const Duration(seconds: 30)});

  final AdminBackend _backend;
  final Duration every;
  Timer? _timer;

  bool get running => _timer != null;

  /// Empieza (y late ya mismo). Repetirlo no duplica.
  void start() {
    if (_timer != null) return;
    unawaited(_beat());
    _timer = Timer.periodic(every, (_) => unawaited(_beat()));
  }

  /// Late ya (por ejemplo, al volver a la app), si está en marcha.
  void nudge() {
    if (_timer != null) unawaited(_beat());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _beat() async {
    try {
      await _backend.touchPresence();
    } catch (_) {
      // sin conexión o sin sesión: se reintenta en el siguiente latido
    }
  }
}

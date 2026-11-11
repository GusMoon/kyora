import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/system_info.dart';

/// El estado del teléfono que enseña Inicio (batería, memoria, almacenamiento, Wi-Fi, Bluetooth). Se vuelve a leer cada [every] mientras
/// alguien lo mira (`watch`) y al volver a la app.
class SystemController extends ChangeNotifier {
  SystemController(this._info, {this.every = const Duration(seconds: 15)});

  final SystemInfo _info;

  /// Cada cuánto se vuelve a leer mientras se mira.
  final Duration every;

  SystemStats? _stats;
  Timer? _timer;
  int _watchers = 0;
  bool _disposed = false;

  /// Lo último que se leyó (`null` hasta la primera lectura o si no se pudo).
  SystemStats? get stats => _stats;

  /// Lee el estado ahora.
  Future<void> refresh() async {
    final next = await _info.stats();
    if (_disposed) return;
    _stats = next;
    notifyListeners();
  }

  /// Empieza a mirar: lee ahora y cada [every]. Cada `watch` lleva su `unwatch`.
  void watch() {
    _watchers++;
    if (_watchers == 1) {
      unawaited(refresh());
      _timer = Timer.periodic(every, (_) => unawaited(refresh()));
    }
  }

  void unwatch() {
    if (_watchers == 0) return;
    _watchers--;
    if (_watchers == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Abre el panel del Wi-Fi o del Bluetooth; al volver se lee otra vez.
  Future<bool> openWifi() => _info.openWifi();
  Future<bool> openBluetooth() => _info.openBluetooth();

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

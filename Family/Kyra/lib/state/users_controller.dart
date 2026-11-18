import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/admin_backend.dart';
import '../data/chat_backend.dart';
import '../models/presence.dart';
import '../models/profile.dart';

/// El panel del administrador: todas las cuentas con su estado (en línea o no) y lo que se puede hacer con ellas (crear, cambiar el rol,
/// pedir un código nuevo, quitar). Se vuelve a leer solo cada 30 segundos mientras esté abierto.
class UsersController extends ChangeNotifier {
  UsersController(this._backend, {this.every = const Duration(seconds: 30)});

  final AdminBackend _backend;
  final Duration every;

  List<PresenceEntry> entries = const [];
  bool loading = true;
  bool busy = false;

  /// El motivo por el que algo falló (ya en español), o `null`.
  String? error;

  Timer? _timer;
  bool _disposed = false;

  int get onlineCount => entries.where((e) => e.online).length;

  void start() {
    unawaited(refresh());
    _timer ??= Timer.periodic(every, (_) => unawaited(refresh(quiet: true)));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh({bool quiet = false}) async {
    if (!quiet) {
      loading = entries.isEmpty;
      notifyListeners();
    }
    try {
      entries = await _backend.listPresence();
      error = null;
    } on ChatException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Crea una cuenta y devuelve su código de 6 dígitos (para enseñarlo una vez), o `null` si falló (el motivo queda en `error`).
  Future<IssuedCode?> create({required String username, required String password, required Role role}) =>
      _run(() => _backend.createAccount(username: username, password: password, role: role));

  Future<bool> changeRole(PresenceEntry entry, Role role) async => await _run(() async {
        await _backend.setRole(entry.id, role);
        return true;
      }) ??
      false;

  Future<IssuedCode?> newCode(PresenceEntry entry) => _run(() => _backend.regenerateCode(entry.id, entry.username));

  Future<bool> remove(PresenceEntry entry) async => await _run(() async {
        await _backend.removeAccount(entry.id);
        return true;
      }) ??
      false;

  Future<T?> _run<T>(Future<T> Function() action) async {
    if (busy) return null;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await action();
      await refresh(quiet: true);
      return result;
    } on ChatException catch (e) {
      error = e.message;
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}

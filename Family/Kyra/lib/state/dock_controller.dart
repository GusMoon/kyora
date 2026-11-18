import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/dock_store.dart';
import '../data/installed_apps.dart';
import '../util/format.dart';

/// Los paquetes que se prefieren cuando el disco se rellena solo (teléfono, mensajes, cámara, navegador…), en este orden.
const preferredPackages = [
  'com.google.android.dialer',
  'com.android.dialer',
  'com.samsung.android.dialer',
  'com.google.android.apps.messaging',
  'com.samsung.android.messaging',
  'com.whatsapp',
  'com.android.camera',
  'com.android.camera2',
  'com.sec.android.app.camera',
  'com.google.android.GoogleCamera',
  'com.android.chrome',
  'com.google.android.apps.photos',
  'com.google.android.gm',
  'com.google.android.apps.maps',
  'com.google.android.youtube',
  'com.android.settings',
];

/// Las 8 apps del disco de Inicio. Mientras la persona no elija ninguna, se rellena solo (las más comunes que haya instaladas y, si faltan,
/// las primeras por nombre). En cuanto cambia una ranura, las 8 quedan fijas. Una app que se desinstaló deja su ranura vacía.
class DockController extends ChangeNotifier {
  DockController(this._store, this._apps) : _saved = _store.load();

  final DockStore _store;
  final InstalledApps _apps;

  List<String?>? _saved;
  List<InstalledApp> _installed = const [];
  bool _loaded = false;
  bool _launcher = false;

  /// Todas las apps que se pueden elegir (vacío hasta que se leen).
  List<InstalledApp> get installed => _installed;

  /// Todas las apps ordenadas de la A a la Z (sin distinguir mayúsculas ni acentos; lo que no empieza por letra, al final).
  List<InstalledApp> get alphabetical => [..._installed]..sort((a, b) => compareAppNames(a.label, b.label));

  /// Abre una app por su paquete (la lista alfabética). `false` si no se pudo.
  Future<bool> launch(String package) => _apps.launch(package);

  /// Ya se leyeron las apps del teléfono.
  bool get loaded => _loaded;

  /// Kyra es la pantalla de inicio del teléfono.
  bool get isLauncher => _launcher;

  /// Pide a Android que Kyra sea la pantalla de inicio.
  Future<bool> chooseLauncher() => _apps.chooseLauncher();

  /// Deja (o quita) que Kyra se ofrezca como pantalla de inicio del teléfono. Solo el administrador puede: para el resto Kyra es una app normal.
  Future<void> allowLauncher(bool allowed) async {
    await _apps.setLauncherEnabled(allowed);
    _launcher = await _apps.isDefaultLauncher();
    notifyListeners();
  }

  /// Las ranuras sin elegir nunca: el disco se rellena solo.
  bool get automatic => _saved == null;

  /// Lee las apps del teléfono (al abrir Inicio y al volver a la app: pudo instalarse o quitarse alguna).
  Future<void> refresh() async {
    final found = await _apps.list();
    _installed = found;
    _launcher = await _apps.isDefaultLauncher();
    _loaded = true;
    notifyListeners();
  }

  InstalledApp? _find(String? package) {
    if (package == null) return null;
    for (final app in _installed) {
      if (app.package == package) return app;
    }
    return null;
  }

  /// Las 8 ranuras: la app de cada una, o `null` si está vacía.
  List<InstalledApp?> get slots {
    final saved = _saved;
    if (saved != null) return [for (var i = 0; i < dockSlots; i++) _find(saved[i])];
    final picked = <InstalledApp>[];
    for (final package in preferredPackages) {
      final app = _find(package);
      if (app != null && picked.length < dockSlots) picked.add(app);
    }
    for (final app in _installed) {
      if (picked.length >= dockSlots) break;
      if (!picked.contains(app)) picked.add(app);
    }
    return [for (var i = 0; i < dockSlots; i++) i < picked.length ? picked[i] : null];
  }

  Future<void> _fix(List<String?> next) async {
    _saved = next;
    notifyListeners();
    await _store.save(next);
  }

  List<String?> _current() => [for (final app in slots) app?.package];

  /// Pone [package] en la ranura [index]. Si ya estaba en otra, esa se vacía (no se repite).
  Future<void> setSlot(int index, String package) {
    final next = _current();
    for (var i = 0; i < next.length; i++) {
      if (next[i] == package) next[i] = null;
    }
    next[index] = package;
    return _fix(next);
  }

  /// Deja vacía la ranura [index].
  Future<void> clearSlot(int index) {
    final next = _current();
    next[index] = null;
    return _fix(next);
  }

  /// Vuelve a rellenar el disco solo.
  Future<void> reset() async {
    _saved = null;
    notifyListeners();
    await _store.save(null);
  }

  /// Abre la app de la ranura [index]. Devuelve `false` si está vacía o no se pudo abrir.
  Future<bool> open(int index) async {
    final app = slots[index];
    if (app == null) return false;
    final ok = await _apps.launch(app.package);
    if (!ok) unawaited(refresh()); // quizá se desinstaló
    return ok;
  }
}

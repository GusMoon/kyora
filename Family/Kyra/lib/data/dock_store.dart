import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cuántas apps caben en el disco de Inicio.
const dockSlots = 8;

/// Dónde se recuerdan las 8 apps del disco: el paquete de cada ranura (o nada si está vacía). `null` = nunca se eligió: se rellena solo.
abstract class DockStore {
  List<String?>? load();
  Future<void> save(List<String?>? slots);
}

class MemoryDockStore implements DockStore {
  List<String?>? slots;

  @override
  List<String?>? load() => slots;

  @override
  Future<void> save(List<String?>? value) async => slots = value;
}

class PrefsDockStore implements DockStore {
  PrefsDockStore._(this._prefs);

  static const _key = 'dock.apps';

  final SharedPreferences _prefs;

  static Future<PrefsDockStore> open() async => PrefsDockStore._(await SharedPreferences.getInstance());

  @override
  List<String?>? load() {
    final text = _prefs.getString(_key);
    if (text == null) return null;
    try {
      final list = (jsonDecode(text) as List).cast<String?>();
      return [for (var i = 0; i < dockSlots; i++) i < list.length ? list[i] : null];
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(List<String?>? slots) async {
    if (slots == null) {
      await _prefs.remove(_key);
    } else {
      await _prefs.setString(_key, jsonEncode(slots));
    }
  }
}

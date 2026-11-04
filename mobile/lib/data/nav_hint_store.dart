import 'package:shared_preferences/shared_preferences.dart';

/// Si ya se enseñó cómo abrir el menú circular (mantener el dedo): la pista de Inicio sale hasta que se usa una vez.
abstract class NavHintStore {
  bool get seen;
  Future<void> markSeen();
}

class MemoryNavHintStore implements NavHintStore {
  MemoryNavHintStore({this.seen = false});

  @override
  bool seen;

  @override
  Future<void> markSeen() async => seen = true;
}

class PrefsNavHintStore implements NavHintStore {
  PrefsNavHintStore._(this._prefs);

  static const _key = 'nav.hint_seen';

  final SharedPreferences _prefs;

  static Future<PrefsNavHintStore> open() async => PrefsNavHintStore._(await SharedPreferences.getInstance());

  @override
  bool get seen => _prefs.getBool(_key) ?? false;

  @override
  Future<void> markSeen() async {
    await _prefs.setBool(_key, true);
  }
}

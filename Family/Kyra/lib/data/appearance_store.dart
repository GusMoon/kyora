import 'package:shared_preferences/shared_preferences.dart';

/// La apariencia elegida en KyraFamily: el tema de colores (su id) y si va en modo oscuro.
class Appearance {
  const Appearance({this.themeId, this.dark = false});

  final String? themeId;
  final bool dark;
}

/// Dónde se recuerda la apariencia. La real usa SharedPreferences; los tests, una en memoria.
abstract class AppearanceStore {
  Appearance load();
  Future<void> save(Appearance value);
}

class MemoryAppearanceStore implements AppearanceStore {
  MemoryAppearanceStore([this.value = const Appearance()]);

  Appearance value;

  @override
  Appearance load() => value;

  @override
  Future<void> save(Appearance next) async => value = next;
}

class PrefsAppearanceStore implements AppearanceStore {
  PrefsAppearanceStore._(this._prefs);

  static const _themeKey = 'family.theme';
  static const _darkKey = 'family.dark';

  final SharedPreferences _prefs;

  static Future<PrefsAppearanceStore> open() async => PrefsAppearanceStore._(await SharedPreferences.getInstance());

  @override
  Appearance load() => Appearance(themeId: _prefs.getString(_themeKey), dark: _prefs.getBool(_darkKey) ?? false);

  @override
  Future<void> save(Appearance value) async {
    if (value.themeId == null) {
      await _prefs.remove(_themeKey);
    } else {
      await _prefs.setString(_themeKey, value.themeId!);
    }
    await _prefs.setBool(_darkKey, value.dark);
  }
}

import 'package:flutter/foundation.dart';

import '../data/appearance_store.dart';
import '../ui/neo/neo_theme.dart';
import '../ui/neo/neo_themes.dart';

/// La apariencia de KyraFamily: el tema de colores y el modo oscuro, elegidos en Ajustes y recordados en el teléfono. Al cambiar algo avisa y
/// toda la app cambia de colores a la vez.
class AppearanceController extends ChangeNotifier {
  AppearanceController(this._store) {
    final saved = _store.load();
    _theme = NeoThemes.byId(saved.themeId);
    _dark = saved.dark;
  }

  final AppearanceStore _store;
  late NeoThemeSpec _theme;
  late bool _dark;
  NeoScheme? _scheme;

  NeoThemeSpec get theme => _theme;
  bool get dark => _dark;

  /// Los colores de ahora (se calculan una vez por cambio).
  NeoScheme get scheme => _scheme ??= NeoScheme.of(_theme, dark: _dark);

  Future<void> setTheme(NeoThemeSpec theme) async {
    if (theme.id == _theme.id) return;
    _theme = theme;
    await _changed();
  }

  Future<void> setDark(bool dark) async {
    if (dark == _dark) return;
    _dark = dark;
    await _changed();
  }

  Future<void> _changed() async {
    _scheme = null;
    notifyListeners();
    await _store.save(Appearance(themeId: _theme.id, dark: _dark));
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dónde se recuerdan las canciones favoritas (solo en el teléfono, no en Supabase).
abstract class FavoritesStore {
  Set<String> load();
  Future<void> save(Set<String> keys);
}

class MemoryFavoritesStore implements FavoritesStore {
  Set<String> keys = {};

  @override
  Set<String> load() => Set.of(keys);

  @override
  Future<void> save(Set<String> value) async => keys = Set.of(value);
}

class PrefsFavoritesStore implements FavoritesStore {
  PrefsFavoritesStore._(this._prefs);

  static const _key = 'music.favorites';

  final SharedPreferences _prefs;

  static Future<PrefsFavoritesStore> open() async => PrefsFavoritesStore._(await SharedPreferences.getInstance());

  @override
  Set<String> load() => (_prefs.getStringList(_key) ?? const []).toSet();

  @override
  Future<void> save(Set<String> keys) async => _prefs.setStringList(_key, keys.toList());
}

/// Las canciones con el corazón puesto. La clave de cada una es `Track.durationKey` (el id de la recibida, o dirección + tamaño +
/// fecha del archivo del teléfono).
class FavoritesController extends ChangeNotifier {
  FavoritesController([FavoritesStore? store]) : this._(store ?? MemoryFavoritesStore());

  FavoritesController._(this._store) : _keys = _store.load();

  final FavoritesStore _store;
  final Set<String> _keys;

  bool isFavorite(String key) => _keys.contains(key);

  int get count => _keys.length;

  Future<void> toggle(String key) async {
    if (!_keys.remove(key)) _keys.add(key);
    notifyListeners();
    try {
      await _store.save(_keys);
    } catch (_) {
      // sin poder guardarlo, el corazón vale mientras la app siga abierta
    }
  }
}

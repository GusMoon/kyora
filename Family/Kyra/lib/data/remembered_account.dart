import 'package:shared_preferences/shared_preferences.dart';

import 'account_backend.dart';

/// El nombre del visitante que ya entró, guardado en el teléfono (la contraseña nunca se guarda).
class PrefsRememberedAccount implements RememberedAccount {
  PrefsRememberedAccount(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'account.remembered';

  static Future<PrefsRememberedAccount> open() async => PrefsRememberedAccount(await SharedPreferences.getInstance());

  @override
  Future<String?> read() async => _prefs.getString(_key);

  @override
  Future<void> write(String username) async {
    await _prefs.setString(_key, username);
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}

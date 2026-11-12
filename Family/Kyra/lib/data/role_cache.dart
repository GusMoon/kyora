import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';
import 'account_backend.dart';

/// El rol de la última vez, guardado en el teléfono (con el id del usuario, para no confundir cuentas).
class PrefsRoleCache implements RoleCache {
  PrefsRoleCache(this._prefs);

  final SharedPreferences _prefs;

  static const _key = 'account.role';

  static Future<PrefsRoleCache> open() async => PrefsRoleCache(await SharedPreferences.getInstance());

  @override
  Future<Role?> read(String userId) async {
    final stored = _prefs.getString(_key);
    if (stored == null || !stored.startsWith('$userId:')) return null;
    return roleFromName(stored.substring(userId.length + 1));
  }

  @override
  Future<void> write(String userId, Role role) async {
    await _prefs.setString(_key, '$userId:${role.name}');
  }
}

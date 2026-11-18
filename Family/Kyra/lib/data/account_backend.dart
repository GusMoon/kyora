import '../models/profile.dart';

/// El dominio inventado de las cuentas que crea el administrador: no llevan correo real (Server/supabase/functions/admin-users).
const accountDomain = 'kyra.local';

/// Con qué correo se entra: lo escrito si ya es un correo (el administrador usa el de siempre); si es solo un nombre de usuario,
/// el correo inventado `<nombre>@kyra.local`.
String loginEmail(String identifier) {
  final text = identifier.trim();
  return text.contains('@') ? text : '${text.toLowerCase()}@$accountDomain';
}

/// La cuenta: entrar, canjear el código de 6 dígitos, salir y saber qué rol tiene quien entró. **Ya no hay registro**: las cuentas solo las
/// crea el administrador. La implementación real es `ChatRepository`; los tests usan una falsa.
abstract class AccountBackend {
  bool get signedIn;

  /// El id del usuario con sesión.
  String? get userId;

  /// Avisa cuando la sesión cambia (entrar, salir, renovarse).
  Stream<void> get authChanges;

  /// Entra con un nombre de usuario (o un correo, el del administrador) y su contraseña.
  Future<void> signIn(String identifier, String password);

  /// Canjea el código de 6 dígitos que dio el administrador (la primera vez en cada cuenta). Lanza `ChatException` en español si es
  /// incorrecto, caducó o se agotaron los intentos.
  Future<void> claimAccount(String code);

  Future<void> signOut();

  /// El perfil de quien tiene sesión (`null` si aún no tiene).
  Future<Profile?> myProfile();
}

/// Recuerda el rol de la última vez para poder abrir la vista correcta aunque no haya internet al arrancar.
///
/// También recuerda **quién** fue la última cuenta que entró: así, sin sesión (la app abre igual, como launcher), se siguen abriendo
/// sus tareas, hábitos y recordatorios locales; solo se pausa lo que necesita el servidor.
abstract class RoleCache {
  Future<Role?> read(String userId);
  Future<void> write(String userId, Role role);

  /// La última cuenta que entró y su rol, o `null` si nunca entró ninguna en este teléfono.
  Future<({String userId, Role role})?> readLast();
}

/// El nombre de usuario del visitante que ya entró en este teléfono: con él, la próxima vez solo se pide la contraseña.
abstract class RememberedAccount {
  Future<String?> read();
  Future<void> write(String username);

  /// «No soy yo»: se olvida, y la próxima vez se pide el nombre otra vez.
  Future<void> clear();
}

/// Sin guardar nada (pruebas y lo que no tenga teléfono).
class MemoryRememberedAccount implements RememberedAccount {
  MemoryRememberedAccount([this._username]);

  String? _username;

  @override
  Future<String?> read() async => _username;

  @override
  Future<void> write(String username) async => _username = username;

  @override
  Future<void> clear() async => _username = null;
}

import '../models/presence.dart';
import '../models/profile.dart';

/// Lo que hace el administrador con las cuentas, y el latido de presencia de todas. La implementación real es `ChatRepository`
/// (funciones `touch_presence` y `list_presence`, y la función `admin-users` de Supabase); los tests usan una falsa.
abstract class AdminBackend {
  /// «Sigo aquí»: cualquier cuenta con sesión lo manda cada ~30 s mientras la app está abierta.
  Future<void> touchPresence();

  /// Todas las cuentas con su estado (solo el administrador): en línea primero, luego por nombre.
  Future<List<PresenceEntry>> listPresence();

  /// Crea una cuenta con nombre y contraseña (sin correo) y devuelve su código de 6 dígitos (se enseña una sola vez).
  Future<IssuedCode> createAccount({required String username, required String password, required Role role});

  Future<void> setRole(String userId, Role role);

  /// Un código nuevo: la cuenta vuelve a pedir verificación (por ejemplo, para entrar desde otro teléfono).
  Future<IssuedCode> regenerateCode(String userId, String username);

  /// Quita la cuenta por completo (pierde el acceso).
  Future<void> removeAccount(String userId);
}

import '../models/profile.dart';

/// La cuenta: entrar, crear una cuenta de pasante, salir y saber qué rol tiene quien entró. La implementación real es
/// `ChatRepository`; los tests usan una falsa.
abstract class AccountBackend {
  bool get signedIn;

  /// El id del usuario con sesión.
  String? get userId;

  /// Avisa cuando la sesión cambia (entrar, salir, renovarse).
  Stream<void> get authChanges;

  Future<void> signIn(String email, String password);

  /// Crea una cuenta nueva de pasante. `true` si ya quedó dentro; `false` si Supabase pide confirmar el correo antes.
  /// Lanza `ChatException` en español si el nombre de usuario o el correo ya están en uso, o si algo no es válido.
  Future<bool> signUp({required String username, required String email, required String password});

  Future<void> signOut();

  /// El perfil de quien tiene sesión (`null` si aún no tiene).
  Future<Profile?> myProfile();
}

/// Recuerda el rol de la última vez para poder abrir la vista correcta aunque no haya internet al arrancar.
abstract class RoleCache {
  Future<Role?> read(String userId);
  Future<void> write(String userId, Role role);
}

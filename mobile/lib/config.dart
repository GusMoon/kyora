/// Datos de la app. La URL y la clave pública (anon) de Supabase llegan al compilar con
/// `--dart-define-from-file=env.json` (lo prepara scripts/preparar_movil.bat a partir de supabase/.env).
/// La contraseña nunca va dentro de la app: se escribe en la pantalla de acceso.
class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Cómo se llama este dispositivo en los mensajes. La PC usa `pc`; tiene que ser otro nombre, porque la PC reconoce
  /// sus propios mensajes por este valor.
  static const deviceName = String.fromEnvironment('DEVICE', defaultValue: 'movil');

  /// El bucket privado de Storage donde viven las fotos y los archivos (ver supabase/schema.sql).
  static const bucket = 'chat-files';

  /// Lo máximo que pesa un archivo (el límite del plan gratuito de Supabase).
  static const maxFileBytes = 50 * 1000 * 1000;

  /// Mensajes que se piden de golpe al abrir y al subir a leer los anteriores.
  static const pageSize = 50;

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

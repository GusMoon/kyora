import 'package:flutter/services.dart' show appFlavor;

/// Cuál de las dos apps es esta. Salen del mismo código pero son dos instalaciones distintas (`flutter build apk --flavor admin|family`):
///  · **KyraAdmin**: solo entran cuentas de administrador; gestiona todas las cuentas (Usuarios) y tiene toda la app;
///  · **KyraFamily**: la de la familia; **no** deja entrar a cuentas de administrador y solo tiene Música, Chat y Ajustes.
enum AppFlavor {
  admin('KyraAdmin'),
  family('KyraFamily');

  const AppFlavor(this.appName);

  /// El nombre con el que se instala la app (y se llama su APK).
  final String appName;

  /// El de esta compilación. Lo fija `--flavor`; sin él (por ejemplo `flutter run` a secas) es la de administrador.
  static AppFlavor get current => fromName(appFlavor);

  static AppFlavor fromName(String? name) => name == 'family' ? family : admin;
}

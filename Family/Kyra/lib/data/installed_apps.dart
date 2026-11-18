import 'package:flutter/services.dart';

/// Una app instalada en el teléfono que se puede abrir.
class InstalledApp {
  const InstalledApp({required this.package, required this.label, required this.icon});

  /// El identificador de Android, «com.whatsapp».
  final String package;

  /// El nombre que ve la persona.
  final String label;

  /// El icono, como PNG.
  final Uint8List icon;
}

/// Las apps del teléfono: cuáles hay y abrir una.
abstract class InstalledApps {
  /// Todas las que tienen icono de lanzador, por nombre y sin Kyra.
  Future<List<InstalledApp>> list();

  /// Abre la app. Devuelve `false` si ya no está instalada o no se pudo abrir.
  Future<bool> launch(String package);

  /// ¿Kyra es la pantalla de inicio del teléfono (el launcher)?
  Future<bool> isDefaultLauncher();

  /// Pide a Android que Kyra sea la pantalla de inicio (el aviso del sistema, o la lista de apps de inicio). `false` si no se pudo abrir.
  Future<bool> chooseLauncher();

  /// Enciende o apaga que Kyra se **ofrezca** como pantalla de inicio. Apagado (lo normal) Kyra es una app más y Android no se lo propone al
  /// teléfono; solo el administrador la enciende. `false` si no se pudo cambiar.
  Future<bool> setLauncherEnabled(bool enabled);
}

/// El real: la parte de Android está en `MainActivity.kt` (canal `kyora/apps`).
class AndroidInstalledApps implements InstalledApps {
  static const _channel = MethodChannel('kyora/apps');

  Future<bool> _flag(String method) async {
    try {
      return (await _channel.invokeMethod<bool>(method)) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> isDefaultLauncher() => _flag('isDefaultLauncher');

  @override
  Future<bool> chooseLauncher() => _flag('chooseLauncher');

  @override
  Future<bool> setLauncherEnabled(bool enabled) async {
    try {
      return (await _channel.invokeMethod<bool>('setLauncherEnabled', {'enabled': enabled})) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<List<InstalledApp>> list() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('listApps') ?? const [];
      return [
        for (final item in raw)
          InstalledApp(package: item['package'] as String, label: item['label'] as String, icon: item['icon'] as Uint8List),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<bool> launch(String package) async {
    try {
      return (await _channel.invokeMethod<bool>('launch', {'package': package})) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// Unas cuantas apps de mentira, para las pruebas.
class FakeInstalledApps implements InstalledApps {
  FakeInstalledApps(this.apps);

  List<InstalledApp> apps;

  /// Lo que se abrió, en orden.
  final List<String> launched = [];

  /// Si Kyra es la pantalla de inicio, y las veces que se pidió serlo.
  bool launcher = false;
  int chooseCalls = 0;

  /// Si Kyra se ofrece como pantalla de inicio (de fábrica, sí: así las pruebas viejas no cambian) y lo que se pidió, en orden.
  bool launcherEnabled = true;
  final List<bool> launcherEnabledCalls = [];

  @override
  Future<bool> isDefaultLauncher() async => launcher && launcherEnabled;

  @override
  Future<bool> chooseLauncher() async {
    chooseCalls++;
    return true;
  }

  @override
  Future<bool> setLauncherEnabled(bool enabled) async {
    launcherEnabled = enabled;
    launcherEnabledCalls.add(enabled);
    return true;
  }

  @override
  Future<List<InstalledApp>> list() async => apps;

  @override
  Future<bool> launch(String package) async {
    launched.add(package);
    return apps.any((a) => a.package == package);
  }
}

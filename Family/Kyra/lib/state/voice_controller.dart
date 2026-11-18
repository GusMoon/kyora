import 'package:flutter/foundation.dart';

import '../data/voice_reader.dart';

/// La voz de KyraAdmin en Configuración → Voz: encenderla, dar el acceso a notificaciones, elegir de qué apps se leen y probarla. Con la
/// pantalla apagada, Android (el servicio `KyraNotificationListener`) lee en voz alta lo que llegue de esas apps.
class VoiceController extends ChangeNotifier {
  VoiceController(this._reader);

  final VoiceReader _reader;

  bool enabled = false;
  Set<String> packages = const {};

  /// ¿Ya tiene el acceso a notificaciones? (`null` hasta que se pregunta)
  bool? granted;
  bool _loaded = false;

  bool get loaded => _loaded;

  /// Lee la configuración y el permiso (al abrir la ficha y al volver de los ajustes de Android).
  Future<void> refresh() async {
    final config = await _reader.load();
    enabled = config.enabled;
    packages = config.packages;
    granted = await _reader.isAccessGranted();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    enabled = value;
    notifyListeners();
    await _save();
  }

  bool reads(String package) => packages.contains(package);

  /// Pone o quita una app de la lista que se lee.
  Future<void> toggle(String package) async {
    final next = {...packages};
    if (!next.remove(package)) next.add(package);
    packages = next;
    notifyListeners();
    await _save();
  }

  Future<void> openAccessSettings() => _reader.openAccessSettings();

  Future<void> test() => _reader.test('Mensaje de WhatsApp. Ana dice: ya llegué.');

  Future<void> _save() => _reader.save(VoiceConfig(enabled: enabled, packages: packages));
}

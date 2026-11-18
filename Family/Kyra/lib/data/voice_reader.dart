import 'package:flutter/services.dart';

/// La configuración de la voz de KyraAdmin: si está encendida y de qué apps se leen las notificaciones (por su paquete; `kyra.chat` es el
/// chat de Kyra).
class VoiceConfig {
  const VoiceConfig({this.enabled = false, this.packages = const {}});

  final bool enabled;
  final Set<String> packages;
}

/// La voz que lee las notificaciones con la pantalla apagada (la parte de Android está en `KyraNotificationListener.kt` y el canal
/// `kyora/voice` de `MainActivity.kt`). Los tests usan una falsa.
abstract class VoiceReader {
  /// ¿La persona ya le dio a Kyra el «acceso a notificaciones» en los ajustes de Android?
  Future<bool> isAccessGranted();

  /// Abre esos ajustes de Android.
  Future<void> openAccessSettings();

  Future<VoiceConfig> load();
  Future<void> save(VoiceConfig config);

  /// Dice una frase de ejemplo ya mismo.
  Future<void> test(String phrase);
}

/// El paquete fijo del chat de Kyra en la lista de apps de la voz.
const kyraChatPackage = 'kyra.chat';

class AndroidVoiceReader implements VoiceReader {
  static const _channel = MethodChannel('kyora/voice');

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> isAccessGranted() async => (await _call<bool>('isAccessGranted')) ?? false;

  @override
  Future<void> openAccessSettings() => _call<bool>('openAccessSettings');

  @override
  Future<VoiceConfig> load() async {
    final raw = await _call<Map<Object?, Object?>>('getConfig');
    if (raw == null) return const VoiceConfig();
    return VoiceConfig(
      enabled: (raw['enabled'] as bool?) ?? false,
      packages: {for (final p in (raw['packages'] as List<Object?>? ?? const [])) ?p as String?},
    );
  }

  @override
  Future<void> save(VoiceConfig config) => _call<bool>('setConfig', {'enabled': config.enabled, 'packages': config.packages.toList()});

  @override
  Future<void> test(String phrase) => _call<bool>('testSpeak', {'text': phrase});
}

class FakeVoiceReader implements VoiceReader {
  FakeVoiceReader({this.granted = false, this.config = const VoiceConfig()});

  bool granted;
  VoiceConfig config;
  int openedSettings = 0;
  final List<String> spoken = [];

  @override
  Future<bool> isAccessGranted() async => granted;

  @override
  Future<void> openAccessSettings() async => openedSettings++;

  @override
  Future<VoiceConfig> load() async => config;

  @override
  Future<void> save(VoiceConfig next) async => config = next;

  @override
  Future<void> test(String phrase) async => spoken.add(phrase);
}

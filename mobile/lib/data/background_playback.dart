import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Lo que hace falta del teléfono para que la música siga sonando con la app en segundo plano o la pantalla apagada.
/// El reproductor avisa cuando empieza y cuando para (`started` / `stopped`).
abstract class PlaybackHooks {
  /// Empezó a sonar: pide el permiso de las notificaciones (la primera vez) y mantiene despierta la red mientras suena.
  Future<void> started();

  /// Paró o hizo pausa: suelta lo que mantenía despierto.
  Future<void> stopped();
}

/// Además, el estado de la optimización de batería (los fabricantes matan los servicios en segundo plano si la app no está excluida).
abstract class BackgroundPlayback implements PlaybackHooks {
  /// ¿La app está excluida de la optimización de batería? (Entonces Android no la detiene en segundo plano.)
  Future<bool> batteryUnrestricted();

  /// Abre el aviso del sistema para excluir la app de la optimización de batería.
  Future<void> requestBatteryExemption();
}

/// El real: la parte de Android está en `MainActivity.kt` (canal `kyora/background`).
class AndroidBackgroundPlayback implements BackgroundPlayback {
  static const _channel = MethodChannel('kyora/background');

  bool _askedNotifications = false;

  @override
  Future<void> started() async {
    if (!_askedNotifications) {
      _askedNotifications = true;
      try {
        // Android 13 o más nuevo: sin este permiso la notificación con los controles no se ve y el sistema trata peor al servicio.
        await FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      } catch (_) {
        // sin permiso la música suena igual
      }
    }
    await _call('wifiLock', {'on': true});
  }

  @override
  Future<void> stopped() => _call('wifiLock', {'on': false});

  @override
  Future<bool> batteryUnrestricted() async => (await _call('batteryUnrestricted')) == true;

  @override
  Future<void> requestBatteryExemption() async {
    await _call('requestBatteryExemption');
  }

  Future<Object?> _call(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null; // sin código nativo (las pruebas) no hay nada que mantener
    }
  }
}

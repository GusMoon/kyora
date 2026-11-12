import 'package:flutter/services.dart';

/// El estado del teléfono para Inicio: batería, memoria, almacenamiento, Wi-Fi y Bluetooth. Lo que no se pudo leer va en `null`.
class SystemStats {
  const SystemStats({this.battery, this.charging = false, this.ramTotal, this.ramFree, this.storageTotal, this.storageFree, this.wifi, this.bluetooth});

  /// La batería, de 0 a 100.
  final int? battery;
  final bool charging;

  /// La memoria y el almacenamiento, en bytes.
  final int? ramTotal;
  final int? ramFree;
  final int? storageTotal;
  final int? storageFree;

  /// Encendidos o no (`null` si no se sabe).
  final bool? wifi;
  final bool? bluetooth;

  /// La memoria en uso, de 0 a 1.
  double? get ramUsed => ramTotal == null || ramFree == null || ramTotal! <= 0 ? null : ((ramTotal! - ramFree!) / ramTotal!).clamp(0.0, 1.0);

  /// El almacenamiento ocupado, de 0 a 1.
  double? get storageUsed =>
      storageTotal == null || storageFree == null || storageTotal! <= 0 ? null : ((storageTotal! - storageFree!) / storageTotal!).clamp(0.0, 1.0);

  static int? _int(Object? v) => v is num ? v.toInt() : null;

  factory SystemStats.fromMap(Map<Object?, Object?> map) => SystemStats(
    battery: _int(map['battery']),
    charging: map['charging'] == true,
    ramTotal: _int(map['ramTotal']),
    ramFree: _int(map['ramFree']),
    storageTotal: _int(map['storageTotal']),
    storageFree: _int(map['storageFree']),
    wifi: map['wifi'] as bool?,
    bluetooth: map['bluetooth'] as bool?,
  );
}

/// De dónde sale el estado del teléfono y cómo se abren los paneles del Wi-Fi y del Bluetooth.
abstract class SystemInfo {
  /// El estado ahora, o `null` si no se pudo leer.
  Future<SystemStats?> stats();

  /// Abre el panel del Wi-Fi del sistema (una app no puede encenderlo por su cuenta). `false` si no se pudo.
  Future<bool> openWifi();

  /// Abre los ajustes del Bluetooth. `false` si no se pudo.
  Future<bool> openBluetooth();
}

/// El real: la parte de Android está en `MainActivity.kt` (canal `kyora/system`).
class AndroidSystemInfo implements SystemInfo {
  static const _channel = MethodChannel('kyora/system');

  @override
  Future<SystemStats?> stats() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('stats');
      return raw == null ? null : SystemStats.fromMap(raw);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> _open(String method) async {
    try {
      return (await _channel.invokeMethod<bool>(method)) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> openWifi() => _open('openWifi');

  @override
  Future<bool> openBluetooth() => _open('openBluetooth');
}

/// Un teléfono de mentira, para las pruebas.
class FakeSystemInfo implements SystemInfo {
  FakeSystemInfo([this.current]);

  SystemStats? current;
  final List<String> opened = [];
  int reads = 0;

  @override
  Future<SystemStats?> stats() async {
    reads++;
    return current;
  }

  @override
  Future<bool> openWifi() async {
    opened.add('wifi');
    return true;
  }

  @override
  Future<bool> openBluetooth() async {
    opened.add('bluetooth');
    return true;
  }
}

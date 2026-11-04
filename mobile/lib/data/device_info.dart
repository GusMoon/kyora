import 'package:flutter/services.dart';

/// El espacio del teléfono, en bytes.
class StorageInfo {
  const StorageInfo({required this.total, required this.free});

  final int total;
  final int free;

  int get used => (total - free).clamp(0, total);

  /// La parte usada, de 0 a 1.
  double get usedFraction => total <= 0 ? 0 : used / total;
}

/// Lo que se pregunta al teléfono (en las pruebas, uno falso).
abstract class DeviceInfo {
  /// El almacenamiento interno, o `null` si no se puede saber.
  Future<StorageInfo?> storage();
}

/// Lee el espacio con `StatFs`, en `MainActivity.kt` (canal `kyora/device`).
class AndroidDeviceInfo implements DeviceInfo {
  static const _channel = MethodChannel('kyora/device');

  @override
  Future<StorageInfo?> storage() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('storage');
      final total = result?['total'], free = result?['free'];
      if (total is! num || free is! num || total <= 0) return null;
      return StorageInfo(total: total.toInt(), free: free.toInt());
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

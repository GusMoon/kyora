import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_backdrop.dart';

/// Marca lo que está dentro de la pantalla: ahí el fondo es el de la pantalla (las pantallas empujadas no pintan otro).
class DeviceScreen extends InheritedWidget {
  const DeviceScreen({super.key, required super.child});

  static bool isInside(BuildContext context) => context.getInheritedWidgetOfExactType<DeviceScreen>() != null;

  @override
  bool updateShouldNotify(DeviceScreen oldWidget) => false;
}

/// La app es **solo la pantalla**: de borde a borde del dispositivo. Lo de dentro ve los márgenes del
/// sistema (la barra de estado, la de gestos) tal cual, para colocarse fuera de ellos; las barras del sistema van transparentes y con los
/// iconos claros, sobre el fondo oscuro.
class DeviceShell extends StatelessWidget {
  const DeviceShell({super.key, required this.screen, this.screenKey});

  /// Lo que se ve en la pantalla.
  final Widget screen;

  /// La clave de la caja de la pantalla (para saber dónde está).
  final Key? screenKey;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: DeviceScreenFrame(key: screenKey, child: screen),
    );
  }
}

/// La pantalla: el fondo oscuro y lo de dentro.
class DeviceScreenFrame extends StatelessWidget {
  const DeviceScreenFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DeviceScreen(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const BackdropLayers(),
          child,
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Una sección de la app: su icono y su nombre (lo que enseña el menú circular) y la pantalla que se ve.
class AppSection {
  const AppSection({required this.id, required this.icon, required this.label, required this.builder});

  /// Con esto se encuentra su botón en el menú (`radial-<id>`) y se salta a ella (`SectionHost.goTo`).
  final String id;
  final IconData icon;
  final String label;
  final WidgetBuilder builder;
}

/// Una opción del menú circular que no es una sección sino una acción (por ejemplo, abrir la hoja de Configuración).
class NavAction {
  const NavAction({required this.id, required this.icon, required this.label, required this.run});

  final String id;
  final IconData icon;
  final String label;

  /// Lo que hace al elegirla; recibe el contexto de la sección que se ve.
  final void Function(BuildContext context) run;
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/pixel_glyph.dart';

/// Dibuja un círculo con el dedo (más de una vuelta, para que cuente): a la derecha (`clockwise`) salen las funciones; a la izquierda, las
/// apps. Se deja el dedo levantado y se espera a que el menú termine de salir.
Future<void> drawCircle(WidgetTester tester, {Offset? center, bool clockwise = true, double radius = 70}) async {
  final c = center ?? tester.getRect(find.byKey(SectionHost.screenKey)).center;
  final sign = clockwise ? 1.0 : -1.0;
  final gesture = await tester.startGesture(c + Offset(radius, 0));
  const steps = 40;
  for (var i = 1; i <= steps; i++) {
    await gesture.moveTo(c + Offset.fromDirection(sign * 2 * math.pi * 1.15 * i / steps, radius));
    await tester.pump(const Duration(milliseconds: 8));
  }
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 500)); // se proyecta el aro
}

/// Va a otra sección como lo haría el dedo: dibuja un círculo a la derecha (sale el aro de funciones), toca la opción `id` (`home`, `chat`,
/// `music`, `tasks`, `reminders`, `settings`…) y espera a que termine la animación.
Future<void> goToSection(WidgetTester tester, String id, {Offset? from}) async {
  await drawCircle(tester, center: from);
  await tester.tap(find.byKey(Key('radial-$id')), warnIfMissed: false);
  await tester.pumpAndSettle();
}

/// Las opciones que ofrece el menú circular: lo abre con un giro a la derecha, mira cuáles salen y lo cierra con «atrás».
Future<Set<String>> menuOptions(WidgetTester tester) async {
  await drawCircle(tester);
  final ids = <String>{
    for (final widget in tester.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('radial-'))))
      (widget.key! as ValueKey<String>).value.substring('radial-'.length),
  }..removeAll(['menu', 'label', 'veil', 'center', 'touch', 'turn-hint', 'all-hint', 'cut', 'edge', 'reactor']);
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  return ids;
}

/// Con la página de Configuración abierta, expande la ficha [id] del mosaico y espera a que acabe de moverse.
Future<void> openSettingsTile(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('mosaic-tile-$id')));
  await tester.pumpAndSettle();
}

/// Con Configuración abierta, expande la ficha de la cuenta: ahí está «Cerrar sesión».
Future<void> revealSignOut(WidgetTester tester) => openSettingsTile(tester, 'account');

/// Busca un icono de la app (pintado con bloques: `LcdIcon`) por su `IconData`.
Finder findIcon(IconData icon) => find.byWidgetPredicate((w) => w is LcdIcon && w.icon == icon, description: 'LcdIcon $icon');

/// Pide «menos animaciones» (como en el teléfono): la cinta del modo visitante se queda quieta y `pumpAndSettle` puede terminar.
void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

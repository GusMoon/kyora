import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/section_host.dart';

/// Va a otra sección como lo haría el dedo: mantiene el dedo en la pantalla hasta que sale el menú circular, lo desliza hasta la opción
/// `id` (`home`, `chat`, `music`, `tasks`, `reminders`, `settings`) y suelta. Espera a que termine la animación.
Future<void> goToSection(WidgetTester tester, String id, {Offset? from}) async {
  final screen = tester.getRect(find.byType(SectionHost));
  final start = from ?? screen.center;
  final gesture = await tester.startGesture(start);
  await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 300)); // salen los círculos
  await gesture.moveTo(tester.getCenter(find.byKey(Key('radial-$id'))));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Las opciones que ofrece el menú circular: lo abre manteniendo el dedo, mira cuáles salen y lo cierra soltando sin elegir ninguna.
Future<Set<String>> menuOptions(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getRect(find.byType(SectionHost)).center);
  await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 300));
  final ids = <String>{
    for (final widget in tester.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('radial-'))))
      (widget.key! as ValueKey<String>).value.substring('radial-'.length),
  }..removeAll(['menu', 'label']);
  await gesture.up();
  await tester.pumpAndSettle();
  return ids;
}

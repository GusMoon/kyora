import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/app_section.dart';
import 'package:kyora_chat/ui/widgets/radial_menu.dart';

import 'sections.dart';

void main() {
  group('geometría del círculo', () {
    const screen = Rect.fromLTWH(0, 0, 400, 800);
    final touches = [
      const Offset(200, 400), // centro
      const Offset(4, 400), // borde izquierdo
      const Offset(396, 400), // derecho
      const Offset(200, 4), // arriba
      const Offset(200, 796), // abajo
      const Offset(4, 4), // esquinas
      const Offset(396, 4),
      const Offset(4, 796),
      const Offset(396, 796),
    ];

    test('la primera opción va arriba y las demás en el sentido del reloj, repartiendo la vuelta entera', () {
      final g = RadialGeometry(count: 6, bounds: screen, touch: const Offset(200, 400));
      expect(g.angleOf(0), closeTo(-math.pi / 2, 1e-9));
      expect(g.positionOf(0).dx, closeTo(g.center.dx, 1e-9));
      expect(g.positionOf(0).dy, lessThan(g.center.dy));
      expect(g.positionOf(1).dx, greaterThan(g.center.dx)); // la siguiente, a la derecha
      expect(g.positionOf(3).dy, greaterThan(g.center.dy)); // la de en medio, abajo
      expect(g.step * 6, closeTo(2 * math.pi, 1e-9));
    });

    test('cada opción cae siempre en la misma dirección, se toque donde se toque', () {
      for (final count in [5, 6]) {
        final reference = RadialGeometry(count: count, bounds: screen, touch: const Offset(200, 400));
        for (final touch in touches) {
          final g = RadialGeometry(count: count, bounds: screen, touch: touch);
          for (var i = 0; i < count; i++) {
            final seen = g.positionOf(i) - g.center;
            final expected = reference.positionOf(i) - reference.center;
            expect((seen - expected).distance, closeTo(0, 1e-9), reason: '$count opciones, dedo en $touch, opción $i');
          }
        }
      }
    });

    test('todas las opciones quedan dentro de la pantalla, toques donde se toque', () {
      for (final count in [2, 4, 6, 7]) {
        for (final touch in touches) {
          final g = RadialGeometry(count: count, bounds: screen, touch: touch);
          for (var i = 0; i < count; i++) {
            final p = g.positionOf(i);
            final reason = '$count opciones, dedo en $touch, opción $i en $p';
            expect(p.dx - RadialGeometry.item / 2, greaterThanOrEqualTo(0), reason: reason);
            expect(p.dx + RadialGeometry.item / 2, lessThanOrEqualTo(400), reason: reason);
            expect(p.dy - RadialGeometry.item / 2, greaterThanOrEqualTo(0), reason: reason);
            expect(p.dy + RadialGeometry.item / 2, lessThanOrEqualTo(800), reason: reason);
          }
        }
      }
    });

    test('las opciones no se tocan entre sí, ni con la seleccionada más grande', () {
      for (final count in [5, 6, 7]) {
        final g = RadialGeometry(count: count, bounds: screen, touch: const Offset(200, 400));
        for (var i = 0; i < count; i++) {
          final next = g.positionOf((i + 1) % count);
          expect((next - g.positionOf(i)).distance, greaterThan(RadialGeometry.item * 1.28));
        }
      }
    });

    test('el centro solo se corre si hace falta: en el medio de la pantalla se queda donde está el dedo', () {
      final g = RadialGeometry(count: 6, bounds: screen, touch: const Offset(200, 400));
      expect(g.center, const Offset(200, 400));
      expect(RadialGeometry(count: 6, bounds: screen, touch: const Offset(4, 4)).center, isNot(const Offset(4, 4)));
    });

    test('se elige por el ángulo, en cualquier dirección; solo en el centro no se elige nada', () {
      final g = RadialGeometry(count: 6, bounds: screen, touch: const Offset(200, 400));
      for (var i = 0; i < 6; i++) {
        expect(g.pick(g.center + Offset.fromDirection(g.angleOf(i), 80)), i);
        expect(g.pick(g.center + Offset.fromDirection(g.angleOf(i), 200)), i); // da igual cuánto se aleje el dedo
        expect(g.pick(g.center + Offset.fromDirection(g.angleOf(i) + g.step * 0.4, 80)), i); // ni que no apunte justo
        expect(g.pick(g.center + Offset.fromDirection(g.angleOf(i) - g.step * 0.4, 80)), i);
      }
      expect(g.pick(g.center + const Offset(10, 10)), isNull); // zona muerta del centro
      for (var degrees = 0; degrees < 360; degrees += 7) {
        expect(g.pick(g.center + Offset.fromDirection(degrees * math.pi / 180, 90)), isNotNull, reason: '$degrees°'); // ya no hay hueco
      }
    });
  });

  group('el menú en pantalla', () {
    late List<String> ran;

    Future<void> open(WidgetTester tester, {List<String> ids = const ['home', 'chat', 'music', 'tasks'], Widget Function(BuildContext)? body}) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ran = [];
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SectionHost(
          sections: [
            for (final id in ids)
              AppSection(id: id, icon: Icons.circle_outlined, label: 'Sección $id', builder: id == 'home' && body != null ? body : (_) => Scaffold(body: Center(child: Text('Pantalla $id')))),
          ],
          actions: [NavAction(id: 'settings', icon: Icons.settings_outlined, label: 'Configuración', run: (_) => ran.add('settings'))],
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no sale antes de tiempo y sale al mantener el dedo', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(const Offset(200, 400));
      await tester.pump(SectionHost.holdTime - const Duration(milliseconds: 100));
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('radial-menu')), findsOneWidget);
      for (final id in ['home', 'chat', 'music', 'tasks', 'settings']) {
        expect(find.byKey(Key('radial-$id')), findsOneWidget, reason: id);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('radial-menu')), findsNothing);
    });

    testWidgets('un toque corto no lo abre y sigue pulsando lo de debajo', (tester) async {
      var taps = 0;
      await open(tester, body: (_) => Scaffold(body: Center(child: TextButton(key: const Key('tap-me'), onPressed: () => taps++, child: const Text('toca')))));
      await tester.tap(find.byKey(const Key('tap-me')));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.byKey(const Key('radial-menu')), findsNothing);
    });

    testWidgets('si el dedo se mueve antes de tiempo (un desplazamiento) no se abre y la lista se desplaza', (tester) async {
      await open(tester, body: (_) => Scaffold(body: ListView(children: [for (var i = 0; i < 40; i++) SizedBox(height: 80, child: Text('fila $i'))])));
      final gesture = await tester.startGesture(const Offset(200, 500));
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 200));
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      await gesture.moveBy(const Offset(0, -200));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('fila 0'), findsNothing); // se desplazó
    });

    testWidgets('soltar sin elegir (sin mover el dedo) cancela y no cambia de sección', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(const Offset(200, 400));
      await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Pantalla home'), findsOneWidget);
    });

    testWidgets('al deslizar hacia una opción se resalta con su nombre en el centro y al soltar se va a ella', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(const Offset(200, 400));
      await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 400));
      expect(find.byKey(const Key('radial-label')), findsNothing); // aún sin elegir
      await gesture.moveTo(tester.getCenter(find.byKey(const Key('radial-music'))));
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('radial-label'))).data, 'Sección music');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Pantalla music'), findsOneWidget);
      expect(find.byKey(const Key('radial-menu')), findsNothing);
    });

    testWidgets('si se vuelve al centro antes de soltar, se cancela', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(const Offset(200, 400));
      await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 400));
      await gesture.moveTo(tester.getCenter(find.byKey(const Key('radial-chat'))));
      await tester.pump();
      expect(find.byKey(const Key('radial-label')), findsOneWidget);
      await gesture.moveTo(const Offset(205, 402));
      await tester.pump();
      expect(find.byKey(const Key('radial-label')), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('Pantalla home'), findsOneWidget);
    });

    testWidgets('Configuración es una acción: no cambia de sección, hace lo suyo', (tester) async {
      await open(tester);
      await goToSection(tester, 'settings');
      expect(ran, ['settings']);
      expect(find.text('Pantalla home'), findsOneWidget);
    });

    testWidgets('con el dedo en cada esquina todas las opciones están a la vista', (tester) async {
      await open(tester);
      for (final touch in const [Offset(6, 6), Offset(394, 6), Offset(6, 794), Offset(394, 794)]) {
        final gesture = await tester.startGesture(touch);
        await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 400));
        for (final id in ['home', 'chat', 'music', 'tasks', 'settings']) {
          final r = tester.getRect(find.byKey(Key('radial-$id')));
          expect(r.left, greaterThanOrEqualTo(0), reason: '$id con el dedo en $touch');
          expect(r.right, lessThanOrEqualTo(400), reason: '$id con el dedo en $touch');
          expect(r.top, greaterThanOrEqualTo(0), reason: '$id con el dedo en $touch');
          expect(r.bottom, lessThanOrEqualTo(800), reason: '$id con el dedo en $touch');
        }
        await gesture.up();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('el orden es el mismo con el dedo en el centro y en una esquina: no gira', (tester) async {
      await open(tester);
      Future<Map<String, Offset>> around(Offset touch) async {
        final gesture = await tester.startGesture(touch);
        await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 400));
        final home = tester.getCenter(find.byKey(const Key('radial-home')));
        final seen = {for (final id in ['chat', 'music', 'tasks', 'settings']) id: tester.getCenter(find.byKey(Key('radial-$id'))) - home};
        await gesture.up();
        await tester.pumpAndSettle();
        return seen;
      }

      final middle = await around(const Offset(200, 400));
      final corner = await around(const Offset(394, 794));
      for (final id in middle.keys) {
        expect((middle[id]! - corner[id]!).distance, closeTo(0, 0.01), reason: id);
      }
    });

    testWidgets('con el menú abierto todo lo de debajo se ve borroso, de borde a borde', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(const Offset(200, 400));
      await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 400));
      final blur = find.byKey(const Key('radial-blur'));
      expect(tester.widget(blur), isA<BackdropFilter>());
      expect(tester.getRect(blur), const Rect.fromLTWH(0, 0, 400, 800));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(blur, findsNothing);
    });

    testWidgets('la sección en la que se está va marcada', (tester) async {
      await open(tester);
      await goToSection(tester, 'tasks');
      final gesture = await tester.startGesture(const Offset(200, 400));
      await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 400));
      BoxDecoration of(String id) => tester.widget<DecoratedBox>(find.byKey(Key('radial-$id'))).decoration as BoxDecoration;
      expect(of('tasks').border!.top.width, greaterThan(of('home').border!.top.width));
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('una pulsación larga de dentro de la pantalla gana: ahí no sale el menú', (tester) async {
      var held = 0;
      await open(tester, body: (_) => Scaffold(body: Center(child: GestureDetector(onLongPress: () => held++, child: Container(key: const Key('held'), width: 200, height: 200, color: Colors.red)))));
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('held'))));
      await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(held, 1);
      expect(find.byKey(const Key('radial-menu')), findsNothing);
    });

    testWidgets('el menú no lleva ninguna capa de opacidad (los círculos crecen, no se funden)', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(const Offset(200, 400));
      await tester.pump(SectionHost.holdTime + const Duration(milliseconds: 50));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.descendant(of: find.byKey(const Key('radial-menu')), matching: find.byWidgetPredicate((w) => w is Opacity || w is FadeTransition || w is AnimatedOpacity)), findsNothing);
      }
      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/app_section.dart';
import 'package:kyora_chat/ui/widgets/pixel_glyph.dart';
import 'package:kyora_chat/ui/widgets/radial_menu.dart';

import 'sections.dart';

const _icons = {'home': Icons.home_outlined, 'chat': Icons.chat_bubble_outline, 'music': Icons.music_note_outlined, 'tasks': Icons.checklist_rounded};

/// El icono del disco del centro.
IconData? centerIcon(WidgetTester tester) => tester.widget<LcdIcon>(find.byKey(const Key('radial-center'))).icon;

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
              AppSection(id: id, icon: _icons[id] ?? Icons.circle_outlined, label: 'Sección $id', builder: id == 'home' && body != null ? body : (_) => Scaffold(body: Center(child: Text('Pantalla $id')))),
          ],
          actions: [NavAction(id: 'settings', icon: Icons.settings_outlined, label: 'Configuración', run: (_) => ran.add('settings'))],
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no sale con un toque ni manteniendo el dedo; sale con un giro a la derecha y se ven las opciones', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(200, 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      final hold = await tester.startGesture(const Offset(200, 400));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      await hold.up();
      await drawCircle(tester);
      expect(find.byKey(const Key('radial-menu')), findsOneWidget);
      for (final id in ['home', 'chat', 'music', 'tasks', 'settings']) {
        expect(find.byKey(Key('radial-$id')), findsOneWidget, reason: id);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('radial-menu')), findsNothing);
    });

    testWidgets('un toque corto sigue pulsando lo de debajo', (tester) async {
      var taps = 0;
      await open(tester, body: (_) => Scaffold(body: Center(child: TextButton(key: const Key('tap-me'), onPressed: () => taps++, child: const Text('toca')))));
      await tester.tap(find.byKey(const Key('tap-me')));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(find.byKey(const Key('radial-menu')), findsNothing);
    });

    testWidgets('un desplazamiento en línea recta no abre el menú y la lista se desplaza', (tester) async {
      await open(tester, body: (_) => Scaffold(body: ListView(children: [for (var i = 0; i < 40; i++) SizedBox(height: 80, child: Text('fila $i'))])));
      final gesture = await tester.startGesture(const Offset(200, 600));
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(0, -12));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      expect(find.text('fila 0'), findsNothing); // se desplazó
    });

    testWidgets('con un giro a la izquierda sale el aro de apps (sin dock, vacío), no el de funciones', (tester) async {
      await open(tester);
      await drawCircle(tester, clockwise: false);
      expect(find.byKey(const Key('radial-menu')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('radial-label'))).data, 'APPS');
      expect(find.byKey(const Key('radial-chat')), findsNothing);
    });

    testWidgets('el menú se abre donde se dibujó el círculo, con su icono y su nombre en el centro', (tester) async {
      await open(tester);
      await drawCircle(tester);
      expect(centerIcon(tester), Icons.home_outlined); // aún sin elegir: la sección en la que se está
      expect(tester.widget<Text>(find.byKey(const Key('radial-label'))).data, 'Sección home');
    });

    testWidgets('Configuración es una acción: no cambia de sección, hace lo suyo', (tester) async {
      await open(tester);
      await goToSection(tester, 'settings');
      expect(ran, ['settings']);
      expect(find.text('Pantalla home'), findsOneWidget);
    });

    testWidgets('con el círculo dibujado cerca de una esquina todas las opciones están a la vista, dentro de la pantalla', (tester) async {
      await open(tester);
      final screen = tester.getRect(find.byKey(SectionHost.screenKey));
      for (final at in [const Offset(120, 140), const Offset(280, 140), const Offset(120, 660), const Offset(280, 660)]) {
        await drawCircle(tester, center: at, radius: 60);
        for (final id in ['home', 'chat', 'music', 'tasks', 'settings']) {
          final r = tester.getRect(find.byKey(Key('radial-$id')));
          expect(r.left, greaterThanOrEqualTo(screen.left), reason: '$id con el círculo en $at');
          expect(r.right, lessThanOrEqualTo(screen.right), reason: '$id con el círculo en $at');
          expect(r.top, greaterThanOrEqualTo(screen.top), reason: '$id con el círculo en $at');
          expect(r.bottom, lessThanOrEqualTo(screen.bottom), reason: '$id con el círculo en $at');
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('con el menú abierto el contenido cercano se corta para dejarle sitio y baja de opacidad, sin desenfoque ni oscurecer nada', (tester) async {
      await open(tester);
      final cut = find.byKey(const Key('radial-cut'));
      expect(tester.widget<ClipPath>(cut).clipBehavior, Clip.none); // sin menú: el contenido va entero
      await drawCircle(tester, center: const Offset(200, 400));
      final clipper = tester.widget<ClipPath>(cut).clipper!;
      final path = clipper.getClip(const Size(400, 800));
      final hole = tester.getCenter(find.byKey(const Key('radial-label')));
      expect(path.contains(hole), isFalse); // donde está el reactor, el contenido se ha cortado
      expect(path.contains(const Offset(5, 5)), isTrue); // lo de lejos sigue ahí
      expect(tester.widget<ClipPath>(cut).clipBehavior, isNot(Clip.none));
      final opacity = tester.widget<Opacity>(find.descendant(of: cut, matching: find.byType(Opacity)).first).opacity;
      expect(opacity, lessThan(1)); // el contenido baja el tono...
      expect(opacity, greaterThan(0.4)); // ...pero se sigue viendo
      expect(find.byType(BackdropFilter), findsNothing); // nada de desenfoque
      expect(find.byKey(const Key('focus-veil')), findsNothing);
      expect(find.byKey(const Key('radial-edge')), findsOneWidget); // el borde del hueco se deshace en fragmentos
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(tester.widget<ClipPath>(cut).clipBehavior, Clip.none);
      expect(tester.widget<Opacity>(find.descendant(of: cut, matching: find.byType(Opacity)).first).opacity, 1);
    });

    test('el hueco crece con suavidad desde nada hasta su tamaño y su borde es un círculo cuando termina', () {
      const c = Offset(200, 400);
      expect(RadialCutout.path(c, 0).getBounds().width, 0);
      var last = 0.0;
      for (var i = 1; i <= 10; i++) {
        final w = RadialCutout.path(c, i / 10).getBounds().width;
        expect(w, greaterThanOrEqualTo(last - RadialCutout.radius * 0.3)); // salta algo, pero crece
        last = w;
      }
      final done = RadialCutout.path(c, 1);
      expect(done.getBounds().width, closeTo(RadialCutout.radius * 2, 4));
      expect(done.contains(c + const Offset(RadialCutout.radius * 0.9, 0)), isTrue);
      expect(done.contains(c + const Offset(RadialCutout.radius * 1.1, 0)), isFalse);
    });

    testWidgets('el reactor gira mientras el menú está abierto y se para al cerrarlo', (tester) async {
      ReactorSpin.enabled = true;
      addTearDown(() => ReactorSpin.enabled = false);
      await open(tester);
      await drawCircle(tester);
      CustomPaint reactor() => tester.widget<CustomPaint>(find.byKey(const Key('radial-reactor')));
      final spin = (reactor().painter! as dynamic).spin as Animation<double>;
      final before = spin.value;
      await tester.pump(const Duration(seconds: 2));
      expect(spin.value, isNot(before)); // da vueltas
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pumpAndSettle(); // al cerrar ya no hay animación que espere
    });

    testWidgets('la sección en la que se está va marcada', (tester) async {
      await open(tester);
      await goToSection(tester, 'tasks');
      await drawCircle(tester);
      BoxDecoration of(String id) => tester.widget<DecoratedBox>(find.byKey(Key('radial-$id'))).decoration as BoxDecoration;
      expect(of('tasks').border, isNotNull); // la actual lleva un aro de acento
      expect(of('home').border, isNull);
      expect(of('tasks').border!.top.color, KyoraColors.classic().accent);
    });

    testWidgets('con iconos de puntos, el menú los pinta en vez de los iconos normales', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SectionHost(sections: [
          AppSection(id: 'home', icon: Icons.home_outlined, glyph: PixelGlyphs.home, label: 'Inicio', builder: (_) => const Scaffold(body: Text('Pantalla home'))),
          AppSection(id: 'music', icon: Icons.music_note_outlined, glyph: PixelGlyphs.music, label: 'Música', builder: (_) => const Scaffold(body: Text('Pantalla music'))),
        ]),
      ));
      await tester.pumpAndSettle();
      await drawCircle(tester);
      expect(find.descendant(of: find.byKey(const Key('radial-music')), matching: find.byType(PixelIcon)), findsOneWidget);
      expect(tester.widget<PixelIcon>(find.byKey(const Key('radial-center'))).glyph, PixelGlyphs.home);
    });
  });
}

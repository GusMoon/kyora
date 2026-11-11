import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/installed_apps.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/widgets/apps_arch.dart';
import 'package:kyora_chat/ui/widgets/swirl_detector.dart';

import 'home_page_test.dart' show app;

/// Los puntos de un círculo de radio `r` alrededor de `c`, de `turns` vueltas, uno cada `step` ms.
Swirl? feed(SwirlTracker t, {required Offset c, double r = 70, double turns = 1.0, bool clockwise = true, int points = 40, int step = 16}) {
  Swirl? found;
  final sign = clockwise ? 1.0 : -1.0;
  for (var i = 0; i <= points; i++) {
    found ??= t.add(c + Offset.fromDirection(sign * 2 * math.pi * turns * i / points, r), Duration(milliseconds: i * step));
  }
  return found;
}

void main() {
  group('reconocer un giro del dedo', () {
    test('una vuelta a la derecha se reconoce, con su centro y su sentido', () {
      final swirl = feed(SwirlTracker(), c: const Offset(200, 400));
      expect(swirl, isNotNull);
      expect(swirl!.clockwise, isTrue);
      expect((swirl.center - const Offset(200, 400)).distance, lessThan(50));
    });

    test('una vuelta a la izquierda se reconoce como tal', () {
      final swirl = feed(SwirlTracker(), c: const Offset(200, 400), clockwise: false);
      expect(swirl, isNotNull);
      expect(swirl!.clockwise, isFalse);
    });

    test('media vuelta no basta', () {
      expect(feed(SwirlTracker(), c: const Offset(200, 400), turns: 0.5), isNull);
    });

    test('una raya recta (desplazarse por una lista) no es un giro', () {
      final t = SwirlTracker();
      Swirl? found;
      for (var i = 0; i < 60; i++) {
        found ??= t.add(Offset(200, 700 - i * 8.0), Duration(milliseconds: i * 16));
      }
      expect(found, isNull);
    });

    test('ir y volver en zigzag tampoco', () {
      final t = SwirlTracker();
      Swirl? found;
      for (var i = 0; i < 80; i++) {
        final phase = (i % 20) / 20; // sube y baja
        final y = 500 - (phase < 0.5 ? phase : 1 - phase) * 200;
        found ??= t.add(Offset(200 + (i % 3), y), Duration(milliseconds: i * 16));
      }
      expect(found, isNull);
    });

    test('un temblor pequeño o un círculo enorme no cuentan', () {
      expect(feed(SwirlTracker(), c: const Offset(200, 400), r: 6), isNull);
      expect(feed(SwirlTracker(), c: const Offset(200, 400), r: 400), isNull);
    });

    test('hecho muy despacio (fuera de la ventana de tiempo) no cuenta', () {
      expect(feed(SwirlTracker(), c: const Offset(200, 400), step: 200), isNull);
    });

    test('al reiniciar se olvida lo anterior', () {
      final t = SwirlTracker();
      feed(t, c: const Offset(200, 400), turns: 0.6);
      t.reset();
      expect(feed(t, c: const Offset(200, 400), turns: 0.6), isNull);
    });
  });

  group('el detector sobre la pantalla', () {
    Future<void> show(WidgetTester tester, List<Swirl> seen, {bool enabled = true}) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: SwirlDetector(enabled: enabled, onSwirl: seen.add, child: const SizedBox.expand())));
    }

    Future<void> circle(WidgetTester tester, {int fingers = 1}) async {
      final gesture = await tester.startGesture(const Offset(270, 400));
      TestGesture? second;
      if (fingers == 2) second = await tester.startGesture(const Offset(50, 50));
      for (var i = 1; i <= 40; i++) {
        await gesture.moveTo(const Offset(200, 400) + Offset.fromDirection(2 * math.pi * 1.15 * i / 40, 70));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await second?.up();
    }

    testWidgets('avisa una sola vez por giro', (tester) async {
      final seen = <Swirl>[];
      await show(tester, seen);
      await circle(tester);
      expect(seen, hasLength(1));
      expect(seen.single.clockwise, isTrue);
    });

    testWidgets('con dos dedos (un pellizco) no mira', (tester) async {
      final seen = <Swirl>[];
      await show(tester, seen);
      await circle(tester, fingers: 2);
      expect(seen, isEmpty);
    });

    testWidgets('desactivado no hace nada', (tester) async {
      final seen = <Swirl>[];
      await show(tester, seen, enabled: false);
      await circle(tester);
      expect(seen, isEmpty);
    });
  });

  group('las apps en forma de «n»', () {
    final arch = ArchPath(size: const Size(400, 800), insets: const EdgeInsets.only(top: 30, bottom: 20));

    test('empieza abajo a la izquierda, sube pegada al borde, pasa por la cima en el centro y baja por la derecha', () {
      final (start, _) = arch.at(0);
      final (end, _) = arch.at(arch.length);
      expect(start.dx, closeTo(arch.left, 0.01));
      expect(end.dx, closeTo(arch.right, 0.01));
      expect(start.dy, closeTo(arch.yBottom, 0.01));
      expect(end.dy, closeTo(arch.yBottom, 0.01));
      final (top, _) = arch.at(arch.apex);
      expect(top.dy, closeTo(arch.yTop, 0.5));
      expect(top.dx, closeTo(200, 1));
    });

    test('es una sola curva sin tramos rectos: la dirección cambia poco a poco, siempre hacia el mismo lado', () {
      var previous = arch.at(1).$2;
      for (var s = 6.0; s < arch.length - 1; s += 5) {
        final angle = arch.at(s).$2;
        var turn = angle - previous;
        while (turn > math.pi) {
          turn -= 2 * math.pi;
        }
        while (turn < -math.pi) {
          turn += 2 * math.pi;
        }
        expect(turn, greaterThanOrEqualTo(-0.001), reason: 's=$s'); // gira siempre hacia la derecha (en el sentido del reloj)
        expect(turn, lessThan(0.3), reason: 's=$s'); // y sin esquinas
        previous = angle;
      }
    });

    test('es continuo: dos puntos seguidos nunca saltan y nada se sale de la pantalla', () {
      var previous = arch.at(0).$1;
      for (var s = 1.0; s <= arch.length; s += 1) {
        final p = arch.at(s).$1;
        expect((p - previous).distance, lessThan(1.5), reason: 's=$s');
        expect(p.dx, inInclusiveRange(0, 400));
        expect(p.dy, inInclusiveRange(0, 800));
        previous = p;
      }
    });

    test('el punto más cercano a un toque da su distancia en la curva', () {
      final (p, _) = arch.at(300);
      expect(arch.nearest(p + const Offset(2, 2)), closeTo(300, arch.length / 200));
    });
  });

  group('todas las apps a pantalla completa', () {
    Future<void> show(WidgetTester tester, List<InstalledApp> apps, List<String> opened, {Size size = const Size(400, 800)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: AppsArch(apps: apps, onOpen: (a) => opened.add(a.package), onClose: () => opened.add('cerrado')))));
      await tester.pumpAndSettle();
    }

    /// La letra resaltada en la columna (la de la app que está en la cima).
    String? highlighted(WidgetTester tester) {
      for (final l in AppsArch.letters) {
        final box = tester.widget<Container>(find.descendant(of: find.byKey(Key('letter-$l')), matching: find.byType(Container)));
        if (box.color != null) return l;
      }
      return null;
    }

    testWidgets('las apps van solo con el icono (sin nombre) por la curva y el abecedario en columna en el centro; nada se oscurece', (tester) async {
      await show(tester, [for (var i = 0; i < 20; i++) app('com.a$i', 'App $i')], []);
      expect(find.text('App 0'), findsNothing); // sin nombres
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byKey(const Key('focus-veil')), findsNothing);
      final first = tester.getCenter(find.byKey(const Key('arch-app-com.a0')));
      expect(first.dx, lessThan(80)); // la primera, abajo en el borde izquierdo
      expect(first.dy, greaterThan(500));
      final letters = [for (final l in AppsArch.letters) tester.getCenter(find.byKey(Key('letter-$l')))];
      for (final c in letters) {
        expect(c.dx, closeTo(200, 1)); // todas en el centro
      }
      for (var i = 1; i < letters.length; i++) {
        expect(letters[i].dy, greaterThan(letters[i - 1].dy)); // en columna, de la A a la #
      }
    });

    testWidgets('al abrirse entran por abajo a la izquierda y se deslizan por la curva hasta dejar la primera app en el arranque', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: AppsArch(apps: [for (var i = 0; i < 12; i++) app('com.a$i', 'App $i')], onOpen: (_) {}, onClose: () {}))));
      await tester.pump();
      expect(find.byKey(const Key('arch-app-com.a0')), findsNothing); // aún no ha entrado: está antes del arranque
      await tester.pump(AppsArch.entering * 0.7); // casi llegada: aún en el tramo de abajo
      final mid = tester.getCenter(find.byKey(const Key('arch-app-com.a0')));
      await tester.pumpAndSettle();
      final end = tester.getCenter(find.byKey(const Key('arch-app-com.a0')));
      expect(mid.dy, greaterThan(end.dy)); // por el camino: aún más abajo (más cerca de donde entra) que en su sitio final
      expect(end.dx, lessThan(80));
      expect(end.dy, greaterThan(500));
    });

    testWidgets('al arrastrar por la curva las apps siguen al dedo y la letra de la columna es la de la que llega a la cima', (tester) async {
      final apps = [for (final l in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) app('com.${l.toLowerCase()}', '${l}pp')];
      await show(tester, apps, []);
      final before = tester.getCenter(find.byKey(const Key('arch-app-com.d')));
      final startLetter = highlighted(tester);
      expect(startLetter, isNotNull);
      await tester.dragFrom(const Offset(34, 300), const Offset(0, 160)); // por el borde izquierdo, hacia abajo: llegan más apps
      await tester.pumpAndSettle();
      final after = tester.getCenter(find.byKey(const Key('arch-app-com.d')));
      expect(after.dy, greaterThan(before.dy));
      expect(highlighted(tester), isNot(startLetter)); // otra app está ahora en la cima
      expect(highlighted(tester)!.codeUnitAt(0), greaterThan(startLetter!.codeUnitAt(0)));
    });

    testWidgets('tocar una letra lleva a la primera app con esa inicial hasta la cima', (tester) async {
      final apps = [for (final l in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) app('com.${l.toLowerCase()}', '${l}pp')];
      await show(tester, apps, []);
      await tester.tap(find.byKey(const Key('letter-T')));
      await tester.pumpAndSettle();
      expect(highlighted(tester), 'T');
      final top = tester.getCenter(find.byKey(const Key('arch-app-com.t')));
      expect(top.dx, closeTo(200, 6)); // en la cima, en el centro
      await tester.tap(find.byKey(const Key('letter-B')));
      await tester.pumpAndSettle();
      expect(highlighted(tester), 'B');
    });

    testWidgets('arrastrar por la columna del abecedario cambia de letra; una letra sin apps no se puede elegir', (tester) async {
      final apps = [app('com.alfa', 'Alfa'), app('com.beta', 'Beta'), app('com.cesar', 'César')];
      await show(tester, apps, []);
      final a = tester.getCenter(find.byKey(const Key('letter-A')));
      await tester.dragFrom(a, tester.getCenter(find.byKey(const Key('letter-C'))) - a);
      await tester.pumpAndSettle();
      expect(highlighted(tester), 'C');
      await tester.tap(find.byKey(const Key('letter-Q')));
      await tester.pumpAndSettle();
      expect(highlighted(tester), 'C'); // sigue igual
    });

    testWidgets('tocar una app la abre y la cruz cierra; lo que no empieza por letra va en «#»', (tester) async {
      final opened = <String>[];
      await show(tester, [app('com.uno', '1Password'), app('com.zeta', 'Zeta')], opened);
      await tester.tap(find.byKey(const Key('letter-#')));
      await tester.pumpAndSettle();
      expect(highlighted(tester), '#');
      await tester.tap(find.byKey(const Key('arch-app-com.uno')));
      await tester.tap(find.byKey(const Key('arch-close')));
      expect(opened, ['com.uno', 'cerrado']);
    });

    testWidgets('en una pantalla baja no se desborda', (tester) async {
      await show(tester, [for (var i = 0; i < 40; i++) app('com.a$i', 'Aplicación $i')], [], size: const Size(320, 560));
      expect(tester.takeException(), isNull);
    });
  });
}

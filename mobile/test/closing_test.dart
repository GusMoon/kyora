import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/app_section.dart';
import 'package:kyora_chat/ui/widgets/focus_space.dart';
import 'package:kyora_chat/ui/widgets/hack_text.dart';
import 'package:kyora_chat/ui/widgets/radial_menu.dart';
import 'package:kyora_chat/ui/widgets/section_motion.dart';

import 'sections.dart';

/// Lo que se ve de un texto que se deshace.
String shownText(WidgetTester tester, Finder finder) {
  final rich = tester.widget<Text>(finder);
  return rich.textSpan?.toPlainText() ?? rich.data ?? '';
}

void main() {
  group('el texto también se deshace al irse', () {
    setUp(() => HackText.enabled = true);
    tearDown(() => HackText.enabled = false);

    Future<void> pumpText(WidgetTester tester, Animation<double> animation, {required bool leaving}) => tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: SectionMotion(
          animation: animation,
          leaving: leaving,
          moving: true,
          child: const Scaffold(body: HackText('Hola mundo cruel', textKey: Key('t'))),
        ),
      ),
    );

    testWidgets('en la sección que se va, las letras se convierten en signos y desaparecen de derecha a izquierda', (tester) async {
      final controller = AnimationController(vsync: const TestVSync(), duration: SectionMotion.total);
      addTearDown(controller.dispose);
      await pumpText(tester, controller, leaving: true);
      expect(shownText(tester, find.byKey(const Key('t'))), 'Hola mundo cruel'); // al empezar, entero
      controller.value = SectionMotion.exitTime.inMilliseconds / 2 / SectionMotion.total.inMilliseconds;
      await tester.pump();
      final mid = tester.widget<Text>(find.byKey(const Key('t'))).textSpan! as TextSpan;
      final parts = [for (final c in mid.children!) (c as TextSpan).text ?? ''];
      expect(parts[0], isNotEmpty); // lo que queda, a la izquierda
      expect(parts[1], isNotEmpty); // signos cambiantes
      expect('Hola mundo cruel'.startsWith(parts[0]), isTrue);
      controller.value = SectionMotion.exitTime.inMilliseconds / SectionMotion.total.inMilliseconds;
      await tester.pump();
      final end = tester.widget<Text>(find.byKey(const Key('t'))).textSpan! as TextSpan;
      expect((end.children![0] as TextSpan).text, isEmpty); // no queda nada escrito
      expect((end.children![1] as TextSpan).text, isEmpty);
    });

    testWidgets('en la que llega no se deshace: se escribe', (tester) async {
      final controller = AnimationController(vsync: const TestVSync(), duration: SectionMotion.total)..value = 1;
      addTearDown(controller.dispose);
      await pumpText(tester, controller, leaving: false);
      await tester.pumpAndSettle();
      expect(shownText(tester, find.byKey(const Key('t'))), 'Hola mundo cruel');
    });

    testWidgets('con HackExit, al cerrarse el panel (la animación baja) se deshace; al abrirse (sube) no', (tester) async {
      final controller = AnimationController(vsync: const TestVSync(), duration: const Duration(milliseconds: 400), value: 1);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: HackExit(animation: controller, child: const HackText('Hola mundo cruel', textKey: Key('t'))))));
      await tester.pumpAndSettle();
      expect(shownText(tester, find.byKey(const Key('t'))), 'Hola mundo cruel');
      unawaited(controller.reverse());
      await tester.pump(); // el primer cuadro solo fija la hora de salida
      await tester.pump(const Duration(milliseconds: 200));
      final span = tester.widget<Text>(find.byKey(const Key('t'))).textSpan! as TextSpan;
      expect((span.children![2] as TextSpan).text, isNotEmpty); // y ya hay parte deshecha
      await tester.pump(const Duration(milliseconds: 190));
      final gone = tester.widget<Text>(find.byKey(const Key('t'))).textSpan! as TextSpan;
      expect((gone.children![0] as TextSpan).text, isEmpty); // casi al final no queda nada escrito
      await tester.pumpAndSettle();
    });
  });

  group('el panel focal se deshace al cerrarse', () {
    testWidgets('al cerrarlo no desaparece de golpe: sigue ahí un momento, parpadeando, y luego se va', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox.expand();
      }))));
      unawaited(showFocusPanel<void>(ctx, title: 'Opciones', builder: (_) => const SizedBox(height: 80, child: Text('dentro'))));
      await tester.pumpAndSettle();
      Navigator.of(ctx).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('focus-panel')), findsOneWidget); // se está yendo
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('focus-panel')), findsNothing);
    });
  });

  group('el menú circular', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: SectionHost(
          sections: [
            AppSection(id: 'home', icon: Icons.home_outlined, label: 'Inicio', builder: (_) => const Scaffold(body: Center(child: Text('Pantalla home')))),
            AppSection(id: 'music', icon: Icons.music_note_outlined, label: 'Música', builder: (_) => const Scaffold(body: Center(child: Text('Pantalla music')))),
          ],
        ),
      ));
      await tester.pumpAndSettle();
    }

    double ringScale(WidgetTester tester) => tester.widget<ScaleTransition>(find.descendant(of: find.byKey(const Key('radial-menu')), matching: find.byType(ScaleTransition)).first).scale.value;

    double ringOpacity(WidgetTester tester) => tester.widget<Opacity>(find.descendant(of: find.byType(ScaleTransition), matching: find.byType(Opacity)).first).opacity;

    Future<void> circleQuickly(WidgetTester tester) async {
      final gesture = await tester.startGesture(const Offset(270, 400));
      for (var i = 1; i <= 40; i++) {
        await gesture.moveTo(const Offset(200, 400) + Offset.fromDirection(2 * 3.14159 * 1.15 * i / 40, 70));
        await tester.pump(const Duration(milliseconds: 8));
        if (find.byKey(const Key('radial-menu')).evaluate().isNotEmpty) break;
      }
      await gesture.up();
    }

    testWidgets('al abrirse crece sin rebote (nunca pasa de su tamaño) y al final no hay un salto de brillo: desde la mitad de la apertura queda entero', (tester) async {
      await open(tester);
      await circleQuickly(tester);
      var lastScale = 0.0;
      var lastOpacity = 0.0;
      for (var ms = 0; ms <= 520; ms += 16) {
        await tester.pump(const Duration(milliseconds: 16));
        final scale = ringScale(tester);
        expect(scale, lessThanOrEqualTo(1.0001), reason: 'rebote a los $ms ms');
        expect(scale, greaterThanOrEqualTo(lastScale - 0.0001), reason: 'a los $ms ms');
        lastScale = scale;
        final opacity = ringOpacity(tester);
        if (ms > 260) {
          expect(opacity, 1, reason: 'parpadeo tardío a los $ms ms');
        }
        lastOpacity = opacity;
      }
      expect(lastScale, closeTo(1, 0.0001));
      expect(lastOpacity, 1);
    });

    testWidgets('al cerrarlo se deshace: sigue unos instantes y luego se quita; en ese rato no recibe toques', (tester) async {
      await open(tester);
      await drawCircle(tester);
      expect(ringScale(tester), closeTo(1, 0.0001));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(const Key('radial-menu')), findsOneWidget); // todavía deshaciéndose
      expect(ringScale(tester), lessThan(1));
      // el contenido de alrededor va recuperando su opacidad mientras el hueco se cierra
      final cut = find.byKey(const Key('radial-cut'));
      expect(tester.widget<Opacity>(find.descendant(of: cut, matching: find.byType(Opacity)).first).opacity, greaterThan(1 - RadialCutout.fade - 0.0001));
      await tester.tap(find.byKey(const Key('radial-music')), warnIfMissed: false); // un toque mientras se cierra no hace nada
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      expect(find.text('Pantalla home'), findsOneWidget);
    });

    testWidgets('al elegir una opción el menú se deshace a la vez que cambia la sección', (tester) async {
      await open(tester);
      await drawCircle(tester);
      await tester.tap(find.byKey(const Key('radial-music')), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('radial-menu')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('radial-menu')), findsNothing);
      expect(find.text('Pantalla music'), findsOneWidget);
    });

    testWidgets('el borde del hueco no cambia de golpe al terminar de abrirse', (tester) async {
      await open(tester);
      await circleQuickly(tester);
      await tester.pump(const Duration(milliseconds: 380));
      final before = find.byKey(const Key('radial-edge'));
      expect(before, findsOneWidget);
      // sin saltos: el painter acaba de dibujar con 0.9 y con 1.0 casi igual (se comprueba que ambos se pintan sin fallar)
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

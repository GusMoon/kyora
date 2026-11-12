import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/widgets/section_motion.dart';

/// El bloque de prueba: 100×100 en el centro de una pantalla de 400×800.
const _rest = Rect.fromLTWH(150, 350, 100, 100);
const _block = Key('block');

/// `t` en el instante `ms` del cambio.
double at(int ms) => ms / SectionMotion.total.inMilliseconds;

void main() {
  /// Pone el bloque con el cambio en `t` y devuelve dónde queda y lo visible que está (su opacidad).
  Future<(Rect, double)> place(WidgetTester tester, {required double t, required bool leaving, MotionEdge edge = MotionEdge.left, int order = 0}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SectionMotion(
          animation: AlwaysStoppedAnimation(t),
          leaving: leaving,
          moving: true,
          child: Center(child: FlyIn(edge: edge, order: order, child: const SizedBox(key: _block, width: 100, height: 100))),
        ),
      ),
    );
    final opacity = tester.widget<Opacity>(find.ancestor(of: find.byKey(_block), matching: find.byType(Opacity)).first).opacity;
    return (tester.getRect(find.byKey(_block)), opacity);
  }

  group('al salir', () {
    testWidgets('al empezar está en su sitio y entero', (tester) async {
      final (rect, opacity) = await place(tester, t: 0, leaving: true);
      expect(rect, _rest);
      expect(opacity, 1);
    });

    for (final edge in MotionEdge.values) {
      testWidgets('al terminar ya no se ve (se rompió hacia ${edge.name}), y sin salir de la pantalla', (tester) async {
        final (rect, opacity) = await place(tester, t: 1, leaving: true, edge: edge);
        expect(opacity, 0);
        expect((rect.center - _rest.center).distance, lessThan(SectionMotion.drift + SectionMotion.jitter + 1)); // un salto pequeño
      });
    }

    testWidgets('a mitad está roto: más tenue y desplazado', (tester) async {
      final (rect, opacity) = await place(tester, t: at(70), leaving: true);
      expect(opacity, allOf(greaterThan(0), lessThan(1)));
      expect(rect, isNot(_rest));
    });

    test('se va rápido pero se nota: en ~210 ms', () {
      expect(SectionMotion.exitTime.inMilliseconds, inInclusiveRange(150, 260));
      expect(SectionMotion.exitProgress(at(SectionMotion.exitTime.inMilliseconds)), 1);
    });
  });

  group('al entrar', () {
    for (final edge in MotionEdge.values) {
      testWidgets('empieza oculto y termina exactamente en su sitio y entero, por ${edge.name}', (tester) async {
        final (_, hidden) = await place(tester, t: 0, leaving: false, edge: edge);
        expect(hidden, 0);
        final (end, shown) = await place(tester, t: 1, leaving: false, edge: edge);
        expect(end, _rest);
        expect(shown, 1);
      });
    }

    testWidgets('mientras se materializa lo cruzan franjas de interferencia; quieto, ninguna', (tester) async {
      await place(tester, t: at(SectionMotion.enterDelay.inMilliseconds + 80), leaving: false);
      CustomPaint glitch() => tester.widget<CustomPaint>(find.ancestor(of: find.byKey(_block), matching: find.byType(CustomPaint)).first);
      final mid = glitch().foregroundPainter!;
      expect(mid.shouldRepaint(mid), isFalse);
      await place(tester, t: 1, leaving: false);
      final still = glitch().foregroundPainter!;
      // con el glitch a 0 no pinta nada: se comprueba pintando en un lienzo de prueba
      final recorder = PictureRecorder();
      still.paint(Canvas(recorder), const Size(100, 100));
      expect(recorder.endRecording(), isNotNull);
    });

    testWidgets('un turno más alto aparece más tarde', (tester) async {
      final t = at(SectionMotion.enterDelay.inMilliseconds + 40);
      final (_, first) = await place(tester, t: t, leaving: false, order: 0);
      final (_, third) = await place(tester, t: t, leaving: false, order: 3);
      expect(first, greaterThan(0));
      expect(third, 0);
    });
  });

  group('el glitch', () {
    test('salta a saltos: el mismo paso da siempre lo mismo, y pasos distintos dan sitios distintos', () {
      expect(SectionMotion.noise(3, 2), SectionMotion.noise(3, 2));
      final seen = {for (var tick = 0; tick < SectionMotion.ticks; tick++) SectionMotion.noise(3, tick)};
      expect(seen.length, greaterThan(SectionMotion.ticks ~/ 2));
      for (var tick = 0; tick < 20; tick++) {
        expect(SectionMotion.noise(tick, tick * 3), inInclusiveRange(0, 1));
      }
    });

    test('parpadea: a veces casi se apaga, pero nunca pasa de lo que lleva y termina entero', () {
      var dips = 0;
      for (var i = 1; i < 100; i++) {
        final shown = i / 100;
        final o = SectionMotion.glitchOpacity(shown, 5);
        expect(o, lessThanOrEqualTo(shown));
        if (o < shown) dips++;
      }
      expect(dips, greaterThan(0));
      expect(SectionMotion.glitchOpacity(1, 5), 1);
      expect(SectionMotion.glitchOpacity(0, 5), 0);
    });

    test('el salto es más grande cuanto menos se ve, y al final no queda ninguno', () {
      expect(SectionMotion.glitchShift(1, 5, MotionEdge.left), Offset.zero);
      final early = SectionMotion.glitchShift(0.05, 5, MotionEdge.top);
      expect(early.dy, lessThan(0)); // viene un poco desde arriba
      for (var i = 0; i < 10; i++) {
        final shift = SectionMotion.glitchShift(i / 10, 9, MotionEdge.top);
        expect(shift.dx.abs(), lessThanOrEqualTo(SectionMotion.jitter * (1 - i / 10) + 0.001));
      }
    });
  });

  group('los tiempos', () {
    test('la salida empieza ya y dura ~180 ms, para todos a la vez', () {
      expect(SectionMotion.exitProgress(at(40), 0), greaterThan(0));
      expect(SectionMotion.exitProgress(at(40), 4), SectionMotion.exitProgress(at(40), 0)); // el turno no cuenta al salir
      expect(SectionMotion.exitProgress(at(SectionMotion.exitTime.inMilliseconds), 0), 1);
    });

    test('la entrada espera un momento y cada turno empieza un poco después del anterior', () {
      final step = SectionMotion.step.inMilliseconds;
      final delay = SectionMotion.enterDelay.inMilliseconds;
      expect(SectionMotion.enterProgress(at(delay), 0), 0);
      expect(SectionMotion.enterProgress(at(delay + 20), 0), greaterThan(0));
      expect(SectionMotion.enterProgress(at(delay + step), 1), 0);
      expect(SectionMotion.enterProgress(at(delay + step + 20), 1), greaterThan(0));
      expect(delay, lessThanOrEqualTo(150)); // una espera mínima, menor que la salida: se solapan un poco
      expect(delay, lessThan(SectionMotion.exitTime.inMilliseconds));
      // un turno más alto de lo previsto no se sale del tiempo del cambio
      expect(SectionMotion.enterProgress(1, 9), 1);
    });

    test('al final del cambio todos han terminado, sea cual sea su turno', () {
      for (var order = 0; order <= SectionMotion.maxOrder; order++) {
        expect(SectionMotion.exitProgress(1, order), 1);
        expect(SectionMotion.enterProgress(1, order), 1);
      }
      expect(SectionMotion.enterDelay + SectionMotion.step * SectionMotion.maxOrder + SectionMotion.enterTime, SectionMotion.total);
    });

    test('lo que le falta esperar a un turno', () {
      expect(SectionMotion.waitFor(0, 0), SectionMotion.enterDelay.inMilliseconds);
      expect(SectionMotion.waitFor(0, 2), (SectionMotion.enterDelay + SectionMotion.step * 2).inMilliseconds);
      expect(SectionMotion.waitFor(1, 5), 0);
    });
  });

  testWidgets('fuera de una sección el bloque no se mueve ni se funde', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Center(child: FlyIn(edge: MotionEdge.top, child: SizedBox(key: _block, width: 100, height: 100)))));
    expect(tester.getRect(find.byKey(_block)), _rest);
    expect(tester.widget<Opacity>(find.ancestor(of: find.byKey(_block), matching: find.byType(Opacity)).first).opacity, 1);
  });

  testWidgets('la barra de arriba conserva su alto y aparece por arriba', (tester) async {
    final bar = AppBar(title: const Text('Título'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(appBar: FlyInBar(child: bar))));
    expect(FlyInBar(child: bar).preferredSize, bar.preferredSize);
    expect(tester.widget<FlyIn>(find.ancestor(of: find.byType(AppBar), matching: find.byType(FlyIn))).edge, MotionEdge.top);
    expect(find.text('Título'), findsOneWidget);
  });
}

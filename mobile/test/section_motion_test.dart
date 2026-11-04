import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/widgets/section_motion.dart';

/// El bloque de prueba: 100×100 en el centro de una pantalla de 400×800.
const _rest = Rect.fromLTWH(150, 350, 100, 100);
const _block = Key('block');

/// `t` en el instante `ms` del cambio.
double at(int ms) => ms / SectionMotion.total.inMilliseconds;

void main() {
  Future<Rect> place(WidgetTester tester, {required double t, required bool leaving, MotionEdge edge = MotionEdge.left, int order = 0}) async {
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
    return tester.getRect(find.byKey(_block));
  }

  bool isOffScreen(Rect r) => r.right <= 0 || r.left >= 400 || r.bottom <= 0 || r.top >= 800;

  group('al salir', () {
    testWidgets('al empezar está en su sitio', (tester) async {
      expect(await place(tester, t: 0, leaving: true), _rest);
    });

    for (final edge in MotionEdge.values) {
      testWidgets('al terminar queda fuera de la pantalla, por ${edge.name}', (tester) async {
        final r = await place(tester, t: 1, leaving: true, edge: edge);
        expect(isOffScreen(r), isTrue);
        switch (edge) {
          case MotionEdge.top:
            expect(r.bottom, lessThanOrEqualTo(0));
          case MotionEdge.bottom:
            expect(r.top, greaterThanOrEqualTo(800));
          case MotionEdge.left:
            expect(r.right, lessThanOrEqualTo(0));
          case MotionEdge.right:
            expect(r.left, greaterThanOrEqualTo(400));
        }
      });
    }

    testWidgets('se va solo por su eje: el otro no se mueve', (tester) async {
      final side = await place(tester, t: at(120), leaving: true, edge: MotionEdge.right);
      expect(side.top, _rest.top);
      expect(side.left, greaterThan(_rest.left));
      final up = await place(tester, t: at(120), leaving: true, edge: MotionEdge.top);
      expect(up.left, _rest.left);
      expect(up.top, lessThan(_rest.top));
    });
  });

  group('al entrar', () {
    for (final edge in MotionEdge.values) {
      testWidgets('empieza fuera de la pantalla y termina exactamente en su sitio, por ${edge.name}', (tester) async {
        expect(isOffScreen(await place(tester, t: 0, leaving: false, edge: edge)), isTrue);
        expect(await place(tester, t: 1, leaving: false, edge: edge), _rest);
      });
    }

    testWidgets('sale del mismo borde por el que saldría', (tester) async {
      final entering = await place(tester, t: at(150), leaving: false, edge: MotionEdge.left);
      expect(entering.left, lessThan(_rest.left)); // viene de la izquierda
      final leaving = await place(tester, t: at(150), leaving: true, edge: MotionEdge.left);
      expect(leaving.left, lessThan(_rest.left)); // y se va hacia ella
    });
  });

  group('los tiempos', () {
    test('la salida empieza ya; la entrada espera un momento y arranca casi a la vez', () {
      expect(SectionMotion.exitProgress(at(40), 0), greaterThan(0));
      final delay = SectionMotion.enterDelay.inMilliseconds;
      expect(SectionMotion.enterProgress(at(delay), 0), 0);
      expect(SectionMotion.enterProgress(at(delay + 20), 0), greaterThan(0));
      expect(delay, lessThanOrEqualTo(100)); // una espera mínima
    });

    test('cada turno empieza un poco después del anterior', () {
      final step = SectionMotion.step.inMilliseconds;
      final delay = SectionMotion.enterDelay.inMilliseconds;
      expect(SectionMotion.exitProgress(at(step), 1), 0);
      expect(SectionMotion.exitProgress(at(step + 20), 1), greaterThan(0));
      expect(SectionMotion.enterProgress(at(delay + step), 1), 0);
      expect(SectionMotion.enterProgress(at(delay + step + 20), 1), greaterThan(0));
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
  });

  testWidgets('fuera de una sección el bloque no se mueve, y nada usa opacidad', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: Center(child: FlyIn(edge: MotionEdge.top, child: SizedBox(key: _block, width: 100, height: 100)))));
    expect(tester.getRect(find.byKey(_block)), _rest);
    final inside = find.descendant(of: find.byType(FlyIn), matching: find.byWidgetPredicate((w) => w is Opacity || w is FadeTransition || w is AnimatedOpacity));
    expect(inside, findsNothing);
  });

  testWidgets('la barra de arriba conserva su alto y sale por arriba', (tester) async {
    final bar = AppBar(title: const Text('Título'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(appBar: FlyInBar(child: bar))));
    expect(FlyInBar(child: bar).preferredSize, bar.preferredSize);
    expect(tester.widget<FlyIn>(find.ancestor(of: find.byType(AppBar), matching: find.byType(FlyIn))).edge, MotionEdge.top);
    expect(find.text('Título'), findsOneWidget);
  });
}

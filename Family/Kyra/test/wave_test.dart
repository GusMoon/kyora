import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/ui/widgets/radial_menu.dart';
import 'package:kyora_chat/ui/widgets/wave_sweep.dart';

void main() {
  group('la ola', () {
    test('mide la diagonal: 0 arriba a la izquierda, 1 abajo a la derecha, y crece hacia abajo y a la derecha', () {
      const size = Size(400, 800);
      expect(WaveSweep.along(Offset.zero, size), 0);
      expect(WaveSweep.along(const Offset(400, 800), size), closeTo(1, 1e-9));
      expect(WaveSweep.along(const Offset(300, 100), size), lessThan(WaveSweep.along(const Offset(300, 500), size)));
      expect(WaveSweep.along(const Offset(100, 400), size), lessThan(WaveSweep.along(const Offset(300, 400), size)));
    });

    test('al empezar no ha cambiado nada, al acabar todo, y llega antes a lo de arriba a la izquierda que a lo de abajo a la derecha', () {
      expect(WaveSweep.passed(0, 0), 0);
      expect(WaveSweep.passed(1, 1), closeTo(1, 1e-9));
      for (final t in [0.1, 0.3, 0.5, 0.7, 0.9]) {
        expect(WaveSweep.passed(t, 0.1), greaterThanOrEqualTo(WaveSweep.passed(t, 0.9)), reason: 't=$t');
      }
      expect(WaveSweep.passed(0.4, 0.1), closeTo(1, 1e-9));
      expect(WaveSweep.passed(0.4, 0.9), 0);
    });

    testWidgets('al esconderse la ola corre igual: primero se va lo de arriba a la izquierda', (tester) async {
      final shown = AnimationController(vsync: tester, duration: const Duration(milliseconds: 100), value: 1);
      addTearDown(shown.dispose);
      // parado o mostrándose, no se esconde
      expect(WaveSweep.hiding(shown), isFalse);
      shown.value = 0.5;
      final showing = WaveSweep.visibility(shown, 0.9);
      expect(showing, 0); // mostrándose, a media ola lo de abajo a la derecha aún no ha llegado
      unawaited(shown.reverse());
      expect(WaveSweep.hiding(shown), isTrue);
      expect(WaveSweep.visibility(shown, 0.1), lessThan(WaveSweep.visibility(shown, 0.9))); // lo de arriba a la izquierda ya casi no se ve
      shown.stop();
    });
  });

  group('el contenido bajo la ola', () {
    Widget host(AnimationController reveal) => MaterialApp(
      home: RadialCut(
        center: null,
        opening: const AlwaysStoppedAnimation(0),
        reveal: reveal,
        child: const SizedBox.expand(child: Text('contenido')),
      ),
    );

    testWidgets('mientras se deshace o vuelve lleva la máscara de la ola; a la vista del todo, no', (tester) async {
      final reveal = AnimationController(vsync: tester, duration: const Duration(milliseconds: 400), value: 1);
      addTearDown(reveal.dispose);
      await tester.pumpWidget(host(reveal));
      expect(find.byKey(const Key('wave-mask')), findsNothing);
      unawaited(reveal.reverse());
      await tester.pump(); // arranca el reloj
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const Key('wave-mask')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('wave-mask')), findsNothing);
      expect(find.text('contenido'), findsNothing); // quitado del todo (sigue vivo, fuera de pantalla)
      unawaited(reveal.forward());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const Key('wave-mask')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('contenido'), findsOneWidget);
      expect(find.byKey(const Key('wave-mask')), findsNothing);
    });
  });
}

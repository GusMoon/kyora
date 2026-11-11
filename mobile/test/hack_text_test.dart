import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/widgets/hack_text.dart';
import 'package:kyora_chat/ui/widgets/section_motion.dart';

void main() {
  group('el cuadro del efecto', () {
    const text = 'Hola mundo cruel';

    test('al empezar no se ve nada y el texto real guarda el sitio; al acabar está entero', () {
      final start = HackText.frame(text, 0, 0);
      expect(start.$1, '');
      expect(start.$2, '');
      expect(start.$3, text);
      final end = HackText.frame(text, 1, 0);
      expect(end.$1, text);
      expect(end.$2, '');
      expect(end.$3, '');
    });

    test('en medio hay lo escrito, unos signos de ruido delante y lo que falta; siempre suman el texto entero', () {
      for (var i = 0; i <= 20; i++) {
        final (done, noise, rest) = HackText.frame(text, i / 20, 3);
        expect(done.length + noise.length + rest.length, text.length);
        expect(text.startsWith(done), isTrue);
        expect(text.endsWith(rest), isTrue);
        expect(noise.length, lessThanOrEqualTo(HackText.window));
      }
      final (done, noise, rest) = HackText.frame(text, 0.5, 3);
      expect(done, isNotEmpty);
      expect(noise, isNotEmpty);
      expect(rest, isNotEmpty);
    });

    test('lo escrito solo crece, de izquierda a derecha', () {
      var before = 0;
      for (var i = 0; i <= 40; i++) {
        final done = HackText.frame(text, i / 40, 1).$1.length;
        expect(done, greaterThanOrEqualTo(before));
        before = done;
      }
    });

    test('el ruido sale de los signos del efecto y respeta los espacios y los saltos de línea', () {
      const spaced = 'a b\nc d';
      for (var tick = 0; tick < 10; tick++) {
        final noise = HackText.frame(spaced, 0.6, tick).$2;
        for (final ch in noise.split('')) {
          expect(HackText.glyphs.contains(ch) || ch.trim().isEmpty, isTrue, reason: 'signo «$ch»');
        }
      }
      final (done, noise, rest) = HackText.frame(spaced, 0.6, 0);
      expect(('$done$noise$rest').length, spaced.length);
    });

    test('el ruido cambia de un instante al siguiente', () {
      final a = HackText.frame(text, 0.5, 0).$2;
      final b = HackText.frame(text, 0.5, 1).$2;
      expect(a, isNot(b));
    });

    test('un texto largo tarda más, dentro de unos límites', () {
      const per = Duration(milliseconds: 22);
      expect(HackText.timeFor(1, per), HackText.minTime);
      expect(HackText.timeFor(20, per), greaterThan(HackText.timeFor(5, per)));
      expect(HackText.timeFor(5000, per), HackText.maxTime);
    });
  });

  group('el widget', () {
    setUp(() => HackText.enabled = true);
    tearDown(() => HackText.enabled = false);

    const key = Key('t');
    Widget app(Widget child, {bool disableAnimations = false}) => MaterialApp(
          theme: buildTheme(),
          builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations), child: c!),
          home: Scaffold(body: Center(child: child)),
        );

    /// Lo que se ve de verdad (lo escrito y el ruido, sin lo transparente).
    String visible(WidgetTester tester) {
      final span = tester.widget<Text>(find.byKey(key)).textSpan;
      if (span == null) return tester.widget<Text>(find.byKey(key)).data!;
      final parts = (span as TextSpan).children!.cast<TextSpan>().where((s) => s.style?.color != Colors.transparent);
      return parts.map((s) => s.text).join();
    }

    testWidgets('se escribe poco a poco y al acabar es un Text normal con el texto entero', (tester) async {
      await tester.pumpWidget(app(const HackText('Hola mundo', textKey: key)));
      expect(tester.widget<Text>(find.byKey(key)).data, isNull); // escribiéndose: Text.rich
      expect(visible(tester), '');
      await tester.pump(const Duration(milliseconds: 120));
      expect(visible(tester), isNotEmpty);
      expect(visible(tester).length, lessThan('Hola mundo'.length + 1));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(key)).data, 'Hola mundo');
      expect(find.text('Hola mundo'), findsOneWidget);
    });

    testWidgets('mientras se escribe el tamaño no cambia: lo que falta guarda su sitio con el texto real', (tester) async {
      await tester.pumpWidget(app(const HackText('Hola mundo', textKey: key, style: TextStyle(fontFamily: monoFont, fontSize: 16))));
      final start = tester.getSize(find.byKey(key));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(find.byKey(key)).width, closeTo(start.width, 1));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(key)).width, closeTo(start.width, 1));
    });

    testWidgets('al cambiar el texto se vuelve a escribir', (tester) async {
      await tester.pumpWidget(app(const HackText('Primero', textKey: key)));
      await tester.pumpAndSettle();
      expect(find.text('Primero'), findsOneWidget);
      await tester.pumpWidget(app(const HackText('Segundo texto', textKey: key)));
      expect(tester.widget<Text>(find.byKey(key)).data, isNull); // otra vez escribiéndose
      await tester.pumpAndSettle();
      expect(find.text('Segundo texto'), findsOneWidget);
    });

    testWidgets('con el mismo texto no se repite', (tester) async {
      await tester.pumpWidget(app(const HackText('Igual', textKey: key)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(const HackText('Igual', textKey: key)));
      expect(tester.widget<Text>(find.byKey(key)).data, 'Igual');
    });

    testWidgets('con las animaciones del sistema quitadas sale entero al instante', (tester) async {
      await tester.pumpWidget(app(const HackText('Hola mundo', textKey: key), disableAnimations: true));
      expect(tester.widget<Text>(find.byKey(key)).data, 'Hola mundo');
    });

    testWidgets('con animate en falso sale entero, y el texto vacío no falla', (tester) async {
      await tester.pumpWidget(app(const Column(children: [HackText('Ya estaba', textKey: key, animate: false), HackText('')])));
      expect(tester.widget<Text>(find.byKey(key)).data, 'Ya estaba');
    });

    testWidgets('apagado con HackText.enabled sale entero', (tester) async {
      HackText.enabled = false;
      await tester.pumpWidget(app(const HackText('Hola', textKey: key)));
      expect(tester.widget<Text>(find.byKey(key)).data, 'Hola');
    });

    testWidgets('dentro de un cambio de sección espera el turno de su bloque', (tester) async {
      await tester.pumpWidget(app(SectionMotion(animation: const AlwaysStoppedAnimation(0), leaving: false, moving: true, child: const HackText('Hola mundo', textKey: key, order: 3))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(visible(tester), ''); // aún le falta: 60 ms + 3 turnos de 70 ms
      await tester.pump(const Duration(milliseconds: 500));
      expect(visible(tester), isNotEmpty);
      await tester.pumpAndSettle();
      expect(find.text('Hola mundo'), findsOneWidget);
    });

    testWidgets('en la sección que se va el texto sale entero', (tester) async {
      await tester.pumpWidget(app(SectionMotion(animation: const AlwaysStoppedAnimation(0), leaving: true, moving: true, child: const HackText('Hola mundo', textKey: key))));
      expect(tester.widget<Text>(find.byKey(key)).data, 'Hola mundo');
    });

    testWidgets('quitarlo a mitad no deja ningún ticker vivo', (tester) async {
      await tester.pumpWidget(app(const HackText('Un texto bastante largo para escribirse', textKey: key)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(app(const SizedBox()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('al escribirse el texto lleva su etiqueta de accesibilidad entera', (tester) async {
      await tester.pumpWidget(app(const HackText('Hola mundo', textKey: key)));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.bySemanticsLabel('Hola mundo'), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });
}

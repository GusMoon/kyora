import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/widgets/options_reactor.dart';
import 'package:kyora_chat/ui/widgets/radial_menu.dart' show ReactorSpin;

void main() {
  final taps = <String>[];

  Future<void> show(WidgetTester tester, {bool warn = true, double rate = 1, ValueChanged<double>? onRate}) async {
    taps.clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: OptionsReactor(
              size: 300,
              onClose: () => taps.add('close'),
              options: [
                DiscOption(id: 'move', icon: Icons.drive_file_move_rounded, label: 'Mover', onTap: () => taps.add('move')),
                DiscOption(id: 'delete', icon: Icons.delete_rounded, label: 'Borrar', warn: warn, onTap: () => taps.add('delete')),
                DiscOption(
                  id: 'speed',
                  icon: Icons.speed_rounded,
                  label: 'Velocidad',
                  dials: [ReactorDial(id: 'rate', icon: Icons.speed_rounded, label: 'Velocidad', min: 0.5, max: 1.5, step: 0.05, value: () => rate, onChanged: onRate ?? (_) {}, format: (v) => '${v}x', neutral: 1)],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ReactorPainter painter(WidgetTester tester) => tester.widget<CustomPaint>(find.byKey(const Key('options-dial'))).painter! as ReactorPainter;

  testWidgets('el reactor se pinta con el acento del tema, tantos radios como opciones y las mismas claves de siempre', (tester) async {
    await show(tester);
    final accent = tester.element(find.byType(OptionsReactor)).colors.accent;
    expect(painter(tester).accent, accent);
    expect(painter(tester).count, 3);
    expect(painter(tester).gauge, isNull); // sin dial
    for (final key in ['options-disc', 'options-disc-back', 'disc-options-close', 'disc-option-move', 'disc-option-delete', 'disc-option-speed']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('solo iconos: ninguna opción lleva texto', (tester) async {
    await show(tester);
    for (final id in ['move', 'delete', 'speed']) {
      expect(find.descendant(of: find.byKey(Key('disc-option-$id')), matching: find.byType(Text)), findsNothing, reason: id);
      expect(find.descendant(of: find.byKey(Key('disc-option-$id')), matching: find.byType(Icon)), findsOneWidget, reason: id);
    }
    expect(find.text('Mover'), findsNothing);
  });

  testWidgets('tocar una opción la ejecuta y tocar el centro cierra', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const Key('disc-option-move')));
    await tester.tap(find.byKey(const Key('disc-options-close')));
    expect(taps, ['move', 'close']);
  });

  testWidgets('la acción peligrosa va en el color de aviso y las demás en el normal', (tester) async {
    await show(tester);
    final warn = tester.element(find.byType(OptionsReactor)).colors.warn;
    Color iconOf(String id) => tester.widget<Icon>(find.descendant(of: find.byKey(Key('disc-option-$id')), matching: find.byType(Icon))).color!;
    expect(iconOf('delete'), warn);
    expect(iconOf('move'), isNot(warn));
  });

  testWidgets('una opción de ajuste convierte el reactor en un dial: enseña el valor en el núcleo y la pista del dial', (tester) async {
    await show(tester, rate: 1.25);
    await tester.tap(find.byKey(const Key('disc-option-speed')));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('reactor-value'))).data, '1.25x');
    expect(painter(tester).gauge, closeTo(0.75, 1e-9)); // (1,25 - 0,5) / (1,5 - 0,5)
    expect(find.byKey(const Key('disc-option-move')), findsNothing); // las opciones ya no están
    expect(find.byKey(const Key('reactor-reset')), findsOneWidget);
    await tester.tap(find.byKey(const Key('reactor-back')));
    await tester.pump();
    expect(painter(tester).gauge, isNull);
    expect(find.byKey(const Key('disc-option-move')), findsOneWidget);
  });

  testWidgets('girando el dedo por el aro se pone el valor, de paso en paso y sin salirse del rango', (tester) async {
    final seen = <double>[];
    await show(tester, onRate: seen.add);
    await tester.tap(find.byKey(const Key('disc-option-speed')));
    await tester.pump();
    final box = tester.getRect(find.byKey(const Key('options-disc')));
    Offset at(double f) => box.center + Offset.fromDirection(OptionsReactor.gaugeStart + OptionsReactor.gaugeSweep * f, box.width / 2 * 0.7);
    final g = await tester.startGesture(at(0.1));
    await g.moveTo(at(0.2));
    await g.moveTo(at(0.6));
    await g.up();
    expect(seen, isNotEmpty);
    expect(seen.last, 1.1); // el 60 % del dial, de 0,5× a 1,5×
    for (final v in seen) {
      expect(v, inInclusiveRange(0.5, 1.5));
      expect(((v - 0.5) / 0.05 - ((v - 0.5) / 0.05).round()).abs(), lessThan(1e-6), reason: '$v va de 0,05 en 0,05');
    }
  });

  testWidgets('quieto en las pruebas (ReactorSpin apagado): no hay animación que impida terminar y el aro no avanza', (tester) async {
    expect(ReactorSpin.enabled, isFalse);
    await show(tester); // pumpAndSettle termina
    expect(painter(tester).spin!.value, 0);
    await tester.pump(const Duration(seconds: 3));
    expect(painter(tester).spin!.value, 0);
  });

  testWidgets('con ReactorSpin encendido el aro gira', (tester) async {
    ReactorSpin.enabled = true;
    addTearDown(() => ReactorSpin.enabled = false);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: Center(child: OptionsReactor(size: 300, onClose: () {}, options: [DiscOption(id: 'a', icon: Icons.speed_rounded, label: 'A', onTap: () {})]))),
      ),
    );
    final before = painter(tester).spin!.value;
    await tester.pump(const Duration(seconds: 2));
    expect(painter(tester).spin!.value, isNot(before));
    await tester.pumpWidget(const SizedBox()); // al desmontar se para el reloj
  });

  group('el panel y el reactor al cerrarse', () {
    Future<void> openRoute(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('go'),
                  onPressed: () => showOptionsReactor(context, center: const Offset(200, 300), options: [DiscOption(id: 'a', icon: Icons.speed_rounded, label: 'A', onTap: () => taps.add('a'))]),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();
    }

    testWidgets('abre sobre un velo oscuro (más que antes) y elegir una opción cierra el reactor y la ejecuta', (tester) async {
      taps.clear();
      await openRoute(tester);
      final veil = tester.widget<ColoredBox>(find.descendant(of: find.byKey(const Key('focus-veil')), matching: find.byType(ColoredBox)).first);
      expect(veil.color.a, closeTo(0.74, 0.01));
      await tester.tap(find.byKey(const Key('disc-option-a')));
      await tester.pumpAndSettle();
      expect(taps, ['a']);
      expect(find.byKey(const Key('options-disc')), findsNothing);
    });

    testWidgets('al cerrarse se apaga rápido (150 ms) y sin parpadear: la opacidad solo baja', (tester) async {
      await openRoute(tester);
      await tester.tap(find.byKey(const Key('disc-options-close')));
      await tester.pump(); // arranca el cierre
      final seen = <double>[];
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 18));
        final fade = find.ancestor(of: find.byKey(const Key('options-disc')), matching: find.byType(Opacity));
        if (fade.evaluate().isEmpty) break;
        seen.add(tester.widget<Opacity>(fade.first).opacity);
      }
      expect(seen, isNotEmpty);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], lessThanOrEqualTo(seen[i - 1] + 1e-9), reason: 'no vuelve a subir (sin parpadeo): $seen');
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('options-disc')), findsNothing);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/home_shell.dart';
import 'package:kyora_chat/ui/widgets/section_rail.dart';

import 'sections.dart';

/// Una sección de prueba: una pantalla con su nombre y un campo de texto.
AppSection section(String id, String label, IconData icon) => AppSection(
      id: id,
      icon: icon,
      label: label,
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text('Pantalla $label')),
        body: Column(children: [
          TextField(key: Key('field-$id')),
          TextButton(key: Key('snack-$id'), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aviso de $label'))), child: const Text('aviso')),
        ]),
      ),
    );

final sections = [
  section('chat', 'Chat', Icons.chat_bubble_outline_rounded),
  section('music', 'Música', Icons.music_note_outlined),
  section('tasks', 'Tareas', Icons.checklist_rounded),
];

void main() {
  Future<void> open(WidgetTester tester, {int initial = 0, bool hint = false, List<AppSection>? list}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: HomeShell(sections: list ?? sections, initial: initial, hintOnStart: hint, hideAfter: const Duration(milliseconds: 500)),
    ));
    await tester.pumpAndSettle();
  }

  double railOpacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.ancestor(of: find.byKey(const Key('section-rail')), matching: find.byType(AnimatedOpacity))).opacity;

  /// Cuánto se resalta el icono de una sección en la barra (0 = apagado, 1 = el de la sección que se ve): su tamaño va de 21 a 25.
  double highlight(WidgetTester tester, String id) =>
      (tester.widget<Icon>(find.descendant(of: find.byKey(Key('section-$id')), matching: find.byType(Icon))).size! - 21) / 4;

  group('deslizar', () {
    testWidgets('arranca en la sección inicial y deslizar de lado cambia de sección, sin pasarse de los extremos', (tester) async {
      await open(tester);
      expect(find.text('Pantalla Chat'), findsOneWidget);
      await swipeSections(tester, -1); // a la derecha del todo: no hay nada antes
      expect(find.text('Pantalla Chat'), findsOneWidget);
      await swipeSections(tester, 1);
      expect(find.text('Pantalla Música'), findsOneWidget);
      await swipeSections(tester, 1);
      expect(find.text('Pantalla Tareas'), findsOneWidget);
      await swipeSections(tester, 1); // ya es la última
      expect(find.text('Pantalla Tareas'), findsOneWidget);
      await swipeSections(tester, -2);
      expect(find.text('Pantalla Chat'), findsOneWidget);
    });

    testWidgets('puede arrancar en otra sección (el pasante empieza en música)', (tester) async {
      await open(tester, initial: 1);
      expect(find.text('Pantalla Música'), findsOneWidget);
    });

    testWidgets('cada sección conserva su estado al ir y volver', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('field-chat')), 'algo a medio escribir');
      await swipeSections(tester, 2);
      expect(find.text('Pantalla Tareas'), findsOneWidget);
      await swipeSections(tester, -2);
      expect(find.text('algo a medio escribir'), findsOneWidget);
    });

    testWidgets('un aviso sale solo en su pantalla, aunque las otras sigan vivas', (tester) async {
      await open(tester);
      await swipeSections(tester, 1); // la de chat queda viva detrás
      await tester.tap(find.byKey(const Key('snack-music')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Aviso de Música'), findsOneWidget);
    });

    testWidgets('«atrás» vuelve a la sección de inicio', (tester) async {
      await open(tester);
      await swipeSections(tester, 2);
      expect(find.text('Pantalla Tareas'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Pantalla Chat'), findsOneWidget);
    });
  });

  group('barra', () {
    testWidgets('en reposo no se ve; al deslizar aparece y se esconde sola un momento después', (tester) async {
      await open(tester);
      expect(railOpacity(tester), 0);
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('sections-pager'))));
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(railOpacity(tester), 1);
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1)); // más que `hideAfter`
      await tester.pumpAndSettle();
      expect(railOpacity(tester), 0);
    });

    testWidgets('lleva solo el icono de cada sección (sin nombres) y resalta el de la sección que se ve', (tester) async {
      await open(tester);
      for (final id in ['chat', 'music', 'tasks']) {
        expect(find.byKey(Key('section-$id')), findsOneWidget);
      }
      expect(find.descendant(of: find.byKey(const Key('section-rail')), matching: find.byType(Text)), findsNothing); // ni nombres ni textos
      expect(highlight(tester, 'chat'), 1);
      expect(highlight(tester, 'music'), 0);
      expect(highlight(tester, 'tasks'), 0);
      await swipeSections(tester, 1);
      expect(highlight(tester, 'chat'), 0);
      expect(highlight(tester, 'music'), 1);
    });

    testWidgets('el resaltado pasa de un icono al siguiente al ritmo del dedo', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('sections-pager'))));
      await gesture.moveBy(const Offset(-200, 0)); // la mitad del ancho de la pantalla
      await tester.pump();
      expect(highlight(tester, 'chat'), closeTo(0.5, 0.15));
      expect(highlight(tester, 'music'), closeTo(0.5, 0.15));
      expect(highlight(tester, 'tasks'), 0);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('un deslizamiento vertical no la saca, ni uno de lado que apenas mueve la página', (tester) async {
      await open(tester);
      await tester.drag(find.byKey(const Key('sections-pager')), const Offset(0, 250));
      await tester.pumpAndSettle();
      expect(railOpacity(tester), 0);
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('sections-pager'))));
      await gesture.moveBy(const Offset(-20, 90)); // en diagonal, casi vertical
      await tester.pump(const Duration(milliseconds: 400));
      expect(railOpacity(tester), 0);
      await gesture.moveBy(const Offset(-200, 0)); // ahora sí, de lado
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(railOpacity(tester), 1);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('en cuanto se vuelve a tocar la pantalla se esconde al instante', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('sections-pager'))));
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(railOpacity(tester), 1); // sigue a la vista un momento
      final touch = await tester.startGesture(const Offset(100, 400));
      await tester.pump();
      expect(railOpacity(tester), 0); // un toque nuevo la esconde, sin esperar al temporizador
      await touch.up();
      await tester.pumpAndSettle();
    });

    test('el peso de cada sección: 1 en la que se ve, 0 a una sección o más de distancia', () {
      expect(SectionRail.weightOf(1, 1.0), 1);
      expect(SectionRail.weightOf(1, 1.5), 0.5);
      expect(SectionRail.weightOf(1, 2.0), 0);
      expect(SectionRail.weightOf(0, 2.0), 0);
      expect(SectionRail.weightOf(2, 1.25), 0.25);
    });

    testWidgets('al entrar no se ve (solo sale al deslizar), salvo que se pida el aviso', (tester) async {
      await open(tester);
      expect(railOpacity(tester), 0);
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(key: UniqueKey(), sections: sections, hintOnStart: true, hideAfter: const Duration(milliseconds: 500))));
      await tester.pump(const Duration(milliseconds: 300));
      expect(railOpacity(tester), 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(railOpacity(tester), 0);
    });

    testWidgets('tocar un icono mientras se ve salta a esa sección', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('sections-pager'))));
      await gesture.moveBy(const Offset(-120, 0));
      await tester.pump(); // el aviso del deslizamiento pone la barra a entrar...
      await tester.pump(const Duration(milliseconds: 400)); // ...y termina de entrar
      expect(railOpacity(tester), 1);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50)); // la barra sigue a la vista un momento
      await tester.tap(find.byKey(const Key('section-tasks')));
      await tester.pumpAndSettle();
      expect(find.text('Pantalla Tareas'), findsOneWidget);
    });

    testWidgets('con una sola sección no se enseña nada al entrar', (tester) async {
      await open(tester, hint: true, list: [sections.first]);
      expect(railOpacity(tester), 0);
    });
  });
}

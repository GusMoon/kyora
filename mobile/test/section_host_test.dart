import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/nav_hint_store.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/app_section.dart';
import 'package:kyora_chat/ui/widgets/glass_card.dart';
import 'package:kyora_chat/ui/widgets/section_motion.dart';

import 'blur_guard_test.dart' show expectNoLayerAbove;
import 'sections.dart';

/// Una sección de prueba: una pantalla con su nombre, un campo de texto y un botón que enseña un aviso.
AppSection section(String id, String label, IconData icon, {List<String>? built}) => AppSection(
      id: id,
      icon: icon,
      label: label,
      builder: (context) {
        built?.add(id);
        return Scaffold(
          key: Key('page-$id'),
          appBar: FlyInBar(child: AppBar(key: Key('bar-$id'), title: Text('Pantalla $label'))),
          body: Column(children: [
            FlyIn(
              edge: MotionEdge.left,
              order: 1,
              child: Column(key: Key('middle-$id'), children: [
                TextField(key: Key('field-$id')),
                TextButton(key: Key('snack-$id'), onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aviso de $label'))), child: const Text('aviso')),
                TextButton(key: Key('go-$id'), onPressed: () => SectionHost.goTo(context, 'tasks'), child: const Text('ir a tareas')),
              ]),
            ),
            const Spacer(),
            FlyIn(edge: MotionEdge.bottom, order: 2, child: GlassCard(key: Key('card-$id'), child: const SizedBox(height: 40, width: 100))),
          ]),
        );
      },
    );

void main() {
  late List<String> built;
  late List<AppSection> sections;

  setUp(() {
    built = [];
    sections = [
      section('home', 'Inicio', Icons.home_outlined, built: built),
      section('chat', 'Chat', Icons.chat_bubble_outline_rounded, built: built),
      section('music', 'Música', Icons.music_note_outlined, built: built),
      section('tasks', 'Tareas', Icons.checklist_rounded, built: built),
    ];
  });

  Future<void> open(WidgetTester tester, {int initial = 0, List<NavAction> actions = const [], NavHintStore? hint, List<AppSection>? list}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: SectionHost(key: UniqueKey(), sections: list ?? sections, actions: actions, initial: initial, hint: hint),
    ));
    await tester.pumpAndSettle();
  }

  group('el fondo', () {
    double depth(WidgetTester tester) => tester.widget<FadeTransition>(find.byKey(const Key('backdrop-depth'))).opacity.value;

    testWidgets('en la sección inicial no hay efecto completo; llega a la vez que los bloques y dura lo mismo', (tester) async {
      await open(tester);
      expect(depth(tester), 0);
      SectionHost.goTo(tester.element(find.byKey(const Key('go-home'))), 'chat');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 210));
      expect(depth(tester), inExclusiveRange(0, 1));
      await tester.pump(SectionMotion.total - const Duration(milliseconds: 200));
      expect(depth(tester), 1);
    });

    testWidgets('entre dos secciones que no son la inicial no cambia, y al volver a la inicial se va', (tester) async {
      await open(tester);
      SectionHost.goTo(tester.element(find.byKey(const Key('go-home'))), 'chat');
      await tester.pumpAndSettle();
      SectionHost.goTo(tester.element(find.byKey(const Key('go-chat'))), 'tasks');
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(depth(tester), 1);
      }
      await tester.pumpAndSettle();
      SectionHost.goTo(tester.element(find.byKey(const Key('go-tasks'))), 'home');
      await tester.pumpAndSettle();
      expect(depth(tester), 0);
    });

    testWidgets('si se cambia otra vez a mitad, termina según la última sección', (tester) async {
      await open(tester);
      SectionHost.goTo(tester.element(find.byKey(const Key('go-home'))), 'chat');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      SectionHost.goTo(tester.element(find.byKey(const Key('go-chat'))), 'home');
      await tester.pumpAndSettle();
      expect(depth(tester), 0);
    });

    testWidgets('la capa del fundido va debajo de las secciones: el cristal no la tiene por encima', (tester) async {
      await open(tester);
      SectionHost.goTo(tester.element(find.byKey(const Key('go-home'))), 'chat');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.ancestor(of: find.byKey(const Key('card-chat')), matching: find.byKey(const Key('backdrop-depth'))), findsNothing);
      expectNoLayerAbove(tester);
      await tester.pumpAndSettle();
    });
  });

  group('una sección a la vez', () {
    testWidgets('arranca en la sección inicial y solo esa se construye (las demás ni existen)', (tester) async {
      await open(tester, initial: 1);
      expect(find.text('Pantalla Chat'), findsOneWidget);
      expect(find.text('Pantalla Inicio'), findsNothing);
      expect(built.toSet(), {'chat'});
    });

    testWidgets('al cambiar, la anterior se destruye: ni se ve ni sigue viva', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('field-home')), 'a medio escribir');
      await goToSection(tester, 'music');
      expect(find.text('Pantalla Música'), findsOneWidget);
      expect(find.text('Pantalla Inicio'), findsNothing);
      expect(find.byKey(const Key('field-home')), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget); // nada en segundo plano
      await goToSection(tester, 'home');
      expect(find.text('a medio escribir'), findsNothing); // empieza de cero
    });

    testWidgets('SectionHost.goTo salta a una sección por su id; un id que no existe o la sección actual no hacen nada', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('go-home')));
      await tester.pumpAndSettle();
      expect(find.text('Pantalla Tareas'), findsOneWidget);
      built.clear();
      SectionHost.goTo(tester.element(find.byKey(const Key('go-tasks'))), 'no-existe');
      SectionHost.goTo(tester.element(find.byKey(const Key('go-tasks'))), 'tasks');
      await tester.pumpAndSettle();
      expect(find.text('Pantalla Tareas'), findsOneWidget);
      expect(built, isEmpty);
    });

    testWidgets('«atrás» vuelve a la sección de inicio', (tester) async {
      await open(tester);
      await goToSection(tester, 'tasks');
      expect(find.text('Pantalla Tareas'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Pantalla Inicio'), findsOneWidget);
      expect(find.text('Pantalla Tareas'), findsNothing);
    });

    testWidgets('un aviso sale en la pantalla de su sección', (tester) async {
      await open(tester);
      await goToSection(tester, 'music');
      await tester.tap(find.byKey(const Key('snack-music')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Aviso de Música'), findsOneWidget);
    });
  });

  group('la transición: cada bloque por su borde', () {
    /// Dónde está cada bloque en reposo (son iguales en todas las secciones de prueba).
    late Rect barAtRest, middleAtRest, cardAtRest;

    Future<void> start(WidgetTester tester) async {
      await open(tester);
      barAtRest = tester.getRect(find.byKey(const Key('bar-home')));
      middleAtRest = tester.getRect(find.byKey(const Key('middle-home')));
      cardAtRest = tester.getRect(find.byKey(const Key('card-home')));
      await tester.tap(find.byKey(const Key('go-home')));
      await tester.pump(); // arranca (t = 0)
    }

    testWidgets('los de la sección actual salen cada uno por su borde hasta desaparecer', (tester) async {
      await start(tester);
      // al empezar siguen en su sitio
      expect(tester.getRect(find.byKey(const Key('bar-home'))), barAtRest);
      expect(tester.getRect(find.byKey(const Key('middle-home'))), middleAtRest);
      expect(tester.getRect(find.byKey(const Key('card-home'))), cardAtRest);
      // a mitad, cada uno va hacia su borde y sin moverse en el otro eje
      await tester.pump(const Duration(milliseconds: 120));
      final bar = tester.getRect(find.byKey(const Key('bar-home')));
      final middle = tester.getRect(find.byKey(const Key('middle-home')));
      final card = tester.getRect(find.byKey(const Key('card-home')));
      expect(bar.top, lessThan(barAtRest.top));
      expect(bar.left, barAtRest.left);
      expect(middle.left, lessThan(middleAtRest.left));
      expect(middle.top, middleAtRest.top);
      expect(card.top, greaterThan(cardAtRest.top));
      expect(card.left, cardAtRest.left);
      // al terminar su salida ya no se ven
      await tester.pump(const Duration(milliseconds: 140));
      expect(tester.getRect(find.byKey(const Key('bar-home'))).bottom, lessThanOrEqualTo(0));
      expect(tester.getRect(find.byKey(const Key('middle-home'))).right, lessThanOrEqualTo(0));
      expect(tester.getRect(find.byKey(const Key('card-home'))).top, greaterThanOrEqualTo(800));
    });

    testWidgets('los de la nueva esperan un momento y entran desde los bordes hasta su sitio', (tester) async {
      await start(tester);
      Rect bar() => tester.getRect(find.byKey(const Key('bar-tasks')));
      Rect middle() => tester.getRect(find.byKey(const Key('middle-tasks')));
      Rect card() => tester.getRect(find.byKey(const Key('card-tasks')));
      // al principio, y durante la espera, fuera de la pantalla
      expect(bar().bottom, lessThanOrEqualTo(0));
      expect(middle().right, lessThanOrEqualTo(0));
      expect(card().top, greaterThanOrEqualTo(800));
      await tester.pump(SectionMotion.enterDelay - const Duration(milliseconds: 10));
      expect(bar().bottom, lessThanOrEqualTo(0));
      // ya en camino, y el primero en llegar es el de turno más bajo
      await tester.pump(const Duration(milliseconds: 150));
      expect(bar().top, greaterThan(-800));
      expect(middle().left, greaterThan(-400));
      expect(card().top, lessThan(1600));
      // todos terminan exactamente en su sitio
      await tester.pumpAndSettle();
      expect(bar(), barAtRest);
      expect(middle(), middleAtRest);
      expect(card(), cardAtRest);
    });

    testWidgets('casi a la vez: la nueva ya viene entrando antes de que la anterior termine de irse', (tester) async {
      await start(tester);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getRect(find.byKey(const Key('middle-home'))).left, lessThan(middleAtRest.left)); // todavía se está yendo
      expect(tester.getRect(find.byKey(const Key('middle-home'))).right, greaterThan(0));
      expect(tester.getRect(find.byKey(const Key('middle-tasks'))).left, greaterThan(-400)); // y la otra ya viene
    });

    testWidgets('al terminar la sección anterior se destruye y el fondo no se toca', (tester) async {
      await start(tester);
      expect(find.byKey(const Key('page-home')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-home')), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('mientras se mueven no reciben toques', (tester) async {
      await start(tester);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byKey(const Key('snack-tasks')), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Aviso de Tareas'), findsNothing);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('snack-tasks')));
      await tester.pump();
      expect(find.text('Aviso de Tareas'), findsOneWidget);
    });

    testWidgets('si llega otro cambio a mitad, la que se iba se destruye y se sigue sin saltos de pantalla', (tester) async {
      await start(tester);
      await tester.pump(const Duration(milliseconds: 100));
      SectionHost.goTo(tester.element(find.byKey(const Key('go-tasks'))), 'music');
      await tester.pumpAndSettle();
      expect(find.text('Pantalla Música'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('sin ninguna capa de opacidad encima del cristal, durante toda la transición', (tester) async {
      await start(tester);
      for (var i = 0; i < 7; i++) {
        expectNoLayerAbove(tester, reason: 'a los ${i * 50} ms');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expectNoLayerAbove(tester);
    });
  });

  group('la pista del menú', () {
    testWidgets('en Inicio dice cómo abrirlo hasta que se usa una vez', (tester) async {
      final hint = MemoryNavHintStore();
      await open(tester, hint: hint);
      expect(find.byKey(const Key('nav-hint')), findsOneWidget);
      expect(find.text('Mantén el dedo para navegar'), findsOneWidget);
      await menuOptions(tester);
      expect(find.byKey(const Key('nav-hint')), findsNothing);
      expect(hint.seen, isTrue);
    });

    testWidgets('no sale si ya se vio, ni en las otras secciones, ni sin almacén', (tester) async {
      await open(tester, hint: MemoryNavHintStore(seen: true));
      expect(find.byKey(const Key('nav-hint')), findsNothing);
      await open(tester);
      expect(find.byKey(const Key('nav-hint')), findsNothing);
      // ni en las otras secciones (aunque no se haya usado el menú: se llegó con un botón)
      await open(tester, hint: MemoryNavHintStore());
      expect(find.byKey(const Key('nav-hint')), findsOneWidget);
      await tester.tap(find.byKey(const Key('go-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nav-hint')), findsNothing);
    });
  });
}

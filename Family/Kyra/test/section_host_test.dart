import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/nav_hint_store.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/section_host.dart';
import 'package:kyora_chat/ui/widgets/app_section.dart';
import 'package:kyora_chat/ui/widgets/glass_card.dart';
import 'package:kyora_chat/ui/widgets/section_motion.dart';

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

    testWidgets('«atrás» en Inicio cierra la app, salvo que Kyra sea la pantalla de inicio del teléfono (ahí no se cierra)', (tester) async {
      final closed = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') closed.add(call);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var launcher = true;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: SectionHost(sections: sections, canExit: () => !launcher)));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(closed, isEmpty); // como launcher no se cierra
      expect(find.text('Pantalla Inicio'), findsOneWidget);
      launcher = false;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(closed, hasLength(1));
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

  group('la transición: glitch / holograma', () {
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

    /// Lo visible que está un bloque (la opacidad de su capa).
    double shown(WidgetTester tester, String key) =>
        tester.widget<Opacity>(find.ancestor(of: find.byKey(Key(key)), matching: find.byType(Opacity)).first).opacity;

    testWidgets('los de la sección actual se rompen todos a la vez y desaparecen en un instante', (tester) async {
      await start(tester);
      // al empezar siguen en su sitio, enteros
      for (final key in ['bar-home', 'middle-home', 'card-home']) {
        expect(shown(tester, key), 1, reason: key);
      }
      expect(tester.getRect(find.byKey(const Key('bar-home'))), barAtRest);
      // a mitad de su salida, rotos: más tenues y fuera de su sitio
      await tester.pump(const Duration(milliseconds: 60));
      for (final key in ['bar-home', 'middle-home', 'card-home']) {
        expect(shown(tester, key), allOf(greaterThan(0), lessThan(1)), reason: key);
      }
      expect(tester.getRect(find.byKey(const Key('middle-home'))), isNot(middleAtRest));
      // y al acabar la salida ya no se ven
      await tester.pump(SectionMotion.exitTime);
      for (final key in ['bar-home', 'middle-home', 'card-home']) {
        expect(shown(tester, key), 0, reason: key);
      }
    });

    testWidgets('los de la nueva esperan un momento y se materializan uno tras otro, por su turno, hasta quedar exactamente en su sitio', (tester) async {
      await start(tester);
      // al principio, y durante la espera, ocultos
      for (final key in ['bar-tasks', 'middle-tasks', 'card-tasks']) {
        expect(shown(tester, key), 0, reason: key);
      }
      await tester.pump(SectionMotion.enterDelay - const Duration(milliseconds: 10));
      expect(shown(tester, 'bar-tasks'), 0);
      // el primero ya empezó y el último (turno 2) aún no
      await tester.pump(const Duration(milliseconds: 40));
      expect(shown(tester, 'bar-tasks'), greaterThan(0));
      expect(shown(tester, 'card-tasks'), 0);
      // todos terminan enteros y exactamente en su sitio
      await tester.pumpAndSettle();
      for (final key in ['bar-tasks', 'middle-tasks', 'card-tasks']) {
        expect(shown(tester, key), 1, reason: key);
      }
      expect(tester.getRect(find.byKey(const Key('bar-tasks'))), barAtRest);
      expect(tester.getRect(find.byKey(const Key('middle-tasks'))), middleAtRest);
      expect(tester.getRect(find.byKey(const Key('card-tasks'))), cardAtRest);
    });

    testWidgets('todo es rápido: la anterior se ha ido antes de 260 ms y la nueva está entera antes de 650 ms', (tester) async {
      await start(tester);
      await tester.pump(const Duration(milliseconds: 260));
      expect(shown(tester, 'middle-home'), 0);
      await tester.pump(const Duration(milliseconds: 390));
      expect(shown(tester, 'card-tasks'), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('casi a la vez: la nueva ya empieza a materializarse antes de que la anterior termine de irse', (tester) async {
      await start(tester);
      await tester.pump(const Duration(milliseconds: 150));
      expect(shown(tester, 'middle-home'), greaterThan(0)); // todavía se está yendo
      expect(shown(tester, 'bar-tasks'), greaterThan(0)); // y la otra ya viene
    });

    testWidgets('al terminar la sección anterior se destruye', (tester) async {
      await start(tester);
      expect(find.byKey(const Key('page-home')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('page-home')), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('la que se va no recibe toques; la que llega sí, desde el primer momento', (tester) async {
      await start(tester);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byKey(const Key('snack-home')), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Aviso de Inicio'), findsNothing);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('snack-tasks')));
      await tester.pump();
      expect(find.text('Aviso de Tareas'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('si llega otro cambio a mitad, la que se iba se destruye y se sigue sin saltos de pantalla', (tester) async {
      await start(tester);
      await tester.pump(const Duration(milliseconds: 100));
      SectionHost.goTo(tester.element(find.byKey(const Key('go-tasks'))), 'music');
      await tester.pumpAndSettle();
      expect(find.text('Pantalla Música'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('sin cristal durante toda la transición', (tester) async {
      await start(tester);
      for (var i = 0; i < 12; i++) {
        expect(find.byType(BackdropFilter), findsNothing);
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();
    });
  });

  group('la pista del menú', () {
    testWidgets('en Inicio dice cómo abrirlo hasta que se usa una vez', (tester) async {
      final hint = MemoryNavHintStore();
      await open(tester, hint: hint);
      expect(find.byKey(const Key('nav-hint')), findsOneWidget);
      expect(find.text(NavHintPill.text), findsOneWidget);
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

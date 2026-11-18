import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/models/task.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/task_detail_page.dart';
import 'package:kyora_chat/ui/widgets/cyber_panel.dart';

import 'auth_gate_test.dart' show FakeAccount, MemoryRoleCache;
import 'fake_backend.dart';
import 'fake_engine.dart';
import 'sections.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'task_controller_test.dart' show FakeTaskBackend;

void main() {
  late FakeTaskBackend backend;
  late TaskController c;
  var n = 0;

  setUp(() {
    backend = FakeTaskBackend();
    n = 0;
    c = TaskController(MemoryTaskStore(), backend, newId: () => 'id-${++n}', retry: const Duration(hours: 1));
  });

  tearDown(() => c.dispose());

  /// La tarea cuyo detalle abre el botón del anfitrión.
  var openId = '';

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(c.start);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: Builder(builder: (context) => Center(child: TextButton(key: const Key('open-detail'), onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TaskDetailPage(controller: c, taskId: openId))), child: const Text('abrir')))))));
    await tester.pumpAndSettle();
  }

  /// ¿Está elegida la pestaña de estado o la etiqueta con esa clave? (lo dice su semántica)
  bool chosen(WidgetTester tester, Key key) => tester.widget<Semantics>(find.descendant(of: find.byKey(key), matching: find.byType(Semantics)).first).properties.selected ?? false;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
  }

  group('detalle', () {
    Future<TaskItem> openDetail(WidgetTester tester, {String name = 'Informe'}) async {
      final t = (await c.add(name))!;
      openId = t.id;
      await open(tester);
      await tester.tap(find.byKey(const Key('open-detail')));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailPage), findsOneWidget);
      return t;
    }

    testWidgets('la ficha es plana, como el detalle del clima: un rótulo apagado y debajo el dato, sin paneles', (tester) async {
      await openDetail(tester);
      for (final title in ['ESTADO', 'ENTREGA', 'TIEMPO ESPERADO', 'DESCRIPCIÓN', 'ETIQUETAS']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.byType(CyberPanel), findsNothing); // nada de bloques con caja
      expect(find.byKey(const Key('flat-backdrop')), findsOneWidget); // y el fondo va un poco oscurecido
      expect(find.text('Tarea'), findsNothing); // el título de arriba es un rótulo de consola
      expect(find.text('TAREA'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      for (final s in TaskStatus.values) {
        expect(find.byKey(Key('status-${s.wire}')), findsOneWidget, reason: s.wire);
      }
      expect(find.byWidgetPredicate((w) => w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius != null), findsNothing);
    });

    testWidgets('los campos de la ficha se ven como texto: sin caja, sin relleno y sin línea', (tester) async {
      await openDetail(tester);
      for (final key in ['task-name', 'task-expected', 'task-description']) {
        final field = tester.widget<TextField>(find.byKey(Key(key)));
        expect(field.decoration!.filled, isFalse, reason: key);
        expect(field.decoration!.border, InputBorder.none, reason: key);
        expect(field.decoration!.enabledBorder, InputBorder.none, reason: key);
        expect(field.decoration!.focusedBorder, InputBorder.none, reason: key);
      }
      // y los campos de otras pantallas, por tema, tampoco van en negro
      final c = tester.element(find.byKey(const Key('task-name'))).colors;
      final theme = Theme.of(tester.element(find.byKey(const Key('task-name'))));
      expect(theme.inputDecorationTheme.fillColor, isNot(c.field));
    });

    testWidgets('las subtareas llevan su cuenta (hechas/total) en el rótulo', (tester) async {
      final t = await openDetail(tester);
      expect(find.text('00/00'), findsNothing); // sin subtareas no hay cuenta
      await tester.runAsync(() => c.add('Uno', parentId: t.id));
      await tester.runAsync(() => c.add('Dos', parentId: t.id));
      await tester.pumpAndSettle();
      expect(find.text('00/02'), findsOneWidget);
      final sub = c.subtasksOf(t.id).first;
      await tester.tap(find.byKey(Key('sub-check-${sub.id}')));
      await settle(tester);
      expect(find.text('01/02'), findsOneWidget);
    });

    testWidgets('editar el nombre, la descripción y el tiempo esperado se guarda al salir', (tester) async {
      final t = await openDetail(tester);
      await tester.enterText(find.byKey(const Key('task-name')), 'Informe final');
      await tester.enterText(find.byKey(const Key('task-description')), 'Con cifras de octubre');
      await tester.enterText(find.byKey(const Key('task-expected')), '1h30');
      await tester.pageBack();
      await settle(tester);
      final saved = c.byId(t.id)!;
      expect(saved.name, 'Informe final');
      expect(saved.description, 'Con cifras de octubre');
      expect(saved.expectedMin, 90);
      expect(backend.tasks[t.id]!.name, 'Informe final');
    });

    testWidgets('un tiempo que no se entiende avisa y no se guarda', (tester) async {
      final t = await openDetail(tester);
      await tester.enterText(find.byKey(const Key('task-expected')), 'mucho');
      await tester.tap(find.byKey(const Key('task-name')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.textContaining('No entiendo'), findsOneWidget);
      expect(c.byId(t.id)!.expectedMin, isNull);
    });

    testWidgets('los estados se cambian con las fichas', (tester) async {
      final t = await openDetail(tester);
      await tester.tap(find.byKey(const Key('status-doing')));
      await settle(tester);
      expect(c.byId(t.id)!.status, TaskStatus.doing);
      await tester.tap(find.byKey(const Key('status-done')));
      await settle(tester);
      expect(c.byId(t.id)!.finished, isNotNull);
      expect(chosen(tester, const Key('status-done')), isTrue);
    });

    testWidgets('las subtareas se añaden, se finalizan y se borran', (tester) async {
      final t = await openDetail(tester);
      await tester.ensureVisible(find.byKey(const Key('subtask-input')));
      await tester.enterText(find.byKey(const Key('subtask-input')), 'Reunir datos');
      await tester.tap(find.byKey(const Key('subtask-add')));
      await settle(tester);
      expect(find.text('Reunir datos'), findsOneWidget);
      final sub = c.subtasksOf(t.id).single;
      await tester.tap(find.byKey(Key('sub-check-${sub.id}')));
      await settle(tester);
      expect(c.byId(sub.id)!.isDone, isTrue);
      await tester.tap(find.byKey(Key('sub-delete-${sub.id}')));
      await settle(tester);
      expect(find.text('Reunir datos'), findsNothing);
      expect(c.subtasksOf(t.id), isEmpty);
    });

    testWidgets('una etiqueta nueva se crea y se pone; tocarla otra vez la quita', (tester) async {
      final t = await openDetail(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -600)); // la lista se desliza hasta las etiquetas
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tag-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ask-field')), 'Urgente');
      await tester.tap(find.byKey(const Key('ask-ok')));
      await settle(tester);
      expect(c.tagsOf(t.id).map((x) => x.name), ['Urgente']);
      final tag = c.tags.single;
      expect(chosen(tester, Key('tag-${tag.id}')), isTrue);
      await tester.tap(find.byKey(Key('tag-${tag.id}')));
      await settle(tester);
      expect(c.tagsOf(t.id), isEmpty);
    });

    testWidgets('borrar pide confirmación, borra la tarea y cierra el detalle', (tester) async {
      final t = await openDetail(tester);
      await tester.tap(find.byKey(const Key('task-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-ok')));
      await settle(tester);
      expect(find.byType(TaskDetailPage), findsNothing);
      expect(c.byId(t.id), isNull);
      expect(backend.tasks[t.id]!.deletedAt, isNotNull);
    });

    testWidgets('una tarea borrada desde otro dispositivo mientras se mira lo dice', (tester) async {
      final t = await openDetail(tester);
      backend.remoteTask(backend.tasks[t.id]!.copyWith(deletedAt: DateTime.now().toUtc().add(const Duration(days: 1)), updatedAt: DateTime.now().toUtc().add(const Duration(days: 1))));
      await tester.runAsync(c.sync);
      await tester.pumpAndSettle();
      expect(find.text('Esta tarea ya no existe.'), findsOneWidget);
    });
  });

  group('desde la app', () {
    Future<void> gate(WidgetTester tester, FakeAccount account, {bool withTasks = true}) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: AuthGate(
          account: account,
          chat: FakeBackend(),
          music: FakeMusicBackend(),
          musicStore: MemoryMusicStore(since: DateTime.utc(2026, 10, 1)),
          saver: FakeSaver(),
          roleCache: MemoryRoleCache(),
          engine: FakeEngine.new,
          tasks: withTasks ? backend : null,
          openTaskStore: (_) async => MemoryTaskStore(),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    /// Toca la hora de Inicio: se expande y enseña la agenda.
    Future<void> openAgenda(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('home-time-tile')));
      await tester.pumpAndSettle();
      await settle(tester);
    }

    /// El campo «Añadir una tarea…» del día abierto de la semana.
    Finder weekField() => find.descendant(of: find.byKey(const Key('cal-week')), matching: find.byType(TextField));

    testWidgets('el administrador anota tareas desde la hora de Inicio y lo anotado sube a Supabase', (tester) async {
      await gate(tester, FakeAccount(uid: 'u1', profile: const Profile(id: 'u1', username: 'gustavo', role: Role.admin)));
      final options = await menuOptions(tester);
      expect(options, isNot(contains('calendar'))); // ya no es una sección
      expect(options, isNot(contains('tasks')));
      await openAgenda(tester);
      expect(find.byKey(const Key('cal-all-tasks')), findsNothing); // ya no hay una página aparte de tareas
      await tester.ensureVisible(weekField());
      await tester.enterText(weekField(), 'Desde el móvil');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(backend.tasks.values.single.name, 'Desde el móvil');
    });

    testWidgets('un visitante no tiene Inicio, así que tampoco las tareas ni el calendario', (tester) async {
      await gate(tester, FakeAccount(uid: 'u2', profile: const Profile(id: 'u2', username: 'ana', role: Role.intern)));
      expect(find.byKey(const Key('home-time-tile')), findsNothing);
      expect(find.byKey(const Key('nav-music')), findsOneWidget); // solo Música, Chat y Ajustes
    });

    testWidgets('sin tareas, recordatorios ni hábitos la hora no se expande', (tester) async {
      await gate(tester, FakeAccount(uid: 'u1', profile: const Profile(id: 'u1', username: 'gustavo', role: Role.admin)), withTasks: false);
      expect(find.byKey(const Key('home-time-tile')), findsNothing);
      expect(await menuOptions(tester), isNot(contains('calendar')));
    });
  });
}

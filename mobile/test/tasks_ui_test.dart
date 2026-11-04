import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/models/task.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/task_detail_page.dart';
import 'package:kyora_chat/ui/tasks_page.dart';

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

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(c.start);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: TasksPage(controller: c)));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
  }

  group('lista', () {
    testWidgets('sin tareas lo dice y deja anotar la primera', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('tasks-empty')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('task-input')), 'Comprar pan');
      await tester.tap(find.byKey(const Key('task-add')));
      await settle(tester);
      expect(find.text('Comprar pan'), findsOneWidget);
      expect(find.byKey(const Key('tasks-empty')), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const Key('task-input'))).controller!.text, isEmpty);
      expect(backend.tasks.values.single.name, 'Comprar pan'); // y subió a Supabase
    });

    testWidgets('«Intro» en el teclado también añade, y un texto vacío no crea nada', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('task-add')));
      await tester.pump();
      expect(c.roots(), isEmpty);
      await tester.enterText(find.byKey(const Key('task-input')), 'Llamar');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(c.roots().map((t) => t.name), ['Llamar']);
    });

    testWidgets('la casilla finaliza: sale de «Activas» y aparece en «Finalizada»; los filtros cuentan', (tester) async {
      await c.add('Uno');
      final two = (await c.add('Dos'))!;
      await c.setStatus(two, TaskStatus.doing);
      await open(tester);
      expect(find.text('Activas · 2'), findsOneWidget);
      expect(find.text('Pendiente · 1'), findsOneWidget);
      expect(find.text('En proceso · 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('task-check-id-1')));
      await settle(tester);
      expect(find.text('Uno'), findsNothing);
      expect(find.text('Activas · 1'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('filter-done'))); // los filtros se desplazan de lado
      await tester.tap(find.byKey(const Key('filter-done')));
      await tester.pumpAndSettle();
      expect(find.text('Uno'), findsOneWidget);
      expect(find.text('Dos'), findsNothing);
      await tester.tap(find.byKey(const Key('task-check-id-1'))); // otra vez: vuelve a pendiente
      await settle(tester);
      expect(find.text('No hay tareas «Finalizada».'), findsOneWidget);
    });

    testWidgets('cada tarea enseña su estado, su entrega, sus subtareas y sus etiquetas', (tester) async {
      final t = (await c.add('Informe', due: DateTime.now().add(const Duration(days: 1)).toUtc()))!;
      await c.setStatus(t, TaskStatus.review);
      await c.add('Datos', parentId: t.id);
      final tag = (await c.createTag('Trabajo'))!;
      await c.toggleTag(t.id, tag);
      await open(tester);
      expect(find.text('En revisión'), findsWidgets);
      expect(find.textContaining('Mañana'), findsOneWidget);
      expect(find.text('0/1 subtareas'), findsOneWidget);
      expect(find.text('Trabajo'), findsOneWidget);
    });

    testWidgets('la insignia dice cómo va la sincronización y sin red cuántas faltan por subir', (tester) async {
      backend.error = const ChatException('Sin conexión con Supabase', retryable: true);
      await c.add('Uno');
      await open(tester);
      await settle(tester);
      expect(find.byKey(const Key('sync-offline')), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(const Key('sync-offline'))).tooltip, 'Sin conexión: 1 por subir');
      backend.error = null;
      await tester.tap(find.byKey(const Key('sync-offline')));
      await settle(tester);
      expect(find.byKey(const Key('sync-idle')), findsOneWidget);
      expect(backend.tasks.length, 1);
    });
  });

  group('detalle', () {
    Future<TaskItem> openDetail(WidgetTester tester, {String name = 'Informe'}) async {
      final t = (await c.add(name))!;
      await open(tester);
      await tester.tap(find.byKey(Key('task-${t.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDetailPage), findsOneWidget);
      return t;
    }

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
      expect(find.text('Informe final'), findsOneWidget);
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
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('status-done'))).selected, isTrue);
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
      await tester.ensureVisible(find.byKey(const Key('tag-new')));
      await tester.tap(find.byKey(const Key('tag-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('ask-field')), 'Urgente');
      await tester.tap(find.byKey(const Key('ask-ok')));
      await settle(tester);
      expect(c.tagsOf(t.id).map((x) => x.name), ['Urgente']);
      final tag = c.tags.single;
      expect(tester.widget<FilterChip>(find.byKey(Key('tag-${tag.id}'))).selected, isTrue);
      await tester.tap(find.byKey(Key('tag-${tag.id}')));
      await settle(tester);
      expect(c.tagsOf(t.id), isEmpty);
    });

    testWidgets('borrar pide confirmación, borra la tarea y vuelve a la lista', (tester) async {
      final t = await openDetail(tester);
      await tester.tap(find.byKey(const Key('task-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-ok')));
      await settle(tester);
      expect(find.byType(TaskDetailPage), findsNothing);
      expect(c.byId(t.id), isNull);
      expect(find.byKey(const Key('tasks-empty')), findsOneWidget);
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

    testWidgets('el administrador llega a las tareas con el menú circular y lo anotado sube a Supabase', (tester) async {
      await gate(tester, FakeAccount(uid: 'u1', profile: const Profile(id: 'u1', username: 'gustavo', role: Role.admin)));
      final options = await menuOptions(tester);
      expect(options, contains('tasks'));
      expect(options, isNot(contains('reminders'))); // sin programador de avisos no hay recordatorios
      await goToSection(tester, 'tasks');
      await settle(tester);
      expect(find.byType(TasksPage), findsOneWidget);
      await tester.enterText(find.byKey(const Key('task-input')), 'Desde el móvil');
      await tester.tap(find.byKey(const Key('task-add')));
      await settle(tester);
      expect(backend.tasks.values.single.name, 'Desde el móvil');
    });

    testWidgets('el pasante también las alcanza con el menú circular', (tester) async {
      await gate(tester, FakeAccount(uid: 'u2', profile: const Profile(id: 'u2', username: 'ana', role: Role.intern)));
      await goToSection(tester, 'tasks');
      await settle(tester);
      expect(find.byType(TasksPage), findsOneWidget);
    });

    testWidgets('sin el servicio de tareas no hay sección de tareas', (tester) async {
      await gate(tester, FakeAccount(uid: 'u1', profile: const Profile(id: 'u1', username: 'gustavo', role: Role.admin)), withTasks: false);
      expect(await menuOptions(tester), isNot(contains('tasks')));
    });
  });
}

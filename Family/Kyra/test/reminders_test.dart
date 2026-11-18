import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/reminder_scheduler.dart';
import 'package:kyora_chat/data/reminder_store.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/models/reminder.dart';
import 'package:kyora_chat/state/reminder_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/ui/agenda_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_gate_test.dart' show FakeAccount, MemoryRoleCache;
import 'fake_backend.dart';
import 'fake_engine.dart';
import 'sections.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;

/// El programador de avisos de mentira: apunta qué avisos hay programados.
class FakeScheduler implements ReminderScheduler {
  final Map<int, Reminder> scheduled = {};
  bool granted = true;
  int inits = 0;
  int permissionAsks = 0;
  bool failSchedule = false;

  @override
  Future<void> init() async => inits++;

  @override
  Future<bool> ensurePermissions() async {
    permissionAsks++;
    return granted;
  }

  @override
  Future<void> schedule(Reminder reminder) async {
    if (failSchedule) throw StateError('no se pudo');
    scheduled[reminder.notifId] = reminder;
  }

  /// Los avisos semanales (de los hábitos): número → (título, día, hora, minuto).
  final Map<int, (String, int, int, int)> weekly = {};

  @override
  Future<void> scheduleWeekly({required int id, required String title, required int weekday, required int hour, required int minute}) async {
    if (failSchedule) throw StateError('no se pudo');
    weekly[id] = (title, weekday, hour, minute);
  }

  @override
  Future<void> cancel(int notifId) async {
    scheduled.remove(notifId);
    weekly.remove(notifId);
  }

  /// Las notificaciones que se mostraron al momento: número → (título, texto).
  final Map<int, (String, String)> shown = {};

  @override
  Future<void> showNow({required int id, required String title, required String body}) async {
    if (failSchedule) throw StateError('no se pudo');
    shown[id] = (title, body);
  }
}

void main() {
  late MemoryReminderStore store;
  late FakeScheduler scheduler;
  late ReminderController c;
  var ids = 0;
  var now = DateTime.utc(2026, 11, 2, 12);

  setUp(() {
    store = MemoryReminderStore();
    scheduler = FakeScheduler();
    ids = 0;
    now = DateTime.utc(2026, 11, 2, 12);
    c = ReminderController(store, scheduler, now: () => now, newId: () => 'r-${++ids}');
  });

  tearDown(() => c.dispose());

  group('controlador', () {
    test('un recordatorio nuevo se guarda y programa su aviso a su hora', () async {
      final at = DateTime.utc(2026, 11, 3, 8);
      final r = (await c.add('  Llamar al banco  ', at, notes: ' antes de las 9 '))!;
      expect(r.title, 'Llamar al banco');
      expect(r.notes, 'antes de las 9');
      expect(scheduler.scheduled[r.notifId]!.at, at);
      expect((await store.load()).single.id, r.id);
      expect(scheduler.permissionAsks, 1);
      expect(c.notificationsBlocked, isFalse);
    });

    test('un título vacío no crea nada', () async {
      expect(await c.add('  ', DateTime.utc(2026, 11, 3)), isNull);
      expect(c.items, isEmpty);
    });

    test('cada uno tiene su propio número de aviso', () async {
      final a = (await c.add('A', DateTime.utc(2026, 11, 3)))!;
      final b = (await c.add('B', DateTime.utc(2026, 11, 4)))!;
      expect(b.notifId, isNot(a.notifId));
      await c.delete(a);
      final d = (await c.add('D', DateTime.utc(2026, 11, 5)))!;
      expect({b.notifId, d.notifId}.length, 2); // no se reutiliza el de uno que sigue vivo
    });

    test('una hora que ya pasó se guarda pero no programa aviso', () async {
      final r = (await c.add('Ayer', DateTime.utc(2026, 11, 1)))!;
      expect(scheduler.scheduled, isEmpty);
      expect(c.isOverdue(r), isTrue);
      expect(c.items.single.title, 'Ayer');
    });

    test('van por hora: los pendientes con el más próximo primero, y los hechos al final', () async {
      final late = (await c.add('Tarde', DateTime.utc(2026, 11, 9)))!;
      await c.add('Pronto', DateTime.utc(2026, 11, 3));
      final done = (await c.add('Hecho', DateTime.utc(2026, 11, 2, 13)))!;
      await c.toggleDone(done);
      expect(c.items.map((r) => r.title), ['Pronto', 'Tarde', 'Hecho']);
      expect(late.title, 'Tarde');
    });

    test('marcarlo como hecho cancela el aviso y volver a pendiente lo programa otra vez', () async {
      final r = (await c.add('Llamar', DateTime.utc(2026, 11, 3, 8)))!;
      await c.toggleDone(c.items.single);
      expect(scheduler.scheduled, isEmpty);
      expect(c.items.single.done, isTrue);
      await c.toggleDone(c.items.single);
      expect(scheduler.scheduled.keys, [r.notifId]);
    });

    test('editar la hora cambia el aviso (no quedan dos)', () async {
      final r = (await c.add('Llamar', DateTime.utc(2026, 11, 3, 8)))!;
      await c.update(r, title: 'Llamar a Ana', at: DateTime.utc(2026, 11, 4, 10), notes: 'su número está en la agenda');
      final saved = c.items.single;
      expect(saved.title, 'Llamar a Ana');
      expect(saved.notes, 'su número está en la agenda');
      expect(scheduler.scheduled.length, 1);
      expect(scheduler.scheduled[r.notifId]!.at, DateTime.utc(2026, 11, 4, 10));
      await c.update(saved, title: '  '); // sin título no se guarda
      expect(c.items.single.title, 'Llamar a Ana');
    });

    test('borrar quita el recordatorio y su aviso', () async {
      final r = (await c.add('Llamar', DateTime.utc(2026, 11, 3, 8)))!;
      await c.delete(r);
      expect(c.items, isEmpty);
      expect(scheduler.scheduled, isEmpty);
      // el borrado es suave: la fila se queda (marcada) para que el borrado llegue a Supabase
      final kept = (await store.load()).single;
      expect(kept.isDeleted, isTrue);
      expect(kept.dirty, isTrue);
    });

    test('al abrir la app se vuelven a programar los pendientes futuros (no los hechos ni los pasados)', () async {
      store.items = [
        Reminder(id: 'a', notifId: 1, title: 'Futuro', at: DateTime.utc(2026, 11, 3), createdAt: now),
        Reminder(id: 'b', notifId: 2, title: 'Pasado', at: DateTime.utc(2026, 11, 1), createdAt: now),
        Reminder(id: 'c', notifId: 3, title: 'Hecho', at: DateTime.utc(2026, 11, 4), createdAt: now, done: true),
      ];
      await c.start();
      expect(c.loaded, isTrue);
      expect(scheduler.inits, 1);
      expect(scheduler.scheduled.keys, [1]);
      expect(c.items.length, 3);
    });

    test('sin permiso de notificaciones se guarda igual y se avisa de que no sonará', () async {
      scheduler.granted = false;
      await c.add('Llamar', DateTime.utc(2026, 11, 3, 8));
      expect(c.notificationsBlocked, isTrue);
      expect(c.items.length, 1);
    });

    test('si programar el aviso falla, el recordatorio no se pierde', () async {
      scheduler.failSchedule = true;
      await c.add('Llamar', DateTime.utc(2026, 11, 3, 8));
      expect(c.items.length, 1);
      expect(c.notificationsBlocked, isTrue);
    });

    test('lo que se guarda en el teléfono se lee igual al volver, y lo dañado no rompe', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await PrefsReminderStore.open('u1');
      final r = Reminder(id: 'a', notifId: 7, title: 'Llamar', notes: 'n', at: DateTime.utc(2026, 11, 3, 8), createdAt: now, done: true, updatedAt: now);
      await prefs.save([r]);
      final back = (await (await PrefsReminderStore.open('u1')).load()).single;
      expect(back.toJson(), r.toJson());
      expect(back.dirty, isFalse);
      expect(await (await PrefsReminderStore.open('u2')).load(), isEmpty); // uno por cuenta
      SharedPreferences.setMockInitialValues({'reminders.u3': 'esto no es json'});
      expect(await (await PrefsReminderStore.open('u3')).load(), isEmpty);
    });
  });

  group('en el Calendario', () {
    // un día fijo para la pantalla; los recordatorios se crean ese día
    final day = DateTime(2026, 11, 5, 9);

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(c.start);
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: AgendaView(reminders: Future.value(c), now: () => day)));
      await tester.pumpAndSettle();
    }

    testWidgets('sin nada lo dice; «+» → Recordatorio crea uno con su título y notas', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('cal-day-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cal-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-add-task')), findsNothing); // sin tareas no se ofrecen
      await tester.tap(find.byKey(const Key('cal-add-reminder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reminder-save'))); // sin título no guarda
      await tester.pumpAndSettle();
      expect(find.text('Escribe qué quieres recordar.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('reminder-title')), 'Pagar la luz');
      await tester.enterText(find.byKey(const Key('reminder-notes')), 'vence el 10');
      await tester.tap(find.byKey(const Key('reminder-save')));
      await tester.pumpAndSettle();
      expect(c.items.single.title, 'Pagar la luz');
      expect(c.items.single.notes, 'vence el 10');
    });

    testWidgets('sale en su día; la casilla lo marca como hecho, tocarlo lo edita y desde ahí se borra', (tester) async {
      final r = (await c.add('Llamar', DateTime(2026, 11, 5, 15).toUtc()))!;
      await open(tester);
      expect(find.byKey(Key('cal-reminder-${r.id}')), findsOneWidget);
      // la hora va en el bloque de color de la tarjeta, en 12 h: 3 PM
      expect(find.descendant(of: find.byKey(Key('card-time-reminder-${r.id}')), matching: find.text('3')), findsOneWidget);
      expect(find.descendant(of: find.byKey(Key('card-time-reminder-${r.id}')), matching: find.text('PM')), findsOneWidget);
      await tester.tap(find.byKey(Key('cal-reminder-check-${r.id}')));
      await tester.pumpAndSettle();
      expect(c.items.single.done, isTrue);
      await tester.tap(find.text('Llamar'));
      await tester.pumpAndSettle();
      expect(find.text('Editar recordatorio'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('reminder-title')), 'Llamar a Ana');
      await tester.tap(find.byKey(const Key('reminder-save')));
      await tester.pumpAndSettle();
      expect(find.text('Llamar a Ana'), findsOneWidget);
      await tester.tap(find.text('Llamar a Ana'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reminder-delete')));
      await tester.pumpAndSettle();
      expect(c.items, isEmpty);
      expect(find.byKey(const Key('cal-day-empty')), findsOneWidget);
    });

    testWidgets('el «+» empieza el recordatorio en el día elegido', (tester) async {
      await open(tester);
      // el día se elige tocando su banda de la semana
      await tester.tap(find.byKey(const Key('cal-week-day-2026-11-07')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cal-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cal-add-reminder')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reminder-title')), 'Sábado');
      await tester.tap(find.byKey(const Key('reminder-save')));
      await tester.pumpAndSettle();
      final at = c.items.single.at.toLocal();
      expect((at.year, at.month, at.day, at.hour), (2026, 11, 7, 9));
      expect(find.text('Sábado'), findsOneWidget); // sale en el día elegido
    });

    testWidgets('si las notificaciones están bloqueadas, el Calendario lo avisa', (tester) async {
      scheduler.granted = false;
      await c.add('Llamar', DateTime.now().toUtc().add(const Duration(days: 1)));
      await open(tester);
      expect(find.byKey(const Key('reminders-blocked')), findsOneWidget);
    });
  });

  group('desde la app', () {
    testWidgets('el administrador llega a los recordatorios en el Calendario', (tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: AuthGate(
          account: FakeAccount(uid: 'u1', profile: const Profile(id: 'u1', username: 'gustavo', role: Role.admin)),
          chat: FakeBackend(),
          music: FakeMusicBackend(),
          musicStore: MemoryMusicStore(since: DateTime.utc(2026, 10, 1)),
          saver: FakeSaver(),
          roleCache: MemoryRoleCache(),
          engine: FakeEngine.new,
          reminderScheduler: scheduler,
          openReminderStore: (_) async => store,
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
      final options = await menuOptions(tester);
      expect(options, isNot(contains('calendar'))); // tampoco es sección: vive en la hora de Inicio
      expect(options, isNot(contains('tasks')));
      expect(options, isNot(contains('reminders'))); // ya no son secciones: viven en la agenda de la hora
      await tester.tap(find.byKey(const Key('home-time-tile')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pumpAndSettle();
      expect(find.byType(AgendaView), findsOneWidget);
      expect(find.byKey(const Key('cal-tab-tasks')), findsNothing); // sin Supabase de tareas no hay pestaña de tareas
      expect(scheduler.inits, 1);
    });
  });
}

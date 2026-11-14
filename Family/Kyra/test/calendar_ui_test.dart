import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/event_store.dart';
import 'package:kyora_chat/data/habit_store.dart';
import 'package:kyora_chat/data/reminder_store.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/models/event.dart';
import 'package:kyora_chat/models/habit.dart';
import 'package:kyora_chat/models/task.dart';
import 'package:kyora_chat/state/event_controller.dart';
import 'package:kyora_chat/state/habit_controller.dart';
import 'package:kyora_chat/state/reminder_controller.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/agenda_view.dart';
import 'package:kyora_chat/ui/tasks_page.dart';
import 'package:kyora_chat/util/agenda.dart';
import 'package:kyora_chat/util/calendar_marks.dart';
import 'package:kyora_chat/ui/widgets/month_dial.dart';
import 'package:kyora_chat/ui/widgets/dot_matrix.dart';

import 'calendar_sync_test.dart' show FakeRowBackend;
import 'habit_test.dart' show FakeHabitBackend;
import 'reminders_test.dart' show FakeScheduler;
import 'task_controller_test.dart' show FakeTaskBackend;

void main() {
  // un jueves a media mañana
  final now = DateTime(2026, 11, 5, 10, 30);
  late TaskController tasks;
  late ReminderController reminders;
  late HabitController habits;
  late EventController events;
  late FakeRowBackend<CalendarEvent> eventBackend;
  late FakeScheduler scheduler;
  var n = 0;

  setUp(() {
    n = 0;
    AgendaView.lastMode = CalendarMode.week;
    scheduler = FakeScheduler();
    eventBackend = FakeRowBackend<CalendarEvent>((e, at) => CalendarEvent(
          id: e.id, title: e.title, description: e.description, startsAt: e.startsAt, endsAt: e.endsAt, allDay: e.allDay, color: e.color, taskId: e.taskId, createdAt: e.createdAt, updatedAt: e.updatedAt, deletedAt: e.deletedAt, syncedAt: at,
        ));
    tasks = TaskController(MemoryTaskStore(), FakeTaskBackend(), now: () => now.toUtc(), newId: () => 't${++n}', retry: const Duration(hours: 1));
    reminders = ReminderController(MemoryReminderStore(), scheduler, now: () => now.toUtc(), newId: () => 'r${++n}');
    habits = HabitController(MemoryHabitStore(), FakeHabitBackend(), scheduler: scheduler, now: () => now.toUtc(), newId: () => 'h${++n}', retry: const Duration(hours: 1));
    events = EventController(MemoryEventStore(), eventBackend, now: () => now.toUtc(), newId: () => 'e${++n}', retry: const Duration(hours: 1));
  });

  tearDown(() {
    tasks.dispose();
    reminders.dispose();
    habits.dispose();
    events.dispose();
  });

  Future<void> open(WidgetTester tester, {bool withTasks = true, bool withReminders = true, bool withHabits = true, bool withEvents = true}) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tasks.start();
      await reminders.start();
      await habits.start();
      await events.start();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: AgendaView(
        tasks: withTasks ? Future.value(tasks) : null,
        reminders: withReminders ? Future.value(reminders) : null,
        habits: withHabits ? Future.value(habits) : null,
        events: withEvents ? Future.value(events) : null,
        now: () => now,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  String title(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('cal-title'))).data!;

  Future<void> openDial(WidgetTester tester) => tapKey(tester, 'cal-open-month');

  /// Gira el anillo de los meses del dial `months` meses hacia delante (o hacia atrás, si es negativo), despacio.
  Future<void> turnMonths(WidgetTester tester, int months) async {
    final dial = tester.getRect(find.byKey(const Key('month-dial')));
    final width = dial.width;
    final start = Offset(MonthDial.monthRadius(width), dial.center.dy);
    await tester.timedDragFrom(start, Offset(0, -MonthDial.monthRadius(width) * MonthDial.monthStep * months), Duration(milliseconds: 1500 * months.abs()));
    await tester.pumpAndSettle();
  }

  group('las vistas', () {
    testWidgets('al abrir es la semana: el título es su rango y las tres vistas están arriba', (tester) async {
      await open(tester);
      expect(title(tester), '2 – 8 nov 2026');
      expect(find.byKey(const Key('cal-week')), findsOneWidget);
      for (final m in ['day', 'week', 'month']) {
        expect(find.byKey(Key('cal-mode-$m')), findsOneWidget);
      }
      expect(find.byKey(const Key('cal-strip-2026-11-05')), findsOneWidget);
    });

    testWidgets('Mes: seis semanas en cuadros sueltos; el 1 de cada mes lleva su nombre; tocar un día lo elige y enseña lo suyo debajo', (tester) async {
      await tester.runAsync(() async {
        await reminders.add('Llamar', DateTime(2026, 11, 12, 9).toUtc());
      });
      await open(tester);
      await tapKey(tester, 'cal-mode-month');
      expect(title(tester), 'Noviembre 2026');
      expect(find.byKey(const Key('cal-cell-2026-10-26')), findsOneWidget); // la rejilla empieza el lunes anterior al 1
      expect(find.byKey(const Key('cal-cell-2026-12-06')), findsOneWidget);
      expect(find.text('1 nov'), findsOneWidget);
      // un pequeño margen entre un día y el siguiente
      final a = tester.getRect(find.byKey(const Key('cal-cell-2026-11-04')));
      final b = tester.getRect(find.byKey(const Key('cal-cell-2026-11-05')));
      expect(b.left - a.right, closeTo(3, 0.5));
      expect(find.text('Llamar'), findsNothing); // es del 12
      await tapKey(tester, 'cal-cell-2026-11-12');
      expect(find.text('Llamar'), findsOneWidget);
      expect(find.byKey(const Key('cal-day')), findsOneWidget);
    });

    testWidgets('Día: la columna de 24 h con cada cosa en su hora y lo de todo el día arriba', (tester) async {
      late Habit habit;
      await tester.runAsync(() async {
        await reminders.add('Llamar', DateTime(2026, 11, 5, 11).toUtc());
        await events.add('Reunión', DateTime(2026, 11, 5, 11).toUtc(), endsAt: DateTime(2026, 11, 5, 12).toUtc());
        await events.add('Cumple', DateTime(2026, 11, 5), allDay: true);
        habit = (await habits.add('Agua'))!; // sin aviso: va en la franja de todo el día
      });
      await open(tester);
      await tapKey(tester, 'cal-mode-day');
      expect(title(tester), 'Jueves 5 nov 2026');
      expect(find.byKey(const Key('cal-timeline')), findsOneWidget);
      expect(find.byKey(Key('cal-block-reminder-${reminders.items.single.id}')), findsOneWidget);
      expect(find.byKey(Key('cal-block-event-${events.items.firstWhere((e) => e.title == 'Reunión').id}')), findsOneWidget);
      expect(find.text('Cumple'), findsOneWidget);
      expect(find.byKey(Key('cal-habit-check-${habit.id}')), findsOneWidget);
      expect(find.byKey(const Key('cal-now')), findsOneWidget); // la línea de «ahora» (es hoy)
      // lo que se solapa va en carriles, uno junto a otro
      final reminderBlock = tester.getRect(find.byKey(Key('cal-block-reminder-${reminders.items.single.id}')));
      final eventBlock = tester.getRect(find.byKey(Key('cal-block-event-${events.items.firstWhere((e) => e.title == 'Reunión').id}')));
      expect(eventBlock.right, lessThanOrEqualTo(reminderBlock.left + 1));
    });

    testWidgets('‹ y › mueven el rango según la vista, y «Hoy» vuelve', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-next');
      expect(title(tester), '9 – 15 nov 2026');
      await tapKey(tester, 'cal-mode-month');
      await tapKey(tester, 'cal-prev');
      expect(title(tester), 'Octubre 2026');
      await tapKey(tester, 'cal-mode-day');
      await tapKey(tester, 'cal-next');
      expect(title(tester), 'Martes 13 oct 2026'); // el 12 de octubre, un día después
      await tapKey(tester, 'cal-today');
      expect(title(tester), 'Jueves 5 nov 2026');
    });

    testWidgets('la vista que se eligió se recuerda al volver a abrir', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-mode-month');
      expect(AgendaView.lastMode, CalendarMode.month);
    });

    testWidgets('en la semana, tocar un día de la tira lo elige', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-strip-2026-11-07');
      final label = find.descendant(of: find.byKey(const Key('cal-week-day-2026-11-07')), matching: find.byType(Text));
      expect(tester.widget<Text>(label).style!.fontWeight, FontWeight.w700);
    });
  });

  group('qué se muestra', () {
    testWidgets('hay un recuadro por clase, con cuántas hay; apagar una la quita de la lista', (tester) async {
      await tester.runAsync(() async {
        await reminders.add('Llamar', DateTime(2026, 11, 5, 9).toUtc());
        await tasks.add('Informe', due: DateTime(2026, 11, 5, 18).toUtc());
        await events.add('Cena', DateTime(2026, 11, 6, 20).toUtc());
      });
      await open(tester);
      for (final k in ['event', 'task', 'reminder', 'habit']) {
        expect(find.byKey(Key('cal-show-$k')), findsOneWidget);
      }
      expect(find.descendant(of: find.byKey(const Key('cal-show-reminder')), matching: find.text('1')), findsOneWidget);
      expect(find.text('Llamar'), findsOneWidget);
      await tapKey(tester, 'cal-show-reminder');
      expect(find.text('Llamar'), findsNothing);
      expect(find.text('Informe'), findsOneWidget);
      await tapKey(tester, 'cal-show-reminder');
      expect(find.text('Llamar'), findsOneWidget);
    });

    testWidgets('solo se ofrecen las clases que existen', (tester) async {
      await open(tester, withEvents: false, withHabits: false);
      expect(find.byKey(const Key('cal-show-event')), findsNothing);
      expect(find.byKey(const Key('cal-show-habit')), findsNothing);
      expect(find.byKey(const Key('cal-show-task')), findsOneWidget);
    });
  });

  group('actualizar', () {
    testWidgets('el botón «Actualizar» pone al día con Supabase: baja lo que llegó de otro dispositivo', (tester) async {
      await open(tester);
      final before = eventBackend.pulls;
      eventBackend.remote(CalendarEvent(id: 'w1', title: 'Desde la web', startsAt: DateTime(2026, 11, 6, 10).toUtc(), createdAt: now.toUtc(), updatedAt: now.toUtc()));
      expect(find.text('Desde la web'), findsNothing);
      await tester.tap(find.byKey(const Key('cal-refresh')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(eventBackend.pulls, greaterThan(before));
      expect(find.text('Desde la web'), findsOneWidget);
    });

    testWidgets('sin conexión lo dice en una línea, y al volver se quita', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('cal-sync-problem')), findsNothing);
      eventBackend.failWith = const ChatException('Sin conexión', retryable: true);
      await tester.tap(find.byKey(const Key('cal-refresh')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-sync-problem')), findsOneWidget);
      eventBackend.failWith = null;
      await tester.tap(find.byKey(const Key('cal-refresh')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-sync-problem')), findsNothing);
    });
  });

  group('el mini calendario', () {
    Future<void> pinch(WidgetTester tester, {required bool inward}) async {
      final panels = tester.getRect(find.byKey(const Key('cal-week')));
      final c = panels.center;
      final a = await tester.startGesture(c + Offset(inward ? -120 : -30, 0), pointer: 7);
      final b = await tester.startGesture(c + Offset(inward ? 120 : 30, 0), pointer: 8);
      await tester.pump();
      for (var i = 1; i <= 6; i++) {
        await a.moveBy(Offset(inward ? 15 : -15, 0));
        await b.moveBy(Offset(inward ? -15 : 15, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
    }

    testWidgets('pellizcando con dos dedos se abre; separándolos se cierra', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('month-dial')), findsNothing);
      await pinch(tester, inward: true);
      expect(find.byKey(const Key('month-dial')), findsOneWidget);
      await pinch(tester, inward: false);
      expect(find.byKey(const Key('month-dial')), findsNothing);
    });

    testWidgets('también se abre con su botón; el núcleo va en el borde izquierdo con la fecha en matriz de puntos', (tester) async {
      await open(tester);
      await openDial(tester);
      expect(tester.widget<DotMatrixText>(find.byKey(const Key('dial-focus-day'))).text, '05');
      expect(tester.widget<DotMatrixText>(find.byKey(const Key('dial-focus-month'))).text, 'NOV');
      final hub = tester.getRect(find.byKey(const Key('dial-hub')));
      expect(hub.left, 0);
      expect(hub.center.dy, closeTo(850 / 2, 1));
      expect(find.byKey(const Key('dial-day-2026-11-05')), findsOneWidget);
      expect(find.byKey(const Key('dial-month')), findsOneWidget);
    });

    testWidgets('los días llevan marcadores de colores: tareas, recordatorios y hábitos', (tester) async {
      await tester.runAsync(() async {
        await reminders.add('Llamar', DateTime(2026, 11, 6, 9).toUtc());
        await tasks.add('Entregar', due: DateTime(2026, 11, 7, 18).toUtc());
        await habits.add('Correr', weekdays: Habit.maskOf([3]));
      });
      await open(tester);
      await openDial(tester);
      final c = KyoraColors.classic();
      Color markColor(String key) => tester.widget<Container>(find.byKey(Key(key))).color!;
      expect(markColor('dial-mark-reminders-2026-11-06'), c.reminders);
      expect(markColor('dial-mark-tasks-2026-11-07'), c.tasks);
      expect(markColor('dial-mark-habits-2026-11-11'), c.habits); // el miércoles siguiente (los anteriores a crearlo no cuentan)
      expect(find.byKey(const Key('dial-mark-habits-2026-11-12')), findsNothing); // jueves: no toca
      expect(find.byKey(const Key('dial-mark-tasks-2026-11-06')), findsNothing);
    });

    testWidgets('girar el anillo de los días cambia el del centro; tocar el núcleo lo elige y cierra', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-mode-day');
      await openDial(tester);
      final dial = tester.getRect(find.byKey(const Key('month-dial')));
      final step = MonthDial.dayRadius(dial.width) * MonthDial.dayStep;
      await tester.timedDragFrom(Offset(dial.width * 0.62, dial.center.dy), Offset(0, -step * 3), const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.widget<DotMatrixText>(find.byKey(const Key('dial-focus-day'))).text, '08');
      await tapKey(tester, 'dial-hub');
      expect(find.byKey(const Key('month-dial')), findsNothing);
      expect(title(tester), 'Domingo 8 nov 2026');
    });

    testWidgets('girar el anillo de los meses pasa de mes; tocar un día lo elige', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-mode-day');
      await openDial(tester);
      await turnMonths(tester, 1);
      expect(tester.widget<DotMatrixText>(find.byKey(const Key('dial-focus-month'))).text, 'DIC');
      await tapKey(tester, 'dial-day-2026-12-05');
      expect(title(tester), 'Sábado 5 dic 2026');
    });

    testWidgets('tocar fuera o «atrás» lo cierra sin cambiar de día', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-mode-day');
      await openDial(tester);
      await tester.tapAt(const Offset(390, 60));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('month-dial')), findsNothing);
      expect(title(tester), 'Jueves 5 nov 2026');
      await openDial(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('month-dial')), findsNothing);
    });

    test('los marcadores y el resumen de un día', () async {
      await tasks.start();
      await reminders.start();
      await habits.start();
      await reminders.add('A', DateTime(2026, 11, 6, 9).toUtc());
      await reminders.add('B', DateTime(2026, 11, 6, 11).toUtc());
      await tasks.add('T', due: DateTime(2026, 11, 6, 18).toUtc());
      await habits.add('H', weekdays: Habit.maskOf([5]));
      final day = DateTime(2026, 11, 6);
      final marks = marksFor(day, tasks: tasks, reminders: reminders, habits: habits);
      expect(marks, const DayMarks(tasks: 1, reminders: 2, habits: 1));
      expect(marksSummary(marks), '1 tarea · 1 hábito · 2 recordatorios');
      expect(marksSummary(marks, withReminders: false), '1 tarea · 1 hábito');
      expect(marksSummary(const DayMarks()), 'sin pendientes');
      final month = monthMarks(DateTime(2026, 11), tasks: tasks, reminders: reminders, habits: habits);
      expect(month.length, 30);
      expect(month[6], marks);
      expect(month[7]!.tasks, 0);
    });
  });

  group('lo del día', () {
    testWidgets('reúne recordatorios, tareas, eventos y hábitos de hoy; las casillas los marcan', (tester) async {
      late TaskItem task;
      late Habit habit;
      await tester.runAsync(() async {
        await reminders.add('Tomar la medicina', DateTime(2026, 11, 5, 14).toUtc());
        task = (await tasks.add('Entregar el informe', due: DateTime(2026, 11, 5, 18).toUtc()))!;
        await tasks.add('Otro día', due: DateTime(2026, 11, 9, 18).toUtc()); // la semana que viene: no sale
        await events.add('Cena', DateTime(2026, 11, 5, 20).toUtc());
        habit = (await habits.add('Leer', weekdays: Habit.maskOf([4])))!;
      });
      await open(tester);
      expect(find.text('Tomar la medicina'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('Entregar el informe'), findsOneWidget);
      expect(find.text('Otro día'), findsNothing);
      expect(find.text('Cena'), findsOneWidget);
      expect(find.text('Leer'), findsOneWidget);
      await tapKey(tester, 'cal-task-check-${task.id}');
      expect(tasks.byId(task.id)!.isDone, isTrue);
      await tapKey(tester, 'cal-habit-check-${habit.id}');
      expect(habits.isDone(habit, now), isTrue);
      final reminder = reminders.items.single;
      await tapKey(tester, 'cal-reminder-check-${reminder.id}');
      expect(reminders.items.single.done, isTrue);
    });

    testWidgets('hoy también enseña lo vencido de antes, con su día; otro día, no', (tester) async {
      await tester.runAsync(() => tasks.add('Pagar', due: DateTime(2026, 10, 30, 18).toUtc()));
      await open(tester);
      expect(find.text('Pagar'), findsOneWidget);
      expect(find.text('VENCIDO'), findsOneWidget);
      expect(find.textContaining('30 oct'), findsOneWidget);
      await tapKey(tester, 'cal-mode-month');
      await tapKey(tester, 'cal-cell-2026-11-04');
      expect(find.text('Pagar'), findsNothing);
      await tapKey(tester, 'cal-cell-2026-11-05');
      expect(find.text('Pagar'), findsOneWidget);
    });

    testWidgets('un día que todavía no llega enseña sus hábitos, pero no se pueden marcar', (tester) async {
      late Habit habit;
      await tester.runAsync(() async => habit = (await habits.add('Leer', weekdays: Habit.maskOf([6])))!);
      await open(tester);
      expect(find.text('Leer'), findsOneWidget); // el sábado de esta semana
      await tapKey(tester, 'cal-habit-check-${habit.id}');
      expect(habits.isDone(habit, DateTime(2026, 11, 7, 12)), isFalse);
    });

    testWidgets('sin nada ese día lo dice', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('cal-day-empty')), findsOneWidget);
    });

    testWidgets('un evento se abre al tocarlo: se edita y desde ahí se borra', (tester) async {
      await tester.runAsync(() => events.add('Cena', DateTime(2026, 11, 5, 20).toUtc()));
      await open(tester);
      await tester.tap(find.text('Cena'));
      await tester.pumpAndSettle();
      expect(find.text('Editar evento'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('event-title')), 'Cena con Ana');
      await tapKey(tester, 'event-save');
      expect(events.items.single.title, 'Cena con Ana');
      await tester.tap(find.text('Cena con Ana'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'event-delete');
      expect(events.items, isEmpty);
    });
  });

  group('el «+»', () {
    testWidgets('ofrece evento, tarea, recordatorio y hábito; la tarea nace con el día elegido', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-strip-2026-11-07');
      await tapKey(tester, 'cal-add');
      for (final k in ['event', 'task', 'reminder', 'habit']) {
        expect(find.byKey(Key('cal-add-$k')), findsOneWidget);
      }
      await tapKey(tester, 'cal-add-task');
      await tapKey(tester, 'quick-task-save'); // sin nombre no guarda
      expect(find.text('Escribe la tarea.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('quick-task-name')), 'Comprar pan');
      await tapKey(tester, 'quick-task-save');
      final due = tasks.roots().single.due!.toLocal();
      expect((due.year, due.month, due.day, due.hour), (2026, 11, 7, 18));
      expect(find.text('Comprar pan'), findsOneWidget); // sale en el día elegido
    });

    testWidgets('un evento: sin título no guarda; con él nace el día elegido a las 9:00, con su color', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-strip-2026-11-06');
      await tapKey(tester, 'cal-add');
      await tapKey(tester, 'cal-add-event');
      await tapKey(tester, 'event-save');
      expect(find.text('Escribe el título del evento.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('event-title')), 'Dentista');
      await tapKey(tester, 'event-color-#ff5a1f');
      await tapKey(tester, 'event-save');
      final e = events.items.single;
      expect(e.title, 'Dentista');
      expect(e.color, '#ff5a1f');
      expect(e.allDay, isFalse);
      expect(e.startsAt.toLocal(), DateTime(2026, 11, 6, 9));
      expect(find.text('Dentista'), findsOneWidget);
    });

    testWidgets('un evento de todo el día no guarda hora', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-add');
      await tapKey(tester, 'cal-add-event');
      await tester.enterText(find.byKey(const Key('event-title')), 'Cumpleaños');
      await tapKey(tester, 'event-allday');
      expect(find.byKey(const Key('event-start')), findsNothing);
      await tapKey(tester, 'event-save');
      final e = events.items.single;
      expect(e.allDay, isTrue);
      expect(e.startsAt.toLocal(), DateTime(2026, 11, 5));
    });

    testWidgets('en la vista Día, mantener el dedo en un hueco de la columna crea un evento a esa hora (al cuarto de hora)', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-mode-day');
      final box = tester.getRect(find.byKey(const Key('cal-timeline')));
      // la columna se abre una hora antes de la actual: arriba del todo son las 9:00, y cada hora mide 60 px
      await tester.longPressAt(Offset(box.left + 200, box.top + 100));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo evento'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('event-title')), 'Café');
      await tapKey(tester, 'event-save');
      final start = events.items.single.startsAt.toLocal();
      expect((start.year, start.month, start.day, start.hour), (2026, 11, 5, 10));
      expect(start.minute % 15, 0);
    });

    testWidgets('sin eventos ni tareas solo se ofrece lo demás', (tester) async {
      await open(tester, withTasks: false, withEvents: false);
      expect(find.byKey(const Key('cal-all-tasks')), findsNothing);
      await tapKey(tester, 'cal-add');
      expect(find.byKey(const Key('cal-add-event')), findsNothing);
      expect(find.byKey(const Key('cal-add-task')), findsNothing);
      expect(find.byKey(const Key('cal-add-habit')), findsOneWidget);
    });

    testWidgets('una tarea sin fecha no sale en ningún día', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-add');
      await tapKey(tester, 'cal-add-task');
      await tester.enterText(find.byKey(const Key('quick-task-name')), 'Algún día');
      await tapKey(tester, 'quick-task-dated');
      await tapKey(tester, 'quick-task-save');
      expect(tasks.roots().single.due, isNull);
      expect(find.text('Algún día'), findsNothing);
    });
  });

  group('tareas y hábitos', () {
    testWidgets('«Todas las tareas» abre la lista completa con sus filtros y su campo', (tester) async {
      await open(tester);
      await tester.scrollUntilVisible(find.byKey(const Key('cal-all-tasks')), 100, scrollable: find.descendant(of: find.byKey(const Key('cal-week')), matching: find.byType(Scrollable)));
      await tapKey(tester, 'cal-all-tasks');
      expect(find.byType(TasksView), findsOneWidget);
      await tester.enterText(find.byKey(const Key('task-input')), 'Desde el calendario');
      await tapKey(tester, 'task-add');
      expect(tasks.roots().single.name, 'Desde el calendario');
    });

    testWidgets('Hábitos: crear uno con sus días y su aviso, verlo en su día, editarlo y borrarlo', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-add');
      await tapKey(tester, 'cal-add-habit');
      await tapKey(tester, 'habit-save'); // sin nombre no guarda
      expect(find.text('Escribe el hábito.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('habit-name')), 'Correr');
      await tapKey(tester, 'habit-day-6'); // sin sábado ni domingo
      await tapKey(tester, 'habit-day-7');
      await tapKey(tester, 'habit-remind');
      await tapKey(tester, 'habit-save');
      final h = habits.habits.single;
      expect(h.weekdays, Habit.maskOf([1, 2, 3, 4, 5]));
      expect(h.remindAt, 8 * 60);
      expect(find.text('Correr'), findsNWidgets(2)); // jueves y viernes de esta semana (antes de crearlo no cuenta)
      expect(find.text('08:00'), findsNWidgets(2));
      expect(scheduler.weekly.length, 5); // un aviso por cada día que toca
      await tester.tap(find.text('Correr').first);
      await tester.pumpAndSettle();
      expect(find.text('Editar hábito'), findsOneWidget);
      await tapKey(tester, 'habit-delete');
      expect(habits.habits, isEmpty);
      expect(scheduler.weekly, isEmpty);
      expect(find.text('Correr'), findsNothing);
    });

    testWidgets('el nombre de los días del hábito', (tester) async {
      expect(habitDaysLabel(Habit.everyDay), 'Todos los días');
      expect(habitDaysLabel(Habit.maskOf([1, 2, 3, 4, 5])), 'Entre semana');
      expect(habitDaysLabel(Habit.maskOf([6, 7])), 'Fines de semana');
      expect(habitDaysLabel(Habit.maskOf([1, 3, 5])), 'L M V');
    });
  });
}

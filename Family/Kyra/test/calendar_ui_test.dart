import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/habit_store.dart';
import 'package:kyora_chat/data/reminder_store.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/models/habit.dart';
import 'package:kyora_chat/models/task.dart';
import 'package:kyora_chat/state/habit_controller.dart';
import 'package:kyora_chat/state/reminder_controller.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/agenda_view.dart';
import 'package:kyora_chat/ui/tasks_page.dart';
import 'package:kyora_chat/util/calendar_marks.dart';
import 'package:kyora_chat/ui/widgets/month_dial.dart';
import 'package:kyora_chat/ui/widgets/dot_matrix.dart';

import 'habit_test.dart' show FakeHabitBackend;
import 'reminders_test.dart' show FakeScheduler;
import 'task_controller_test.dart' show FakeTaskBackend;

void main() {
  // un jueves a media mañana
  final now = DateTime(2026, 11, 5, 10, 30);
  late TaskController tasks;
  late ReminderController reminders;
  late HabitController habits;
  late FakeScheduler scheduler;
  var n = 0;

  setUp(() {
    n = 0;
    scheduler = FakeScheduler();
    tasks = TaskController(MemoryTaskStore(), FakeTaskBackend(), now: () => now.toUtc(), newId: () => 't${++n}', retry: const Duration(hours: 1));
    reminders = ReminderController(MemoryReminderStore(), scheduler, now: () => now.toUtc(), newId: () => 'r${++n}');
    habits = HabitController(MemoryHabitStore(), FakeHabitBackend(), scheduler: scheduler, now: () => now.toUtc(), newId: () => 'h${++n}', retry: const Duration(hours: 1));
  });

  tearDown(() {
    tasks.dispose();
    reminders.dispose();
    habits.dispose();
  });

  Future<void> open(WidgetTester tester, {bool withTasks = true, bool withReminders = true, bool withHabits = true}) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tasks.start();
      await reminders.start();
      await habits.start();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: AgendaView(
        tasks: withTasks ? Future.value(tasks) : null,
        reminders: withReminders ? Future.value(reminders) : null,
        habits: withHabits ? Future.value(habits) : null,
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

  String dayNumber(WidgetTester tester) => tester.widget<DotMatrixText>(find.byKey(const Key('cal-day-number'))).text;

  /// Abre el mini calendario con su botón.
  Future<void> openDial(WidgetTester tester) => tapKey(tester, 'cal-open-month');

  /// Gira el anillo de los meses del dial `months` meses hacia delante (o hacia atrás, si es negativo), despacio.
  Future<void> turnMonths(WidgetTester tester, int months) async {
    final dial = tester.getRect(find.byKey(const Key('month-dial')));
    final width = dial.width;
    final start = Offset(MonthDial.monthRadius(width), dial.center.dy);
    await tester.timedDragFrom(start, Offset(0, -MonthDial.monthRadius(width) * MonthDial.monthStep * months), Duration(milliseconds: 1500 * months.abs()));
    await tester.pumpAndSettle();
  }

  /// Elige un día con el mini calendario: lo abre, gira hasta su mes si hace falta y lo toca.
  Future<void> pickDay(WidgetTester tester, DateTime day) async {
    if (find.byKey(const Key('month-dial')).evaluate().isEmpty) await openDial(tester);
    final months = (day.year * 12 + day.month) - (2026 * 12 + 11);
    if (months != 0) await turnMonths(tester, months);
    final key = Key('dial-day-${dialDayKey(day)}');
    if (find.byKey(key).evaluate().isEmpty) {
      // está lejos en el anillo: se gira hasta que asome
      final dial = tester.getRect(find.byKey(const Key('month-dial')));
      final step = MonthDial.dayRadius(dial.width) * MonthDial.dayStep;
      final focus = int.parse(tester.widget<DotMatrixText>(find.byKey(const Key('dial-focus-day'))).text);
      await tester.timedDragFrom(Offset(dial.width * 0.62, dial.center.dy), Offset(0, -step * (day.day - focus)), Duration(milliseconds: 600 * (day.day - focus).abs()));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  group('la consola', () {
    testWidgets('arriba, el día elegido en grande en matriz de puntos, la fecha y lo que hay ese día', (tester) async {
      await tester.runAsync(() async {
        await reminders.add('Llamar', DateTime(2026, 11, 5, 9).toUtc());
        await tasks.add('Informe', due: DateTime(2026, 11, 5, 18).toUtc());
        await tasks.add('Otro', due: DateTime(2026, 11, 5, 19).toUtc());
        await habits.add('Leer');
      });
      await open(tester);
      expect(dayNumber(tester), '05');
      expect(title(tester), 'HOY · Jue, 5 de noviembre 2026');
      expect(tester.widget<Text>(find.byKey(const Key('cal-summary'))).data, '> 2 tareas · 1 hábito · 1 recordatorio');
    });

    testWidgets('sin nada ese día, el resumen lo dice', (tester) async {
      await open(tester);
      expect(tester.widget<Text>(find.byKey(const Key('cal-summary'))).data, '> sin pendientes');
    });

    testWidgets('el anillo cuenta lo hecho del día sobre el total y se actualiza al marcar', (tester) async {
      late TaskItem task;
      await tester.runAsync(() async {
        await reminders.add('Llamar', DateTime(2026, 11, 5, 9).toUtc());
        task = (await tasks.add('Informe', due: DateTime(2026, 11, 5, 18).toUtc()))!;
      });
      await open(tester);
      String ring() => tester.widget<Text>(find.descendant(of: find.byKey(const Key('cal-ring')), matching: find.byType(Text))).data!;
      expect(ring(), '0/2');
      await tapKey(tester, 'cal-task-check-${task.id}');
      expect(ring(), '1/2');
    });

    testWidgets('sin nada ese día el anillo va vacío', (tester) async {
      await open(tester);
      expect(tester.widget<Text>(find.descendant(of: find.byKey(const Key('cal-ring')), matching: find.byType(Text))).data, '–');
    });

    testWidgets('la consola está arriba y los paneles debajo', (tester) async {
      await open(tester);
      expect(tester.getRect(find.byKey(const Key('cal-summary'))).bottom, lessThan(tester.getRect(find.byKey(const Key('cal-panels'))).top));
    });
  });

  group('los paneles', () {
    testWidgets('deslizando a un lado se pasa de Hoy a Hábitos y luego a Recordatorios; y se vuelve', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('cal-day')), findsOneWidget);
      await tester.fling(find.byKey(const Key('cal-panels')), const Offset(-300, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('habits-empty')), findsOneWidget);
      expect(find.text('[HÁBITOS]'), findsOneWidget);
      await tester.fling(find.byKey(const Key('cal-panels')), const Offset(-300, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-reminders')), findsOneWidget);
      expect(find.text('[RECORDATORIOS]'), findsOneWidget);
      await tester.fling(find.byKey(const Key('cal-panels')), const Offset(600, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-day')), findsOneWidget);
    });

    testWidgets('las etiquetas de arriba llevan a cada panel', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-tab-reminders');
      expect(find.byKey(const Key('cal-reminders')), findsOneWidget);
      await tapKey(tester, 'cal-tab-day');
      expect(find.byKey(const Key('cal-day')), findsOneWidget);
    });

    testWidgets('Recordatorios: todos, los pendientes por fecha y luego los hechos; se marcan ahí mismo', (tester) async {
      await tester.runAsync(() async {
        await reminders.add('Mañana', DateTime(2026, 11, 6, 9).toUtc());
        await reminders.add('Hoy', DateTime(2026, 11, 5, 16).toUtc());
      });
      await open(tester);
      await tapKey(tester, 'cal-tab-reminders');
      final today = tester.getTopLeft(find.text('Hoy')).dy;
      final tomorrow = tester.getTopLeft(find.text('Mañana')).dy;
      expect(today, lessThan(tomorrow));
      final first = reminders.items.firstWhere((r) => r.title == 'Hoy');
      await tapKey(tester, 'rem-check-${first.id}');
      expect(reminders.items.firstWhere((r) => r.title == 'Hoy').done, isTrue);
      expect(find.text('HECHOS'), findsOneWidget);
    });

    testWidgets('sin recordatorios lo dice', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-tab-reminders');
      expect(find.byKey(const Key('reminders-empty')), findsOneWidget);
    });

    testWidgets('sin hábitos ni avisos solo queda el panel de Hoy, sin etiquetas', (tester) async {
      await open(tester, withHabits: false, withReminders: false);
      expect(find.byKey(const Key('cal-tab-day')), findsNothing);
      expect(find.byKey(const Key('cal-day')), findsOneWidget);
    });
  });

  group('el mini calendario', () {
    Future<void> pinch(WidgetTester tester, {required bool inward}) async {
      final panels = tester.getRect(find.byKey(const Key('cal-panels')));
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
      await openDial(tester);
      final dial = tester.getRect(find.byKey(const Key('month-dial')));
      final step = MonthDial.dayRadius(dial.width) * MonthDial.dayStep;
      await tester.timedDragFrom(Offset(dial.width * 0.62, dial.center.dy), Offset(0, -step * 3), const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.widget<DotMatrixText>(find.byKey(const Key('dial-focus-day'))).text, '08');
      await tapKey(tester, 'dial-hub');
      expect(find.byKey(const Key('month-dial')), findsNothing);
      expect(dayNumber(tester), '08');
      expect(title(tester), 'Dom, 8 de noviembre 2026');
    });

    testWidgets('girar el anillo de los meses pasa de mes; tocar un día lo elige', (tester) async {
      await open(tester);
      await openDial(tester);
      await turnMonths(tester, 1);
      expect(tester.widget<DotMatrixText>(find.byKey(const Key('dial-focus-month'))).text, 'DIC');
      await tapKey(tester, 'dial-day-2026-12-05');
      expect(title(tester), 'Sáb, 5 de diciembre 2026');
    });

    testWidgets('tocar fuera o «atrás» lo cierra sin cambiar de día', (tester) async {
      await open(tester);
      await openDial(tester);
      await tester.tapAt(const Offset(390, 60));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('month-dial')), findsNothing);
      expect(dayNumber(tester), '05');
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

  group('Día', () {
    testWidgets('reúne lo del día: recordatorios, tareas que vencen y hábitos que tocan', (tester) async {
      late TaskItem task;
      late Habit habit;
      await tester.runAsync(() async {
        await reminders.add('Tomar la medicina', DateTime(2026, 11, 5, 14).toUtc());
        task = (await tasks.add('Entregar el informe', due: DateTime(2026, 11, 5, 18).toUtc()))!;
        await tasks.add('Otro día', due: DateTime(2026, 11, 9, 18).toUtc());
        habit = (await habits.add('Leer'))!;
      });
      await open(tester);
      expect(find.text('Tomar la medicina'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('Entregar el informe'), findsOneWidget);
      expect(find.text('Otro día'), findsNothing);
      expect(find.text('Leer'), findsOneWidget);
      await tapKey(tester, 'cal-task-check-${task.id}');
      expect(tasks.byId(task.id)!.isDone, isTrue);
      await tapKey(tester, 'cal-habit-check-${habit.id}');
      expect(habits.isDone(habit, now), isTrue);
    });

    testWidgets('hoy también enseña lo vencido de otros días, con su día corto; otro día, no', (tester) async {
      await tester.runAsync(() => tasks.add('Pagar', due: DateTime(2026, 11, 3, 18).toUtc()));
      await open(tester);
      expect(find.text('Pagar'), findsOneWidget);
      expect(find.text('3 nov'), findsOneWidget);
      await pickDay(tester, DateTime(2026, 11, 4));
      expect(find.text('Pagar'), findsNothing);
    });

    testWidgets('un día que todavía no llega enseña sus hábitos, pero no se pueden marcar', (tester) async {
      late Habit habit;
      await tester.runAsync(() async => habit = (await habits.add('Leer'))!);
      await open(tester);
      await pickDay(tester, DateTime(2026, 11, 7));
      expect(find.text('Leer'), findsOneWidget);
      await tapKey(tester, 'cal-habit-check-${habit.id}');
      expect(habits.isDone(habit, DateTime(2026, 11, 7, 12)), isFalse);
    });

    testWidgets('sin nada ese día lo dice', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('cal-day-empty')), findsOneWidget);
    });
  });

  group('el «+»', () {
    testWidgets('ofrece tarea, recordatorio y hábito; la tarea nace con el día elegido', (tester) async {
      await open(tester);
      await pickDay(tester, DateTime(2026, 11, 7));
      await tapKey(tester, 'cal-add');
      expect(find.byKey(const Key('cal-add-task')), findsOneWidget);
      expect(find.byKey(const Key('cal-add-reminder')), findsOneWidget);
      expect(find.byKey(const Key('cal-add-habit')), findsOneWidget);
      await tapKey(tester, 'cal-add-task');
      await tapKey(tester, 'quick-task-save'); // sin nombre no guarda
      expect(find.text('Escribe la tarea.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('quick-task-name')), 'Comprar pan');
      await tapKey(tester, 'quick-task-save');
      final due = tasks.roots().single.due!.toLocal();
      expect((due.year, due.month, due.day, due.hour), (2026, 11, 7, 18));
      expect(find.text('Comprar pan'), findsOneWidget); // sale en el día elegido
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

    testWidgets('sin tareas no hay acceso a la lista de tareas ni se ofrece crearlas', (tester) async {
      await open(tester, withTasks: false);
      expect(find.byKey(const Key('cal-all-tasks')), findsNothing);
      await tapKey(tester, 'cal-add');
      expect(find.byKey(const Key('cal-add-task')), findsNothing);
      expect(find.byKey(const Key('cal-add-habit')), findsOneWidget);
    });
  });

  group('tareas y hábitos', () {
    testWidgets('«Todas las tareas» abre la lista completa con sus filtros y su campo', (tester) async {
      await open(tester);
      await tester.scrollUntilVisible(find.byKey(const Key('cal-all-tasks')), 100, scrollable: find.descendant(of: find.byKey(const Key('cal-day')), matching: find.byType(Scrollable)));
      await tapKey(tester, 'cal-all-tasks');
      expect(find.byType(TasksView), findsOneWidget);
      await tester.enterText(find.byKey(const Key('task-input')), 'Desde el calendario');
      await tapKey(tester, 'task-add');
      expect(tasks.roots().single.name, 'Desde el calendario');
    });

    testWidgets('Hábitos: crear uno con sus días y su aviso, verlo en la lista, editarlo y borrarlo', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-tab-habits');
      expect(find.byKey(const Key('habits-empty')), findsOneWidget);
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
      expect(find.text('Correr'), findsOneWidget);
      expect(find.text('Entre semana · 08:00'), findsOneWidget);
      expect(scheduler.weekly.length, 5); // un aviso por cada día que toca
      await tester.tap(find.text('Correr')); // en el nombre: a la derecha están las casillas de la semana
      await tester.pumpAndSettle();
      expect(find.text('Editar hábito'), findsOneWidget);
      await tapKey(tester, 'habit-delete');
      expect(habits.habits, isEmpty);
      expect(scheduler.weekly, isEmpty);
      expect(find.byKey(const Key('habits-empty')), findsOneWidget);
    });

    testWidgets('Hábitos: las casillas de la semana marcan días pasados que tocaban, no los que no tocan ni los futuros', (tester) async {
      late Habit h;
      await tester.runAsync(() async => h = (await habits.add('Leer', weekdays: Habit.maskOf([2, 4, 6])))!);
      await open(tester);
      await tapKey(tester, 'cal-tab-habits');
      await tapKey(tester, 'habit-cell-${h.id}-2026-11-05'); // jueves: toca y ya llegó
      expect(habits.isDone(h, DateTime(2026, 11, 5, 12)), isTrue);
      await tapKey(tester, 'habit-cell-${h.id}-2026-11-04'); // miércoles: no toca
      expect(habits.isDone(h, DateTime(2026, 11, 4, 12)), isFalse);
      await tapKey(tester, 'habit-cell-${h.id}-2026-11-07'); // sábado: todavía no llega
      expect(habits.isDone(h, DateTime(2026, 11, 7, 12)), isFalse);
    });

    testWidgets('el nombre de los días del hábito', (tester) async {
      expect(habitDaysLabel(Habit.everyDay), 'Todos los días');
      expect(habitDaysLabel(Habit.maskOf([1, 2, 3, 4, 5])), 'Entre semana');
      expect(habitDaysLabel(Habit.maskOf([6, 7])), 'Fines de semana');
      expect(habitDaysLabel(Habit.maskOf([1, 3, 5])), 'L M V');
    });
  });
}

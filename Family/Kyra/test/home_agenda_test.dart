import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/calendar_view_store.dart';
import 'package:kyora_chat/data/habit_store.dart';
import 'package:kyora_chat/data/reminder_store.dart';
import 'package:kyora_chat/data/system_info.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/models/habit.dart';
import 'package:kyora_chat/state/habit_controller.dart';
import 'package:kyora_chat/state/reminder_controller.dart';
import 'package:kyora_chat/state/system_controller.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/state/weather_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/home_page.dart';
import 'package:kyora_chat/util/agenda.dart';
import 'package:kyora_chat/ui/widgets/cyber_panel.dart';

import 'habit_test.dart' show FakeHabitBackend;
import 'reminders_test.dart' show FakeScheduler;
import 'task_controller_test.dart' show FakeTaskBackend;
import 'weather_test.dart' show FakeWeather;

/// La hora de Inicio abre la agenda a pantalla completa (antes era la sección «Calendario»).
void main() {
  // un jueves a media mañana
  final now = DateTime(2026, 11, 5, 10, 30);
  late TaskController tasks;
  late ReminderController reminders;
  late HabitController habits;
  late WeatherController weather;
  late SystemController system;
  late FakeScheduler scheduler;
  var n = 0;

  setUp(() {
    n = 0;
    scheduler = FakeScheduler();
    tasks = TaskController(MemoryTaskStore(), FakeTaskBackend(), now: () => now.toUtc(), newId: () => 't${++n}', retry: const Duration(hours: 1));
    reminders = ReminderController(MemoryReminderStore(), scheduler, now: () => now.toUtc(), newId: () => 'r${++n}');
    habits = HabitController(MemoryHabitStore(), FakeHabitBackend(), scheduler: scheduler, now: () => now.toUtc(), newId: () => 'h${++n}', retry: const Duration(hours: 1));
    weather = WeatherController(FakeWeather(), MemoryWeatherStore());
    system = SystemController(
      FakeSystemInfo(const SystemStats(battery: 82, charging: true, ramTotal: 8000, ramFree: 2000, storageTotal: 128 * 1024 * 1024 * 1024, storageFree: 40 * 1024 * 1024 * 1024, wifi: true, bluetooth: false)),
      every: const Duration(hours: 1),
    );
  });

  tearDown(() {
    tasks.dispose();
    reminders.dispose();
    habits.dispose();
    weather.dispose();
    system.dispose();
  });

  Future<void> open(WidgetTester tester, {Size size = const Size(400, 850), bool agenda = true, Future<void> Function()? seed, CalendarViewStore? calendarView}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tasks.start();
      await reminders.start();
      await habits.start();
      await seed?.call();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: HomePage(
        key: UniqueKey(),
        onOpenSettings: () {},
        weather: weather,
        system: system,
        now: () => now,
        tasks: agenda ? Future.value(tasks) : null,
        reminders: agenda ? Future.value(reminders) : null,
        habits: agenda ? Future.value(habits) : null,
        calendarView: calendarView,
      ),
    ));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('home-time-tile')));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  group('la hora expandible', () {
    testWidgets('al tocar la hora el tablero se disuelve y la agenda ocupa la pantalla, sin marco, con las tareas de hoy', (tester) async {
      await open(tester, seed: () async {
        await tasks.add('Informe', due: DateTime(2026, 11, 5, 18).toUtc());
      });
      expect(find.byKey(const Key('cal-week')), findsNothing); // cerrada: solo la hora
      expect(find.byKey(const Key('home-weather')), findsOneWidget);

      await expand(tester);
      expect(find.byKey(const Key('cal-week')), findsOneWidget);
      expect(find.text('Informe'), findsOneWidget);
      expect(find.byKey(const Key('home-time-small')), findsOneWidget);
      // el resto del tablero ya no está: ni las teselas ni los accesos
      for (final key in ['home-grid', 'home-weather', 'home-system', 'home-quick', 'home-time']) {
        expect(find.byKey(Key(key)), findsNothing, reason: key);
      }
      // y la agenda no va dentro de ningún panel con marco
      expect(find.ancestor(of: find.byKey(const Key('cal-week')), matching: find.byType(CyberPanel)), findsNothing);
      // ocupa todo el ancho de la pantalla (menos un margen)
      expect(tester.getRect(find.byKey(const Key('cal-week'))).width, greaterThan(360));
    });

    testWidgets('mientras el tablero se rompe sigue ahí un instante y después entra la agenda', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('home-time-tile')));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byKey(const Key('home-grid')), findsOneWidget);
      expect(find.byKey(const Key('cal-week')), findsNothing);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-grid')), findsNothing);
      expect(find.byKey(const Key('cal-week')), findsOneWidget);
    });

    testWidgets('con el pellizco se pasa a Mes, y la agenda enseña lo del día elegido', (tester) async {
      await open(tester, seed: () async {
        await habits.add('Leer', weekdays: Habit.maskOf([4]));
        await reminders.add('Llamar', DateTime(2026, 11, 5, 9).toUtc());
      });
      await expand(tester);
      expect(find.text('Llamar'), findsOneWidget);
      final center = tester.getCenter(find.byKey(const Key('cal-week')));
      final a = await tester.startGesture(center + const Offset(-80, 0), pointer: 21);
      final b = await tester.startGesture(center + const Offset(80, 0), pointer: 22);
      await a.moveTo(center + const Offset(-30, 0));
      await b.moveTo(center + const Offset(30, 0));
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-cell-2026-11-05')), findsOneWidget);
      expect(find.byKey(const Key('cal-day')), findsOneWidget);
      // el mes ocupa la pantalla: las tarjetas del día están debajo de la cuadrícula
      await tester.scrollUntilVisible(find.text('Llamar'), 200, scrollable: find.descendant(of: find.byKey(const Key('cal-day')), matching: find.byType(Scrollable)).first);
      expect(find.text('Llamar'), findsOneWidget);
      expect(find.byKey(const Key('cal-mode-day')), findsNothing);
    });

    testWidgets('abre con la semana por defecto', (tester) async {
      await open(tester);
      await expand(tester);
      expect(find.byKey(const Key('cal-week')), findsOneWidget);
      expect(find.byKey(const Key('cal-month-day')), findsNothing);
    });

    testWidgets('con el mes elegido en Configuración, la agenda se abre en el mes', (tester) async {
      await open(tester, calendarView: MemoryCalendarViewStore(CalendarMode.month));
      await expand(tester);
      expect(find.byKey(const Key('cal-month-day')), findsOneWidget);
      expect(find.byKey(const Key('cal-week')), findsNothing);
    });

    testWidgets('desde ahí se puede hacer lo del calendario: crear una tarea', (tester) async {
      await open(tester);
      await expand(tester);
      await tester.tap(find.byKey(const Key('cal-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cal-add-task')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('quick-task-name')), 'Comprar pan');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar').first);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(tasks.roots().map((t) => t.name), ['Comprar pan']);
      expect(find.text('Comprar pan'), findsOneWidget);
    });

    testWidgets('«atrás» la cierra; ya no hay botón de contraer', (tester) async {
      await open(tester);
      await expand(tester);
      expect(find.byKey(const Key('home-time-close')), findsNothing);
      expect(find.byKey(const Key('cal-refresh')), findsOneWidget); // en su lugar, Actualizar y «+» en la esquina
      expect(find.byKey(const Key('cal-add')), findsOneWidget);
      await tester.binding.handlePopRoute(); // «atrás» contrae la hora
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-week')), findsNothing);
      expect(find.byKey(const Key('home-weather')), findsOneWidget);
    });

    testWidgets('en una pantalla pequeña también cabe, sin desbordarse', (tester) async {
      await open(tester, size: const Size(320, 560));
      await expand(tester);
      expect(find.byKey(const Key('cal-week')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin tareas, hábitos ni recordatorios la hora no se puede expandir', (tester) async {
      await open(tester, agenda: false);
      expect(find.byKey(const Key('home-time-tile')), findsNothing);
      await tester.tap(find.byKey(const Key('home-time')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-week')), findsNothing);
    });
  });
}

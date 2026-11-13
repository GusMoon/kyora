import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/habit_store.dart';
import 'package:kyora_chat/data/reminder_store.dart';
import 'package:kyora_chat/data/system_info.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/data/weather_store.dart';
import 'package:kyora_chat/state/habit_controller.dart';
import 'package:kyora_chat/state/reminder_controller.dart';
import 'package:kyora_chat/state/system_controller.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/state/weather_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/home_page.dart';
import 'package:kyora_chat/ui/widgets/home_grid.dart';

import 'habit_test.dart' show FakeHabitBackend;
import 'reminders_test.dart' show FakeScheduler;
import 'task_controller_test.dart' show FakeTaskBackend;
import 'weather_test.dart' show FakeWeather;

/// La hora de Inicio se expande y ahí vive la agenda (antes era la sección «Calendario»).
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

  Future<void> open(WidgetTester tester, {Size size = const Size(400, 850), bool agenda = true, Future<void> Function()? seed}) async {
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
    testWidgets('al tocar la hora se expande y enseña las tareas de hoy (y el resto del tablero queda en una franja)', (tester) async {
      await open(tester, seed: () async {
        await tasks.add('Informe', due: DateTime(2026, 11, 5, 18).toUtc());
      });
      final collapsed = tester.getRect(find.byKey(const Key('home-grid')));
      expect(find.byKey(const Key('cal-panels')), findsNothing); // cerrada: solo la hora
      expect(find.byKey(const Key('home-weather')), findsOneWidget);

      await expand(tester);
      expect(find.byKey(const Key('cal-panels')), findsOneWidget);
      expect(find.byKey(const Key('cal-day')), findsOneWidget); // empieza en Hoy: las tareas
      expect(find.text('Informe'), findsOneWidget);
      expect(find.byKey(const Key('home-time-small')), findsOneWidget);
      // las otras tres teselas siguen ahí, en su versión compacta, debajo de la agenda
      for (final key in ['home-weather-compact', 'home-system-compact', 'home-quick-compact']) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.byKey(const Key('home-weather')), findsNothing);
      final agendaBottom = tester.getRect(find.byKey(const Key('home-time-close'))).bottom;
      expect(tester.getRect(find.byKey(const Key('home-quick-compact'))).top, greaterThan(agendaBottom));
      expect(tester.getRect(find.byKey(const Key('home-grid'))).height, greaterThan(collapsed.height)); // el tablero creció hasta la pantalla
    });

    testWidgets('deslizando se pasa a los hábitos y a los recordatorios', (tester) async {
      await open(tester, seed: () async {
        await habits.add('Leer');
        await reminders.add('Llamar', DateTime(2026, 11, 5, 9).toUtc());
      });
      await expand(tester);
      await tester.drag(find.byKey(const Key('cal-panels')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('habit-list')), findsOneWidget);
      await tester.drag(find.byKey(const Key('cal-panels')), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-reminders')), findsOneWidget);
      expect(find.text('Llamar'), findsOneWidget);
    });

    testWidgets('desde ahí se puede hacer lo del calendario: crear y completar una tarea, y abrir el mini calendario', (tester) async {
      await open(tester);
      await expand(tester);
      await tester.tap(find.byKey(const Key('cal-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cal-add-task')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Comprar pan');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar').first);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(tasks.roots().map((t) => t.name), ['Comprar pan']);
      expect(find.text('Comprar pan'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cal-open-month')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('month-dial')), findsOneWidget);
    });

    testWidgets('el botón de contraer y «atrás» la cierran; «atrás» cierra antes el mini calendario', (tester) async {
      await open(tester);
      await expand(tester);
      await tester.tap(find.byKey(const Key('home-time-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-panels')), findsNothing);
      expect(find.byKey(const Key('home-weather')), findsOneWidget); // la cuadrícula vuelve

      await expand(tester);
      await tester.tap(find.byKey(const Key('cal-open-month')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute(); // 1.º: cierra el mini calendario
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('month-dial')), findsNothing);
      expect(find.byKey(const Key('cal-panels')), findsOneWidget);
      await tester.binding.handlePopRoute(); // 2.º: contrae la hora
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-panels')), findsNothing);
    });

    testWidgets('en una pantalla pequeña también cabe, sin desbordarse', (tester) async {
      await open(tester, size: const Size(320, 560));
      await expand(tester);
      expect(find.byKey(const Key('cal-panels')), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(const Key('home-grid'))).height, greaterThanOrEqualTo(HomeGrid.minExpandedHeight));
    });

    testWidgets('sin tareas, hábitos ni recordatorios la hora no se puede expandir', (tester) async {
      await open(tester, agenda: false);
      expect(find.byKey(const Key('home-time-tile')), findsNothing);
      await tester.tap(find.byKey(const Key('home-time')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cal-panels')), findsNothing);
    });
  });
}

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
import 'package:kyora_chat/ui/calendar_views.dart' show CellState, cellStateOf;
import 'package:kyora_chat/util/agenda.dart';
import 'package:kyora_chat/ui/widgets/dot_matrix.dart';
import 'package:kyora_chat/ui/widgets/section_motion.dart';

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

  Future<void> open(WidgetTester tester, {bool withTasks = true, bool withReminders = true, bool withHabits = true, bool withEvents = true, CalendarMode mode = CalendarMode.week}) async {
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
        initialMode: mode,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  /// Un pellizco con dos dedos: juntándolos (`inward`, «minimizar») pasa de la semana al mes; separándolos, del mes a la semana.
  Future<void> pinch(WidgetTester tester, {required bool inward}) async {
    final center = tester.getCenter(find.byType(AgendaView));
    final a = await tester.startGesture(center + const Offset(-80, 0), pointer: 11);
    final b = await tester.startGesture(center + const Offset(80, 0), pointer: 12);
    await a.moveTo(center + Offset(inward ? -30 : -140, 0));
    await b.moveTo(center + Offset(inward ? 30 : 140, 0));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
  }

  String title(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('cal-title'))).data!;

  group('las vistas', () {
    testWidgets('al abrir es la semana: el título es su rango, no hay selector de vista y los siete días están apilados', (tester) async {
      await open(tester);
      expect(title(tester), '2 – 8 nov 2026');
      expect(find.byKey(const Key('cal-week')), findsOneWidget);
      // ya no hay selector Semana/Mes, ni vista Día, ni el mini calendario circular
      for (final m in ['week', 'month', 'day']) {
        expect(find.byKey(Key('cal-mode-$m')), findsNothing);
      }
      expect(find.byKey(const Key('cal-open-month')), findsNothing);
      // al abrir, el día de hoy sube hasta arriba; se vuelve al principio para ver los siete
      await tester.drag(find.byKey(const Key('cal-week')), const Offset(0, 800));
      await tester.pumpAndSettle();
      for (var d = 2; d <= 8; d++) {
        expect(find.byKey(Key('cal-week-day-2026-11-0$d')), findsOneWidget, reason: 'día $d');
      }
      final names = [for (var d = 2; d <= 8; d++) tester.widget<Text>(find.descendant(of: find.byKey(Key('cal-week-day-2026-11-0$d')), matching: find.byType(Text)).first).data];
      expect(names, ['LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES', 'SÁBADO', 'DOMINGO']);
    });

    testWidgets('Semana: solo el día elegido está abierto (con su fecha y hora); tocar otro lo abre y cierra el anterior', (tester) async {
      await tester.runAsync(() async {
        await reminders.add('De hoy', DateTime(2026, 11, 5, 9).toUtc());
        await reminders.add('Del sábado', DateTime(2026, 11, 7, 9).toUtc());
      });
      await open(tester);
      expect(find.text('Noviembre 5, 2026 · 10:30'), findsOneWidget); // hoy, con la hora de ahora
      expect(find.text('De hoy'), findsOneWidget);
      expect(find.text('Del sábado'), findsNothing); // su día está cerrado
      expect(find.byKey(const Key('cal-week-count-2026-11-07')), findsOneWidget); // pero dice cuántas cosas tiene
      await tapKey(tester, 'cal-week-day-2026-11-07');
      expect(find.text('Del sábado'), findsOneWidget);
      expect(find.text('De hoy'), findsNothing);
      expect(find.text('Noviembre 7, 2026'), findsOneWidget); // otro día: sin hora
      expect(find.text('Noviembre 5, 2026 · 10:30'), findsNothing);
      // el día abierto se ve con el nombre más fuerte
      TextStyle styleOf(String key) => tester.widget<Text>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text)).first).style!;
      expect(styleOf('cal-week-day-2026-11-07').fontWeight, FontWeight.w800);
      expect(styleOf('cal-week-day-2026-11-05').fontWeight, FontWeight.w700);
    });

    testWidgets('Semana: las bandas de los días cerrados se oscurecen de arriba a abajo', (tester) async {
      await open(tester);
      Color bandOf(String day) => ((tester.widget<DecoratedBox>(find.ancestor(of: find.byKey(Key('cal-week-day-$day')), matching: find.byType(DecoratedBox)).first)).decoration as BoxDecoration).color!;
      final friday = bandOf('2026-11-06');
      final sunday = bandOf('2026-11-08');
      expect(sunday.computeLuminance(), lessThan(friday.computeLuminance()));
    });

    testWidgets('Mes: el número grande del día elegido, el mes y el año, y seis semanas de cuadros sueltos', (tester) async {
      await tester.runAsync(() async {
        await reminders.add('Llamar', DateTime(2026, 11, 12, 9).toUtc());
      });
      await open(tester);
      await pinch(tester, inward: true);
      expect(title(tester), 'Noviembre 2026');
      // la cabecera: el 5 grande en puntos cuadrados, NOVIEMBRE 2026 y Jue
      final big = tester.widget<DotMatrixText>(find.byKey(const Key('cal-month-day')));
      expect(big.text, '5');
      expect(big.square, isTrue);
      expect(tester.widget<Text>(find.byKey(const Key('cal-month-name'))).data, 'NOVIEMBRE');
      expect(find.text('2026'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('cal-month-weekday'))).data, 'Jue');
      // las letras de la semana (la de hoy, jueves, en acento)
      final accent = tester.element(find.byKey(const Key('cal-letter-3'))).colors.accent;
      expect(tester.widget<Text>(find.byKey(const Key('cal-letter-3'))).style!.color, accent);
      expect(tester.widget<Text>(find.byKey(const Key('cal-letter-0'))).style!.color, isNot(accent));
      // 42 cuadros: la rejilla empieza el lunes anterior al 1 y acaba el domingo de la sexta semana
      expect(find.byKey(const Key('cal-cell-2026-10-26')), findsOneWidget);
      expect(find.byKey(const Key('cal-cell-2026-12-06')), findsOneWidget);
      expect(find.text('1 nov'), findsOneWidget);
      // cuadros (no círculos) con un pequeño margen entre un día y el siguiente
      final a = tester.getRect(find.byKey(const Key('cal-cell-2026-11-04')));
      final b = tester.getRect(find.byKey(const Key('cal-cell-2026-11-05')));
      expect(b.left - a.right, closeTo(3, 0.5));
      expect(a.height, greaterThanOrEqualTo(44));
      final decoration = tester.widget<Container>(find.descendant(of: find.byKey(const Key('cal-cell-2026-11-05')), matching: find.byType(Container)).first).decoration as BoxDecoration?;
      expect(decoration?.shape ?? BoxShape.rectangle, BoxShape.rectangle);
      expect(decoration?.borderRadius, isNull);
      // tocar un día lo elige: cambia el número grande y enseña lo suyo debajo
      expect(find.text('Llamar'), findsNothing); // es del 12
      await tapKey(tester, 'cal-cell-2026-11-12');
      expect(tester.widget<DotMatrixText>(find.byKey(const Key('cal-month-day'))).text, '12');
      expect(tester.widget<Text>(find.byKey(const Key('cal-month-weekday'))).data, 'Jue');
      expect(find.text('Llamar'), findsOneWidget);
      expect(find.byKey(const Key('cal-day')), findsOneWidget);
    });

    testWidgets('arriba solo queda ‹ título › y «Hoy», y en la esquina Actualizar y «+»; sin la fila de antes', (tester) async {
      await open(tester);
      final title = tester.getRect(find.byKey(const Key('cal-title')));
      final refresh = tester.getRect(find.byKey(const Key('cal-refresh')));
      final add = tester.getRect(find.byKey(const Key('cal-add')));
      final screen = tester.getRect(find.byType(Scaffold));
      // todo en una sola fila, con Actualizar y «+» al final (a la derecha)
      expect(refresh.center.dy, closeTo(title.center.dy, 4));
      expect(add.center.dy, closeTo(title.center.dy, 4));
      expect(refresh.left, greaterThan(title.right));
      expect(add.left, greaterThan(refresh.right));
      expect(screen.right - add.right, lessThan(16));
      // y el contenido empieza justo debajo: no hay otra fila de botones
      expect(tester.getRect(find.byKey(const Key('cal-week-day-2026-11-02'))).top, lessThan(add.bottom + 24));
    });

    testWidgets('el pellizco cambia de vista: juntar los dedos pasa de la semana al mes; separarlos, del mes a la semana', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('cal-week')), findsOneWidget);
      await pinch(tester, inward: false); // en la semana, separar no hace nada
      expect(find.byKey(const Key('cal-week')), findsOneWidget);
      await pinch(tester, inward: true);
      expect(find.byKey(const Key('cal-week')), findsNothing);
      expect(find.byKey(const Key('cal-cell-2026-11-05')), findsOneWidget);
      await pinch(tester, inward: true); // en el mes, juntar no hace nada
      expect(find.byKey(const Key('cal-cell-2026-11-05')), findsOneWidget);
      await pinch(tester, inward: false);
      expect(find.byKey(const Key('cal-week')), findsOneWidget);
    });

    testWidgets('Semana: las bandas ocupan todo el ancho y son de cristal oscuro con el acento (se ve el fondo), no grises', (tester) async {
      await open(tester);
      final screen = tester.getRect(find.byType(Scaffold));
      final c = tester.element(find.byKey(const Key('cal-week'))).colors;
      for (final day in ['2026-11-02', '2026-11-03', '2026-11-08']) {
        final band = find.ancestor(of: find.byKey(Key('cal-week-day-$day')), matching: find.byType(DecoratedBox)).first;
        final rect = tester.getRect(band);
        expect(rect.left, closeTo(screen.left, 0.5), reason: day);
        expect(rect.right, closeTo(screen.right, 0.5), reason: day);
        final color = (tester.widget<DecoratedBox>(band).decoration as BoxDecoration).color!;
        expect(color.a, lessThan(1), reason: '$day: translúcida, deja ver el fondo');
        expect(color, isNot(c.pick), reason: day);
        expect(color, isNot(c.field), reason: day);
      }
      // el panel del día abierto también va de borde a borde
      final openDay = tester.getRect(find.byKey(const Key('cal-week-date-2026-11-05')));
      expect(openDay.left, lessThan(40));
    });

    testWidgets('Semana: la columna de los días llega hasta abajo de la pantalla (las bandas cerradas se estiran)', (tester) async {
      await open(tester);
      final screen = tester.getRect(find.byType(Scaffold));
      final sunday = tester.getRect(find.byKey(const Key('cal-week-day-2026-11-08')));
      expect(sunday.bottom, closeTo(screen.bottom, 1)); // el domingo, la última, acaba en el borde de abajo
      // sin hueco entre bandas: cada una empieza donde acaba la anterior
      final monday = tester.getRect(find.byKey(const Key('cal-week-day-2026-11-02')));
      final tuesday = tester.getRect(find.byKey(const Key('cal-week-day-2026-11-03')));
      expect(tuesday.top, closeTo(monday.bottom, 1));
      // y las cerradas son más altas que antes (reparten el resto del alto)
      expect(monday.height, greaterThan(74));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Semana: abrir otro día no deja un hueco abajo: la columna sigue llegando al borde', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-week-day-2026-11-07');
      final screen = tester.getRect(find.byType(Scaffold));
      final bottom = tester.getRect(find.byKey(const Key('cal-week-day-2026-11-08'))).bottom;
      expect(bottom, closeTo(screen.bottom, 1));
    });

    testWidgets('al cambiar de vista con el pellizco, el cuerpo se materializa con el efecto de holograma (y acaba nítido)', (tester) async {
      await open(tester);
      final center = tester.getCenter(find.byType(AgendaView));
      final a = await tester.startGesture(center + const Offset(-80, 0), pointer: 31);
      final b = await tester.startGesture(center + const Offset(80, 0), pointer: 32);
      await a.moveTo(center + const Offset(-30, 0));
      await b.moveTo(center + const Offset(30, 0));
      await a.up();
      await b.up();
      await tester.pump(); // arranca el holograma
      await tester.pump(const Duration(milliseconds: 60));
      final reveal = find.descendant(of: find.byType(AgendaView), matching: find.byType(HologramReveal));
      expect(reveal, findsOneWidget);
      double opacity() => tester.widget<Opacity>(find.descendant(of: reveal, matching: find.byType(Opacity)).first).opacity;
      expect(opacity(), lessThan(1)); // a medias: parpadeando
      await tester.pumpAndSettle();
      expect(opacity(), 1); // al final, nítido
      expect(find.byKey(const Key('cal-cell-2026-11-05')), findsOneWidget);
    });

    testWidgets('Semana: las bandas tienen líneas de barrido y una marca a la izquierda', (tester) async {
      await open(tester);
      final band = find.ancestor(of: find.byKey(const Key('cal-week-day-2026-11-02')), matching: find.byType(CustomPaint));
      expect(band, findsWidgets);
      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == '_BandPainter'), findsWidgets);
    });

    testWidgets('Mes: la cuadrícula llena la pantalla (no queda un hueco) y las tarjetas del día salen debajo, a la vista', (tester) async {
      await tester.runAsync(() => reminders.add('Llamar', DateTime(2026, 11, 5, 9).toUtc()));
      await open(tester, mode: CalendarMode.month);
      final screen = tester.getRect(find.byType(Scaffold));
      final lastRow = tester.getRect(find.byKey(const Key('cal-cell-2026-12-06')));
      final firstRow = tester.getRect(find.byKey(const Key('cal-cell-2026-10-26')));
      expect(lastRow.bottom, greaterThan(screen.top + screen.height * 0.6)); // la rejilla baja hasta más de la mitad
      expect(lastRow.height, greaterThan(firstRow.width * 0.8)); // y las filas son altas, casi cuadros
      expect(tester.getRect(find.text('Llamar')).bottom, lessThan(screen.bottom)); // lo del día se ve sin deslizar
      expect(find.byKey(const Key('cal-all-tasks')), findsNothing);
    });

    testWidgets('Mes: la cabecera dice cuánto falta para el día elegido', (tester) async {
      await open(tester, mode: CalendarMode.month);
      String tag() => tester.widget<Text>(find.descendant(of: find.byKey(const Key('cal-month-relative')), matching: find.byType(Text))).data!;
      expect(tag(), 'HOY');
      await tapKey(tester, 'cal-cell-2026-11-06');
      expect(tag(), 'MAÑANA');
      await tapKey(tester, 'cal-cell-2026-11-04');
      expect(tag(), 'AYER');
      await tapKey(tester, 'cal-cell-2026-11-20');
      expect(tag(), 'EN 15 DÍAS');
      await tapKey(tester, 'cal-cell-2026-11-01');
      expect(tag(), 'HACE 4 DÍAS');
    });

    testWidgets('Mes: lo pasado va relleno, hoy en acento, lo que falta oscuro y lo de otro mes solo con contorno', (tester) async {
      await open(tester, mode: CalendarMode.month);
      final c = tester.element(find.byKey(const Key('cal-cell-2026-11-05'))).colors;
      Container boxOf(String day) => tester.widget<Container>(find.descendant(of: find.byKey(Key('cal-cell-$day')), matching: find.byType(Container)).first);
      Color? fillOf(String day) => (boxOf(day).decoration as BoxDecoration).color;
      expect(fillOf('2026-11-05'), c.accent); // hoy
      expect(fillOf('2026-11-03'), c.pick); // pasado
      expect(fillOf('2026-11-20'), c.field); // futuro
      expect(fillOf('2026-10-28'), Colors.transparent); // de otro mes
      expect(cellStateOf(DateTime(2026, 11, 3), DateTime(2026, 11, 5), inMonth: true), CellState.past);
      expect(cellStateOf(DateTime(2026, 12, 1), DateTime(2026, 11, 5), inMonth: false), CellState.outside);
    });

    testWidgets('‹ y › mueven el rango según la vista, y «Hoy» vuelve', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-next');
      expect(title(tester), '9 – 15 nov 2026');
      await pinch(tester, inward: true);
      await tapKey(tester, 'cal-prev');
      expect(title(tester), 'Octubre 2026');
      await tapKey(tester, 'cal-today');
      expect(title(tester), 'Noviembre 2026');
      expect(tester.widget<DotMatrixText>(find.byKey(const Key('cal-month-day'))).text, '5');
    });

    testWidgets('se abre con la vista que se le da (la de Configuración) y cambiarla desde la barra no la guarda', (tester) async {
      await open(tester, mode: CalendarMode.month);
      expect(title(tester), 'Noviembre 2026');
      expect(find.byKey(const Key('cal-month-day')), findsOneWidget);
      expect(find.byKey(const Key('cal-week')), findsNothing);
      await pinch(tester, inward: false);
      expect(find.byKey(const Key('cal-week')), findsOneWidget);
    });
  });

  group('la semana: tareas y desplazamiento', () {
    testWidgets('al abrir, las tarjetas de hoy se ven sin tener que deslizar', (tester) async {
      await tester.runAsync(() async {
        await reminders.add('Llamar', DateTime(2026, 11, 5, 9).toUtc());
        await tasks.add('Informe', due: DateTime(2026, 11, 5, 18).toUtc());
      });
      await open(tester); // hoy es jueves: tres bandas cerradas encima
      final screen = tester.getRect(find.byType(Scaffold));
      expect(tester.getRect(find.text('Informe')).bottom, lessThan(screen.bottom));
    });

    testWidgets('el campo «Añadir una tarea…» crea una tarea con entrega ese día a las 18:00, y el campo se vacía', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-week-day-2026-11-07');
      expect(find.byKey(const Key('cal-week-add-2026-11-05')), findsNothing); // solo el día abierto lo lleva
      await tester.enterText(find.byKey(const Key('cal-week-add-2026-11-07')), '  Comprar pan ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      final t = tasks.roots().single;
      expect(t.name, 'Comprar pan');
      final due = t.due!.toLocal();
      expect((due.year, due.month, due.day, due.hour, due.minute), (2026, 11, 7, 18, 0));
      expect(find.text('Comprar pan'), findsOneWidget); // sale ya en su tarjeta
      expect(tester.widget<TextField>(find.byKey(const Key('cal-week-add-2026-11-07'))).controller!.text, isEmpty);
    });

    testWidgets('el botón del campo también añade; un campo vacío no crea nada', (tester) async {
      await open(tester);
      await tapKey(tester, 'cal-week-add-send-2026-11-05');
      expect(tasks.roots(), isEmpty);
      await tester.enterText(find.byKey(const Key('cal-week-add-2026-11-05')), 'Llamar a Ana');
      await tester.tap(find.byKey(const Key('cal-week-add-send-2026-11-05')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect(tasks.roots().single.name, 'Llamar a Ana');
    });

    testWidgets('hoy después de las 18:00 la tarea nueva vence a las 23:59 (si no, nacería vencida)', (tester) async {
      final evening = DateTime(2026, 11, 5, 19, 30);
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tasks.start();
      });
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: AgendaView(tasks: Future.value(tasks), now: () => evening)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('cal-week-add-2026-11-05')), 'Cerrar el día');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      final due = tasks.roots().single.due!.toLocal();
      expect((due.day, due.hour, due.minute), (5, 23, 59));
    });

    testWidgets('sin tareas no hay campo para añadirlas', (tester) async {
      await open(tester, withTasks: false);
      expect(find.byKey(const Key('cal-week-add-2026-11-05')), findsNothing);
    });

    testWidgets('lo vencido sale arriba del día de hoy, en tarjetas con el bloque en color de aviso', (tester) async {
      await tester.runAsync(() => tasks.add('Pagar', due: DateTime(2026, 10, 30, 18).toUtc()));
      await open(tester);
      final c = tester.element(find.byType(AgendaView)).colors;
      final id = tasks.roots().single.id;
      expect(tester.widget<ColoredBox>(find.byKey(Key('card-time-task-$id'))).color, c.warn);
      expect(find.byKey(const Key('cal-week-count-2026-11-05')), findsOneWidget); // cuenta también lo vencido
    });
  });

  group('siempre se ve todo', () {
    testWidgets('no hay filtros: eventos, tareas, recordatorios y hábitos salen juntos, sin recuadros para escoger', (tester) async {
      await tester.runAsync(() async {
        await reminders.add('Llamar', DateTime(2026, 11, 5, 9).toUtc());
        await tasks.add('Informe', due: DateTime(2026, 11, 5, 18).toUtc());
      });
      await open(tester);
      for (final k in ['event', 'task', 'reminder', 'habit']) {
        expect(find.byKey(Key('cal-show-$k')), findsNothing);
      }
      expect(find.byKey(const Key('cal-show')), findsNothing);
      expect(find.text('Llamar'), findsOneWidget);
      expect(find.text('Informe'), findsOneWidget);
    });

    testWidgets('no queda el botón «Todas las tareas» ni en la semana ni en el mes', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('cal-all-tasks')), findsNothing);
      expect(find.text('TODAS LAS TAREAS ›'), findsNothing);
      await pinch(tester, inward: true);
      expect(find.byKey(const Key('cal-all-tasks')), findsNothing);
    });
  });

  group('actualizar', () {
    testWidgets('el botón «Actualizar» pone al día con Supabase: baja lo que llegó de otro dispositivo', (tester) async {
      await open(tester);
      final before = eventBackend.pulls;
      eventBackend.remote(CalendarEvent(id: 'w1', title: 'Desde la web', startsAt: DateTime(2026, 11, 5, 10).toUtc(), createdAt: now.toUtc(), updatedAt: now.toUtc()));
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
      // la hora va en el bloque de color de su tarjeta, en 12 h
      expect(find.descendant(of: find.byKey(Key('card-time-reminder-${reminders.items.single.id}')), matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: find.byKey(Key('card-time-reminder-${reminders.items.single.id}')), matching: find.text('PM')), findsOneWidget);
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
      expect(find.text('30 OCT'), findsOneWidget); // la fecha, en el bloque de la tarjeta
      await pinch(tester, inward: true);
      await tapKey(tester, 'cal-cell-2026-11-04');
      expect(find.text('Pagar'), findsNothing);
      await tapKey(tester, 'cal-cell-2026-11-05');
      expect(find.text('Pagar'), findsOneWidget);
    });

    testWidgets('un día que todavía no llega enseña sus hábitos, pero no se pueden marcar', (tester) async {
      late Habit habit;
      await tester.runAsync(() async => habit = (await habits.add('Leer', weekdays: Habit.maskOf([6])))!);
      await open(tester);
      await tapKey(tester, 'cal-week-day-2026-11-07'); // el sábado de esta semana
      expect(find.text('Leer'), findsOneWidget);
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
      await tapKey(tester, 'cal-week-day-2026-11-07');
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
      await tapKey(tester, 'cal-week-day-2026-11-06');
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

    testWidgets('sin eventos ni tareas solo se ofrece lo demás', (tester) async {
      await open(tester, withTasks: false, withEvents: false);
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
      expect(find.text('Correr'), findsOneWidget); // en el día abierto (hoy, jueves)
      expect(find.text('8'), findsWidgets); // su aviso, 8 AM, en el bloque de la tarjeta
      expect(find.text('AM'), findsOneWidget);
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

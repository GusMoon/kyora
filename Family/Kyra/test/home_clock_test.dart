import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/clock_store.dart';
import 'package:kyora_chat/state/clock_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/home_page.dart';
import 'package:kyora_chat/ui/widgets/dot_matrix.dart';
import 'package:kyora_chat/ui/widgets/home_clock_panel.dart';

import 'clock_test.dart' show FakeAlarmScheduler;

/// El componente del reloj en Inicio: un cronómetro en marcha y/o la próxima alarma, solo si hay algo que enseñar.
void main() {
  // un jueves a media mañana
  final base = DateTime(2026, 11, 5, 10, 30);
  late DateTime clock;
  late MemoryClockStore store;
  late AlarmController alarms;
  late StopwatchController sw;

  setUp(() {
    clock = base;
    store = MemoryClockStore();
    alarms = AlarmController(store, FakeAlarmScheduler(), now: () => clock);
    sw = StopwatchController(store, now: () => clock);
  });

  tearDown(() {
    alarms.dispose();
    sw.dispose();
  });

  Future<void> open(WidgetTester tester, {VoidCallback? onOpen}) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await alarms.start();
      await sw.start();
    });
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [HomeClockPanel(alarms: alarms, stopwatch: sw, now: () => clock, onOpen: onOpen)]))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sin cronómetro ni alarmas no sale nada', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('home-clock')), findsNothing);
  });

  testWidgets('con una alarma próxima sale su panel, a todo el ancho: la hora, el nombre y cuánto falta', (tester) async {
    await tester.runAsync(() => alarms.add(hour: 12, minute: 15, label: 'Comer', days: 127));
    await open(tester);
    expect(find.byKey(const Key('home-clock')), findsOneWidget);
    expect(find.byKey(const Key('home-clock-alarm')), findsOneWidget);
    expect(find.byKey(const Key('home-clock-stopwatch')), findsNothing);
    expect(tester.widget<Text>(find.byKey(const Key('home-clock-alarm-time'))).data, '12:15');
    expect(find.text('PM'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('home-clock-alarm-until'))).data, 'Comer · en 1 h 45 min');
    expect(tester.getSize(find.byKey(const Key('home-clock-alarm'))).width, closeTo(400 - 32, 1)); // todo el ancho
  });

  testWidgets('la próxima alarma es la que antes suena; una apagada no sale; sin nombre dice «Alarma»', (tester) async {
    await tester.runAsync(() async {
      await alarms.add(hour: 22, minute: 0, days: 127);
      final soon = await alarms.add(hour: 11, minute: 0, days: 127);
      await alarms.setEnabled(soon.id, false);
      await alarms.add(hour: 18, minute: 30, days: 127);
    });
    await open(tester);
    expect(tester.widget<Text>(find.byKey(const Key('home-clock-alarm-time'))).data, '6:30'); // las 18:30; la de las 11 está apagada
    expect(tester.widget<Text>(find.byKey(const Key('home-clock-alarm-until'))).data, startsWith('Alarma · en 8 h'));
  });

  testWidgets('con el cronómetro en marcha sale su panel y cuenta en vivo; en pausa se queda con el tiempo', (tester) async {
    await tester.runAsync(sw.toggle);
    await open(tester);
    expect(find.byKey(const Key('home-clock-stopwatch')), findsOneWidget);
    String main() => tester.widget<DotMatrixText>(find.byKey(const Key('home-clock-sw-main'))).text;
    expect(main(), '00:00');
    clock = clock.add(const Duration(seconds: 75));
    await tester.pump(const Duration(milliseconds: 150)); // su reloj propio repinta
    expect(main(), '01:15');
    await tester.runAsync(sw.toggle); // pausa
    await tester.pump();
    clock = clock.add(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 16));
    expect(main(), '01:15');
    expect(find.byKey(const Key('home-clock-stopwatch')), findsOneWidget); // con tiempo contado sigue saliendo
    await tester.runAsync(sw.reset);
    await tester.pump();
    expect(find.byKey(const Key('home-clock')), findsNothing); // reiniciado, ya no hay nada que enseñar
  });

  testWidgets('con las dos cosas van lado a lado, cada una en su panel', (tester) async {
    await tester.runAsync(() async {
      await alarms.add(hour: 12, minute: 0, days: 127);
      await sw.toggle();
    });
    await open(tester);
    final a = tester.getRect(find.byKey(const Key('home-clock-stopwatch')));
    final b = tester.getRect(find.byKey(const Key('home-clock-alarm')));
    expect(a.left, lessThan(b.left));
    expect(a.top, closeTo(b.top, 1));
    expect(a.width, closeTo(b.width, 1));
    expect(b.right, closeTo(400 - 16 - 0, 12));
    expect(tester.takeException(), isNull); // y nada desborda
  });

  testWidgets('tocar un panel abre el reloj', (tester) async {
    await tester.runAsync(() => alarms.add(hour: 12, minute: 0, days: 127));
    var opened = 0;
    await open(tester, onOpen: () => opened++);
    await tester.tap(find.byKey(const Key('home-clock-alarm')));
    expect(opened, 1);
  });

  testWidgets('apagar la última alarma hace desaparecer el panel', (tester) async {
    final a = (await tester.runAsync(() => alarms.add(hour: 12, minute: 0, days: 127)))!;
    await open(tester);
    expect(find.byKey(const Key('home-clock')), findsOneWidget);
    await tester.runAsync(() => alarms.setEnabled(a.id, false));
    await tester.pump();
    expect(find.byKey(const Key('home-clock')), findsNothing);
  });

  testWidgets('en Inicio sale debajo del tablero y encima del reproductor', (tester) async {
    await tester.runAsync(() => alarms.add(hour: 12, minute: 0, label: 'Comer', days: 127));
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await alarms.start();
      await sw.start();
    });
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: HomePage(onOpenSettings: () {}, alarms: alarms, stopwatch: sw, now: () => clock)));
    await tester.pumpAndSettle();
    final grid = tester.getRect(find.byKey(const Key('home-grid')));
    final panel = tester.getRect(find.byKey(const Key('home-clock')));
    expect(panel.top, greaterThanOrEqualTo(grid.bottom));
    expect(find.byKey(const Key('home-clock-alarm')), findsOneWidget);
  });

  testWidgets('sin los controladores del reloj, Inicio no enseña nada de él', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: HomePage(onOpenSettings: () {}, now: () => clock)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-clock')), findsNothing);
  });
}

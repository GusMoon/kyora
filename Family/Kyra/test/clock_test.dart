import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/models/profile.dart';
import 'package:kyora_chat/ui/auth_gate.dart';
import 'package:kyora_chat/data/alarm_scheduler.dart';
import 'package:kyora_chat/data/clock_store.dart';
import 'package:kyora_chat/models/clock_alarm.dart';
import 'package:kyora_chat/state/clock_controller.dart';
import 'package:kyora_chat/theme.dart';
import 'package:kyora_chat/ui/clock_page.dart';
import 'package:kyora_chat/ui/widgets/dot_matrix.dart';
import 'package:kyora_chat/util/clock_format.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_gate_test.dart' show FakeAccount, MemoryRoleCache;
import 'fake_backend.dart';
import 'fake_engine.dart';
import 'music_test.dart' show FakeMusicBackend, FakeSaver, MemoryMusicStore;
import 'sections.dart';

/// Un programador de mentira: apunta lo que se le pide.
class FakeAlarmScheduler implements AlarmScheduler {
  final Map<int, (String, String, DateTime)> once = {};
  final Map<int, (String, int, int, int)> weekly = {};
  final List<int> cancelled = [];
  bool granted = true;
  bool fail = false;
  int inits = 0;
  int permissionAsks = 0;

  @override
  Future<void> init() async => inits++;

  @override
  Future<bool> ensurePermissions() async {
    permissionAsks++;
    return granted;
  }

  @override
  Future<void> scheduleOnce({required int id, required String title, required String body, required DateTime at}) async {
    if (fail) throw StateError('no se pudo');
    once[id] = (title, body, at);
  }

  @override
  Future<void> scheduleWeekly({required int id, required String title, required String body, required int weekday, required int hour, required int minute}) async {
    if (fail) throw StateError('no se pudo');
    weekly[id] = (title, weekday, hour, minute);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    once.remove(id);
    weekly.remove(id);
  }
}

void main() {
  // un jueves a media mañana
  final now = DateTime(2026, 11, 5, 10, 30, 15);

  group('una alarma', () {
    test('la próxima vez que dan esa hora: hoy si falta, mañana si ya pasó', () {
      expect(ClockAlarm.nextOnce(now, 11, 0), DateTime(2026, 11, 5, 11, 0));
      expect(ClockAlarm.nextOnce(now, 10, 30), DateTime(2026, 11, 6, 10, 30)); // las 10:30:15 ya pasaron las 10:30
      expect(ClockAlarm.nextOnce(now, 8, 0), DateTime(2026, 11, 6, 8, 0));
    });

    test('una que se repite suena el próximo de sus días; apagada, nunca', () {
      const monWed = ClockAlarm(id: 1, hour: 7, minute: 0, days: 1 | 4); // lunes y miércoles
      expect(monWed.nextRing(now), DateTime(2026, 11, 9, 7, 0)); // jueves 5 → el lunes 9
      const everyDay = ClockAlarm(id: 2, hour: 12, minute: 0, days: 127);
      expect(everyDay.nextRing(now), DateTime(2026, 11, 5, 12, 0)); // hoy, que aún no llega
      expect(monWed.copyWith(enabled: false).nextRing(now), isNull);
    });

    test('una de una sola vez suena en su hora fijada y después ya no', () {
      final a = ClockAlarm(id: 1, hour: 11, minute: 0, firesAt: DateTime(2026, 11, 5, 11, 0));
      expect(a.nextRing(now), DateTime(2026, 11, 5, 11, 0));
      expect(a.rangBefore(now), isFalse);
      expect(a.rangBefore(DateTime(2026, 11, 5, 11, 0, 1)), isTrue);
      expect(a.nextRing(DateTime(2026, 11, 5, 11, 0, 1)), isNull);
    });

    test('dice los días en palabras', () {
      expect(const ClockAlarm(id: 1, hour: 7, minute: 0).daysLabel, 'Una vez');
      expect(const ClockAlarm(id: 1, hour: 7, minute: 0, days: 127).daysLabel, 'Todos los días');
      expect(const ClockAlarm(id: 1, hour: 7, minute: 0, days: 31).daysLabel, 'Lun a vie');
      expect(const ClockAlarm(id: 1, hour: 7, minute: 0, days: 96).daysLabel, 'Fines de semana');
      expect(const ClockAlarm(id: 1, hour: 7, minute: 0, days: 1 | 8).daysLabel, 'L J');
    });

    test('se guarda y se lee en JSON; lo que no se entiende se descarta', () {
      final a = ClockAlarm(id: 3, hour: 22, minute: 5, label: 'Gimnasio', days: 5, enabled: false, firesAt: DateTime(2026, 11, 6, 22, 5));
      final back = ClockAlarm.fromJson(a.toJson())!;
      expect((back.id, back.hour, back.minute, back.label, back.days, back.enabled, back.firesAt), (3, 22, 5, 'Gimnasio', 5, false, DateTime(2026, 11, 6, 22, 5)));
      expect(ClockAlarm.fromJson('basura'), isNull);
      expect(ClockAlarm.fromJson({'id': 1, 'hour': 30, 'minute': 0}), isNull);
      expect(ClockAlarm.fromJson({'id': 1, 'hour': 7}), isNull);
    });
  });

  group('el formato', () {
    test('cuánto falta', () {
      expect(untilText(const Duration(seconds: 20)), 'en menos de 1 min');
      expect(untilText(const Duration(minutes: 45)), 'en 45 min');
      expect(untilText(const Duration(hours: 7, minutes: 20)), 'en 7 h 20 min');
      expect(untilText(const Duration(hours: 3)), 'en 3 h');
      expect(untilText(const Duration(days: 2, hours: 3)), 'en 2 d 3 h');
    });

    test('el cronómetro: minutos y segundos, y con horas cuando pasa de una', () {
      expect(stopwatchParts(Duration.zero), ('00:00', '.00'));
      expect(stopwatchParts(const Duration(minutes: 5, seconds: 7, milliseconds: 420)), ('05:07', '.42'));
      expect(stopwatchParts(const Duration(hours: 1, minutes: 5, seconds: 7)), ('1:05:07', '.00'));
      expect(stopwatchText(const Duration(seconds: 61, milliseconds: 999)), '01:01.99');
      expect(stopwatchParts(const Duration(seconds: -4)), ('00:00', '.00'));
    });
  });

  group('lo guardado en el teléfono', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('las alarmas y el cronómetro se guardan y vuelven', () async {
      final store = await PrefsClockStore.open();
      expect(await store.loadAlarms(), isEmpty);
      expect((await store.loadStopwatch()).laps, isEmpty);
      await store.saveAlarms([const ClockAlarm(id: 1, hour: 7, minute: 30, label: 'Despertar', days: 31)]);
      await store.saveStopwatch(StopwatchSnapshot(accumulated: const Duration(seconds: 12), startedAt: DateTime(2026, 11, 5, 10), laps: const [Duration(seconds: 5)]));
      final other = await PrefsClockStore.open();
      expect((await other.loadAlarms()).single.label, 'Despertar');
      final sw = await other.loadStopwatch();
      expect((sw.accumulated, sw.startedAt), (const Duration(seconds: 12), DateTime(2026, 11, 5, 10)));
      expect(sw.laps, const [Duration(seconds: 5)]);
    });

    test('un valor guardado que no se entiende se ignora', () async {
      SharedPreferences.setMockInitialValues({PrefsClockStore.alarmsKey: '{no es json', PrefsClockStore.stopwatchKey: '[1,2'});
      final store = await PrefsClockStore.open();
      expect(await store.loadAlarms(), isEmpty);
      expect((await store.loadStopwatch()).accumulated, Duration.zero);
    });
  });

  group('las alarmas (controlador)', () {
    late MemoryClockStore store;
    late FakeAlarmScheduler scheduler;
    late AlarmController alarms;

    setUp(() {
      store = MemoryClockStore();
      scheduler = FakeAlarmScheduler();
      alarms = AlarmController(store, scheduler, now: () => now);
    });

    tearDown(() => alarms.dispose());

    test('crear una de una sola vez la programa en la próxima vez que dan esa hora y pide el permiso una vez', () async {
      await alarms.start();
      expect(scheduler.inits, 1);
      final a = await alarms.add(hour: 7, minute: 30, label: ' Despertar ');
      expect(a.label, 'Despertar');
      final id = alarmNotifId(a.id, 0);
      expect(scheduler.once[id]!.$1, 'Despertar');
      expect(scheduler.once[id]!.$2, '7:30 AM');
      expect(scheduler.once[id]!.$3, DateTime(2026, 11, 6, 7, 30)); // ya pasaron las 7:30 de hoy
      await alarms.add(hour: 23, minute: 0);
      expect(scheduler.permissionAsks, 1);
      expect(scheduler.once[alarmNotifId(2, 0)]!.$1, 'Alarma'); // sin nombre
    });

    test('una que se repite programa un aviso semanal por cada día y ninguno de una vez', () async {
      await alarms.start();
      final a = await alarms.add(hour: 18, minute: 5, days: 1 | 4 | 16); // lunes, miércoles y viernes
      expect(scheduler.weekly.keys.toSet(), {alarmNotifId(a.id, 1), alarmNotifId(a.id, 3), alarmNotifId(a.id, 5)});
      expect(scheduler.weekly[alarmNotifId(a.id, 3)], ('Alarma', 3, 18, 5));
      expect(scheduler.once, isEmpty);
    });

    test('editarla quita los avisos de los días que ya no tiene', () async {
      await alarms.start();
      final a = await alarms.add(hour: 8, minute: 0, days: 1 | 2);
      await alarms.update(a.id, hour: 9, minute: 15, label: 'Cambio', days: 2);
      expect(scheduler.weekly.keys.toSet(), {alarmNotifId(a.id, 2)});
      expect(scheduler.weekly[alarmNotifId(a.id, 2)], ('Cambio', 2, 9, 15));
      expect(alarms.byId(a.id)!.minutes, 9 * 60 + 15);
    });

    test('apagarla cancela sus avisos; encenderla los vuelve a programar; borrarla los cancela y la quita', () async {
      await alarms.start();
      final a = await alarms.add(hour: 8, minute: 0, days: 127);
      expect(scheduler.weekly.length, 7);
      await alarms.setEnabled(a.id, false);
      expect(scheduler.weekly, isEmpty);
      expect(alarms.next(), isNull);
      await alarms.setEnabled(a.id, true);
      expect(scheduler.weekly.length, 7);
      await alarms.remove(a.id);
      expect(scheduler.weekly, isEmpty);
      expect(alarms.alarms, isEmpty);
      expect((await store.loadAlarms()), isEmpty);
    });

    test('van ordenadas por hora y «la próxima» es la que antes suena', () async {
      await alarms.start();
      await alarms.add(hour: 22, minute: 0, days: 127);
      await alarms.add(hour: 12, minute: 0, days: 127);
      await alarms.add(hour: 6, minute: 0, days: 127);
      expect(alarms.alarms.map((a) => a.hour), [6, 12, 22]);
      expect(alarms.next()!.$1.hour, 12); // son las 10:30
      expect(alarms.next()!.$2, DateTime(2026, 11, 5, 12, 0));
    });

    test('al abrir, la de una sola vez que ya sonó se apaga, y las demás se vuelven a programar', () async {
      final past = ClockAlarm(id: 1, hour: 6, minute: 0, firesAt: DateTime(2026, 11, 5, 6, 0));
      final future = ClockAlarm(id: 2, hour: 20, minute: 0, firesAt: DateTime(2026, 11, 5, 20, 0));
      const daily = ClockAlarm(id: 3, hour: 9, minute: 0, days: 127);
      store = MemoryClockStore(alarms: [past, future, daily]);
      alarms = AlarmController(store, scheduler, now: () => now);
      await alarms.start();
      expect(alarms.byId(1)!.enabled, isFalse);
      expect(alarms.byId(2)!.enabled, isTrue);
      expect(scheduler.once.keys.toSet(), {alarmNotifId(2, 0)});
      expect(scheduler.weekly.length, 7);
      expect((await store.loadAlarms()).firstWhere((a) => a.id == 1).enabled, isFalse); // y lo deja guardado
    });

    test('sin permiso para avisar, lo dice (las alarmas se guardan igual); si el teléfono falla al programar, también', () async {
      scheduler.granted = false;
      await alarms.start();
      await alarms.add(hour: 8, minute: 0);
      expect(alarms.permissionDenied, isTrue);
      expect(alarms.alarms, hasLength(1));
      final other = AlarmController(MemoryClockStore(), FakeAlarmScheduler()..fail = true, now: () => now);
      await other.start();
      await other.add(hour: 8, minute: 0);
      expect(other.permissionDenied, isTrue);
      other.dispose();
    });

    test('lo guardado vuelve al abrir otra vez; los números de las notificaciones no chocan con los de los recordatorios', () async {
      await alarms.start();
      await alarms.add(hour: 7, minute: 0, label: 'A');
      final again = AlarmController(store, FakeAlarmScheduler(), now: () => now);
      await again.start();
      expect(again.alarms.single.label, 'A');
      again.dispose();
      expect(alarmNotifId(1, 0), greaterThan(1 << 30)); // los recordatorios llegan a 2^30
      expect(alarmNotifId(9999, 7), lessThan(1 << 31));
      expect({for (var d = 0; d < 8; d++) alarmNotifId(1, d)}.length, 8);
    });
  });

  group('el cronómetro (controlador)', () {
    late DateTime t;
    late MemoryClockStore store;
    late StopwatchController sw;

    setUp(() {
      t = DateTime(2026, 11, 5, 10);
      store = MemoryClockStore();
      sw = StopwatchController(store, now: () => t);
    });

    tearDown(() => sw.dispose());

    test('cuenta mientras corre, se detiene al pausar y sigue donde estaba al continuar', () async {
      await sw.start();
      expect((sw.running, sw.elapsed), (false, Duration.zero));
      await sw.toggle();
      t = t.add(const Duration(seconds: 10));
      expect(sw.elapsed, const Duration(seconds: 10));
      await sw.toggle();
      t = t.add(const Duration(seconds: 30)); // pausado: no cuenta
      expect((sw.running, sw.elapsed), (false, const Duration(seconds: 10)));
      await sw.toggle();
      t = t.add(const Duration(seconds: 5));
      expect(sw.elapsed, const Duration(seconds: 15));
    });

    test('las vueltas guardan el total y la duración de cada una; solo valen corriendo', () async {
      await sw.start();
      await sw.lap();
      expect(sw.laps, isEmpty);
      await sw.toggle();
      t = t.add(const Duration(seconds: 20));
      await sw.lap();
      t = t.add(const Duration(seconds: 25));
      await sw.lap();
      expect(sw.laps, const [Duration(seconds: 20), Duration(seconds: 45)]);
      expect(sw.lapTimes, const [Duration(seconds: 20), Duration(seconds: 25)]);
    });

    test('reiniciar lo deja todo en cero', () async {
      await sw.start();
      await sw.toggle();
      t = t.add(const Duration(seconds: 7));
      await sw.lap();
      await sw.reset();
      expect((sw.running, sw.hasTime, sw.elapsed), (false, false, Duration.zero));
      expect(sw.laps, isEmpty);
    });

    test('se guarda: al abrir otra vez sigue contando (o parado) donde estaba', () async {
      await sw.start();
      await sw.toggle();
      t = t.add(const Duration(seconds: 12));
      await sw.lap();
      final other = StopwatchController(store, now: () => t);
      await other.start();
      expect(other.running, isTrue);
      t = t.add(const Duration(seconds: 3)); // pasó un rato con la app cerrada
      expect(other.elapsed, const Duration(seconds: 15));
      expect(other.laps, const [Duration(seconds: 12)]);
      await other.toggle();
      final paused = StopwatchController(store, now: () => t);
      await paused.start();
      expect((paused.running, paused.elapsed), (false, const Duration(seconds: 15)));
      other.dispose();
      paused.dispose();
    });
  });

  group('la pantalla del reloj', () {
    late DateTime clock;
    late MemoryClockStore store;
    late FakeAlarmScheduler scheduler;
    late AlarmController alarms;
    late StopwatchController sw;

    setUp(() {
      clock = now;
      store = MemoryClockStore();
      scheduler = FakeAlarmScheduler();
      alarms = AlarmController(store, scheduler, now: () => clock);
      sw = StopwatchController(store, now: () => clock);
    });

    tearDown(() {
      alarms.dispose();
      sw.dispose();
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await alarms.start();
        await sw.start();
      });
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: ClockPage(alarms: alarms, stopwatch: sw, now: () => clock)));
      await tester.pumpAndSettle();
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
    }

    Future<void> settleIo(WidgetTester tester) async {
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
    }

    String nextText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('clock-next'))).data!;

    testWidgets('sin alarmas: la hora de ahora en puntos, «sin alarmas activas» y cómo crear la primera', (tester) async {
      await open(tester);
      expect(tester.widget<DotMatrixText>(find.byKey(const Key('clock-now'))).text, '10:30');
      expect(find.text('AM'), findsOneWidget);
      expect(nextText(tester), 'SIN ALARMAS ACTIVAS');
      expect(find.byKey(const Key('clock-empty')), findsOneWidget);
      expect(find.byKey(const Key('clock-add')), findsOneWidget);
      expect(find.byKey(const Key('clock-denied')), findsNothing);
    });

    testWidgets('«+» abre el editor con la hora de ahora; Guardar crea la alarma, la programa y sale en la lista', (tester) async {
      await open(tester);
      await tapKey(tester, 'clock-add');
      expect(find.byKey(const Key('alarm-hour')), findsOneWidget);
      expect(find.byKey(const Key('alarm-minute')), findsOneWidget);
      expect(find.byKey(const Key('alarm-delete')), findsNothing); // es nueva
      expect(tester.widget<Text>(find.byKey(const Key('alarm-days-label'))).data, 'Suena una sola vez.');
      await tapKey(tester, 'alarm-save');
      await settleIo(tester);
      final a = alarms.alarms.single;
      expect((a.hour, a.minute, a.enabled), (10, 30, true));
      expect(find.byKey(Key('alarm-${a.id}')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(Key('alarm-time-${a.id}'))).data, '10:30');
      expect(tester.widget<Text>(find.byKey(Key('alarm-sub-${a.id}'))).data, 'Una vez');
      expect(find.byKey(const Key('clock-empty')), findsNothing);
      expect(scheduler.once.containsKey(alarmNotifId(a.id, 0)), isTrue);
      expect(nextText(tester), 'PRÓXIMA EN 23 H 59 MIN'); // mañana a las 10:30
    });

    testWidgets('en el editor se elige PM, los días y el nombre', (tester) async {
      await open(tester);
      await tapKey(tester, 'clock-add');
      await tapKey(tester, 'alarm-pm');
      await tapKey(tester, 'alarm-day-1');
      await tapKey(tester, 'alarm-day-3');
      expect(tester.widget<Text>(find.byKey(const Key('alarm-days-label'))).data, 'L M');
      await tester.enterText(find.byKey(const Key('alarm-label')), 'Gimnasio');
      await tapKey(tester, 'alarm-save');
      await settleIo(tester);
      final a = alarms.alarms.single;
      expect((a.hour, a.minute, a.days, a.label), (22, 30, 5, 'Gimnasio'));
      expect(tester.widget<Text>(find.byKey(Key('alarm-time-${a.id}'))).data, '10:30');
      expect(find.text('PM'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(Key('alarm-sub-${a.id}'))).data, 'Gimnasio · L M');
      expect(scheduler.weekly.keys.toSet(), {alarmNotifId(a.id, 1), alarmNotifId(a.id, 3)});
      // tocar un día otra vez lo quita
      await tester.tap(find.byKey(Key('alarm-${a.id}')));
      await tester.pumpAndSettle();
      await tapKey(tester, 'alarm-day-1');
      await tapKey(tester, 'alarm-day-3');
      expect(tester.widget<Text>(find.byKey(const Key('alarm-days-label'))).data, 'Suena una sola vez.');
    });

    testWidgets('la rueda de la hora y la de los minutos cambian la hora que se guarda', (tester) async {
      await open(tester);
      await tapKey(tester, 'clock-add');
      await tester.drag(find.byKey(const Key('alarm-hour')), const Offset(0, -100)); // dos horas más
      await tester.pumpAndSettle();
      await tester.drag(find.byKey(const Key('alarm-minute')), const Offset(0, -150)); // tres minutos más
      await tester.pumpAndSettle();
      await tapKey(tester, 'alarm-save');
      await settleIo(tester);
      final a = alarms.alarms.single;
      expect((a.hour, a.minute), (0, 33)); // 10 + 2 = 12 AM = las 0
    });

    testWidgets('el interruptor apaga y enciende la alarma; apagada se ve atenuada y no cuenta para la próxima', (tester) async {
      await tester.runAsync(() => store.saveAlarms([const ClockAlarm(id: 1, hour: 12, minute: 0, label: 'Comer', days: 127)]));
      await open(tester);
      expect(nextText(tester), 'PRÓXIMA EN 1 H 29 MIN');
      await tapKey(tester, 'alarm-switch-1');
      await settleIo(tester);
      expect(alarms.byId(1)!.enabled, isFalse);
      expect(nextText(tester), 'SIN ALARMAS ACTIVAS');
      expect(scheduler.weekly, isEmpty);
      await tapKey(tester, 'alarm-switch-1');
      await settleIo(tester);
      expect(alarms.byId(1)!.enabled, isTrue);
      expect(scheduler.weekly.length, 7);
    });

    testWidgets('tocar una alarma la edita y Eliminar la borra', (tester) async {
      await tester.runAsync(() => store.saveAlarms([const ClockAlarm(id: 1, hour: 7, minute: 15, label: 'Despertar', days: 31)]));
      await open(tester);
      await tapKey(tester, 'alarm-1');
      expect(tester.widget<TextField>(find.byKey(const Key('alarm-label'))).controller!.text, 'Despertar');
      expect(tester.widget<Text>(find.byKey(const Key('alarm-days-label'))).data, 'Lun a vie');
      await tester.enterText(find.byKey(const Key('alarm-label')), 'Trabajo');
      await tapKey(tester, 'alarm-save');
      await settleIo(tester);
      expect(alarms.byId(1)!.label, 'Trabajo');
      expect((alarms.byId(1)!.hour, alarms.byId(1)!.minute), (7, 15)); // lo demás se queda
      await tapKey(tester, 'alarm-1');
      await tapKey(tester, 'alarm-delete');
      await settleIo(tester);
      expect(alarms.alarms, isEmpty);
      expect(find.byKey(const Key('clock-empty')), findsOneWidget);
      expect(scheduler.weekly, isEmpty);
    });

    testWidgets('si el teléfono no deja mostrar avisos, la pantalla lo dice', (tester) async {
      scheduler.granted = false;
      await open(tester);
      await tapKey(tester, 'clock-add');
      await tapKey(tester, 'alarm-save');
      await settleIo(tester);
      expect(find.byKey(const Key('clock-denied')), findsOneWidget);
    });

    testWidgets('el cronómetro: Iniciar → cuenta → Pausar → Continuar; Reiniciar lo pone en cero', (tester) async {
      await open(tester);
      await tapKey(tester, 'clock-tab-stopwatch');
      expect(find.byKey(const Key('clock-add')), findsNothing); // «+» es de las alarmas
      String main() => tester.widget<DotMatrixText>(find.byKey(const Key('sw-main'))).text;
      String fraction() => tester.widget<DotMatrixText>(find.byKey(const Key('sw-fraction'))).text;
      expect((main(), fraction()), ('00:00', '.00'));
      expect(find.text('INICIAR'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sw-toggle')));
      await tester.pump();
      expect(find.text('PAUSAR'), findsOneWidget);
      clock = clock.add(const Duration(minutes: 1, seconds: 5, milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 16)); // cada fotograma se repinta
      expect((main(), fraction()), ('01:05', '.50'));
      await tester.tap(find.byKey(const Key('sw-toggle')));
      await tester.pump();
      expect(find.text('CONTINUAR'), findsOneWidget);
      clock = clock.add(const Duration(seconds: 30)); // pausado: no cuenta
      await tester.pump(const Duration(seconds: 1));
      expect((main(), fraction()), ('01:05', '.50'));
      await tapKey(tester, 'sw-reset');
      expect((main(), fraction()), ('00:00', '.00'));
      expect(find.text('INICIAR'), findsOneWidget);
      expect(find.byKey(const Key('sw-reset')), findsNothing);
    });

    testWidgets('Vuelta anota la vuelta (la última arriba) y marca la más rápida en verde y la más lenta en aviso', (tester) async {
      await open(tester);
      await tapKey(tester, 'clock-tab-stopwatch');
      expect(tester.widget<GestureDetector>(find.ancestor(of: find.text('VUELTA'), matching: find.byType(GestureDetector)).first).onTap, isNull); // parado no se puede
      await tester.tap(find.byKey(const Key('sw-toggle')));
      await tester.pump();
      for (final seconds in [20, 10, 30]) {
        clock = clock.add(Duration(seconds: seconds));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.tap(find.byKey(const Key('sw-lap')));
        await tester.pump();
      }
      expect(sw.laps, const [Duration(seconds: 20), Duration(seconds: 30), Duration(minutes: 1)]);
      // la vuelta 3 (la última) va arriba
      expect(tester.getRect(find.byKey(const Key('sw-lap-3'))).top, lessThan(tester.getRect(find.byKey(const Key('sw-lap-1'))).top));
      final c = tester.element(find.byKey(const Key('sw-lap-1'))).colors;
      Color? timeColor(int n) => tester.widget<Text>(find.descendant(of: find.byKey(Key('sw-lap-$n')), matching: find.text(n == 1 ? '00:20.00' : (n == 2 ? '00:10.00' : '00:30.00'))).first).style!.color;
      expect(timeColor(2), c.habits); // 10 s: la más rápida
      expect(timeColor(3), c.warn); // 30 s: la más lenta
      expect(timeColor(1), c.ink);
      await tester.tap(find.byKey(const Key('sw-toggle'))); // se para el cronómetro para terminar la prueba
      await tester.pump();
    });

    testWidgets('al cambiar de pestaña y volver, todo sigue donde estaba', (tester) async {
      await tester.runAsync(() => store.saveAlarms([const ClockAlarm(id: 1, hour: 7, minute: 15, days: 127)]));
      await open(tester);
      await tapKey(tester, 'clock-tab-stopwatch');
      await tapKey(tester, 'clock-tab-alarms');
      expect(find.byKey(const Key('alarm-1')), findsOneWidget);
    });
  });

  group('en la app', () {
    Future<void> gate(WidgetTester tester, {ClockStore? clockStore, AlarmScheduler? scheduler}) async {
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
          clockStore: clockStore,
          alarmScheduler: scheduler,
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }

    testWidgets('con el almacén del reloj, «Reloj» sale en el menú circular; sin él, no', (tester) async {
      await gate(tester);
      expect(await menuOptions(tester), isNot(contains('clock')));
    });

    testWidgets('«Reloj» abre sus alarmas, que se guardan en el teléfono y se programan', (tester) async {
      final store = MemoryClockStore();
      final scheduler = FakeAlarmScheduler();
      await gate(tester, clockStore: store, scheduler: scheduler);
      expect(await menuOptions(tester), contains('clock'));
      await goToSection(tester, 'clock');
      expect(find.byKey(const Key('clock-tab-alarms')), findsOneWidget);
      await tester.tap(find.byKey(const Key('clock-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('alarm-save')));
      await tester.runAsync(pumpEventQueue);
      await tester.pumpAndSettle();
      expect((await store.loadAlarms()).length, 1);
      expect(scheduler.once, isNotEmpty);
      expect(scheduler.inits, greaterThan(0));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/habit_backend.dart';
import 'package:kyora_chat/data/habit_store.dart';
import 'package:kyora_chat/models/habit.dart';
import 'package:kyora_chat/state/habit_controller.dart';
import 'package:kyora_chat/state/task_controller.dart' show SyncState;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'reminders_test.dart' show FakeScheduler;

final t0 = DateTime.utc(2026, 11, 2, 9);

Habit habit(String id, {String name = 'Leer', DateTime? updated, int weekdays = Habit.everyDay, int? remindAt, DateTime? deleted, String? synced}) =>
    Habit(id: id, name: name, weekdays: weekdays, remindAt: remindAt, createdAt: t0, updatedAt: updated ?? t0, deletedAt: deleted, syncedAt: synced);

/// Supabase de mentira para los hábitos: guarda lo subido (gana el `updated_at` más reciente, como `sync_guard`) y pone `synced_at`.
class FakeHabitBackend implements HabitBackend {
  final Map<String, Habit> habits = {};
  final Map<String, HabitCheck> checks = {};
  final List<HabitData> pushed = [];
  ChatException? error;
  int _tick = 0;

  String _stamp() => DateTime.utc(2026, 11, 2, 12).add(Duration(seconds: ++_tick)).toIso8601String();

  @override
  Future<void> pushHabits(HabitData changes) async {
    if (error != null) throw error!;
    pushed.add(changes);
    for (final h in changes.habits) {
      final old = habits[h.id];
      if (old != null && !h.updatedAt.isAfter(old.updatedAt)) continue;
      habits[h.id] = Habit.fromJson({...h.toJson(), 'synced_at': _stamp()});
    }
    for (final c in changes.checks) {
      final old = checks[c.key];
      if (old != null && !c.updatedAt.isAfter(old.updatedAt)) continue;
      checks[c.key] = HabitCheck.fromJson({...c.toJson(), 'synced_at': _stamp()});
    }
  }

  @override
  Future<HabitData> pullHabits({String? habitsSince, String? checksSince}) async {
    if (error != null) throw error!;
    bool after(String? row, String? since) => since == null || DateTime.parse(row!).isAfter(DateTime.parse(since));
    return HabitData(
      habits: [for (final h in habits.values) if (after(h.syncedAt, habitsSince)) h],
      checks: [for (final c in checks.values) if (after(c.syncedAt, checksSince)) c],
    );
  }

  /// Un cambio hecho desde otro dispositivo.
  void remote(Habit h) => habits[h.id] = Habit.fromJson({...h.toJson(), 'synced_at': _stamp()});
}

/// La misma batería para el almacén real (SQLite) y el de memoria.
void storeTests(String label, Future<HabitStore> Function() open) {
  group(label, () {
    late HabitStore store;

    setUp(() async => store = await open());
    tearDown(() => store.close());

    test('guarda y devuelve todos los campos, también los borrados (hacen falta para cancelar sus avisos)', () async {
      final full = habit('a', name: 'Correr', weekdays: Habit.maskOf([1, 3, 5]), remindAt: 7 * 60 + 30, updated: t0.add(const Duration(minutes: 1)));
      await store.put(HabitData(habits: [full, habit('b', deleted: t0)], checks: [HabitCheck(habitId: 'a', day: '2026-11-03', done: true, updatedAt: t0)]));
      final data = await store.load();
      final a = data.habits.firstWhere((h) => h.id == 'a');
      expect(a.toJson(), full.toJson());
      expect(data.habits.map((h) => h.id).toSet(), {'a', 'b'});
      expect(data.checks.single.done, isTrue);
      expect(data.checks.single.day, '2026-11-03');
    });

    test('lo cambiado queda por subir; al subirse se limpia, salvo lo que cambió mientras tanto', () async {
      final first = habit('a');
      await store.put(HabitData(habits: [first]));
      expect(await store.dirtyCount(), 1);
      final uploaded = await store.dirty();
      await store.put(HabitData(habits: [first.copyWith(name: 'Leer más', updatedAt: t0.add(const Duration(seconds: 1)))]));
      await store.markClean(uploaded);
      expect(await store.dirtyCount(), 1); // el cambio nuevo sigue por subir
      await store.markClean(await store.dirty());
      expect(await store.dirtyCount(), 0);
    });

    test('lo de Supabase gana si es más reciente; lo local sin subir y más nuevo se queda', () async {
      await store.put(HabitData(habits: [habit('a', name: 'Local', updated: t0.add(const Duration(minutes: 5)))]));
      await store.applyRemote(HabitData(habits: [habit('a', name: 'Viejo', updated: t0), habit('b', name: 'Nuevo')]));
      final data = await store.load();
      expect(data.habits.firstWhere((h) => h.id == 'a').name, 'Local');
      expect(data.habits.firstWhere((h) => h.id == 'b').name, 'Nuevo');
      await store.applyRemote(HabitData(habits: [habit('a', name: 'Más nuevo', updated: t0.add(const Duration(minutes: 9)))]));
      expect((await store.load()).habits.firstWhere((h) => h.id == 'a').name, 'Más nuevo');
    });

    test('recuerda por dónde iba cada tabla', () async {
      expect(await store.cursor('habits'), isNull);
      await store.setCursor('habits', '2026-11-02T12:00:00.000Z');
      expect(await store.cursor('habits'), '2026-11-02T12:00:00.000Z');
      expect(await store.cursor('habit_checks'), isNull);
    });
  });
}

void main() {
  group('el modelo', () {
    test('los días van en una máscara: lunes = bit 0 … domingo = bit 6', () {
      final h = habit('a', weekdays: Habit.maskOf([1, 3, 7]));
      expect(h.weekdays, 1 | 4 | 64);
      expect([for (var d = 1; d <= 7; d++) h.on(d)], [true, false, true, false, false, false, true]);
      expect(Habit.maskOf([1, 2, 3, 4, 5, 6, 7]), Habit.everyDay);
    });

    test('el día de una marca es el de calendario, en la hora local', () {
      expect(dayKey(DateTime(2026, 11, 5, 23, 59)), '2026-11-05');
      expect(dayKey(DateTime(2026, 1, 3)), '2026-01-03');
    });

    test('ida y vuelta por JSON, también la marca tal como la manda Supabase (fecha y booleano)', () {
      final h = habit('a', remindAt: 450, weekdays: 5);
      expect(Habit.fromJson(h.toJson()).toJson(), h.toJson());
      final c = HabitCheck.fromJson({'habit_id': 'a', 'day': '2026-11-05', 'done': true, 'updated_at': '2026-11-05T10:00:00Z', 'synced_at': 'x'});
      expect((c.habitId, c.day, c.done, c.syncedAt), ('a', '2026-11-05', true, 'x'));
    });

    test('el número de aviso es estable, propio de cada día y lejos de los de los recordatorios', () {
      final ids = {for (var d = 1; d <= 7; d++) habitNotifId('abc', d)};
      expect(ids.length, 7);
      expect(habitNotifId('abc', 3), habitNotifId('abc', 3));
      expect(habitNotifId('otro', 3), isNot(habitNotifId('abc', 3)));
      for (final id in ids) {
        expect(id, greaterThanOrEqualTo(1 << 30));
        expect(id, lessThan(1 << 31));
      }
    });
  });

  sqfliteFfiInit();
  storeTests('almacén en memoria', () async => MemoryHabitStore());
  storeTests('SQLite', () => SqliteHabitStore.open('prueba', path: inMemoryDatabasePath, factory: databaseFactoryFfi));

  group('el controlador', () {
    late MemoryHabitStore store;
    late FakeHabitBackend backend;
    late FakeScheduler scheduler;
    late HabitController c;
    var n = 0;
    // un jueves a media mañana (UTC; el día local puede variar con la zona del equipo de pruebas, por eso se compara con dayKey)
    var now = DateTime.utc(2026, 11, 5, 12);

    setUp(() {
      n = 0;
      now = DateTime.utc(2026, 11, 5, 12);
      store = MemoryHabitStore();
      backend = FakeHabitBackend();
      scheduler = FakeScheduler();
      c = HabitController(store, backend, scheduler: scheduler, now: () => now, newId: () => 'h${++n}', retry: const Duration(hours: 1));
    });

    tearDown(() => c.dispose());

    test('crear guarda en el teléfono al instante y sube a Supabase', () async {
      await c.start();
      final h = await c.add('  Leer  ');
      expect(h!.name, 'Leer');
      expect(c.habits.single.id, 'h1');
      await c.sync();
      expect(backend.habits.keys, ['h1']);
      expect(c.pending, 0);
      expect(c.syncState, SyncState.idle);
    });

    test('sin nombre o sin ningún día no crea nada', () async {
      await c.start();
      expect(await c.add('   '), isNull);
      expect(await c.add('Correr', weekdays: 0), isNull);
      expect(c.habits, isEmpty);
    });

    test('sin conexión se guarda igual, queda por subir y sube al volver', () async {
      backend.error = const ChatException('Sin conexión con Supabase', retryable: true, code: 'offline');
      await c.start();
      await c.add('Leer');
      await c.sync();
      expect(c.syncState, SyncState.offline);
      expect(c.pending, 1);
      expect(c.habits.single.name, 'Leer'); // se sigue viendo
      backend.error = null;
      await c.sync();
      expect(c.pending, 0);
      expect(backend.habits.values.single.name, 'Leer');
    });

    test('baja lo que cambió en otro dispositivo; si los dos cambian lo mismo, gana el más reciente', () async {
      await c.start();
      backend.remote(habit('x', name: 'De la tablet', updated: now));
      await c.sync();
      expect(c.byId('x')!.name, 'De la tablet');
      await c.update(c.byId('x')!, name: 'Del teléfono');
      backend.remote(habit('x', name: 'Viejo', updated: now.subtract(const Duration(hours: 1))));
      await c.sync();
      expect(c.byId('x')!.name, 'Del teléfono');
      expect(backend.habits['x']!.name, 'Del teléfono');
    });

    test('toca solo los días elegidos y no los anteriores a su creación', () async {
      await c.start();
      final h = (await c.add('Gimnasio', weekdays: Habit.maskOf([1, 3, 5])))!;
      final local = now.toLocal();
      final today = DateTime(local.year, local.month, local.day);
      for (var i = 0; i < 14; i++) {
        final day = DateTime(today.year, today.month, today.day + i);
        expect(c.habitsFor(day).contains(h), h.on(day.weekday), reason: '$day');
      }
      expect(c.habitsFor(DateTime(today.year, today.month, today.day - 7)), isEmpty); // antes de crearlo
    });

    test('marcar y desmarcar un día; un día que no llega no se marca', () async {
      await c.start();
      final h = (await c.add('Leer'))!;
      final today = now.toLocal();
      expect(c.isDone(h, today), isFalse);
      expect(await c.toggle(h, today), isTrue);
      expect(c.isDone(h, today), isTrue);
      await c.toggle(h, today);
      expect(c.isDone(h, today), isFalse); // desmarcar no borra: queda done = false y también se sincroniza
      final tomorrow = DateTime(today.year, today.month, today.day + 1, 12);
      expect(await c.toggle(h, tomorrow), isFalse);
      expect(c.isDone(h, tomorrow), isFalse);
      await c.sync();
      expect(backend.checks.values.single.done, isFalse);
    });

    test('el aviso se programa una vez por cada día que toca, se reprograma al cambiar y se cancela al quitarlo o borrar', () async {
      await c.start();
      final h = (await c.add('Leer', weekdays: Habit.maskOf([1, 3]), remindAt: 7 * 60 + 30))!;
      expect(scheduler.permissionAsks, 1);
      expect(scheduler.weekly.keys.toSet(), {habitNotifId('h1', 1), habitNotifId('h1', 3)});
      expect(scheduler.weekly[habitNotifId('h1', 3)], ('Leer', 3, 7, 30));
      await c.update(h, weekdays: Habit.maskOf([2]), remindAt: 21 * 60);
      expect(scheduler.weekly.keys.toSet(), {habitNotifId('h1', 2)});
      expect(scheduler.weekly[habitNotifId('h1', 2)], ('Leer', 2, 21, 0));
      await c.update(c.byId('h1')!, remindAt: null);
      expect(scheduler.weekly, isEmpty);
      await c.update(c.byId('h1')!, remindAt: 8 * 60);
      expect(scheduler.weekly, isNotEmpty);
      await c.delete(c.byId('h1')!);
      expect(scheduler.weekly, isEmpty);
      expect(c.habits, isEmpty);
    });

    test('un aviso que se borró en otro dispositivo también se cancela aquí', () async {
      await c.start();
      await c.add('Leer', remindAt: 8 * 60);
      await c.sync();
      expect(scheduler.weekly.length, 7);
      backend.remote(backend.habits['h1']!.copyWith(deletedAt: now, updatedAt: now.add(const Duration(minutes: 1))));
      await c.sync();
      expect(scheduler.weekly, isEmpty);
    });

    test('un cambio hecho mientras una sincronización termina también sube en esa misma espera', () async {
      await c.start(); // su sincronización sigue en marcha
      await c.add('Leer');
      await c.sync();
      expect(backend.habits.keys, ['h1']);
      expect(c.pending, 0);
    });

    test('si el teléfono no deja programar avisos, lo dice y los hábitos siguen funcionando', () async {
      scheduler.failSchedule = true;
      await c.start();
      final h = await c.add('Leer', remindAt: 8 * 60);
      expect(h, isNotNull);
      expect(c.notificationsBlocked, isTrue);
      expect(await c.toggle(h!, now.toLocal()), isTrue);
    });
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/event_store.dart';
import 'package:kyora_chat/data/reminder_store.dart';
import 'package:kyora_chat/data/sync_rows.dart';
import 'package:kyora_chat/models/event.dart';
import 'package:kyora_chat/models/reminder.dart';
import 'package:kyora_chat/state/event_controller.dart';
import 'package:kyora_chat/state/reminder_controller.dart';
import 'package:kyora_chat/state/task_controller.dart' show SyncState;
import 'package:shared_preferences/shared_preferences.dart';

import 'reminders_test.dart' show FakeScheduler;

/// Supabase de mentira para una tabla de filas sincronizadas: guarda lo que se sube (gana el `updatedAt` más reciente, como el servidor) y da
/// `synced_at` creciente para poder pedir solo las novedades.
class FakeRowBackend<T extends SyncRow> implements RowBackend<T> {
  FakeRowBackend(this._stamped);

  /// Cómo se marca una fila con su hora de servidor.
  final T Function(T row, String syncedAt) _stamped;

  final Map<String, T> server = {};
  int pushes = 0;
  int pulls = 0;
  int clock = 0;
  ChatException? failWith;
  Completer<void>? hold;

  @override
  Future<void> push(List<T> rows) async {
    pushes++;
    if (hold != null) await hold!.future;
    final error = failWith;
    if (error != null) throw error;
    for (final r in rows) {
      final old = server[r.id];
      if (old != null && !r.updatedAt.isAfter(old.updatedAt)) continue; // el servidor ignora lo que no es más reciente
      server[r.id] = _stamped(r, _next());
    }
  }

  String _next() => DateTime.utc(2026, 11, 5, 12, 0, ++clock).toIso8601String();

  /// Algo que cambió en otro dispositivo.
  void remote(T row) => server[row.id] = _stamped(row, _next());

  @override
  Future<List<T>> pull(String? since) async {
    pulls++;
    final error = failWith;
    if (error != null) throw error;
    return [
      for (final r in server.values)
        if (since == null || DateTime.parse(r.syncedAt!).isAfter(DateTime.parse(since))) r,
    ];
  }
}

Reminder _stampReminder(Reminder r, String at) => Reminder(
      id: r.id,
      notifId: r.notifId,
      title: r.title,
      notes: r.notes,
      at: r.at,
      done: r.done,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
      deletedAt: r.deletedAt,
      syncedAt: at,
    );

CalendarEvent _stampEvent(CalendarEvent e, String at) => CalendarEvent(
      id: e.id,
      title: e.title,
      description: e.description,
      startsAt: e.startsAt,
      endsAt: e.endsAt,
      allDay: e.allDay,
      color: e.color,
      taskId: e.taskId,
      createdAt: e.createdAt,
      updatedAt: e.updatedAt,
      deletedAt: e.deletedAt,
      syncedAt: at,
    );

void main() {
  var now = DateTime.utc(2026, 11, 5, 12);
  var ids = 0;

  setUp(() {
    now = DateTime.utc(2026, 11, 5, 12);
    ids = 0;
  });

  group('recordatorios sincronizados', () {
    late MemoryReminderStore store;
    late FakeRowBackend<Reminder> backend;
    late FakeScheduler scheduler;
    late ReminderController c;

    setUp(() {
      store = MemoryReminderStore();
      backend = FakeRowBackend<Reminder>(_stampReminder);
      scheduler = FakeScheduler();
      c = ReminderController(store, scheduler, backend: backend, now: () => now, newId: () => 'r-${++ids}', retry: const Duration(hours: 1));
    });

    tearDown(() => c.dispose());

    test('un recordatorio nuevo sube a Supabase y deja de estar «por subir»', () async {
      await c.start();
      await c.add('Llamar', DateTime.utc(2026, 11, 6, 9));
      await c.sync();
      expect(backend.server['r-1']!.title, 'Llamar');
      expect(c.pending, 0);
      expect(c.syncState, SyncState.idle);
      expect(c.lastSync, isNotNull);
      expect((await store.load()).single.dirty, isFalse);
    });

    test('lo que se crea en la web (sin número de aviso) baja, y su aviso se programa', () async {
      await c.start();
      backend.remote(Reminder(id: 'web-1', notifId: 0, title: 'Desde la web', at: DateTime.utc(2026, 11, 7, 9), createdAt: now, updatedAt: now));
      await c.sync();
      final r = c.items.single;
      expect(r.title, 'Desde la web');
      expect(r.notifId, reminderNotifIdFor('web-1'));
      expect(scheduler.scheduled.keys, [reminderNotifIdFor('web-1')]);
    });

    test('un cambio más reciente de otro dispositivo gana; uno más viejo, no', () async {
      await c.start();
      final r = (await c.add('Llamar', DateTime.utc(2026, 11, 6, 9)))!;
      await c.sync();
      now = DateTime.utc(2026, 11, 5, 13);
      backend.remote(r.copyWith(title: 'Llamar a Ana', updatedAt: DateTime.utc(2026, 11, 5, 14)));
      await c.sync();
      expect(c.items.single.title, 'Llamar a Ana');
      backend.remote(r.copyWith(title: 'Viejo', updatedAt: DateTime.utc(2026, 11, 5, 10)));
      await c.sync();
      expect(c.items.single.title, 'Llamar a Ana');
    });

    test('borrar sube el borrado suave y lo borrado en otro sitio desaparece y cancela su aviso', () async {
      await c.start();
      final a = (await c.add('A', DateTime.utc(2026, 11, 8, 9)))!;
      final b = (await c.add('B', DateTime.utc(2026, 11, 9, 9)))!;
      await c.sync();
      await c.delete(a);
      await c.sync();
      expect(backend.server[a.id]!.deletedAt, isNotNull);
      expect(c.items.map((r) => r.title), ['B']);
      expect(scheduler.scheduled.containsKey(a.notifId), isFalse);
      now = DateTime.utc(2026, 11, 5, 15);
      backend.remote(b.copyWith(deletedAt: now, updatedAt: now));
      await c.sync();
      expect(c.items, isEmpty);
      expect(scheduler.scheduled.containsKey(b.notifId), isFalse);
    });

    test('sin conexión se guarda y queda «por subir»; al volver se sube', () async {
      await c.start();
      backend.failWith = const ChatException('Sin conexión', retryable: true);
      await c.add('Llamar', DateTime.utc(2026, 11, 6, 9));
      await c.sync();
      expect(c.syncState, SyncState.offline);
      expect(c.pending, 1);
      expect(c.items.single.title, 'Llamar');
      backend.failWith = null;
      await c.sync();
      expect(c.syncState, SyncState.idle);
      expect(c.pending, 0);
      expect(backend.server, isNotEmpty);
    });

    test('un error que no se arregla solo se enseña, sin reintentar', () async {
      await c.start();
      backend.failWith = const ChatException('Falta la tabla reminders en Supabase.', code: '42P01');
      await c.add('Llamar', DateTime.utc(2026, 11, 6, 9));
      await c.sync();
      expect(c.syncState, SyncState.error);
      expect(c.syncError, contains('reminders'));
    });

    test('pedir sincronizar mientras hay una en curso encadena otra al terminar (no se pierde el cambio)', () async {
      await c.start();
      backend.hold = Completer<void>();
      await c.add('Uno', DateTime.utc(2026, 11, 6, 9)); // empieza a subir y se queda esperando
      final first = c.sync();
      await c.add('Dos', DateTime.utc(2026, 11, 6, 10));
      backend.hold!.complete();
      backend.hold = null;
      await first;
      await c.sync();
      expect(backend.server.length, 2);
      expect(c.pending, 0);
    });

    test('lo guardado antes de sincronizar (sin hora de cambio) queda «por subir»', () async {
      final legacy = Reminder.fromJson({'id': 'v1', 'notif_id': 4, 'title': 'Viejo', 'notes': '', 'at': '2026-11-07T09:00:00Z', 'done': false, 'created_at': '2026-11-01T09:00:00Z'});
      expect(legacy.dirty, isTrue);
      expect(legacy.at, DateTime.utc(2026, 11, 7, 9));
      expect(legacy.updatedAt, DateTime.utc(2026, 11, 1, 9));
      store.items = [legacy];
      await c.start();
      await c.sync();
      expect(backend.server['v1']!.title, 'Viejo');
      expect(c.pending, 0);
    });

    test('sin Supabase solo es local: no falla ni intenta subir', () async {
      final local = ReminderController(MemoryReminderStore(), FakeScheduler(), now: () => now, newId: () => 'x');
      await local.start();
      await local.add('Solo aquí', DateTime.utc(2026, 11, 6, 9));
      await local.sync();
      expect(local.items.single.title, 'Solo aquí');
      expect(local.syncState, SyncState.idle);
      local.dispose();
    });

    test('el número de aviso es siempre el mismo para el mismo id y está en su rango', () {
      expect(reminderNotifIdFor('abc'), reminderNotifIdFor('abc'));
      expect(reminderNotifIdFor('abc'), isNot(reminderNotifIdFor('abd')));
      for (final id in ['a', 'b', 'c', '123e4567-e89b-12d3-a456-426614174000']) {
        final n = reminderNotifIdFor(id);
        expect(n, inInclusiveRange(1 << 20, (1 << 30) - 1));
      }
    });
  });

  group('eventos', () {
    late MemoryEventStore store;
    late FakeRowBackend<CalendarEvent> backend;
    late EventController c;

    setUp(() {
      store = MemoryEventStore();
      backend = FakeRowBackend<CalendarEvent>(_stampEvent);
      c = EventController(store, backend, now: () => now, newId: () => 'e-${++ids}', retry: const Duration(hours: 1));
    });

    tearDown(() => c.dispose());

    test('un evento nuevo se guarda, sube y sale por hora de inicio', () async {
      await c.start();
      await c.add('Cena', DateTime.utc(2026, 11, 6, 20), endsAt: DateTime.utc(2026, 11, 6, 22), color: '#ff5a1f');
      await c.add('Desayuno', DateTime.utc(2026, 11, 6, 8));
      await c.sync();
      expect(c.items.map((e) => e.title), ['Desayuno', 'Cena']);
      expect(backend.server['e-1']!.color, '#ff5a1f');
      expect(backend.server['e-1']!.endsAt, DateTime.utc(2026, 11, 6, 22));
      expect(c.pending, 0);
    });

    test('un título vacío no crea nada; editar sin título no guarda', () async {
      await c.start();
      expect(await c.add('  ', DateTime.utc(2026, 11, 6)), isNull);
      final e = (await c.add('Cena', DateTime.utc(2026, 11, 6, 20)))!;
      await c.update(e, title: ' ');
      expect(c.items.single.title, 'Cena');
    });

    test('mover un evento conserva lo que dura, y quitarle el fin lo deja sin fin', () async {
      await c.start();
      final e = (await c.add('Reunión', DateTime.utc(2026, 11, 6, 10), endsAt: DateTime.utc(2026, 11, 6, 11, 30)))!;
      await c.moveTo(e, DateTime.utc(2026, 11, 7, 15));
      expect(c.items.single.startsAt, DateTime.utc(2026, 11, 7, 15));
      expect(c.items.single.endsAt, DateTime.utc(2026, 11, 7, 16, 30));
      await c.update(c.items.single, endsAt: null);
      expect(c.items.single.endsAt, isNull);
    });

    test('cada cambio sube con una hora mayor que la anterior (el servidor ignora lo que no lo es)', () async {
      await c.start();
      final e = (await c.add('Cena', DateTime.utc(2026, 11, 6, 20)))!;
      await c.sync();
      await c.update(e, title: 'Cena con Ana'); // el reloj no avanzó: la hora de cambio igual sube
      await c.sync();
      expect(backend.server['e-1']!.title, 'Cena con Ana');
    });

    test('lo creado en la web baja con su color, y borrarlo aquí llega al servidor', () async {
      await c.start();
      backend.remote(CalendarEvent(id: 'w1', title: 'Boda', startsAt: DateTime.utc(2026, 11, 14), allDay: true, color: '#ff4fd8', createdAt: now, updatedAt: now));
      await c.sync();
      expect(c.items.single.title, 'Boda');
      expect(c.items.single.allDay, isTrue);
      expect(c.items.single.color, '#ff4fd8');
      await c.delete(c.items.single);
      await c.sync();
      expect(c.items, isEmpty);
      expect(backend.server['w1']!.deletedAt, isNotNull);
    });

    test('el JSON de un evento ida y vuelta, y un color raro no rompe', () {
      final e = CalendarEvent(id: 'a', title: 'T', startsAt: DateTime.utc(2026, 11, 6, 8), endsAt: DateTime.utc(2026, 11, 6, 9), color: '#35d4ff', createdAt: now, updatedAt: now, dirty: true);
      final back = CalendarEvent.fromJson(e.toLocalJson());
      expect(back.toJson(), e.toJson());
      expect(back.dirty, isTrue);
      final plain = CalendarEvent.fromJson({'id': 'b', 'title': 'T', 'starts_at': '2026-11-06T08:00:00Z', 'created_at': '2026-11-01T00:00:00Z', 'updated_at': '2026-11-01T00:00:00Z'});
      expect(plain.color, eventColors.first);
      expect(plain.allDay, isFalse);
    });

    test('guardado en las preferencias se lee igual, una cuenta no ve la de otra y lo dañado no rompe', () async {
      SharedPreferences.setMockInitialValues({});
      final e = CalendarEvent(id: 'a', title: 'T', startsAt: DateTime.utc(2026, 11, 6, 8), createdAt: now, updatedAt: now, dirty: true);
      final prefs = await PrefsEventStore.open('u1');
      await prefs.save([e]);
      await prefs.setCursor('2026-11-05T12:00:01.000Z');
      final again = await PrefsEventStore.open('u1');
      final back = (await again.load()).single;
      expect(back.toJson(), e.toJson());
      expect(back.dirty, isTrue);
      expect(await again.cursor(), '2026-11-05T12:00:01.000Z');
      expect(await (await PrefsEventStore.open('u2')).load(), isEmpty);
      SharedPreferences.setMockInitialValues({'events.u3': 'esto no es json'});
      expect(await (await PrefsEventStore.open('u3')).load(), isEmpty);
    });
  });
}

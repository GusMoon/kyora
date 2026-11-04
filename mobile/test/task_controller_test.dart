import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/chat_backend.dart';
import 'package:kyora_chat/data/task_backend.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/models/task.dart';
import 'package:kyora_chat/state/task_controller.dart';
import 'package:kyora_chat/util/task_format.dart';

/// Supabase de mentira: guarda las filas con la hora de servidor (`synced_at`) y descarta las escrituras más viejas que lo guardado,
/// como el trigger `sync_guard` del esquema.
class FakeTaskBackend implements TaskBackend {
  final Map<String, TaskItem> tasks = {};
  final Map<String, Tag> tags = {};
  final Map<String, TaskTag> links = {};
  ChatException? error;
  final List<TaskData> pushed = [];
  int pulls = 0;
  int _tick = 0;

  String _stamp() => DateTime.utc(2026, 11, 2, 12).add(Duration(seconds: ++_tick)).toIso8601String();

  @override
  Future<void> push(TaskData changes) async {
    if (error != null) throw error!;
    pushed.add(changes);
    for (final t in changes.tasks) {
      final old = tasks[t.id];
      if (old != null && !t.updatedAt.isAfter(old.updatedAt)) continue;
      tasks[t.id] = TaskItem.fromJson({...t.toJson(), 'synced_at': _stamp()});
    }
    for (final t in changes.tags) {
      final old = tags[t.id];
      if (old != null && !t.updatedAt.isAfter(old.updatedAt)) continue;
      tags[t.id] = Tag.fromJson({...t.toJson(), 'synced_at': _stamp()});
    }
    for (final l in changes.links) {
      final old = links[l.key];
      if (old != null && !l.updatedAt.isAfter(old.updatedAt)) continue;
      links[l.key] = TaskTag.fromJson({...l.toJson(), 'synced_at': _stamp()});
    }
  }

  @override
  Future<TaskData> pull({String? tasksSince, String? tagsSince, String? linksSince}) async {
    if (error != null) throw error!;
    pulls++;
    bool after(String? row, String? since) => since == null || DateTime.parse(row!).isAfter(DateTime.parse(since));
    return TaskData(
      tasks: [for (final t in tasks.values) if (after(t.syncedAt, tasksSince)) t],
      tags: [for (final t in tags.values) if (after(t.syncedAt, tagsSince)) t],
      links: [for (final l in links.values) if (after(l.syncedAt, linksSince)) l],
    );
  }

  /// Un cambio hecho desde otro dispositivo.
  void remoteTask(TaskItem t) => tasks[t.id] = TaskItem.fromJson({...t.toJson(), 'synced_at': _stamp()});
}

void main() {
  late MemoryTaskStore store;
  late FakeTaskBackend backend;
  late TaskController c;
  var minute = 0;
  var ids = 0;
  final base = DateTime.utc(2026, 11, 2, 9);

  setUp(() {
    minute = 0;
    ids = 0;
    store = MemoryTaskStore();
    backend = FakeTaskBackend();
    c = TaskController(store, backend, now: () => base.add(Duration(minutes: ++minute)), newId: () => 'id-${++ids}', retry: const Duration(hours: 1));
  });

  tearDown(() => c.dispose());

  group('guardar primero en el teléfono', () {
    test('una tarea nueva se ve y se guarda aunque no haya internet, y queda por subir', () async {
      backend.error = const ChatException('Sin conexión con Supabase', retryable: true);
      final task = await c.add('  Comprar pan  ');
      await c.sync();
      expect(task!.name, 'Comprar pan');
      expect(c.roots().map((t) => t.name), ['Comprar pan']);
      expect((await store.load()).tasks.single.name, 'Comprar pan');
      expect(c.pending, 1);
      expect(c.syncState, SyncState.offline);
      expect(c.syncError, 'Sin conexión con Supabase');
      expect(backend.tasks, isEmpty);
    });

    test('al volver la red sube lo pendiente y ya no queda nada por subir', () async {
      backend.error = const ChatException('Sin conexión con Supabase', retryable: true);
      await c.add('Uno');
      await c.add('Dos');
      await c.sync();
      expect(c.pending, 2);
      backend.error = null;
      await c.sync();
      expect(backend.tasks.values.map((t) => t.name), unorderedEquals(['Uno', 'Dos']));
      expect(c.pending, 0);
      expect(c.syncState, SyncState.idle);
      expect(c.syncError, isNull);
      expect(c.lastSync, isNotNull);
    });

    test('con red, cada cambio sube solo, sin pulsar nada', () async {
      await c.add('Uno');
      await c.sync(); // espera a que termine la subida que lanzó el cambio
      expect(backend.tasks.values.single.name, 'Uno');
      expect(c.pending, 0);
    });

    test('un error que no tiene remedio se enseña y no se confunde con estar sin conexión', () async {
      backend.error = const ChatException('Falta la parte de tareas: vuelve a ejecutar supabase/schema.sql en Supabase.');
      await c.add('Uno');
      await c.sync();
      expect(c.syncState, SyncState.error);
      expect(c.syncError, contains('schema.sql'));
      expect(c.pending, 1);
    });

    test('lo que se subió no se vuelve a subir', () async {
      await c.add('Uno');
      await c.sync();
      final before = backend.pushed.length;
      await c.sync();
      expect(backend.pushed.length, before);
    });

    test('lo editado mientras se sube no se da por subido', () async {
      final task = (await c.add('Uno'))!;
      await c.sync();
      await store.put(TaskData(tasks: [c.byId(task.id)!.copyWith(name: 'Uno editado', updatedAt: DateTime.utc(2026, 11, 3))]));
      await store.markClean(TaskData(tasks: [task])); // la subida vieja termina tarde: su hora ya no es la de lo guardado
      expect(await store.dirtyCount(), 1);
    });
  });

  group('tareas', () {
    test('usan el mismo modelo que el escritorio: estados, finalizar pone la hora y reabrir la quita', () async {
      final t = (await c.add('Informe', description: ' mensual ', due: DateTime.utc(2026, 11, 5, 18), expectedMin: 90))!;
      expect(t.status, TaskStatus.pending);
      expect(t.description, 'mensual');
      await c.setStatus(t, TaskStatus.doing);
      expect(c.byId(t.id)!.status, TaskStatus.doing);
      await c.setStatus(c.byId(t.id)!, TaskStatus.done);
      expect(c.byId(t.id)!.finished, isNotNull);
      expect(c.roots(active: true), isEmpty);
      expect(c.count(null), 0);
      expect(c.count(TaskStatus.done), 1);
      await c.toggleDone(c.byId(t.id)!);
      expect(c.byId(t.id)!.status, TaskStatus.pending);
      expect(c.byId(t.id)!.finished, isNull);
    });

    test('un nombre vacío no crea nada y no se puede dejar sin nombre', () async {
      expect(await c.add('   '), isNull);
      final t = (await c.add('Uno'))!;
      await c.update(t, name: '  ');
      expect(c.byId(t.id)!.name, 'Uno');
    });

    test('update guarda solo si algo cambió y siempre con una hora más nueva', () async {
      final t = (await c.add('Uno'))!;
      final before = c.byId(t.id)!.updatedAt;
      await c.update(c.byId(t.id)!, name: 'Uno'); // igual: nada
      expect(c.byId(t.id)!.updatedAt, before);
      await c.update(c.byId(t.id)!, name: 'Dos', expectedMin: 30, due: DateTime.utc(2026, 11, 9, 8));
      final after = c.byId(t.id)!;
      expect(after.name, 'Dos');
      expect(after.expectedMin, 30);
      expect(after.due, DateTime.utc(2026, 11, 9, 8));
      expect(after.updatedAt.isAfter(before), isTrue);
      await c.update(after, due: null, expectedMin: null);
      expect(c.byId(t.id)!.due, isNull);
      expect(c.byId(t.id)!.expectedMin, isNull);
    });

    test('si el reloj va hacia atrás, el cambio igualmente queda más nuevo que el anterior (Supabase no lo toma por viejo)', () async {
      var t = DateTime.utc(2026, 11, 2, 10);
      final slow = TaskController(MemoryTaskStore(), backend, now: () => t, newId: () => 'x-${++ids}', retry: const Duration(hours: 1));
      addTearDown(slow.dispose);
      final task = (await slow.add('Uno'))!;
      t = DateTime.utc(2026, 11, 2, 9); // el reloj se atrasa
      await slow.setStatus(task, TaskStatus.doing);
      expect(slow.byId(task.id)!.updatedAt.isAfter(task.updatedAt), isTrue);
    });

    test('las subtareas van en su orden, con su avance, y solo hay un nivel', () async {
      final t = (await c.add('Mudanza'))!;
      final a = (await c.add('Cajas', parentId: t.id))!;
      final b = (await c.add('Camión', parentId: t.id))!;
      expect(c.subtasksOf(t.id).map((s) => s.name), ['Cajas', 'Camión']);
      expect(c.roots().map((r) => r.name), ['Mudanza']); // las subtareas no salen en la lista principal
      await c.toggleDone(a);
      expect(c.progress(c.byId(t.id)!), (done: 1, total: 2));
      await expectLater(c.add('Nieta', parentId: b.id), throwsStateError);
    });

    test('borrar una tarea borra sus subtareas y marcas de etiqueta (borrado suave) y el borrado sube', () async {
      final t = (await c.add('Mudanza'))!;
      final s = (await c.add('Cajas', parentId: t.id))!;
      final tag = (await c.createTag('Casa'))!;
      await c.toggleTag(t.id, tag);
      await c.sync();
      await c.delete(c.byId(t.id)!);
      await c.sync();
      expect(c.byId(t.id), isNull);
      expect(c.byId(s.id), isNull);
      expect(c.tagsOf(t.id), isEmpty);
      expect(backend.tasks[t.id]!.deletedAt, isNotNull); // llegó a Supabase como borrado suave, no desapareció
      expect(backend.tasks[s.id]!.deletedAt, isNotNull);
      expect(backend.links['${t.id}|${tag.id}']!.deletedAt, isNotNull);
      expect(c.pending, 0);
    });

    test('el orden: sin finalizar primero, las que tienen entrega (la más cercana antes), luego por creación', () async {
      await c.add('Sin fecha vieja');
      await c.add('Lejana', due: DateTime.utc(2026, 12, 1));
      await c.add('Cercana', due: DateTime.utc(2026, 11, 3));
      final done = (await c.add('Hecha', due: DateTime.utc(2026, 11, 1)))!;
      await c.setStatus(done, TaskStatus.done);
      await c.add('Sin fecha nueva');
      expect(c.roots().map((t) => t.name), ['Cercana', 'Lejana', 'Sin fecha vieja', 'Sin fecha nueva', 'Hecha']);
      expect(c.roots(status: TaskStatus.done).map((t) => t.name), ['Hecha']);
    });
  });

  group('etiquetas', () {
    test('una etiqueta con el mismo nombre (sin mayúsculas) es la misma; los colores se reparten por turno', () async {
      final a = (await c.createTag('Casa'))!;
      final b = (await c.createTag('casa'))!;
      expect(b.id, a.id);
      final other = (await c.createTag('Trabajo'))!;
      expect(other.color, isNot(a.color));
      expect(await c.createTag('  '), isNull);
    });

    test('se pone y se quita de una tarea, y se puede volver a poner', () async {
      final t = (await c.add('Uno'))!;
      final tag = (await c.createTag('Casa'))!;
      await c.toggleTag(t.id, tag);
      expect(c.tagsOf(t.id).map((x) => x.name), ['Casa']);
      expect(c.roots(tagId: tag.id).map((x) => x.name), ['Uno']);
      await c.toggleTag(t.id, tag);
      expect(c.tagsOf(t.id), isEmpty);
      await c.sync();
      await c.toggleTag(t.id, tag); // otra vez, ya con la quitada subida
      await c.sync();
      expect(c.tagsOf(t.id).map((x) => x.name), ['Casa']);
      expect(backend.links['${t.id}|${tag.id}']!.deletedAt, isNull);
    });

    test('borrar la etiqueta la quita de todas las tareas', () async {
      final a = (await c.add('Uno'))!;
      final b = (await c.add('Dos'))!;
      final tag = (await c.createTag('Casa'))!;
      await c.toggleTag(a.id, tag);
      await c.toggleTag(b.id, tag);
      await c.deleteTag(tag);
      expect(c.tags, isEmpty);
      expect(c.tagsOf(a.id), isEmpty);
      expect(c.tagsOf(b.id), isEmpty);
    });
  });

  group('sincronizar con Supabase', () {
    test('baja lo que se hizo en otro dispositivo y recuerda hasta dónde leyó', () async {
      backend.remoteTask(TaskItem(id: 'otro-1', name: 'Desde la PC', createdAt: base, updatedAt: base));
      await c.sync();
      expect(c.roots().map((t) => t.name), ['Desde la PC']);
      expect(await store.cursor('tasks'), isNotNull);
      expect(c.pending, 0); // lo que baja no cuenta como pendiente de subir
      final pulls = backend.pulls;
      await c.sync();
      expect(backend.pulls, pulls + 1);
      expect((await store.load()).tasks.length, 1); // no se duplica
    });

    test('si dos dispositivos cambian lo mismo gana el más reciente: el de Supabase', () async {
      final t = (await c.add('Uno'))!;
      await c.sync();
      backend.remoteTask(backend.tasks[t.id]!.copyWith(name: 'Remoto', updatedAt: base.add(const Duration(days: 1))));
      await c.sync();
      expect(c.byId(t.id)!.name, 'Remoto');
    });

    test('si dos dispositivos cambian lo mismo gana el más reciente: el de aquí, aunque llegue después', () async {
      final t = (await c.add('Uno'))!;
      await c.sync();
      backend.error = const ChatException('Sin conexión', retryable: true);
      await c.update(c.byId(t.id)!, name: 'Local sin subir'); // sin red: queda por subir
      backend.error = null;
      backend.remoteTask(backend.tasks[t.id]!.copyWith(name: 'Remoto viejo', updatedAt: base.add(const Duration(seconds: 1))));
      await c.sync();
      expect(c.byId(t.id)!.name, 'Local sin subir');
      expect(backend.tasks[t.id]!.name, 'Local sin subir'); // y lo suyo llegó a Supabase
      expect(c.pending, 0);
    });

    test('una tarea borrada en otro dispositivo desaparece de aquí', () async {
      final t = (await c.add('Uno'))!;
      await c.sync();
      backend.remoteTask(backend.tasks[t.id]!.copyWith(deletedAt: base.add(const Duration(days: 1)), updatedAt: base.add(const Duration(days: 1))));
      await c.sync();
      expect(c.byId(t.id), isNull);
    });

    test('start carga lo guardado y se pone al día sin esperar', () async {
      final t = TaskItem(id: 'guardada', name: 'Ya estaba', createdAt: base, updatedAt: base);
      await store.put(TaskData(tasks: [t]));
      final fresh = TaskController(store, backend, retry: const Duration(hours: 1));
      addTearDown(fresh.dispose);
      await fresh.start();
      expect(fresh.loaded, isTrue);
      expect(fresh.roots().map((x) => x.name), ['Ya estaba']);
      await fresh.sync();
      expect(backend.tasks['guardada'], isNotNull); // lo que quedó pendiente de la vez anterior sube
    });

    test('varias llamadas a la vez no se pisan: una se pone en cola', () async {
      await Future.wait([c.add('Uno'), c.add('Dos'), c.add('Tres')]);
      await c.sync();
      await c.sync();
      expect(backend.tasks.length, 3);
      expect(c.pending, 0);
    });
  });

  group('formatos', () {
    test('el tiempo esperado se entiende en varias formas', () {
      expect(parseMinutes('90'), 90);
      expect(parseMinutes('1:30'), 90);
      expect(parseMinutes('1h30'), 90);
      expect(parseMinutes('1 h 30 min'), 90);
      expect(parseMinutes('45 min'), 45);
      expect(parseMinutes('1,5 h'), 90);
      expect(parseMinutes('  '), isNull);
      expect(() => parseMinutes('mucho'), throwsFormatException);
      expect(minutesLabel(90), '1 h 30 min');
      expect(minutesLabel(45), '45 min');
      expect(minutesLabel(120), '2 h');
      expect(minutesLabel(null), '');
    });

    test('la entrega se dice como en el escritorio', () {
      final now = DateTime(2026, 11, 2, 10);
      expect(dueLabel(DateTime(2026, 11, 2, 18).toUtc(), now), 'Hoy 18:00');
      expect(dueLabel(DateTime(2026, 11, 3, 9, 30).toUtc(), now), 'Mañana 09:30');
      expect(dueLabel(DateTime(2026, 11, 1, 17).toUtc(), now), 'Ayer 17:00');
      expect(dueLabel(DateTime(2026, 11, 6, 18).toUtc(), now), 'vie 6 nov 18:00');
      expect(colorFromHex('#E3B25A').toARGB32(), 0xFFE3B25A);
    });
  });
}

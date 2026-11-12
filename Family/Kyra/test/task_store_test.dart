import 'package:flutter_test/flutter_test.dart';
import 'package:kyora_chat/data/task_store.dart';
import 'package:kyora_chat/models/task.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final t0 = DateTime.utc(2026, 11, 2, 9);

TaskItem task(String id, {String name = 'Tarea', DateTime? updated, String? parent, DateTime? deleted, String? synced}) => TaskItem(
      id: id,
      name: name,
      parentId: parent,
      createdAt: t0,
      updatedAt: updated ?? t0,
      deletedAt: deleted,
      syncedAt: synced,
    );

/// La misma batería para el almacén real (SQLite) y el de memoria: los dos tienen que comportarse igual.
void storeTests(String label, Future<TaskStore> Function() open) {
  group(label, () {
    late TaskStore store;

    setUp(() async => store = await open());
    tearDown(() => store.close());

    test('guarda y devuelve todos los campos de una tarea, sus etiquetas y sus marcas', () async {
      final full = TaskItem(
        id: 'a',
        parentId: 'p',
        position: 3,
        name: 'Informe',
        description: 'mensual',
        status: TaskStatus.review,
        expectedMin: 90,
        realS: 600,
        timerStarted: t0,
        due: DateTime.utc(2026, 11, 5, 18),
        finished: DateTime.utc(2026, 11, 6),
        createdAt: t0,
        updatedAt: t0.add(const Duration(minutes: 1)),
      );
      await store.put(TaskData(
        tasks: [full],
        tags: [Tag(id: 'g', name: 'Casa', color: '#E3B25A', updatedAt: t0)],
        links: [TaskTag(taskId: 'a', tagId: 'g', updatedAt: t0)],
      ));
      final data = await store.load();
      final back = data.tasks.single;
      expect(back.toJson(), full.toJson());
      expect(back.status, TaskStatus.review);
      expect(data.tags.single.name, 'Casa');
      expect(data.tags.single.color, '#E3B25A');
      expect(data.links.single.key, 'a|g');
    });

    test('lo borrado no se ve pero sigue ahí para subir su borrado; lo guardado queda por subir hasta que se sube', () async {
      await store.put(TaskData(tasks: [task('a'), task('b', deleted: t0)]));
      expect((await store.load()).tasks.map((t) => t.id), ['a']);
      expect((await store.dirty()).tasks.map((t) => t.id), unorderedEquals(['a', 'b']));
      expect(await store.dirtyCount(), 2);
      await store.markClean(TaskData(tasks: [task('a'), task('b', deleted: t0)]));
      expect(await store.dirtyCount(), 0);
    });

    test('markClean no limpia lo que cambió después de subirlo', () async {
      await store.put(TaskData(tasks: [task('a')]));
      final uploaded = (await store.dirty()).tasks;
      await store.put(TaskData(tasks: [task('a', name: 'Editada', updated: t0.add(const Duration(minutes: 5)))]));
      await store.markClean(TaskData(tasks: uploaded));
      expect(await store.dirtyCount(), 1);
      expect((await store.load()).tasks.single.name, 'Editada');
    });

    test('lo que llega de Supabase entra limpio; una fila local con cambios por subir más nueva no se pisa', () async {
      await store.put(TaskData(tasks: [task('local', name: 'Mía', updated: t0.add(const Duration(minutes: 10)))]));
      await store.applyRemote(TaskData(tasks: [
        task('nueva', name: 'De fuera', synced: '2026-11-02T10:00:00.000Z'),
        task('local', name: 'Vieja de fuera', updated: t0.add(const Duration(minutes: 1))),
      ]));
      final names = {for (final t in (await store.load()).tasks) t.id: t.name};
      expect(names, {'nueva': 'De fuera', 'local': 'Mía'});
      expect((await store.dirty()).tasks.map((t) => t.id), ['local']); // solo la mía sigue por subir
    });

    test('una fila de Supabase más nueva pisa la local aunque tuviera cambios por subir', () async {
      await store.put(TaskData(tasks: [task('a', name: 'Mía')]));
      await store.applyRemote(TaskData(tasks: [task('a', name: 'Más nueva', updated: t0.add(const Duration(hours: 1)))]));
      expect((await store.load()).tasks.single.name, 'Más nueva');
      expect(await store.dirtyCount(), 0);
    });

    test('un borrado que llega de fuera quita la tarea de la vista', () async {
      await store.put(TaskData(tasks: [task('a')]));
      await store.markClean(TaskData(tasks: [task('a')]));
      await store.applyRemote(TaskData(tasks: [task('a', updated: t0.add(const Duration(hours: 1)), deleted: t0.add(const Duration(hours: 1)))]));
      expect((await store.load()).tasks, isEmpty);
    });

    test('el punto de partida de cada tabla se recuerda por separado', () async {
      expect(await store.cursor('tasks'), isNull);
      await store.setCursor('tasks', '2026-11-02T10:00:00.000Z');
      await store.setCursor('tags', '2026-11-02T11:00:00.000Z');
      await store.setCursor('tasks', '2026-11-02T12:00:00.000Z');
      expect(await store.cursor('tasks'), '2026-11-02T12:00:00.000Z');
      expect(await store.cursor('tags'), '2026-11-02T11:00:00.000Z');
      expect(await store.cursor('task_tags'), isNull);
    });
  });
}

void main() {
  sqfliteFfiInit();
  storeTests('almacén en memoria', () async => MemoryTaskStore());
  storeTests('SQLite', () => SqliteTaskStore.open('prueba', path: inMemoryDatabasePath, factory: databaseFactoryFfi));

  test('SQLite recuerda lo guardado al cerrar y volver a abrir el archivo (una base por cuenta)', () async {
    final dir = await databaseFactoryFfi.getDatabasesPath();
    final path = '$dir/tareas_prueba_${DateTime.now().microsecondsSinceEpoch}.db';
    final first = await SqliteTaskStore.open('a', path: path, factory: databaseFactoryFfi);
    await first.put(TaskData(tasks: [task('a', name: 'Sobrevive')]));
    await first.setCursor('tasks', '2026-11-02T10:00:00.000Z');
    await first.close();
    final again = await SqliteTaskStore.open('a', path: path, factory: databaseFactoryFfi);
    addTearDown(() async {
      await again.close();
      await databaseFactoryFfi.deleteDatabase(path);
    });
    expect((await again.load()).tasks.single.name, 'Sobrevive');
    expect(await again.dirtyCount(), 1); // sigue por subir
    expect(await again.cursor('tasks'), '2026-11-02T10:00:00.000Z');
  });
}

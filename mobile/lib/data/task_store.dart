import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/task.dart';

/// Dónde viven las tareas en el teléfono. Todo cambio se guarda aquí primero (con la marca «por subir»); la sincronización con
/// Supabase lo sube cuando hay internet. Se guardan también las filas borradas (borrado suave): así el borrado llega a Supabase.
abstract class TaskStore {
  /// Lo que se ve: todo lo que no está borrado.
  Future<TaskData> load();

  /// Guarda cambios hechos aquí (nuevos, editados o borrados suaves) y los deja marcados «por subir».
  Future<void> put(TaskData changes);

  /// Lo que falta por subir.
  Future<TaskData> dirty();

  /// Quita la marca «por subir» de lo que se subió, salvo lo que cambió mientras tanto (su `updatedAt` ya no es el que se subió).
  Future<void> markClean(TaskData uploaded);

  /// Cuántas filas faltan por subir.
  Future<int> dirtyCount();

  /// Aplica lo que llegó de Supabase: una fila local solo se sustituye si la de Supabase es más reciente o la local no tiene
  /// cambios por subir.
  Future<void> applyRemote(TaskData remote);

  /// La última hora de servidor leída de cada tabla (`tasks`, `tags`, `task_tags`), para pedir solo las novedades.
  Future<String?> cursor(String table);
  Future<void> setCursor(String table, String value);

  Future<void> close();
}

/// ¿Gana la fila de Supabase sobre la local? Si es más reciente, sí; si es igual o más vieja, solo cuando la local no tiene
/// cambios por subir (entonces es la misma).
bool remoteWins({required DateTime? local, required bool localDirty, required DateTime remote}) {
  if (local == null) return true;
  if (remote.isAfter(local)) return true;
  return !localDirty && !remote.isBefore(local);
}

/// El almacén en memoria: para las pruebas y como respaldo si el teléfono no deja abrir la base.
class MemoryTaskStore implements TaskStore {
  final Map<String, TaskItem> _tasks = {};
  final Map<String, Tag> _tags = {};
  final Map<String, TaskTag> _links = {};
  final Set<String> _dirtyTasks = {};
  final Set<String> _dirtyTags = {};
  final Set<String> _dirtyLinks = {};
  final Map<String, String> _cursors = {};

  @override
  Future<TaskData> load() async => TaskData(
        tasks: [for (final t in _tasks.values) if (!t.isDeleted) t],
        tags: [for (final t in _tags.values) if (t.deletedAt == null) t],
        links: [for (final l in _links.values) if (l.deletedAt == null) l],
      );

  @override
  Future<void> put(TaskData changes) async {
    for (final t in changes.tasks) {
      _tasks[t.id] = t;
      _dirtyTasks.add(t.id);
    }
    for (final t in changes.tags) {
      _tags[t.id] = t;
      _dirtyTags.add(t.id);
    }
    for (final l in changes.links) {
      _links[l.key] = l;
      _dirtyLinks.add(l.key);
    }
  }

  @override
  Future<TaskData> dirty() async => TaskData(
        tasks: [for (final id in _dirtyTasks) _tasks[id]!],
        tags: [for (final id in _dirtyTags) _tags[id]!],
        links: [for (final key in _dirtyLinks) _links[key]!],
      );

  @override
  Future<void> markClean(TaskData uploaded) async {
    for (final t in uploaded.tasks) {
      if (_tasks[t.id]?.updatedAt == t.updatedAt) _dirtyTasks.remove(t.id);
    }
    for (final t in uploaded.tags) {
      if (_tags[t.id]?.updatedAt == t.updatedAt) _dirtyTags.remove(t.id);
    }
    for (final l in uploaded.links) {
      if (_links[l.key]?.updatedAt == l.updatedAt) _dirtyLinks.remove(l.key);
    }
  }

  @override
  Future<int> dirtyCount() async => _dirtyTasks.length + _dirtyTags.length + _dirtyLinks.length;

  @override
  Future<void> applyRemote(TaskData remote) async {
    for (final t in remote.tasks) {
      if (remoteWins(local: _tasks[t.id]?.updatedAt, localDirty: _dirtyTasks.contains(t.id), remote: t.updatedAt)) {
        _tasks[t.id] = t;
        _dirtyTasks.remove(t.id);
      }
    }
    for (final t in remote.tags) {
      if (remoteWins(local: _tags[t.id]?.updatedAt, localDirty: _dirtyTags.contains(t.id), remote: t.updatedAt)) {
        _tags[t.id] = t;
        _dirtyTags.remove(t.id);
      }
    }
    for (final l in remote.links) {
      if (remoteWins(local: _links[l.key]?.updatedAt, localDirty: _dirtyLinks.contains(l.key), remote: l.updatedAt)) {
        _links[l.key] = l;
        _dirtyLinks.remove(l.key);
      }
    }
  }

  @override
  Future<String?> cursor(String table) async => _cursors[table];

  @override
  Future<void> setCursor(String table, String value) async => _cursors[table] = value;

  @override
  Future<void> close() async {}
}

/// El almacén real: una base SQLite en el teléfono, una por cuenta (así al cambiar de cuenta no se mezclan las tareas).
class SqliteTaskStore implements TaskStore {
  SqliteTaskStore._(this._db);

  final Database _db;

  /// Abre (o crea) la base de esa cuenta. `path` solo lo usan las pruebas (`inMemoryDatabasePath`).
  static Future<SqliteTaskStore> open(String userId, {String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final file = path ?? p.join(await f.getDatabasesPath(), 'tareas_$userId.db');
    final db = await f.openDatabase(
      file,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) => _create(db)),
    );
    return SqliteTaskStore._(db);
  }

  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE tasks (
        id TEXT PRIMARY KEY,
        parent_id TEXT,
        position INTEGER NOT NULL DEFAULT 0,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending',
        expected_min INTEGER,
        real_s INTEGER NOT NULL DEFAULT 0,
        timer_started TEXT,
        due TEXT,
        finished TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('CREATE INDEX tasks_parent ON tasks(parent_id, position)');
    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE task_tags (
        task_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (task_id, tag_id)
      )''');
    await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  static Map<String, Object?> _row(Map<String, Object?> json, {required bool dirty}) => {...json, 'dirty': dirty ? 1 : 0};

  static Map<String, Object?> _clean(Map<String, Object?> row) => {...row}..remove('dirty');

  @override
  Future<TaskData> load() async => TaskData(
        tasks: [for (final r in await _db.query('tasks', where: 'deleted_at IS NULL')) TaskItem.fromJson(_clean(r))],
        tags: [for (final r in await _db.query('tags', where: 'deleted_at IS NULL')) Tag.fromJson(_clean(r))],
        links: [for (final r in await _db.query('task_tags', where: 'deleted_at IS NULL')) TaskTag.fromJson(_clean(r))],
      );

  @override
  Future<void> put(TaskData changes) async {
    final batch = _db.batch();
    for (final t in changes.tasks) {
      batch.insert('tasks', _row(t.toJson(), dirty: true), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final t in changes.tags) {
      batch.insert('tags', _row(t.toJson(), dirty: true), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final l in changes.links) {
      batch.insert('task_tags', _row(l.toJson(), dirty: true), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<TaskData> dirty() async => TaskData(
        tasks: [for (final r in await _db.query('tasks', where: 'dirty = 1')) TaskItem.fromJson(_clean(r))],
        tags: [for (final r in await _db.query('tags', where: 'dirty = 1')) Tag.fromJson(_clean(r))],
        links: [for (final r in await _db.query('task_tags', where: 'dirty = 1')) TaskTag.fromJson(_clean(r))],
      );

  @override
  Future<void> markClean(TaskData uploaded) async {
    final batch = _db.batch();
    for (final t in uploaded.tasks) {
      batch.update('tasks', {'dirty': 0}, where: 'id = ? AND updated_at = ?', whereArgs: [t.id, t.updatedAt.toUtc().toIso8601String()]);
    }
    for (final t in uploaded.tags) {
      batch.update('tags', {'dirty': 0}, where: 'id = ? AND updated_at = ?', whereArgs: [t.id, t.updatedAt.toUtc().toIso8601String()]);
    }
    for (final l in uploaded.links) {
      batch.update('task_tags', {'dirty': 0}, where: 'task_id = ? AND tag_id = ? AND updated_at = ?', whereArgs: [l.taskId, l.tagId, l.updatedAt.toUtc().toIso8601String()]);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<int> dirtyCount() async {
    var total = 0;
    for (final table in ['tasks', 'tags', 'task_tags']) {
      total += Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM $table WHERE dirty = 1')) ?? 0;
    }
    return total;
  }

  Future<Map<String, Object?>?> _find(Transaction txn, String table, String where, List<Object?> args) async {
    final rows = await txn.query(table, where: where, whereArgs: args, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  bool _wins(Map<String, Object?>? local, DateTime remote) => remoteWins(
        local: local == null ? null : DateTime.parse(local['updated_at']! as String),
        localDirty: local != null && local['dirty'] == 1,
        remote: remote,
      );

  @override
  Future<void> applyRemote(TaskData remote) async {
    await _db.transaction((txn) async {
      for (final t in remote.tasks) {
        if (_wins(await _find(txn, 'tasks', 'id = ?', [t.id]), t.updatedAt)) {
          await txn.insert('tasks', _row(t.toJson(), dirty: false), conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      for (final t in remote.tags) {
        if (_wins(await _find(txn, 'tags', 'id = ?', [t.id]), t.updatedAt)) {
          await txn.insert('tags', _row(t.toJson(), dirty: false), conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      for (final l in remote.links) {
        if (_wins(await _find(txn, 'task_tags', 'task_id = ? AND tag_id = ?', [l.taskId, l.tagId]), l.updatedAt)) {
          await txn.insert('task_tags', _row(l.toJson(), dirty: false), conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  @override
  Future<String?> cursor(String table) async {
    final rows = await _db.query('meta', where: 'key = ?', whereArgs: ['cursor.$table']);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> setCursor(String table, String value) async {
    await _db.insert('meta', {'key': 'cursor.$table', 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> close() => _db.close();
}

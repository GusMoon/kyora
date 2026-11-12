import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/habit.dart';
import 'task_store.dart' show remoteWins;

/// Dónde viven los hábitos en el teléfono. Igual que las tareas: todo cambio se guarda aquí primero, con la marca «por subir», y la
/// sincronización lo sube a Supabase cuando hay internet. Se guardan también los hábitos borrados (borrado suave).
abstract class HabitStore {
  /// Todo, también los hábitos borrados (hacen falta para cancelar sus avisos).
  Future<HabitData> load();

  /// Guarda cambios hechos aquí y los deja marcados «por subir».
  Future<void> put(HabitData changes);

  /// Lo que falta por subir.
  Future<HabitData> dirty();

  /// Quita la marca «por subir» de lo que se subió, salvo lo que cambió mientras tanto.
  Future<void> markClean(HabitData uploaded);

  Future<int> dirtyCount();

  /// Aplica lo que llegó de Supabase (ver `remoteWins`).
  Future<void> applyRemote(HabitData remote);

  /// La última hora de servidor leída de cada tabla (`habits`, `habit_checks`).
  Future<String?> cursor(String table);
  Future<void> setCursor(String table, String value);

  Future<void> close();
}

/// El almacén en memoria: para las pruebas y como respaldo si el teléfono no deja abrir la base.
class MemoryHabitStore implements HabitStore {
  final Map<String, Habit> _habits = {};
  final Map<String, HabitCheck> _checks = {};
  final Set<String> _dirtyHabits = {};
  final Set<String> _dirtyChecks = {};
  final Map<String, String> _cursors = {};

  @override
  Future<HabitData> load() async => HabitData(habits: _habits.values.toList(), checks: _checks.values.toList());

  @override
  Future<void> put(HabitData changes) async {
    for (final h in changes.habits) {
      _habits[h.id] = h;
      _dirtyHabits.add(h.id);
    }
    for (final c in changes.checks) {
      _checks[c.key] = c;
      _dirtyChecks.add(c.key);
    }
  }

  @override
  Future<HabitData> dirty() async => HabitData(
        habits: [for (final id in _dirtyHabits) _habits[id]!],
        checks: [for (final key in _dirtyChecks) _checks[key]!],
      );

  @override
  Future<void> markClean(HabitData uploaded) async {
    for (final h in uploaded.habits) {
      if (_habits[h.id]?.updatedAt == h.updatedAt) _dirtyHabits.remove(h.id);
    }
    for (final c in uploaded.checks) {
      if (_checks[c.key]?.updatedAt == c.updatedAt) _dirtyChecks.remove(c.key);
    }
  }

  @override
  Future<int> dirtyCount() async => _dirtyHabits.length + _dirtyChecks.length;

  @override
  Future<void> applyRemote(HabitData remote) async {
    for (final h in remote.habits) {
      if (remoteWins(local: _habits[h.id]?.updatedAt, localDirty: _dirtyHabits.contains(h.id), remote: h.updatedAt)) {
        _habits[h.id] = h;
        _dirtyHabits.remove(h.id);
      }
    }
    for (final c in remote.checks) {
      if (remoteWins(local: _checks[c.key]?.updatedAt, localDirty: _dirtyChecks.contains(c.key), remote: c.updatedAt)) {
        _checks[c.key] = c;
        _dirtyChecks.remove(c.key);
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

class SqliteHabitStore implements HabitStore {
  SqliteHabitStore._(this._db);

  final Database _db;

  /// Abre (o crea) la base de esa cuenta. `path` solo lo usan las pruebas (`inMemoryDatabasePath`).
  static Future<SqliteHabitStore> open(String userId, {String? path, DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final file = path ?? p.join(await f.getDatabasesPath(), 'habitos_$userId.db');
    final db = await f.openDatabase(file, options: OpenDatabaseOptions(version: 1, onCreate: (db, _) => _create(db)));
    return SqliteHabitStore._(db);
  }

  static Future<void> _create(Database db) async {
    await db.execute('''
      CREATE TABLE habits (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        weekdays INTEGER NOT NULL DEFAULT 127,
        remind_at INTEGER,
        position INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        dirty INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE habit_checks (
        habit_id TEXT NOT NULL,
        day TEXT NOT NULL,
        done INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (habit_id, day)
      )''');
    await db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  }

  static Map<String, Object?> _habitRow(Habit h, {required bool dirty}) => {...h.toJson(), 'dirty': dirty ? 1 : 0};

  static Map<String, Object?> _checkRow(HabitCheck c, {required bool dirty}) => {...c.toJson(), 'done': c.done ? 1 : 0, 'dirty': dirty ? 1 : 0};

  static Map<String, Object?> _clean(Map<String, Object?> row) => {...row}..remove('dirty');

  Future<HabitData> _query(String? where) async => HabitData(
        habits: [for (final r in await _db.query('habits', where: where)) Habit.fromJson(_clean(r))],
        checks: [for (final r in await _db.query('habit_checks', where: where)) HabitCheck.fromJson(_clean(r))],
      );

  @override
  Future<HabitData> load() => _query(null);

  @override
  Future<void> put(HabitData changes) async {
    final batch = _db.batch();
    for (final h in changes.habits) {
      batch.insert('habits', _habitRow(h, dirty: true), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final c in changes.checks) {
      batch.insert('habit_checks', _checkRow(c, dirty: true), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<HabitData> dirty() => _query('dirty = 1');

  @override
  Future<void> markClean(HabitData uploaded) async {
    final batch = _db.batch();
    for (final h in uploaded.habits) {
      batch.update('habits', {'dirty': 0}, where: 'id = ? AND updated_at = ?', whereArgs: [h.id, h.updatedAt.toUtc().toIso8601String()]);
    }
    for (final c in uploaded.checks) {
      batch.update('habit_checks', {'dirty': 0}, where: 'habit_id = ? AND day = ? AND updated_at = ?', whereArgs: [c.habitId, c.day, c.updatedAt.toUtc().toIso8601String()]);
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<int> dirtyCount() async {
    var total = 0;
    for (final table in ['habits', 'habit_checks']) {
      total += Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM $table WHERE dirty = 1')) ?? 0;
    }
    return total;
  }

  Future<bool> _wins(Transaction txn, String table, String where, List<Object?> args, DateTime remote) async {
    final rows = await txn.query(table, where: where, whereArgs: args, limit: 1);
    final local = rows.isEmpty ? null : rows.first;
    return remoteWins(
      local: local == null ? null : DateTime.parse(local['updated_at']! as String),
      localDirty: local != null && local['dirty'] == 1,
      remote: remote,
    );
  }

  @override
  Future<void> applyRemote(HabitData remote) async {
    await _db.transaction((txn) async {
      for (final h in remote.habits) {
        if (await _wins(txn, 'habits', 'id = ?', [h.id], h.updatedAt)) {
          await txn.insert('habits', _habitRow(h, dirty: false), conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      for (final c in remote.checks) {
        if (await _wins(txn, 'habit_checks', 'habit_id = ? AND day = ?', [c.habitId, c.day], c.updatedAt)) {
          await txn.insert('habit_checks', _checkRow(c, dirty: false), conflictAlgorithm: ConflictAlgorithm.replace);
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

"""Las tareas en SQLite (tasks.db en la carpeta de datos de Kyora).

- Cuatro estados (decisión de Gustavo del 22/10/2026): pendiente, en proceso, en revisión y finalizada. Al
  finalizar se guarda la fecha (`finished`) y se para el cronómetro; al salir de "finalizada" se borra. Sin prioridad.
- Las subtareas son tareas con `parent_id` (un solo nivel) y su `position`; al borrar la tarea se borran con ella.
- Las etiquetas son independientes: al borrar una tarea se conservan.
- Cronómetro: uno a la vez. `timer_started` queda guardado, así que sigue contando aunque Kyora se reinicie; al
  pararlo, lo transcurrido se suma a `real_s`.
"""
import sqlite3
import threading
from datetime import datetime

from kyora.core.actions import ActionError
from kyora.tasks.model import STATUS_KEYS

SCHEMA_VERSION = 2
SCHEMA = """
CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY,
    parent_id INTEGER REFERENCES tasks(id) ON DELETE CASCADE,
    position INTEGER NOT NULL DEFAULT 0,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending',
    expected_min INTEGER,
    real_s INTEGER NOT NULL DEFAULT 0,
    timer_started TEXT,
    created TEXT NOT NULL,
    updated TEXT NOT NULL,
    due TEXT,
    finished TEXT
);
CREATE INDEX IF NOT EXISTS tasks_parent ON tasks(parent_id, position);
CREATE TABLE IF NOT EXISTS tags (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE COLLATE NOCASE,
    color TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS task_tags (
    task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (task_id, tag_id)
);
"""
# colores de los puntos de las etiquetas (como los de la referencia), por turno
TAG_COLORS = ("#5b8def", "#3fb37f", "#e3b25a", "#e07a5f", "#b07ce8", "#4fc1c9", "#e86fa6", "#9aa5b1")
EDITABLE = ("name", "description", "expected_min", "due")


def _stamp(moment):
    return moment.replace(microsecond=0).isoformat()


class TaskStore:
    def __init__(self, path, now=datetime.now):
        """`path`: archivo .db (o ":memory:"). `now`: el reloj (los tests ponen uno falso)."""
        self._now = now
        self._lock = threading.RLock()  # la interfaz y las acciones en hilos usan la misma conexión
        self.db = sqlite3.connect(str(path), check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys = ON")
        with self.db:
            self.db.executescript(SCHEMA)
            self._migrate()
            self.db.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")

    def _migrate(self):
        """Esquema 1 -> 2: la columna de estado (las finalizadas pasan a "done", las demás a "pending")."""
        columns = {row[1] for row in self.db.execute("PRAGMA table_info(tasks)")}
        if "status" not in columns:
            self.db.execute("ALTER TABLE tasks ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'")
            self.db.execute("UPDATE tasks SET status = 'done' WHERE finished IS NOT NULL")

    def close(self):
        self.db.close()

    def _stamp_now(self):
        return _stamp(self._now())

    # ---------- leer ----------

    def _tags_of(self, ids):
        tags = {i: [] for i in ids}
        if ids:
            marks = ",".join("?" * len(ids))
            rows = self.db.execute(
                f"SELECT tt.task_id, g.id, g.name, g.color FROM task_tags tt JOIN tags g ON g.id = tt.tag_id "
                f"WHERE tt.task_id IN ({marks}) ORDER BY g.name COLLATE NOCASE", list(ids))
            for row in rows:
                tags[row["task_id"]].append({"id": row["id"], "name": row["name"], "color": row["color"]})
        return tags

    def _row(self, task_id):
        row = self.db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
        if row is None:
            raise ActionError("not_found", "Esa tarea ya no existe")
        return row

    def tasks(self):
        """Todas las tareas (sin las subtareas), con sus etiquetas y cuántas subtareas tienen y han finalizado."""
        with self._lock:
            rows = [dict(r) for r in self.db.execute("SELECT * FROM tasks WHERE parent_id IS NULL")]
            counts = {r["parent_id"]: (r["total"], r["done"]) for r in self.db.execute(
                "SELECT parent_id, COUNT(*) AS total, COUNT(finished) AS done FROM tasks "
                "WHERE parent_id IS NOT NULL GROUP BY parent_id")}
            tags = self._tags_of([r["id"] for r in rows])
            for r in rows:
                r["tags"] = tags[r["id"]]
                r["subtasks"], r["subtasks_done"] = counts.get(r["id"], (0, 0))
            return rows

    def get(self, task_id):
        """Una tarea con sus etiquetas y sus subtareas en orden."""
        with self._lock:
            task = dict(self._row(task_id))
            task["tags"] = self._tags_of([task_id])[task_id]
            task["children"] = [dict(r) for r in self.db.execute(
                "SELECT * FROM tasks WHERE parent_id = ? ORDER BY position, id", (task_id,))]
            return task

    def running(self):
        """La tarea con el cronómetro en marcha (o None)."""
        with self._lock:
            row = self.db.execute("SELECT * FROM tasks WHERE timer_started IS NOT NULL").fetchone()
            return dict(row) if row else None

    # ---------- escribir ----------

    def create(self, name, parent_id=None, description="", due=None, expected_min=None):
        name = (name or "").strip()
        if not name:
            raise ActionError("empty_name", "La tarea necesita un nombre")
        with self._lock, self.db:
            if parent_id is not None:
                parent = self._row(parent_id)
                if parent["parent_id"] is not None:
                    raise ActionError("too_deep", "Las subtareas no pueden tener subtareas")
            position = self.db.execute(
                "SELECT COALESCE(MAX(position) + 1, 0) FROM tasks WHERE parent_id IS ?", (parent_id,)).fetchone()[0]
            stamp = self._stamp_now()
            cursor = self.db.execute(
                "INSERT INTO tasks (parent_id, position, name, description, expected_min, created, updated, due) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                (parent_id, position, name, description or "", expected_min, stamp, stamp, due))
            if parent_id is not None:
                self._touch(parent_id)
            return cursor.lastrowid

    def _touch(self, task_id):
        self.db.execute("UPDATE tasks SET updated = ? WHERE id = ?", (self._stamp_now(), task_id))

    def update(self, task_id, **fields):
        """Cambia nombre, descripción, tiempo esperado (minutos) o entrega ("2026-10-25T18:00" o None)."""
        unknown = set(fields) - set(EDITABLE)
        if unknown:
            raise ActionError("bad_field", f"No se puede cambiar {', '.join(sorted(unknown))}")
        if "name" in fields:
            fields["name"] = (fields["name"] or "").strip()
            if not fields["name"]:
                raise ActionError("empty_name", "La tarea necesita un nombre")
        if not fields:
            return
        with self._lock, self.db:
            self._row(task_id)
            sets = ", ".join(f"{key} = ?" for key in fields)
            self.db.execute(f"UPDATE tasks SET {sets}, updated = ? WHERE id = ?",
                            [*fields.values(), self._stamp_now(), task_id])

    def delete(self, task_id):
        """Borra la tarea y sus subtareas (las etiquetas se quedan)."""
        with self._lock, self.db:
            row = self._row(task_id)
            self.db.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
            if row["parent_id"] is not None:
                self._renumber(row["parent_id"])

    def set_status(self, task_id, status):
        """Cambia el estado. "done" pone la fecha de finalización y para el cronómetro; salir de "done" la borra."""
        if status not in STATUS_KEYS:
            raise ActionError("bad_status", f"Estado desconocido: {status}")
        with self._lock, self.db:
            row = self._row(task_id)
            if row["status"] == status:
                return
            stamp = self._stamp_now()
            if status == "done":
                if row["timer_started"]:
                    self._stop(task_id)
                self.db.execute("UPDATE tasks SET status = ?, finished = ?, updated = ? WHERE id = ?",
                                (status, stamp, stamp, task_id))
            else:
                self.db.execute("UPDATE tasks SET status = ?, finished = NULL, updated = ? WHERE id = ?",
                                (status, stamp, task_id))

    def finish(self, task_id):
        self.set_status(task_id, "done")

    def reopen(self, task_id):
        self.set_status(task_id, "pending")

    def counts(self):
        """{estado: cuántas tareas} (sin contar subtareas), con los cuatro estados aunque estén a cero."""
        with self._lock:
            found = dict(self.db.execute(
                "SELECT status, COUNT(*) FROM tasks WHERE parent_id IS NULL GROUP BY status").fetchall())
            return {key: found.get(key, 0) for key in STATUS_KEYS}

    def _renumber(self, parent_id, order=None):
        ids = order or [r[0] for r in self.db.execute(
            "SELECT id FROM tasks WHERE parent_id = ? ORDER BY position, id", (parent_id,))]
        for position, child in enumerate(ids):
            self.db.execute("UPDATE tasks SET position = ? WHERE id = ?", (position, child))

    def move(self, task_id, position):
        """Pone la subtarea en `position` (0 = la primera) dentro de su tarea."""
        with self._lock, self.db:
            row = self._row(task_id)
            if row["parent_id"] is None:
                raise ActionError("not_subtask", "Solo se ordenan las subtareas")
            ids = [r[0] for r in self.db.execute(
                "SELECT id FROM tasks WHERE parent_id = ? ORDER BY position, id", (row["parent_id"],))]
            ids.remove(task_id)
            ids.insert(max(0, min(int(position), len(ids))), task_id)
            self._renumber(row["parent_id"], ids)
            self._touch(row["parent_id"])

    # ---------- cronómetro ----------

    def _stop(self, task_id):
        row = self._row(task_id)
        if row["timer_started"]:
            elapsed = max(int((self._now() - datetime.fromisoformat(row["timer_started"])).total_seconds()), 0)
            self.db.execute("UPDATE tasks SET real_s = real_s + ?, timer_started = NULL, updated = ? WHERE id = ?",
                            (elapsed, self._stamp_now(), task_id))

    def timer_start(self, task_id):
        """Arranca el cronómetro de la tarea (y para el que estuviera en marcha)."""
        with self._lock, self.db:
            if self._row(task_id)["finished"]:
                raise ActionError("finished", "La tarea está finalizada: reábrela para cronometrarla")
            for (other,) in self.db.execute("SELECT id FROM tasks WHERE timer_started IS NOT NULL").fetchall():
                self._stop(other)
            self.db.execute("UPDATE tasks SET timer_started = ? WHERE id = ?", (self._stamp_now(), task_id))

    def timer_stop(self, task_id=None):
        """Para el cronómetro de la tarea (o el que esté en marcha) y suma el tiempo."""
        with self._lock, self.db:
            if task_id is None:
                row = self.db.execute("SELECT id FROM tasks WHERE timer_started IS NOT NULL").fetchone()
                if row is None:
                    return
                task_id = row[0]
            self._stop(task_id)

    # ---------- etiquetas ----------

    def tags(self):
        """[{id, name, color, count}] con cuántas tareas (sin contar subtareas) llevan cada una."""
        with self._lock:
            return [dict(r) for r in self.db.execute(
                "SELECT g.id, g.name, g.color, COUNT(t.id) AS count FROM tags g "
                "LEFT JOIN task_tags tt ON tt.tag_id = g.id "
                "LEFT JOIN tasks t ON t.id = tt.task_id AND t.parent_id IS NULL "
                "GROUP BY g.id ORDER BY g.name COLLATE NOCASE")]

    def tag_create(self, name):
        name = (name or "").strip()
        if not name:
            raise ActionError("empty_name", "La etiqueta necesita un nombre")
        with self._lock, self.db:
            row = self.db.execute("SELECT id FROM tags WHERE name = ?", (name,)).fetchone()
            if row:
                return row[0]
            count = self.db.execute("SELECT COUNT(*) FROM tags").fetchone()[0]
            return self.db.execute("INSERT INTO tags (name, color) VALUES (?, ?)",
                                   (name, TAG_COLORS[count % len(TAG_COLORS)])).lastrowid

    def tag_rename(self, tag_id, name):
        name = (name or "").strip()
        if not name:
            raise ActionError("empty_name", "La etiqueta necesita un nombre")
        with self._lock, self.db:
            try:
                self.db.execute("UPDATE tags SET name = ? WHERE id = ?", (name, tag_id))
            except sqlite3.IntegrityError as err:
                raise ActionError("exists", f"Ya hay una etiqueta «{name}»") from err

    def tag_delete(self, tag_id):
        """Borra la etiqueta (se quita de las tareas; las tareas se quedan)."""
        with self._lock, self.db:
            self.db.execute("DELETE FROM tags WHERE id = ?", (tag_id,))

    def tag_assign(self, task_id, tag_id):
        with self._lock, self.db:
            self._row(task_id)
            self.db.execute("INSERT OR IGNORE INTO task_tags (task_id, tag_id) VALUES (?, ?)", (task_id, tag_id))
            self._touch(task_id)

    def tag_unassign(self, task_id, tag_id):
        with self._lock, self.db:
            self.db.execute("DELETE FROM task_tags WHERE task_id = ? AND tag_id = ?", (task_id, tag_id))
            self._touch(task_id)

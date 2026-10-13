import sqlite3
import os
import sys
from contextlib import contextmanager
from typing import Generator

def _get_default_db_path() -> str:
    # En ejecutable compilado (PyInstaller), guardar en %LOCALAPPDATA%\Kiora para persistencia segura
    if getattr(sys, "frozen", False):
        appdata = os.environ.get("LOCALAPPDATA") or os.environ.get("APPDATA")
        if appdata:
            kiora_dir = os.path.join(appdata, "Kiora", "data")
            os.makedirs(kiora_dir, exist_ok=True)
            return os.path.join(kiora_dir, "tasks.db")
        else:
            exe_dir = os.path.dirname(sys.executable)
            return os.path.join(exe_dir, "tasks.db")
    # Modo de desarrollo estándar
    return os.path.join(os.path.dirname(__file__), "tasks.db")

DEFAULT_DB_PATH = _get_default_db_path()

SCHEMA_SQL = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS task_statuses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    color TEXT NULL
);

CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    color TEXT NULL,
    created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NULL,
    status_id INTEGER NOT NULL DEFAULT 1,
    priority INTEGER DEFAULT 0,
    due_date TEXT NULL,
    category_id TEXT NULL,
    estimated_duration_minutes INTEGER NULL,
    time_spent_seconds INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (status_id) REFERENCES task_statuses (id) ON UPDATE CASCADE,
    FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS subtasks (
    id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT NULL,
    is_completed INTEGER DEFAULT 0,
    position INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS time_entries (
    id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    duration_seconds INTEGER NOT NULL,
    started_at TEXT NULL,
    ended_at TEXT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE CASCADE
);
"""

DEFAULT_STATUSES = [
    (1, "pending", "#FFA500"),
    (2, "in_progress", "#00BFFF"),
    (3, "completed", "#00FA9A")
]

# No se pre-registran categorías por defecto; el usuario las crea a demanda.
DEFAULT_CATEGORIES = []


class DatabaseManager:
    """
    Gestiona la conexión y el ciclo de vida del esquema SQLite para el ecosistema de tareas.

    Garantiza la activación de claves foráneas y la creación automática de tablas
    e índices requeridos por el sistema.
    """

    def __init__(self, db_path: str = DEFAULT_DB_PATH):
        """
        Inicializa el administrador con la ruta de la base de datos especificada.

        Args:
            db_path: Ruta absoluta o relativa al archivo SQLite.
        """
        self.db_path = db_path
        os.makedirs(os.path.dirname(os.path.abspath(self.db_path)), exist_ok=True)
        self.initialize_schema()

    @contextmanager
    def get_connection(self) -> Generator[sqlite3.Connection, None, None]:
        """
        Generador de contexto para obtener una conexión SQLite con foreign keys habilitadas.

        Yields:
            sqlite3.Connection: Objeto de conexión activo con Row factory.
        """
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON;")
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    @staticmethod
    def _normalize_subtask_positions(cursor: sqlite3.Cursor) -> None:
        """
        Renumera `position` de las subtareas como 0, 1, 2... por tarea.

        Corrige datos antiguos con posiciones duplicadas o con huecos conservando el orden
        existente (position, luego created_at y rowid como desempate). Es idempotente:
        solo actualiza las filas cuya posición no coincide con la secuencia esperada.
        """
        rows = cursor.execute(
            "SELECT id, task_id, position FROM subtasks "
            "ORDER BY task_id, position ASC, created_at ASC, rowid ASC;"
        ).fetchall()

        counters = {}
        for row in rows:
            expected = counters.get(row["task_id"], 0)
            counters[row["task_id"]] = expected + 1
            if row["position"] != expected:
                cursor.execute(
                    "UPDATE subtasks SET position = ? WHERE id = ?;",
                    (expected, row["id"])
                )

    def initialize_schema(self) -> None:
        """
        Ejecuta las sentencias DDL para inicializar tablas, índices, estados y categorías por defecto,
        así como migraciones incrementales si la base de datos ya existía.
        """
        with self.get_connection() as conn:
            conn.executescript(SCHEMA_SQL)
            cursor = conn.cursor()

            # Migración incremental segura para columnas de tasks preexistentes
            try:
                cols = [r["name"] for r in cursor.execute("PRAGMA table_info(tasks);").fetchall()]
                if "category_id" not in cols:
                    cursor.execute("ALTER TABLE tasks ADD COLUMN category_id TEXT NULL;")
                if "estimated_duration_minutes" not in cols:
                    cursor.execute("ALTER TABLE tasks ADD COLUMN estimated_duration_minutes INTEGER NULL;")
                if "time_spent_seconds" not in cols:
                    cursor.execute("ALTER TABLE tasks ADD COLUMN time_spent_seconds INTEGER DEFAULT 0;")

                # Creación de índices una vez aseguradas las columnas
                cursor.execute("CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status_id);")
                cursor.execute("CREATE INDEX IF NOT EXISTS idx_tasks_category ON tasks(category_id);")
                cursor.execute("CREATE INDEX IF NOT EXISTS idx_subtasks_task_id ON subtasks(task_id);")
                cursor.execute(
                    "CREATE INDEX IF NOT EXISTS idx_subtasks_task_position ON subtasks(task_id, position);"
                )
                cursor.execute("CREATE INDEX IF NOT EXISTS idx_time_entries_task_id ON time_entries(task_id);")
            except Exception:
                pass

            self._normalize_subtask_positions(cursor)

            # Estados por defecto
            for status_id, name, color in DEFAULT_STATUSES:
                cursor.execute(
                    """
                    INSERT INTO task_statuses (id, name, color)
                    VALUES (?, ?, ?)
                    ON CONFLICT(id) DO NOTHING;
                    """,
                    (status_id, name, color)
                )

            # Categorías por defecto (TAR-027)
            for cat_id, name, color in DEFAULT_CATEGORIES:
                cursor.execute(
                    """
                    INSERT INTO categories (id, name, color)
                    VALUES (?, ?, ?)
                    ON CONFLICT(id) DO NOTHING;
                    """,
                    (cat_id, name, color)
                )

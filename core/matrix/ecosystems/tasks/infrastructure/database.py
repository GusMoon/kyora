import sqlite3
import os
from contextlib import contextmanager
from typing import Generator

DEFAULT_DB_PATH = os.path.join(os.path.dirname(__file__), "tasks.db")

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

DEFAULT_CATEGORIES = [
    ("cat-trabajo", "Trabajo", "#FFA500"),
    ("cat-proyectos", "Proyectos personales", "#00BFFF"),
    ("cat-materias", "Materias", "#9370DB"),
    ("cat-admin", "Actividades administrativas", "#00FA9A")
]


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
                cursor.execute("CREATE INDEX IF NOT EXISTS idx_time_entries_task_id ON time_entries(task_id);")
            except Exception:
                pass

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

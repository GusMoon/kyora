import os
import sqlite3
import sys
from contextlib import contextmanager
from typing import Generator


def _get_default_db_path() -> str:
    """Devuelve la ruta de la BD: %LOCALAPPDATA%\\Kiora\\data en el .exe, junto al código en desarrollo."""
    if getattr(sys, "frozen", False):
        appdata = os.environ.get("LOCALAPPDATA") or os.environ.get("APPDATA")
        if appdata:
            data_dir = os.path.join(appdata, "Kiora", "data")
            os.makedirs(data_dir, exist_ok=True)
            return os.path.join(data_dir, "logbook.db")
        return os.path.join(os.path.dirname(sys.executable), "logbook.db")
    return os.path.join(os.path.dirname(__file__), "logbook.db")


DEFAULT_DB_PATH = _get_default_db_path()

SCHEMA_SQL = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS log_entries (
    id TEXT PRIMARY KEY,
    entry_date TEXT NOT NULL UNIQUE,
    content TEXT NOT NULL DEFAULT '',
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);
"""


class DatabaseManager:
    """Gestiona la conexión y el esquema SQLite del ecosistema de bitácora."""

    def __init__(self, db_path: str = DEFAULT_DB_PATH):
        """
        Inicializa el administrador y crea el esquema si no existe.

        Args:
            db_path: Ruta del archivo SQLite.
        """
        self.db_path = db_path
        os.makedirs(os.path.dirname(os.path.abspath(self.db_path)), exist_ok=True)
        self.initialize_schema()

    @contextmanager
    def get_connection(self) -> Generator[sqlite3.Connection, None, None]:
        """
        Entrega una conexión con foreign keys; confirma al salir o revierte ante un error.

        Yields:
            sqlite3.Connection: Conexión activa con `Row` como row factory.
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
        """Crea las tablas si no existen."""
        with self.get_connection() as conn:
            conn.executescript(SCHEMA_SQL)

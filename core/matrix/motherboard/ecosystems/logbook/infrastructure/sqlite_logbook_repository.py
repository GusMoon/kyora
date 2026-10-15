import uuid
from typing import Optional

from core.matrix.motherboard.ecosystems.logbook.domain.entities import LogEntry
from core.matrix.motherboard.ecosystems.logbook.domain.repositories import LogbookRepository
from core.matrix.motherboard.ecosystems.logbook.infrastructure.database import DatabaseManager


class SqliteLogbookRepository(LogbookRepository):
    """Implementación de LogbookRepository respaldada por SQLite."""

    def __init__(self, db_manager: Optional[DatabaseManager] = None):
        """
        Args:
            db_manager: Administrador de BD; si es None se crea uno por defecto.
        """
        self.db_manager = db_manager if db_manager is not None else DatabaseManager()

    def get_entry_by_date(self, entry_date: str) -> Optional[LogEntry]:
        """Obtiene la entrada de una fecha ISO, o None si no existe."""
        with self.db_manager.get_connection() as conn:
            row = conn.execute(
                "SELECT id, entry_date, content, created_at, updated_at "
                "FROM log_entries WHERE entry_date = ?;",
                (entry_date,),
            ).fetchone()
        if row is None:
            return None
        return LogEntry(
            id=row["id"],
            entry_date=row["entry_date"],
            content=row["content"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
        )

    def save_entry(self, entry: LogEntry) -> None:
        """Inserta la entrada o actualiza su contenido si ya existe una para esa fecha."""
        entry_id = entry.id or uuid.uuid4().hex[:8]
        with self.db_manager.get_connection() as conn:
            conn.execute(
                """
                INSERT INTO log_entries (id, entry_date, content) VALUES (?, ?, ?)
                ON CONFLICT(entry_date) DO UPDATE SET
                    content = excluded.content,
                    updated_at = datetime('now');
                """,
                (entry_id, entry.entry_date, entry.content),
            )

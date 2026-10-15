import uuid
from typing import List, Optional

from core.matrix.motherboard.ecosystems.calendar.domain.entities import (
    CalendarEvent, Notification, Reminder,
)
from core.matrix.motherboard.ecosystems.calendar.domain.repositories import CalendarRepository
from core.matrix.motherboard.ecosystems.calendar.infrastructure.database import DatabaseManager

_EVENT_COLUMNS = "id, title, event_date, start_time, end_time, description, kind, recurrence, created_at"
_REMINDER_COLUMNS = "id, text, remind_at, event_id, advance_minutes, notified_at"


def _new_id() -> str:
    """Genera un identificador corto único."""
    return uuid.uuid4().hex[:8]


def _event_from_row(row) -> CalendarEvent:
    """Convierte una fila SQLite en CalendarEvent."""
    return CalendarEvent(
        id=row["id"], title=row["title"], event_date=row["event_date"],
        start_time=row["start_time"], end_time=row["end_time"],
        description=row["description"], kind=row["kind"], recurrence=row["recurrence"],
        created_at=row["created_at"] or "",
    )


def _reminder_from_row(row) -> Reminder:
    """Convierte una fila SQLite en Reminder."""
    return Reminder(
        id=row["id"], text=row["text"], remind_at=row["remind_at"],
        event_id=row["event_id"], advance_minutes=row["advance_minutes"],
        notified_at=row["notified_at"],
    )


class SqliteCalendarRepository(CalendarRepository):
    """Implementación de CalendarRepository respaldada por SQLite."""

    def __init__(self, db_manager: Optional[DatabaseManager] = None):
        """
        Args:
            db_manager: Administrador de BD; si es None se crea uno por defecto.
        """
        self.db_manager = db_manager if db_manager is not None else DatabaseManager()

    # ---------------------------------------------------------------- eventos
    def save_event(self, event: CalendarEvent) -> str:
        """Crea o actualiza un evento y devuelve su identificador."""
        event_id = event.id or _new_id()
        with self.db_manager.get_connection() as conn:
            conn.execute(
                """
                INSERT INTO calendar_events
                    (id, title, event_date, start_time, end_time, description, kind, recurrence)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title, event_date = excluded.event_date,
                    start_time = excluded.start_time, end_time = excluded.end_time,
                    description = excluded.description, kind = excluded.kind,
                    recurrence = excluded.recurrence, updated_at = datetime('now');
                """,
                (event_id, event.title, event.event_date, event.start_time, event.end_time,
                 event.description, event.kind, event.recurrence),
            )
        return event_id

    def get_event(self, event_id: str) -> Optional[CalendarEvent]:
        """Obtiene un evento por identificador, o None si no existe."""
        with self.db_manager.get_connection() as conn:
            row = conn.execute(
                f"SELECT {_EVENT_COLUMNS} FROM calendar_events WHERE id = ?;", (event_id,)
            ).fetchone()
        return _event_from_row(row) if row else None

    def delete_event(self, event_id: str) -> None:
        """Elimina un evento y los recordatorios asociados."""
        with self.db_manager.get_connection() as conn:
            conn.execute("DELETE FROM reminders WHERE event_id = ?;", (event_id,))
            conn.execute("DELETE FROM calendar_events WHERE id = ?;", (event_id,))

    def list_events(self) -> List[CalendarEvent]:
        """Devuelve todos los eventos."""
        with self.db_manager.get_connection() as conn:
            rows = conn.execute(
                f"SELECT {_EVENT_COLUMNS} FROM calendar_events ORDER BY event_date, start_time;"
            ).fetchall()
        return [_event_from_row(r) for r in rows]

    # ----------------------------------------------------------- recordatorios
    def save_reminder(self, reminder: Reminder) -> str:
        """Crea o actualiza un recordatorio y devuelve su identificador."""
        reminder_id = reminder.id or _new_id()
        with self.db_manager.get_connection() as conn:
            conn.execute(
                """
                INSERT INTO reminders (id, text, remind_at, event_id, advance_minutes, notified_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    text = excluded.text, remind_at = excluded.remind_at,
                    event_id = excluded.event_id, advance_minutes = excluded.advance_minutes,
                    notified_at = excluded.notified_at;
                """,
                (reminder_id, reminder.text, reminder.remind_at, reminder.event_id,
                 reminder.advance_minutes, reminder.notified_at),
            )
        return reminder_id

    def get_reminder(self, reminder_id: str) -> Optional[Reminder]:
        """Obtiene un recordatorio por identificador, o None si no existe."""
        with self.db_manager.get_connection() as conn:
            row = conn.execute(
                f"SELECT {_REMINDER_COLUMNS} FROM reminders WHERE id = ?;", (reminder_id,)
            ).fetchone()
        return _reminder_from_row(row) if row else None

    def delete_reminder(self, reminder_id: str) -> None:
        """Elimina un recordatorio."""
        with self.db_manager.get_connection() as conn:
            conn.execute("DELETE FROM reminders WHERE id = ?;", (reminder_id,))

    def list_reminders(self) -> List[Reminder]:
        """Devuelve todos los recordatorios."""
        with self.db_manager.get_connection() as conn:
            rows = conn.execute(
                f"SELECT {_REMINDER_COLUMNS} FROM reminders ORDER BY remind_at;"
            ).fetchall()
        return [_reminder_from_row(r) for r in rows]

    def list_reminders_for_event(self, event_id: str) -> List[Reminder]:
        """Devuelve los recordatorios asociados a un evento."""
        with self.db_manager.get_connection() as conn:
            rows = conn.execute(
                f"SELECT {_REMINDER_COLUMNS} FROM reminders WHERE event_id = ? ORDER BY remind_at;",
                (event_id,),
            ).fetchall()
        return [_reminder_from_row(r) for r in rows]

    def delete_reminders_for_event(self, event_id: str) -> None:
        """Elimina los recordatorios asociados a un evento."""
        with self.db_manager.get_connection() as conn:
            conn.execute("DELETE FROM reminders WHERE event_id = ?;", (event_id,))

    def list_due_reminders(self, now_iso: str) -> List[Reminder]:
        """Devuelve los recordatorios pendientes cuya hora ya llegó."""
        with self.db_manager.get_connection() as conn:
            rows = conn.execute(
                f"SELECT {_REMINDER_COLUMNS} FROM reminders "
                "WHERE notified_at = '' AND remind_at <= ? ORDER BY remind_at;",
                (now_iso,),
            ).fetchall()
        return [_reminder_from_row(r) for r in rows]

    def claim_reminder(self, reminder_id: str, notified_at: str, notification: Notification) -> bool:
        """
        Marca el recordatorio como notificado y encola su aviso, de forma atómica.

        Returns:
            bool: False si otro proceso o ejecución ya lo había notificado.
        """
        with self.db_manager.get_connection() as conn:
            cursor = conn.execute(
                "UPDATE reminders SET notified_at = ? WHERE id = ? AND notified_at = '';",
                (notified_at, reminder_id),
            )
            if cursor.rowcount != 1:
                return False
            conn.execute(
                "INSERT INTO notification_outbox (reminder_id, source_type, source_id, title, body) "
                "VALUES (?, ?, ?, ?, ?);",
                (notification.reminder_id, notification.source_type, notification.source_id,
                 notification.title, notification.body),
            )
        return True

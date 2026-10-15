from abc import ABC, abstractmethod
from typing import List, Optional

from core.matrix.motherboard.ecosystems.calendar.domain.entities import (
    CalendarEvent, Notification, Reminder,
)


class CalendarRepository(ABC):
    """
    Contrato abstracto de persistencia del calendario (eventos y recordatorios).
    Desacopla el dominio y los casos de uso de la implementación técnica (SQLite).
    """

    @abstractmethod
    def save_event(self, event: CalendarEvent) -> str:
        """Crea o actualiza un evento y devuelve su identificador."""

    @abstractmethod
    def get_event(self, event_id: str) -> Optional[CalendarEvent]:
        """Obtiene un evento por identificador, o None si no existe."""

    @abstractmethod
    def delete_event(self, event_id: str) -> None:
        """Elimina un evento y los recordatorios asociados."""

    @abstractmethod
    def list_events(self) -> List[CalendarEvent]:
        """Devuelve todos los eventos."""

    @abstractmethod
    def save_reminder(self, reminder: Reminder) -> str:
        """Crea o actualiza un recordatorio y devuelve su identificador."""

    @abstractmethod
    def get_reminder(self, reminder_id: str) -> Optional[Reminder]:
        """Obtiene un recordatorio por identificador, o None si no existe."""

    @abstractmethod
    def delete_reminder(self, reminder_id: str) -> None:
        """Elimina un recordatorio."""

    @abstractmethod
    def list_reminders(self) -> List[Reminder]:
        """Devuelve todos los recordatorios."""

    @abstractmethod
    def list_reminders_for_event(self, event_id: str) -> List[Reminder]:
        """Devuelve los recordatorios asociados a un evento."""

    @abstractmethod
    def delete_reminders_for_event(self, event_id: str) -> None:
        """Elimina los recordatorios asociados a un evento."""

    @abstractmethod
    def list_due_reminders(self, now_iso: str) -> List[Reminder]:
        """Devuelve los recordatorios pendientes cuya hora ya llegó."""

    @abstractmethod
    def claim_reminder(self, reminder_id: str, notified_at: str, notification: Notification) -> bool:
        """
        Marca un recordatorio como notificado y registra su aviso en la bandeja de salida.

        La operación es atómica: si ya estaba notificado devuelve False y no
        registra nada, de modo que un mismo recordatorio no se avise dos veces.
        """

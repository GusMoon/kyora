from abc import ABC, abstractmethod
from typing import Optional

from core.matrix.motherboard.ecosystems.logbook.domain.entities import LogEntry


class LogbookRepository(ABC):
    """
    Contrato abstracto de persistencia del ecosistema de bitácora.
    Desacopla el dominio y los casos de uso de la implementación técnica (SQLite).
    """

    @abstractmethod
    def get_entry_by_date(self, entry_date: str) -> Optional[LogEntry]:
        """Obtiene la entrada de una fecha ISO (AAAA-MM-DD), o None si no existe."""

    @abstractmethod
    def save_entry(self, entry: LogEntry) -> None:
        """Crea la entrada de su fecha o actualiza su contenido si ya existe."""

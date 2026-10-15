from datetime import date

from core.matrix.motherboard.ecosystems.logbook.domain.entities import LogEntry
from core.matrix.motherboard.ecosystems.logbook.domain.repositories import LogbookRepository


class LogbookUseCases:
    """
    Casos de uso de la bitácora personal.
    Mantiene como regla central una única entrada por fecha.
    """

    def __init__(self, repository: LogbookRepository):
        """
        Args:
            repository: Implementación del contrato LogbookRepository.
        """
        self.repository = repository

    def get_entry(self, entry_date: str) -> LogEntry:
        """
        Obtiene la entrada de una fecha; si no existe devuelve una vacía sin persistirla.

        Args:
            entry_date: Fecha ISO (AAAA-MM-DD).

        Returns:
            LogEntry: Entrada existente o vacía.

        Raises:
            ValueError: Si la fecha no tiene formato ISO válido.
        """
        date.fromisoformat(entry_date)
        return self.repository.get_entry_by_date(entry_date) or LogEntry(entry_date=entry_date)

    def save_entry(self, entry_date: str, content: str) -> None:
        """
        Guarda la entrada de la fecha indicada.

        Un día sin entrada no se crea si el contenido está en blanco; si ya existía,
        sí se actualiza para permitir vaciarla.

        Args:
            entry_date: Fecha ISO (AAAA-MM-DD).
            content: Texto completo de la entrada.

        Raises:
            ValueError: Si la fecha no tiene formato ISO válido.
        """
        date.fromisoformat(entry_date)
        existing = self.repository.get_entry_by_date(entry_date)
        if existing is None and not content.strip():
            return
        self.repository.save_entry(
            LogEntry(entry_date=entry_date, content=content, id=existing.id if existing else "")
        )

import sqlite3

from PySide6.QtCore import QObject, Signal

from core.matrix.motherboard.ecosystems.logbook.use_cases.manage_logbook import LogbookUseCases


class LogbookViewModel(QObject):
    """
    ViewModel del ecosistema de bitácora.

    Conecta la vista con los casos de uso mediante señales Qt y traduce los
    errores de persistencia en mensajes para el usuario.
    """
    entry_loaded = Signal(str, str)   # entry_date, content
    save_succeeded = Signal(str)      # entry_date
    logbook_error = Signal(str)

    def __init__(self, use_cases: LogbookUseCases):
        """
        Args:
            use_cases: Casos de uso del ecosistema.
        """
        super().__init__()
        self._use_cases = use_cases

    def open_date(self, entry_date: str) -> None:
        """Carga la entrada de la fecha y notifica a la vista."""
        try:
            entry = self._use_cases.get_entry(entry_date)
        except (ValueError, sqlite3.Error) as e:
            self.logbook_error.emit(f"No se pudo abrir la entrada: {e}")
            return
        self.entry_loaded.emit(entry.entry_date, entry.content)

    def save_content(self, entry_date: str, content: str) -> None:
        """Guarda la entrada; emite `logbook_error` si no se pudo persistir."""
        try:
            self._use_cases.save_entry(entry_date, content)
        except (ValueError, sqlite3.Error) as e:
            self.logbook_error.emit(f"No se pudo guardar la entrada: {e}")
            return
        self.save_succeeded.emit(entry_date)

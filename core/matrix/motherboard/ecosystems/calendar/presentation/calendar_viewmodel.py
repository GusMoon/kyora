import sqlite3
from datetime import date, datetime, timedelta
from typing import Callable, Optional, Tuple

from PySide6.QtCore import QObject, QTimer, Signal

from core.matrix.motherboard.ecosystems.calendar.domain.entities import CalendarEvent, Reminder
from core.matrix.motherboard.ecosystems.calendar.use_cases.manage_calendar import CalendarUseCases

CHECK_INTERVAL_MS = 30_000
COUNT_WINDOW_DAYS = 14


class CalendarViewModel(QObject):
    """
    ViewModel del ecosistema de calendario.

    Su estado central es el día seleccionado: al cambiarlo emite el detalle del
    día, los contadores de la franja de días y el mes completo. También ejecuta
    las operaciones de eventos y recordatorios y vigila cada 30 segundos los
    recordatorios vencidos. Se crea al arrancar la aplicación, por lo que los
    avisos funcionan aunque el calendario no esté abierto (con la app en marcha).
    """

    agenda_loaded = Signal(str, list, dict, object)   # día ISO, actividades, {día: cantidad}, hoy
    month_loaded = Signal(int, int, dict, object)     # año, mes, {fecha ISO: items}, hoy
    reminder_due = Signal(str, str)                   # título, detalle
    calendar_error = Signal(str)

    def __init__(self, use_cases: CalendarUseCases,
                 clock: Callable[[], datetime] = datetime.now,
                 check_interval_ms: int = CHECK_INTERVAL_MS):
        """
        Args:
            use_cases: Casos de uso del calendario.
            clock: Función que devuelve el momento actual (inyectable en pruebas).
            check_interval_ms: Cada cuánto se buscan recordatorios vencidos.
        """
        super().__init__()
        self._use_cases = use_cases
        self._clock = clock
        self._selected = clock().date()

        self._timer = QTimer(self)
        self._timer.setInterval(check_interval_ms)
        self._timer.timeout.connect(self.check_reminders)
        self._timer.start()
        QTimer.singleShot(1500, self.check_reminders)

    # ----------------------------------------------------------------- lectura
    @property
    def selected(self) -> date:
        """Día actualmente seleccionado."""
        return self._selected

    def now(self) -> datetime:
        """Momento actual según el reloj del ViewModel."""
        return self._clock()

    def today(self) -> date:
        """Fecha actual según el reloj del ViewModel."""
        return self._clock().date()

    def select_date(self, day: date) -> None:
        """
        Selecciona un día y notifica su detalle, los contadores de la franja y el mes.

        Args:
            day: Día a seleccionar.
        """
        self._selected = day
        today = self.today()
        try:
            month_items = self._use_cases.get_month(day.year, day.month, today)
            counts = self._use_cases.count_by_day(
                day - timedelta(days=COUNT_WINDOW_DAYS), day + timedelta(days=COUNT_WINDOW_DAYS), today)
        except sqlite3.Error as e:
            self.calendar_error.emit(f"No se pudo leer el calendario: {e}")
            return
        self.agenda_loaded.emit(day.isoformat(), month_items.get(day.isoformat(), []), counts, today)
        self.month_loaded.emit(day.year, day.month, month_items, today)

    def reload(self) -> None:
        """Vuelve a cargar los datos del día seleccionado."""
        self.select_date(self._selected)

    def get_event(self, event_id: str) -> Optional[Tuple[CalendarEvent, int]]:
        """Devuelve un evento junto con su anticipación en minutos, o None si no existe."""
        try:
            event = self._use_cases.get_event(event_id)
            if event is None:
                return None
            return event, self._use_cases.get_event_advance(event_id)
        except sqlite3.Error as e:
            self.calendar_error.emit(f"No se pudo leer el evento: {e}")
            return None

    def get_reminder(self, reminder_id: str) -> Optional[Reminder]:
        """Devuelve un recordatorio, o None si no existe."""
        try:
            return self._use_cases.get_reminder(reminder_id)
        except sqlite3.Error as e:
            self.calendar_error.emit(f"No se pudo leer el recordatorio: {e}")
            return None

    # --------------------------------------------------------------- escritura
    def _run(self, action: Callable[[], object]) -> Optional[str]:
        """Ejecuta una operación; devuelve el mensaje de error o None si salió bien."""
        try:
            action()
        except ValueError as e:
            return str(e)
        except sqlite3.Error as e:
            return f"Error de base de datos: {e}"
        self.reload()
        return None

    def create_event(self, values: dict) -> Optional[str]:
        """Crea un evento con los valores del formulario; devuelve un error o None."""
        return self._run(lambda: self._use_cases.create_event(now=self._clock(), **values))

    def update_event(self, event_id: str, values: dict) -> Optional[str]:
        """Modifica un evento; devuelve un error o None."""
        return self._run(lambda: self._use_cases.update_event(event_id, now=self._clock(), **values))

    def delete_event(self, event_id: str) -> Optional[str]:
        """Elimina un evento; devuelve un error o None."""
        return self._run(lambda: self._use_cases.delete_event(event_id))

    def create_reminder(self, values: dict) -> Optional[str]:
        """Crea un recordatorio; devuelve un error o None."""
        return self._run(lambda: self._use_cases.create_reminder(**values))

    def update_reminder(self, reminder_id: str, values: dict) -> Optional[str]:
        """Modifica un recordatorio; devuelve un error o None."""
        return self._run(lambda: self._use_cases.update_reminder(reminder_id, **values))

    def delete_reminder(self, reminder_id: str) -> Optional[str]:
        """Elimina un recordatorio; devuelve un error o None."""
        return self._run(lambda: self._use_cases.delete_reminder(reminder_id))

    # ----------------------------------------------------------- notificaciones
    def check_reminders(self) -> None:
        """Busca recordatorios vencidos y emite un aviso por cada uno."""
        try:
            notifications = self._use_cases.collect_due_reminders(self._clock())
        except sqlite3.Error as e:
            self.calendar_error.emit(f"No se pudieron revisar los recordatorios: {e}")
            return
        for notification in notifications:
            self.reminder_due.emit(notification.title, notification.body)
        if notifications:
            self.reload()

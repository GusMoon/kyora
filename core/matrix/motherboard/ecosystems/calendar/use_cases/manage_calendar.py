import calendar
from datetime import date, datetime, timedelta
from typing import Dict, List, Optional

from core.matrix.motherboard.ecosystems.calendar.domain.entities import (
    AgendaItem, CalendarEvent, EVENT_KINDS, Notification, Reminder,
)
from core.matrix.motherboard.ecosystems.calendar.domain.recurrence import (
    next_occurrence, occurrence_in_year, occurs_on,
)
from core.matrix.motherboard.ecosystems.calendar.domain.repositories import CalendarRepository
from core.matrix.motherboard.ecosystems.calendar.domain.task_source import TaskSource

DEFAULT_ALL_DAY_REMINDER_TIME = "09:00"
_KIND_ORDER = {"task": 0, "birthday": 1, "event": 2, "reminder": 3}


def describe_advance(minutes: int) -> str:
    """
    Convierte una anticipación en minutos a texto legible.

    Args:
        minutes: Minutos de anticipación.

    Returns:
        str: Por ejemplo "10 minutos", "1 hora" o "2 días".
    """
    if minutes % 1440 == 0:
        days = minutes // 1440
        return f"{days} día" + ("s" if days != 1 else "")
    if minutes % 60 == 0:
        hours = minutes // 60
        return f"{hours} hora" + ("s" if hours != 1 else "")
    return f"{minutes} minutos"


def _parse_time(value: str, label: str) -> str:
    """Valida una hora "HH:MM" y la devuelve normalizada; vacío se acepta."""
    value = (value or "").strip()
    if not value:
        return ""
    try:
        return datetime.strptime(value, "%H:%M").strftime("%H:%M")
    except ValueError:
        raise ValueError(f"La {label} debe tener formato HH:MM.")


def _parse_date(value: str, label: str) -> date:
    """Valida una fecha ISO y la devuelve como `date`."""
    try:
        return date.fromisoformat((value or "").strip())
    except ValueError:
        raise ValueError(f"La {label} debe tener formato AAAA-MM-DD.")


class CalendarUseCases:
    """
    Casos de uso del calendario.

    Combina las tareas de Tareas (solo lectura), los eventos y fechas importantes
    propios y los recordatorios en una sola agenda, y decide cuándo disparar avisos.
    """

    def __init__(self, repository: CalendarRepository, task_source: TaskSource):
        """
        Args:
            repository: Persistencia de eventos y recordatorios.
            task_source: Fuente de lectura de las tareas con fecha límite.
        """
        self.repository = repository
        self.task_source = task_source

    # ----------------------------------------------------------------- agenda
    def get_month(self, year: int, month: int, today: date) -> Dict[str, List[AgendaItem]]:
        """
        Devuelve todas las actividades de un mes agrupadas por fecha ISO.

        Args:
            year: Año.
            month: Mes (1 a 12).
            today: Fecha actual, usada para marcar tareas vencidas.

        Returns:
            dict: `{fecha ISO: [AgendaItem ordenados]}` solo con los días que tienen actividades.
        """
        last_day = calendar.monthrange(year, month)[1]
        first, last = date(year, month, 1), date(year, month, last_day)
        prefix = f"{year:04d}-{month:02d}-"
        days: Dict[str, List[AgendaItem]] = {}

        def add(item: AgendaItem) -> None:
            days.setdefault(item.item_date, []).append(item)

        for task in self.task_source.list_tasks_with_due_date():
            if task.due_date.startswith(prefix):
                completed = task.status == "completed"
                add(AgendaItem(
                    kind="task", title=task.title, item_date=task.due_date, time=task.due_time,
                    source_id=task.task_id, status=task.status, detail=task.description,
                    overdue=(not completed and task.due_date < today.isoformat()),
                    checklist=list(task.subtasks),
                ))

        for event in self.repository.list_events():
            original = date.fromisoformat(event.event_date)
            if event.recurrence == "yearly":
                if year < original.year:
                    continue
                occurrence = occurrence_in_year(original, year)
                if occurrence.month != month:
                    continue
            else:
                occurrence = original
                if not first <= occurrence <= last:
                    continue
            add(AgendaItem(
                kind=event.kind, title=event.title, item_date=occurrence.isoformat(),
                time=event.start_time, end_time=event.end_time, source_id=event.id,
                detail=event.description, recurring=event.recurrence == "yearly",
            ))

        for reminder in self.repository.list_reminders():
            if reminder.event_id or not reminder.remind_at.startswith(prefix):
                continue
            add(AgendaItem(
                kind="reminder", title=reminder.text, item_date=reminder.remind_at[:10],
                time=reminder.remind_at[11:16], source_id=reminder.id,
                status="notified" if reminder.notified_at else "",
            ))

        for items in days.values():
            items.sort(key=lambda i: (i.time != "", i.time, _KIND_ORDER.get(i.kind, 9), i.title.lower()))
        return days

    def get_day(self, day: date, today: date) -> List[AgendaItem]:
        """Devuelve las actividades de un día, ordenadas."""
        return self.get_month(day.year, day.month, today).get(day.isoformat(), [])

    def count_by_day(self, start: date, end: date, today: date) -> Dict[str, int]:
        """
        Cuenta las actividades por día en un rango, para marcar la franja de días.

        Args:
            start: Primer día del rango (inclusive).
            end: Último día del rango (inclusive).
            today: Fecha actual.

        Returns:
            dict: `{fecha ISO: cantidad}` solo con los días del rango que tienen actividades.
        """
        counts: Dict[str, int] = {}
        year, month = start.year, start.month
        while (year, month) <= (end.year, end.month):
            for iso, items in self.get_month(year, month, today).items():
                if start.isoformat() <= iso <= end.isoformat():
                    counts[iso] = len(items)
            year, month = (year + 1, 1) if month == 12 else (year, month + 1)
        return counts

    # ---------------------------------------------------------------- eventos
    def _validate_event(self, title, event_date, start_time, end_time, kind):
        """Valida y normaliza los datos de un evento; devuelve una tupla lista para persistir."""
        title = (title or "").strip()
        if not title:
            raise ValueError("El nombre del evento no puede estar vacío.")
        if kind not in EVENT_KINDS:
            raise ValueError(f"Tipo de evento desconocido: {kind}")
        parsed_date = _parse_date(event_date, "fecha")
        if kind == "birthday":
            start_time = end_time = ""
        start = _parse_time(start_time, "hora de inicio")
        end = _parse_time(end_time, "hora de fin")
        if end and not start:
            raise ValueError("Define la hora de inicio antes de la hora de fin.")
        if start and end and end < start:
            raise ValueError("La hora de fin no puede ser anterior a la de inicio.")
        recurrence = "yearly" if kind == "birthday" else "none"
        return title, parsed_date, start, end, recurrence

    def _plan_advance(self, event_date: date, recurrence: str, start_time: str,
                      advance_minutes: int, now: datetime) -> Optional[str]:
        """
        Calcula cuándo debe sonar el recordatorio anticipado de un evento.

        Returns:
            str | None: Fecha-hora ISO "AAAA-MM-DDTHH:MM", o None si no hay anticipación.

        Raises:
            ValueError: Si un evento no recurrente quedaría con su aviso en el pasado.
        """
        if advance_minutes <= 0:
            return None
        base = datetime.strptime(start_time or DEFAULT_ALL_DAY_REMINDER_TIME, "%H:%M").time()
        floor = now.replace(second=0, microsecond=0)
        occurrence = next_occurrence(event_date, recurrence, now.date())
        for _ in range(3):
            if occurrence is None:
                break
            remind_at = datetime.combine(occurrence, base) - timedelta(minutes=advance_minutes)
            if remind_at >= floor:
                return remind_at.strftime("%Y-%m-%dT%H:%M")
            if recurrence != "yearly":
                break
            occurrence = occurrence_in_year(event_date, occurrence.year + 1)
        raise ValueError("El recordatorio anticipado quedaría en el pasado.")

    def _write_advance(self, event: CalendarEvent, advance_minutes: int, remind_at: Optional[str]) -> None:
        """Reemplaza el recordatorio anticipado del evento por el calculado."""
        self.repository.delete_reminders_for_event(event.id)
        if remind_at is None:
            return
        self.repository.save_reminder(Reminder(
            text=event.title, remind_at=remind_at, event_id=event.id, advance_minutes=advance_minutes,
        ))

    def create_event(self, title: str, event_date: str, start_time: str = "", end_time: str = "",
                     description: str = "", kind: str = "event", advance_minutes: int = 0,
                     now: Optional[datetime] = None) -> CalendarEvent:
        """
        Crea un evento personal o una fecha importante anual.

        Args:
            title: Nombre del evento.
            event_date: Fecha ISO (AAAA-MM-DD).
            start_time: Hora de inicio "HH:MM"; vacía si es de todo el día.
            end_time: Hora de fin "HH:MM", opcional.
            description: Descripción opcional.
            kind: "event" o "birthday" (se repite cada año).
            advance_minutes: Minutos de anticipación del recordatorio; 0 si no hay.
            now: Momento actual; por defecto `datetime.now()`.

        Returns:
            CalendarEvent: Evento persistido.

        Raises:
            ValueError: Si algún dato es inválido o el aviso quedaría en el pasado.
        """
        now = now or datetime.now()
        title, parsed_date, start, end, recurrence = self._validate_event(
            title, event_date, start_time, end_time, kind)
        remind_at = self._plan_advance(parsed_date, recurrence, start, advance_minutes, now)
        event = CalendarEvent(
            title=title, event_date=parsed_date.isoformat(), start_time=start, end_time=end,
            description=(description or "").strip(), kind=kind, recurrence=recurrence,
        )
        event.id = self.repository.save_event(event)
        self._write_advance(event, advance_minutes, remind_at)
        return event

    def update_event(self, event_id: str, title: str, event_date: str, start_time: str = "",
                     end_time: str = "", description: str = "", kind: str = "event",
                     advance_minutes: int = 0, now: Optional[datetime] = None) -> CalendarEvent:
        """
        Modifica un evento existente y rehace su recordatorio anticipado.

        Raises:
            ValueError: Si el evento no existe, algún dato es inválido o el aviso quedaría en el pasado.
        """
        if self.repository.get_event(event_id) is None:
            raise ValueError("El evento ya no existe.")
        now = now or datetime.now()
        title, parsed_date, start, end, recurrence = self._validate_event(
            title, event_date, start_time, end_time, kind)
        remind_at = self._plan_advance(parsed_date, recurrence, start, advance_minutes, now)
        event = CalendarEvent(
            id=event_id, title=title, event_date=parsed_date.isoformat(), start_time=start,
            end_time=end, description=(description or "").strip(), kind=kind, recurrence=recurrence,
        )
        self.repository.save_event(event)
        self._write_advance(event, advance_minutes, remind_at)
        return event

    def get_event(self, event_id: str) -> Optional[CalendarEvent]:
        """Obtiene un evento por identificador."""
        return self.repository.get_event(event_id)

    def get_event_advance(self, event_id: str) -> int:
        """Devuelve los minutos de anticipación configurados para el evento (0 si no hay)."""
        reminders = self.repository.list_reminders_for_event(event_id)
        return reminders[0].advance_minutes if reminders else 0

    def delete_event(self, event_id: str) -> None:
        """Elimina un evento y sus recordatorios."""
        self.repository.delete_event(event_id)

    # ----------------------------------------------------------- recordatorios
    @staticmethod
    def _remind_at(remind_date: str, remind_time: str) -> str:
        """Valida fecha y hora de un recordatorio y las une en formato ISO."""
        parsed = _parse_date(remind_date, "fecha")
        time_value = _parse_time(remind_time, "hora")
        if not time_value:
            raise ValueError("El recordatorio necesita una hora.")
        return f"{parsed.isoformat()}T{time_value}"

    def create_reminder(self, text: str, remind_date: str, remind_time: str) -> Reminder:
        """
        Crea un recordatorio independiente.

        Args:
            text: Motivo del recordatorio.
            remind_date: Fecha ISO (AAAA-MM-DD).
            remind_time: Hora "HH:MM".

        Returns:
            Reminder: Recordatorio persistido.

        Raises:
            ValueError: Si el texto está vacío o la fecha u hora son inválidas.
        """
        text = (text or "").strip()
        if not text:
            raise ValueError("El motivo del recordatorio no puede estar vacío.")
        reminder = Reminder(text=text, remind_at=self._remind_at(remind_date, remind_time))
        reminder.id = self.repository.save_reminder(reminder)
        return reminder

    def update_reminder(self, reminder_id: str, text: str, remind_date: str, remind_time: str) -> Reminder:
        """
        Modifica un recordatorio y lo vuelve a dejar pendiente de notificar.

        Raises:
            ValueError: Si no existe o algún dato es inválido.
        """
        existing = self.repository.get_reminder(reminder_id)
        if existing is None or existing.event_id:
            raise ValueError("El recordatorio ya no existe.")
        text = (text or "").strip()
        if not text:
            raise ValueError("El motivo del recordatorio no puede estar vacío.")
        reminder = Reminder(id=reminder_id, text=text, remind_at=self._remind_at(remind_date, remind_time))
        self.repository.save_reminder(reminder)
        return reminder

    def get_reminder(self, reminder_id: str) -> Optional[Reminder]:
        """Obtiene un recordatorio por identificador."""
        return self.repository.get_reminder(reminder_id)

    def delete_reminder(self, reminder_id: str) -> None:
        """Elimina un recordatorio."""
        self.repository.delete_reminder(reminder_id)

    # ------------------------------------------------------------ notificación
    def collect_due_reminders(self, now: datetime) -> List[Notification]:
        """
        Reclama los recordatorios cuya hora ya llegó y devuelve sus avisos.

        Cada recordatorio se reclama de forma atómica, así que un mismo aviso no se
        entrega dos veces aunque la comprobación corra repetidamente. Los avisos de
        eventos anuales programan el del año siguiente.

        Args:
            now: Momento actual.

        Returns:
            list: Avisos recién generados.
        """
        now_iso = now.strftime("%Y-%m-%dT%H:%M")
        notifications: List[Notification] = []
        for reminder in self.repository.list_due_reminders(now_iso):
            event = self.repository.get_event(reminder.event_id) if reminder.event_id else None
            if reminder.event_id and event is None:
                self.repository.delete_reminder(reminder.id)
                continue
            if event is not None:
                when = describe_advance(reminder.advance_minutes)
                body = f"Es en {when}" if event.start_time == "" else f"Comienza en {when}"
                notification = Notification(
                    reminder_id=reminder.id, source_type="event", source_id=event.id,
                    title=event.title, body=body,
                )
            else:
                notification = Notification(
                    reminder_id=reminder.id, source_type="reminder", source_id=reminder.id,
                    title=reminder.text, body=f"Recordatorio de las {reminder.remind_at[11:16]}",
                )
            if not self.repository.claim_reminder(reminder.id, now_iso, notification):
                continue
            notifications.append(notification)
            if event is not None and event.recurrence == "yearly" and reminder.advance_minutes > 0:
                self._schedule_next_year(event, reminder)
        return notifications

    def _schedule_next_year(self, event: CalendarEvent, fired: Reminder) -> None:
        """Programa el recordatorio anticipado de la siguiente ocurrencia anual."""
        occurrence = (datetime.fromisoformat(fired.remind_at)
                      + timedelta(minutes=fired.advance_minutes)).date()
        next_date = occurrence_in_year(date.fromisoformat(event.event_date), occurrence.year + 1)
        base = datetime.strptime(event.start_time or DEFAULT_ALL_DAY_REMINDER_TIME, "%H:%M").time()
        remind_at = datetime.combine(next_date, base) - timedelta(minutes=fired.advance_minutes)
        self.repository.save_reminder(Reminder(
            text=event.title, remind_at=remind_at.strftime("%Y-%m-%dT%H:%M"),
            event_id=event.id, advance_minutes=fired.advance_minutes,
        ))

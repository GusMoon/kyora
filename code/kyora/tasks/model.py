"""Lo que no necesita la base de datos (se puede probar): duraciones, el tiempo del cronómetro y los filtros.

Las fechas se guardan como texto ISO local: "2026-10-21T22:45:00" (las de entrega, sin segundos).
"""
import re
from datetime import date, datetime, timedelta

DUE_FILTERS = (
    ("all", "Todas"),
    ("today", "Hoy"),
    ("week", "Esta semana"),
    ("overdue", "Vencidas"),
    ("none", "Sin fecha"),
)
_UNITS = re.compile(r"(\d+(?:[.,]\d+)?)\s*(horas|hora|h|minutos|minuto|mins|min|m)?(?![a-z])")


def parse_duration(text):
    """Minutos de un texto libre: "90", "1:30", "1 h 30 min", "1h30", "2 h", "45 min", "1,5 h". None si está vacío.

    Lanza ValueError si no se entiende."""
    text = (text or "").strip().lower()
    if not text:
        return None
    if re.fullmatch(r"\d+:\d{1,2}", text):
        hours, minutes = text.split(":")
        return int(hours) * 60 + int(minutes)
    if re.fullmatch(r"\d+", text):
        return int(text)
    total, found, unit_before = 0.0, False, None
    for number, unit in _UNITS.findall(text):
        value = float(number.replace(",", "."))
        if unit.startswith("h"):
            total += value * 60
        elif unit or unit_before == "h":
            total += value
        else:
            raise ValueError(f"No entiendo «{text}»")
        unit_before = "h" if unit.startswith("h") else "m"
        found = True
    if not found or re.sub(r"[\d.,\s]|horas?|h|minutos?|mins?|m", "", text):
        raise ValueError(f"No entiendo «{text}»: escribe por ejemplo 1 h 30 min")
    return round(total)


def format_duration(minutes):
    """"1 h 30 min", "45 min", "2 h"; vacío si no hay."""
    if minutes is None:
        return ""
    hours, rest = divmod(int(minutes), 60)
    if hours and rest:
        return f"{hours} h {rest} min"
    return f"{hours} h" if hours else f"{rest} min"


def format_seconds(seconds):
    """Cronómetro: "1:02:03" o "12:05"."""
    seconds = max(int(seconds), 0)
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}:{minutes:02d}:{secs:02d}" if hours else f"{minutes}:{secs:02d}"


def parse_time(text):
    return datetime.fromisoformat(text) if text else None


def real_seconds(task, now):
    """Tiempo real de la tarea, con lo que lleva el cronómetro si está en marcha."""
    started = parse_time(task.get("timer_started"))
    running = max((now - started).total_seconds(), 0) if started else 0
    return int(task.get("real_s") or 0) + int(running)


def week_range(today):
    """(lunes, domingo) de la semana de `today`."""
    monday = today - timedelta(days=today.weekday())
    return monday, monday + timedelta(days=6)


def matches(task, tag_ids, due_filter, now, show_finished):
    """¿Sale la tarea con estos filtros? `tag_ids`: vale con tener una de ellas. `now`: datetime."""
    if task.get("finished") and not show_finished:
        return False
    if tag_ids and not set(tag_ids) & {tag["id"] for tag in task.get("tags", ())}:
        return False
    due = parse_time(task.get("due"))
    if due_filter == "today":
        return due is not None and due.date() == now.date()
    if due_filter == "week":
        monday, sunday = week_range(now.date())
        return due is not None and monday <= due.date() <= sunday
    if due_filter == "overdue":
        return due is not None and not task.get("finished") and due < now
    if due_filter == "none":
        return due is None
    return True


def sort_key(task):
    """Primero las que tienen entrega (la más cercana antes), después las demás por creación; las finalizadas al final."""
    due = task.get("due")
    return (bool(task.get("finished")), due is None, due or "", task.get("created") or "")


def due_label(due_text, today=None):
    """"Hoy 18:00", "Mañana 09:30", "25/10 18:00"; vacío si no hay entrega."""
    due = parse_time(due_text)
    if due is None:
        return ""
    today = today or date.today()
    clock = due.strftime("%H:%M")
    if due.date() == today:
        return f"Hoy {clock}"
    if due.date() == today + timedelta(days=1):
        return f"Mañana {clock}"
    if due.date() == today - timedelta(days=1):
        return f"Ayer {clock}"
    return due.strftime("%d/%m ") + clock

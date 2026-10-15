import calendar
from datetime import date
from typing import Optional


def occurrence_in_year(event_date: date, year: int) -> date:
    """
    Devuelve la fecha del aniversario de `event_date` en el año indicado.

    El 29 de febrero se desplaza al 28 en los años no bisiestos.

    Args:
        event_date: Fecha original del evento.
        year: Año del que se quiere la ocurrencia.

    Returns:
        date: Fecha de la ocurrencia en `year`.
    """
    last_day = calendar.monthrange(year, event_date.month)[1]
    return date(year, event_date.month, min(event_date.day, last_day))


def occurs_on(event_date: date, recurrence: str, day: date) -> bool:
    """
    Indica si un evento ocurre en una fecha dada.

    Args:
        event_date: Fecha original del evento.
        recurrence: "none" o "yearly".
        day: Fecha a comprobar.

    Returns:
        bool: True si el evento cae en `day`.
    """
    if recurrence == "yearly":
        return day.year >= event_date.year and occurrence_in_year(event_date, day.year) == day
    return event_date == day


def next_occurrence(event_date: date, recurrence: str, from_date: date) -> Optional[date]:
    """
    Devuelve la primera ocurrencia en o después de `from_date`.

    Args:
        event_date: Fecha original del evento.
        recurrence: "none" o "yearly".
        from_date: Fecha desde la que se busca (inclusive).

    Returns:
        date | None: La ocurrencia, o None si el evento no recurrente ya pasó.
    """
    if recurrence != "yearly":
        return event_date if event_date >= from_date else None
    year = max(from_date.year, event_date.year)
    occurrence = occurrence_in_year(event_date, year)
    if occurrence < from_date:
        occurrence = occurrence_in_year(event_date, year + 1)
    return occurrence

import calendar
from datetime import date, timedelta

UNITS = ("day", "month", "year")


def shift_date(day: date, unit: str, steps: int) -> date:
    """
    Desplaza una fecha en días, meses o años.

    Al mover meses o años el día se ajusta al último día válido del mes destino
    (31 de enero + 1 mes = 28 o 29 de febrero).

    Args:
        day: Fecha de partida.
        unit: "day", "month" o "year".
        steps: Cantidad de unidades; negativa para retroceder.

    Returns:
        date: Fecha resultante.

    Raises:
        ValueError: Si `unit` no es una unidad conocida.
    """
    if unit == "day":
        return day + timedelta(days=steps)
    if unit == "month":
        months = day.year * 12 + (day.month - 1) + steps
        year, month = divmod(months, 12)
        month += 1
    elif unit == "year":
        year, month = day.year + steps, day.month
    else:
        raise ValueError(f"Unidad desconocida: {unit}")
    year = max(date.min.year, min(date.max.year, year))
    last_day = calendar.monthrange(year, month)[1]
    return date(year, month, min(day.day, last_day))

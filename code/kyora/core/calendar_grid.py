"""Cuadrícula del calendario mensual (sin Qt: se puede probar). Las semanas empiezan en lunes, como en España."""
from datetime import date, timedelta

MONTHS = ("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
          "noviembre", "diciembre")
WEEKDAYS = ("lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo")
INITIALS = ("L", "M", "X", "J", "V", "S", "D")
SHORT = ("Lun", "Mar", "Mié", "Jue", "Vie", "Sáb", "Dom")


def month_grid(year, month):
    """6 semanas de lunes a domingo con todas las fechas que se ven (también las de los meses de al lado)."""
    first = date(year, month, 1)
    start = first - timedelta(days=first.weekday())
    return [[start + timedelta(days=7 * week + day) for day in range(7)] for week in range(6)]


def shift_month(year, month, delta):
    """(año, mes) a `delta` meses de distancia."""
    index = year * 12 + (month - 1) + delta
    return index // 12, index % 12 + 1


def long_date(day):
    """"miércoles, 21 de octubre de 2026"."""
    return f"{WEEKDAYS[day.weekday()]}, {day.day} de {MONTHS[day.month - 1]} de {day.year}"


def week_days(today, before=3, after=3):
    """Los días alrededor de hoy, como la franja de la referencia (22 23 24 [25] 26 27 28)."""
    return [today + timedelta(days=d) for d in range(-before, after + 1)]

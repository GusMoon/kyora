"""
Paleta, textos y utilidades de dibujo del ecosistema de calendario.

Toma sus valores de `kyora_theme` (globalKyoraUI): superficies oscuras, bordes grises,
acento durazno y radios de 4 a 6 px. Los colores de estado de las tareas son los
de Tareas; los demás tipos de actividad usan neutros y el acento.
"""
from PySide6.QtCore import QRectF
from PySide6.QtGui import QPainterPath

from core.matrix.motherboard.ecosystems.calendar.domain.entities import AgendaItem
from core.matrix.motherboard.modules import kyora_theme as kt

FONT_FAMILY = kt.FONT

BG = kt.BG_APP
PANEL = kt.BG_CONTAINER
CELL = kt.BG_INSET
CELL_DIM = kt.BG_APP
CARD = kt.BG_CARD
CARD_HOVER = kt.BG_CARD_HOVER
BORDER = kt.BORDER
BORDER_SOFT = kt.BORDER_SOFT
BORDER_FAINT = kt.BORDER_FAINT
BORDER_HOVER = kt.BORDER_HOVER
TEXT = kt.TEXT
MUTED = kt.TEXT_SUB
DIM = kt.TEXT_DISABLED
ACCENT = kt.ACCENT
ACCENT_TINT = kt.ACCENT_TINT
ERROR = kt.DANGER
BADGE_BG = kt.BG_BADGE

STATUS_COLORS = {
    "pending": kt.STATUS_PENDING,
    "in_progress": kt.STATUS_IN_PROGRESS,
    "completed": kt.STATUS_COMPLETED,
}
STATUS_LABELS = {"pending": "PENDIENTE", "in_progress": "EN PROGRESO", "completed": "COMPLETADA"}
OVERDUE_COLOR = kt.DANGER
EVENT_COLOR = kt.TEXT_BODY
BIRTHDAY_COLOR = kt.ACCENT
REMINDER_COLOR = kt.TEXT_SUB

LEGEND = [
    ("Pendiente", STATUS_COLORS["pending"]),
    ("En progreso", STATUS_COLORS["in_progress"]),
    ("Completada", STATUS_COLORS["completed"]),
    ("Vencida", OVERDUE_COLOR),
    ("Evento", EVENT_COLOR),
    ("✦ Cumpleaños", BIRTHDAY_COLOR),
    ("● Recordatorio", REMINDER_COLOR),
]

MONTHS_ES = [
    "ENERO", "FEBRERO", "MARZO", "ABRIL", "MAYO", "JUNIO", "JULIO",
    "AGOSTO", "SEPTIEMBRE", "OCTUBRE", "NOVIEMBRE", "DICIEMBRE",
]
WEEKDAYS_SHORT = ["LUN", "MAR", "MIÉ", "JUE", "VIE", "SÁB", "DOM"]
WEEKDAYS_FULL = ["LUNES", "MARTES", "MIÉRCOLES", "JUEVES", "VIERNES", "SÁBADO", "DOMINGO"]

_GLYPHS = {"birthday": "✦ ", "reminder": "● "}


def item_color(item: AgendaItem) -> str:
    """
    Devuelve el color que identifica a una actividad.

    Args:
        item: Actividad de la agenda.

    Returns:
        str: Color hexadecimal.
    """
    if item.kind == "task":
        if item.overdue:
            return OVERDUE_COLOR
        return STATUS_COLORS.get(item.status, STATUS_COLORS["pending"])
    return {"event": EVENT_COLOR, "birthday": BIRTHDAY_COLOR, "reminder": REMINDER_COLOR}.get(
        item.kind, MUTED)


def item_glyph(item: AgendaItem) -> str:
    """Devuelve el símbolo que acompaña al título de cumpleaños y recordatorios; vacío en el resto."""
    return _GLYPHS.get(item.kind, "")


def rounded_path(rect: QRectF, radius: float) -> QPainterPath:
    """
    Construye un rectángulo de esquinas redondeadas.

    Args:
        rect: Rectángulo base.
        radius: Radio de las esquinas (4 en tarjetas y celdas, 6 en paneles).

    Returns:
        QPainterPath: Trazado cerrado.
    """
    return kt.rounded_path(rect, radius)


def button_style(kind: str = "standard", padding: str = "7px 14px", font_px: int = 11) -> str:
    """
    Devuelve el QSS de un botón (variantes de globalKyoraUI).

    Args:
        kind: "standard", "primary", "ghost", "accent" o "danger".
        padding: Relleno CSS.
        font_px: Tamaño de la fuente en píxeles.

    Returns:
        str: Hoja de estilos.
    """
    return kt.button_style(kind, padding, font_px)


def chip_style() -> str:
    """Devuelve el QSS de un chip conmutable (reposo y `:checked`)."""
    return kt.chip_style()

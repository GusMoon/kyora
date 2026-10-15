"""
Paleta y tipografía del libro de la bitácora.

Toma sus valores de `kyora_theme` (globalKyoraUI): superficies oscuras, bordes grises,
acento durazno y radios de 6 px. La cubierta usa el tono de contenedor y las
hojas el del cuerpo del archivador de Tareas.
"""
from PySide6.QtCore import QRectF
from PySide6.QtGui import QPainterPath

from core.matrix.motherboard.globalComponents import kyora_theme as kt

FONT_FAMILY = kt.FONT

COVER = kt.BG_CONTAINER
COVER_EDGE = kt.BORDER
PAPER = kt.BG_FOLDER
PAPER_EDGE = kt.BORDER_SOFT
SPINE = kt.BORDER
BRACKET = kt.BORDER

TEXT = kt.TEXT
TEXT_BODY = "#DDDDDD"
TEXT_MUTED = kt.TEXT_SUB
TEXT_DIM = kt.TEXT_DIM
ACCENT = kt.ACCENT

RADIUS = kt.RADIUS_PANEL


def rounded_path(rect: QRectF, radius: float = RADIUS) -> QPainterPath:
    """
    Construye un rectángulo de esquinas redondeadas.

    Args:
        rect: Rectángulo base.
        radius: Radio de las esquinas (6 px por defecto).

    Returns:
        QPainterPath: Trazado cerrado.
    """
    return kt.rounded_path(rect, radius)

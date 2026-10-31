"""Material del marco: degradado gris oscuro y borde en relieve de las piezas que sobresalen.

El marco y todo lo que sale de él (buscador, cápsulas, paneles) comparten un mismo borde nítido: una línea oscura
fina por fuera y un filete de luz por dentro. El borde interior (hueco y buscador) añade una sombra corta y suave,
igual en los 4 lados, que lo despega del fondo de pantalla.
"""
from PySide6.QtCore import Qt
from PySide6.QtGui import (
    QColor,
    QPainter,
    QPainterPath,
    QPen,
)

from kyora.ui import backdrop

SHADOW_STEPS = 10  # pasadas concéntricas de la sombra del borde: suficientes para que no se vean bandas


def frame_gradient(theme, height, window_y=0, window_x=0):
    """El fondo de los paneles: un gris oscuro liso y opaco (ver backdrop.PANEL_GRAY), igual en todos."""
    return QColor(backdrop.PANEL_GRAY)


def paint_raised_edge(painter, piece, bounds, theme, contour=None, shadow=False):
    """Borde de una pieza que sobresale: línea oscura por fuera y filete de luz uniforme por dentro.

    `piece` es la forma rellena de la pieza, `bounds` el rectángulo de la ventana donde se pinta y `contour`
    el trazo del borde (por defecto el de la pieza; el marco solo lo lleva alrededor del hueco, no en la pantalla).
    Con `shadow` el borde proyecta además una sombra corta y suave hacia fuera (el borde interior del marco).
    """
    contour = piece if contour is None else contour
    painter.save()
    painter.setBrush(Qt.NoBrush)
    painter.setRenderHint(QPainter.Antialiasing)
    outside = QPainterPath()
    outside.addRect(bounds)
    outside = outside.subtracted(piece)
    painter.setClipPath(outside)
    if shadow:
        per_step = 1 - (1 - theme.edge_shadow_alpha) ** (1 / SHADOW_STEPS)
        color = QColor(0, 0, 0)
        color.setAlphaF(per_step)
        for i in range(SHADOW_STEPS):
            reach = theme.edge_shadow_size * ((SHADOW_STEPS - i) / SHADOW_STEPS) ** 2  # caída cuadrática: suave hacia fuera
            painter.setPen(QPen(color, 2 * reach))
            painter.drawPath(contour)
    painter.setPen(QPen(QColor(theme.edge_dark), theme.edge_width * 2))
    painter.drawPath(contour)
    painter.setClipPath(piece)
    painter.setPen(QPen(QColor(theme.edge_light), theme.edge_width * 2))
    painter.drawPath(contour)
    painter.restore()


def paint_soft_shadow(painter, piece, bounds, theme, contour=None):
    """Borde minimalista de un panel: nada de filetes ni relieve, solo una sombra suave y sutil alrededor de la pieza.

    `piece` es la forma rellena, `bounds` el rectángulo de la ventana donde se pinta y `contour` el trazo del borde
    (por defecto el de la pieza). La sombra solo cae fuera de la pieza y cae despacio hacia fuera.
    """
    contour = piece if contour is None else contour
    painter.save()
    painter.setBrush(Qt.NoBrush)
    painter.setRenderHint(QPainter.Antialiasing)
    outside = QPainterPath()
    outside.addRect(bounds)
    painter.setClipPath(outside.subtracted(piece))
    per_step = 1 - (1 - theme.dock_shadow_alpha) ** (1 / SHADOW_STEPS)
    color = QColor(0, 0, 0)
    color.setAlphaF(per_step)
    for i in range(SHADOW_STEPS):
        reach = theme.dock_shadow_size * ((SHADOW_STEPS - i) / SHADOW_STEPS) ** 2
        painter.setPen(QPen(color, 2 * reach, Qt.SolidLine, Qt.FlatCap))
        painter.drawPath(contour)
    painter.restore()

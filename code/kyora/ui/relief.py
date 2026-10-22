"""Material del marco: degradado gris oscuro y borde en relieve de las piezas que sobresalen.

El marco y todo lo que sale de él (buscador, cápsulas, paneles) comparten un mismo borde nítido: una línea oscura
fina por fuera y un filete de luz por dentro. El borde interior (hueco y buscador) añade una sombra corta y suave,
igual en los 4 lados, que lo despega del fondo de pantalla.
"""
from PySide6.QtCore import QRectF, Qt
from PySide6.QtGui import (
    QColor,
    QImage,
    QLinearGradient,
    QPainter,
    QPainterPath,
    QPen,
)

from kyora.ui.shapes import frame_path, hole_path

SHADOW_STEPS = 10  # pasadas concéntricas de la sombra del borde: suficientes para que no se vean bandas


def frame_gradient(theme, height, window_y=0):
    """Material del marco: algo más claro arriba. Se usa igual en la barra, el marco y el buscador para que sean uno.

    `window_y` es la posición de la ventana en la pantalla: el degradado abarca siempre la pantalla entera.
    """
    g = QLinearGradient(0, -window_y, 0, height - window_y)
    g.setColorAt(0, QColor(theme.frame_light))
    g.setColorAt(1, QColor(theme.frame_dark))
    return g


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


def build_frame_image(theme, width, height, dpr=1.0):
    """Imagen completa del marco. Se calcula una vez y luego solo se dibuja."""
    image = QImage(round(width * dpr), round(height * dpr), QImage.Format_ARGB32_Premultiplied)
    image.setDevicePixelRatio(dpr)
    image.fill(Qt.transparent)
    insets = theme.insets()
    frame = frame_path(width, height, insets, theme.hole_radius)
    p = QPainter(image)
    p.setRenderHint(QPainter.Antialiasing)
    p.fillPath(frame, frame_gradient(theme, height))
    hole = hole_path(width, height, insets, theme.hole_radius)
    paint_raised_edge(p, frame, QRectF(0, 0, width, height), theme, contour=hole, shadow=True)
    p.end()
    return image

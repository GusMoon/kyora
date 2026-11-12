"""El icono de cada estado de una tarea, el mismo en la línea de tiempo, el Kanban, la tarjeta de la tarea y sus
subtareas:

- Pendiente: un aro de pedacitos (punteado) gris.
- En proceso: un aro completo gris con un círculo pequeño dentro.
- En revisión: un círculo relleno con el color de énfasis y un círculo pequeño dentro.
- Finalizada: un círculo relleno con el color de énfasis y una palomita dentro.
- Las subtareas solo tienen dos: sin terminar ("open": un aro vacío) y terminada (como Finalizada).
"""
from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QPainter, QPen, QPixmap

from kyora.ui import glyphs


def grey(theme):
    """El gris de los estados que aún no llegan a revisión."""
    return QColor(theme.dim)


def paint_status(p, center, radius, status, theme):
    """Pinta el icono de `status` centrado en `center` (QPointF) con el `radius` dado."""
    accent, gray = QColor(theme.gold), grey(theme)
    p.save()
    p.setRenderHint(QPainter.Antialiasing)
    if status == "pending":
        pen = QPen(gray, max(radius * 0.17, 1.4), Qt.CustomDashLine)
        pen.setDashPattern([1.2, 2.2])
        pen.setCapStyle(Qt.RoundCap)
        p.setPen(pen)
        p.setBrush(Qt.NoBrush)
        p.drawEllipse(center, radius - 0.8, radius - 0.8)
    elif status == "open":
        p.setPen(QPen(gray, max(radius * 0.17, 1.4)))
        p.setBrush(Qt.NoBrush)
        p.drawEllipse(center, radius - 0.8, radius - 0.8)
    elif status == "doing":
        p.setPen(QPen(gray, max(radius * 0.17, 1.4)))
        p.setBrush(Qt.NoBrush)
        p.drawEllipse(center, radius - 0.8, radius - 0.8)
        p.setPen(Qt.NoPen)
        p.setBrush(gray)
        p.drawEllipse(center, radius * 0.3, radius * 0.3)
    else:
        p.setPen(Qt.NoPen)
        p.setBrush(accent)
        p.drawEllipse(center, radius, radius)
        ink = QColor(theme.pick_ink)
        if status == "review":
            p.setBrush(ink)
            p.drawEllipse(center, radius * 0.3, radius * 0.3)
        else:  # done: la palomita
            p.setBrush(Qt.NoBrush)
            p.setPen(glyphs.pen(ink, max(radius * 0.2, 1.6)))
            box = QRectF(center.x() - radius * 0.6, center.y() - radius * 0.6, radius * 1.2, radius * 1.2)
            glyphs.status_done(p, box)
    p.restore()


def status_pixmap(theme, status, size, dpr=1.0):
    """El icono como QPixmap de `size` px lógicos (para botones)."""
    pixmap = QPixmap(round(size * dpr), round(size * dpr))
    pixmap.setDevicePixelRatio(dpr)
    pixmap.fill(Qt.transparent)
    p = QPainter(pixmap)
    paint_status(p, QPointF(size / 2, size / 2), size / 2 - 0.5, status, theme)
    p.end()
    return pixmap

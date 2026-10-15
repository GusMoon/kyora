"""
Icono vectorial de Clima (sol tras una nube) para el ecosistema Kiora.
Proporciona renderizado nativo mediante QPainter y generadores de QIcon/QPixmap.
"""
import math
from typing import Union

from PySide6.QtCore import Qt, QPointF, QRectF
from PySide6.QtGui import QColor, QIcon, QPainter, QPainterPath, QPen, QPixmap


def draw(
    painter: QPainter,
    center: QPointF,
    scale: float = 1.0,
    color: Union[QColor, str] = "#FFFFFF",
    base_size: float = 24.0,
) -> None:
    """
    Dibuja un sol con rayos parcialmente cubierto por una nube.

    Args:
        painter: Instancia activa de QPainter.
        center: Coordenada central del dibujo (QPointF).
        scale: Factor multiplicador de escala.
        color: Color del trazo (QColor o string hexadecimal).
        base_size: Tamaño base sobre el cual se proyecta el icono.
    """
    painter.save()
    painter.translate(center)
    final_scale = scale * (base_size / 24.0)
    painter.scale(final_scale, final_scale)

    if isinstance(color, str):
        color = QColor(color)

    painter.setPen(QPen(color, 1.6, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
    painter.setBrush(Qt.NoBrush)

    # Sol arriba a la derecha: disco y rayos en las direcciones no tapadas por la nube
    sun = QPointF(3.5, -4.0)
    painter.drawEllipse(sun, 3.2, 3.2)
    for degrees in (-90, -45, 0, 45):
        angle = math.radians(degrees)
        direction = QPointF(math.cos(angle), math.sin(angle))
        painter.drawLine(sun + direction * 5.4, sun + direction * 7.2)

    # Nube delante: se rellena con el fondo transparente para ocultar el sol detrás
    cloud = QPainterPath()
    cloud.moveTo(-8.5, 8.0)
    cloud.cubicTo(-12.0, 8.0, -12.0, 1.5, -7.0, 1.5)
    cloud.cubicTo(-6.5, -3.0, 0.5, -3.5, 1.5, 0.5)
    cloud.cubicTo(6.5, -0.5, 8.0, 7.5, 3.5, 8.0)
    cloud.closeSubpath()
    painter.save()
    painter.setCompositionMode(QPainter.CompositionMode_Clear)
    painter.fillPath(cloud, Qt.black)
    painter.restore()
    painter.drawPath(cloud)

    painter.restore()


def get_weather_pixmap(size: int = 22, color: Union[QColor, str] = "#FFFFFF") -> QPixmap:
    """
    Genera un QPixmap transparente con el icono de clima.

    Args:
        size: Dimensiones cuadradas en píxeles.
        color: Color del icono.

    Returns:
        QPixmap listo para usar en etiquetas o botones.
    """
    pixmap = QPixmap(size, size)
    pixmap.fill(Qt.transparent)
    painter = QPainter(pixmap)
    painter.setRenderHint(QPainter.Antialiasing)
    draw(painter, QPointF(size / 2.0, size / 2.0), scale=size / 24.0, color=color, base_size=24.0)
    painter.end()
    return pixmap


def get_weather_icon(size: int = 22, color: Union[QColor, str] = "#FFFFFF") -> QIcon:
    """Crea un QIcon con el icono de clima."""
    return QIcon(get_weather_pixmap(size=size, color=color))

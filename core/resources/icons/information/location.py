"""
Icono vectorial de Ubicación (marcador de mapa) para el ecosistema Kiora.
"""
from typing import Union

from PySide6.QtCore import Qt, QPointF
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen


def draw(
    painter: QPainter,
    center: QPointF,
    scale: float = 1.0,
    color: Union[QColor, str] = "#FFFFFF",
    base_size: float = 24.0,
) -> None:
    """
    Dibuja un marcador de ubicación con un círculo en su interior.

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

    # Gota con la punta hacia abajo
    pin = QPainterPath()
    pin.moveTo(0.0, 10.5)
    pin.cubicTo(-9.0, 1.5, -8.0, -10.5, 0.0, -10.5)
    pin.cubicTo(8.0, -10.5, 9.0, 1.5, 0.0, 10.5)
    painter.drawPath(pin)
    painter.drawEllipse(QPointF(0.0, -3.0), 3.2, 3.2)

    painter.restore()

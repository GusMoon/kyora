"""
Icono vectorial de Calendario con estética Sci-Fi para el ecosistema Kiora.
Proporciona renderizado nativo mediante QPainter y generadores de QIcon/QPixmap.
"""
from typing import Union
from PySide6.QtCore import Qt, QPointF, QRectF
from PySide6.QtGui import QPainter, QColor, QPen, QPainterPath, QPixmap, QIcon


def draw(
    painter: QPainter, 
    center: QPointF, 
    scale: float = 1.0, 
    color: Union[QColor, str] = "#FFAA77", 
    base_size: float = 24.0
) -> None:
    """
    Dibuja un icono de calendario con diseño geométrico y futurista.

    Args:
        painter: Instancia activa de QPainter.
        center: Coordenada central del dibujo (QPointF).
        scale: Factor multiplicador de escala.
        color: Color principal del trazo y acentos (QColor o string hexadecimal).
        base_size: Tamaño base sobre el cual se proyecta el icono.
    """
    painter.save()
    painter.translate(center)

    final_scale = scale * (base_size / 24.0)
    painter.scale(final_scale, final_scale)

    if isinstance(color, str):
        color = QColor(color)

    # 1. Configuración del trazo principal
    pen = QPen(color, 1.6, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin)
    painter.setPen(pen)
    painter.setBrush(Qt.NoBrush)

    # 2. Pines superiores de conexión / suspensión tecnológica
    painter.drawLine(QPointF(-5.0, -10.0), QPointF(-5.0, -6.5))
    painter.drawLine(QPointF(5.0, -10.0), QPointF(5.0, -6.5))

    # 3. Marco exterior Sci-Fi con esquina inferior derecha biselada (corte angular)
    path = QPainterPath()
    path.moveTo(-8.5, -7.0)
    path.lineTo(8.5, -7.0)
    path.lineTo(8.5, 4.5)
    path.lineTo(5.5, 7.5)   # Bisel inferior derecho
    path.lineTo(-8.5, 7.5)
    path.closeSubpath()
    painter.drawPath(path)

    # 4. Línea divisoria de cabecera (interfaz de datos)
    painter.drawLine(QPointF(-8.5, -2.5), QPointF(8.5, -2.5))

    # 5. Matriz digital de nodos de fecha
    # Fila superior de nodos
    painter.drawPoint(QPointF(-4.5, 0.8))
    painter.drawPoint(QPointF(0.0, 0.8))
    painter.drawPoint(QPointF(4.5, 0.8))

    # Fila inferior de nodos
    painter.drawPoint(QPointF(-4.5, 4.5))

    # Nodo activo resaltado (celda de fecha actual/seleccionada)
    painter.setPen(Qt.NoPen)
    painter.setBrush(color)
    painter.drawRect(QRectF(-1.0, 3.5, 2.0, 2.0))

    # 6. Muesca angular decorativa en el bisel
    pen_detail = QPen(color, 1.0, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin)
    painter.setPen(pen_detail)
    painter.setBrush(Qt.NoBrush)
    painter.drawLine(QPointF(5.5, 7.5), QPointF(8.5, 4.5))

    painter.restore()


def get_calendar_pixmap(size: int = 22, color: Union[QColor, str] = "#FFAA77") -> QPixmap:
    """
    Genera un QPixmap con transparencia y renderizado antialiasing del icono.

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
    center = QPointF(size / 2.0, size / 2.0)
    scale = size / 24.0
    draw(painter, center, scale=scale, color=color, base_size=24.0)
    painter.end()

    return pixmap


def get_calendar_icon(size: int = 22, color: Union[QColor, str] = "#FFAA77") -> QIcon:
    """
    Crea un QIcon a partir del icono de calendario Sci-Fi.

    Args:
        size: Tamaño del icono en píxeles.
        color: Color de trazo del icono.

    Returns:
        QIcon compatible con QPushButton y otros widgets de Qt.
    """
    return QIcon(get_calendar_pixmap(size=size, color=color))

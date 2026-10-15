"""
Icono vectorial de Bote de Basura (Eliminar) con estética Sci-Fi para el ecosistema Kiora.
Proporciona renderizado nativo mediante QPainter y generadores de QIcon/QPixmap.
"""
from typing import Union, Optional
from PySide6.QtCore import Qt, QPointF
from PySide6.QtGui import QPainter, QColor, QPen, QPainterPath, QPixmap, QIcon


def draw(
    painter: QPainter, 
    center: QPointF, 
    scale: float = 1.0, 
    color: Union[QColor, str] = "#888888", 
    base_size: float = 24.0
) -> None:
    """
    Dibuja un icono de bote de basura con diseño geométrico y futurista Sci-Fi.

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

    # 1. Trazo principal con uniones limpias
    pen = QPen(color, 1.6, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin)
    painter.setPen(pen)
    painter.setBrush(Qt.NoBrush)

    # 2. Asa superior (Handle Sci-Fi)
    handle_path = QPainterPath()
    handle_path.moveTo(-2.8, -6.5)
    handle_path.lineTo(-2.8, -8.8)
    handle_path.lineTo(2.8, -8.8)
    handle_path.lineTo(2.8, -6.5)
    painter.drawPath(handle_path)

    # 3. Tapa Sci-Fi extendida (Lid plate)
    painter.drawLine(QPointF(-8.8, -6.5), QPointF(8.8, -6.5))

    # 4. Cuerpo del contenedor con biseles inferiores Sci-Fi
    body = QPainterPath()
    body.moveTo(-6.5, -4.5)
    body.lineTo(-5.4, 6.8)
    body.lineTo(-3.6, 8.8)
    body.lineTo(3.6, 8.8)
    body.lineTo(5.4, 6.8)
    body.lineTo(6.5, -4.5)
    painter.drawPath(body)

    # 5. Ranuras verticales interiores de desintegración
    pen_slots = QPen(color, 1.5, Qt.SolidLine, Qt.RoundCap)
    painter.setPen(pen_slots)
    painter.drawLine(QPointF(-2.2, -1.5), QPointF(-2.2, 5.0))
    painter.drawLine(QPointF(2.2, -1.5), QPointF(2.2, 5.0))

    painter.restore()


def get_trash_pixmap(size: int = 16, color: Union[QColor, str] = "#888888") -> QPixmap:
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


def get_trash_icon(
    size: int = 16, 
    color: Union[QColor, str] = "#888888",
    hover_color: Optional[Union[QColor, str]] = "#FF5555"
) -> QIcon:
    """
    Crea un QIcon a partir del icono de bote de basura Sci-Fi.

    Args:
        size: Tamaño del icono en píxeles.
        color: Color de trazo del icono en estado normal.
        hover_color: Color de trazo del icono en estado activo/hover (opcional).

    Returns:
        QIcon compatible con QPushButton y otros widgets de Qt.
    """
    icon = QIcon()
    pixmap_normal = get_trash_pixmap(size=size, color=color)
    icon.addPixmap(pixmap_normal, QIcon.Normal, QIcon.Off)

    if hover_color:
        pixmap_hover = get_trash_pixmap(size=size, color=hover_color)
        icon.addPixmap(pixmap_hover, QIcon.Active, QIcon.Off)
        icon.addPixmap(pixmap_hover, QIcon.Selected, QIcon.Off)

    return icon

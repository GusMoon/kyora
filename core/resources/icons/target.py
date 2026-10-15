from PySide6.QtCore import Qt, QRectF, QPointF
from PySide6.QtGui import QColor, QPen

def draw(painter, center, scale, color):
    painter.save()
    painter.translate(center)
    
    # Para igualar el tamaño visual con los font icons, escalamos un poco
    base_target_scale = 1.3
    final_scale = base_target_scale * scale
    painter.scale(final_scale, final_scale)
    
    pen = QPen(color, 1.8, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin)
    painter.setPen(pen)
    painter.setBrush(Qt.NoBrush)
    
    # Outer ring
    painter.drawArc(QRectF(-14, -14, 28, 28), 55 * 16, 340 * 16)
    # Middle ring
    painter.drawArc(QRectF(-8, -8, 16, 16), 65 * 16, 320 * 16)
    
    # Inner dot
    painter.setBrush(color)
    painter.drawEllipse(QRectF(-2.5, -2.5, 5, 5))
    
    # Arrow shaft
    painter.setBrush(Qt.NoBrush)
    painter.drawLine(QPointF(2, -2), QPointF(19, -19))
    
    # Chevron 1
    painter.drawLine(QPointF(11, -11), QPointF(11, -15))
    painter.drawLine(QPointF(11, -11), QPointF(15, -11))
    
    # Chevron 2
    painter.drawLine(QPointF(15, -15), QPointF(15, -19))
    painter.drawLine(QPointF(15, -15), QPointF(19, -15))
    
    painter.restore()

from PySide6.QtGui import QFont
from PySide6.QtCore import Qt, QRectF

def draw_font_icon(painter, center, scale, color, unicode_char, base_size=24):
    painter.save()
    painter.translate(center)
    
    # Escalamos dinamicamente usando la propiedad del font para evitar pixelación
    font = QFont("Segoe MDL2 Assets", int(base_size * scale))
    painter.setFont(font)
    painter.setPen(color)
    
    # La caja del texto se mantiene constante y centrada
    # Ya que el texto se dibuja centrado dentro de este rectangulo
    rect_size = 100
    painter.drawText(QRectF(-rect_size/2, -rect_size/2, rect_size, rect_size), Qt.AlignCenter, unicode_char)
    painter.restore()

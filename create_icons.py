import os

base_path = r"c:\secondBrain\proyectos\kiora\core\resources\icons"
os.makedirs(base_path, exist_ok=True)

font_icon_code = """from PySide6.QtGui import QFont
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
"""

target_code = """from PySide6.QtCore import Qt, QRectF, QPointF
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
"""

icons = {
    "globe": "\uE12B",
    "clock": "\uE121",
    "weather": "\uE706",
    "settings": "\uE713",
    "close": "\uE711",
    "music": "\uE8D6",
    "explorer": "\uE188"
}

with open(os.path.join(base_path, "__init__.py"), "w", encoding="utf-8") as f:
    pass

with open(os.path.join(base_path, "font_icon.py"), "w", encoding="utf-8") as f:
    f.write(font_icon_code)

with open(os.path.join(base_path, "target.py"), "w", encoding="utf-8") as f:
    f.write(target_code)

for name, char in icons.items():
    code = f"""from .font_icon import draw_font_icon

def draw(painter, center, scale, color, base_size=24):
    draw_font_icon(painter, center, scale, color, "{char}", base_size)
"""
    with open(os.path.join(base_path, f"{name}.py"), "w", encoding="utf-8") as f:
        f.write(code)

print("Icons created successfully.")

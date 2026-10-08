from PySide6.QtWidgets import QWidget, QHBoxLayout, QPushButton
from PySide6.QtCore import Qt, Signal, QRectF, QPointF, QTimer
from PySide6.QtGui import QPainter, QColor, QPen, QFont, QPolygonF
import math

class SciFiNavButton(QPushButton):
    def __init__(self, icon_text, parent=None):
        super().__init__(icon_text, parent)
        self.setFixedSize(60, 60)
        self.setCursor(Qt.PointingHandCursor)
        self.setCheckable(True)
        
        # Animación de rotación
        self.rotation_angle = 0.0
        self.anim_timer = QTimer(self)
        self.anim_timer.timeout.connect(self._update_rotation)
        self.anim_timer.setInterval(20) # 50fps aprox
        
    def _update_rotation(self):
        self.rotation_angle += 1.5
        if self.rotation_angle >= 360:
            self.rotation_angle -= 360
        self.update()
        
    def setChecked(self, checked):
        super().setChecked(checked)
        if checked:
            self.anim_timer.start()
        else:
            self.anim_timer.stop()
            self.rotation_angle = 0
            self.update()
        
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        w = self.width()
        h = self.height()
        center = QPointF(w / 2, h / 2)
        
        is_active = self.isChecked()
        is_hover = self.underMouse()
        
        # Factores de escalado (más grande si está seleccionado)
        scale = 1.3 if is_active else 1.0
        if is_hover and not is_active:
            scale = 1.1
            
        # Colores: Azul (#0099FF) y Naranja Sci-Fi (#FF9900)
        outer_color = QColor("#0099FF") if is_active else QColor("#384553")
        inner_color = QColor("#FF9900") if is_active else QColor("#384553")
        
        if is_hover and not is_active:
            outer_color = QColor("#80BFFF")
            inner_color = QColor("#80BFFF")
            
        base_radius = 20 * scale
            
        # 1. Dibujar anillo exterior
        pen = QPen(outer_color, max(1.0, 1.5 * scale))
        painter.setPen(pen)
        painter.drawEllipse(center, base_radius, base_radius)
            
        # 2. Dibujar arcos gruesos rotativos
        painter.setBrush(Qt.NoBrush)
        pen.setWidthF(3.0 * scale)
        pen.setColor(inner_color)
        painter.setPen(pen)
        
        radius_inner = base_radius - (5 * scale)
        rect_inner = QRectF(center.x() - radius_inner, center.y() - radius_inner, radius_inner * 2, radius_inner * 2)
        
        span_angle = 100 * 16 # 100 grados
        for start_angle in [30, 150, 270]:
            painter.drawArc(rect_inner, int((start_angle + self.rotation_angle) * 16), span_angle)
            
        # 3. Dibujar ícono
        font = self.font()
        font.setFamily("Segoe MDL2 Assets")
        font.setPointSize(int(15 * scale))
        painter.setFont(font)
        painter.setPen(outer_color)
        painter.drawText(self.rect(), Qt.AlignCenter, self.text())

class NavBar(QWidget):
    option_selected = Signal(str)
    
    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(-5) # Acercar mucho más los botones
        
        self.buttons = {}
        # Íconos de Segoe MDL2 Assets
        self.options = [("EXPLORER", "\uE8B7"), ("MUSIC", "\uE8D6"), ("CONFIG", "\uE713")]
        
        for opt_id, opt_icon in self.options:
            btn = SciFiNavButton(opt_icon)
            self.buttons[opt_id] = btn
            layout.addWidget(btn)
            btn.clicked.connect(lambda checked, o=opt_id: self.select_option(o))
            
        self.select_option("EXPLORER")
        
    def select_option(self, option):
        for opt, btn in self.buttons.items():
            btn.setChecked(opt == option)
        self.option_selected.emit(option)

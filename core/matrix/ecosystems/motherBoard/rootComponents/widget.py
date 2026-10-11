from PySide6.QtWidgets import QWidget
from PySide6.QtCore import Qt, QRectF, QPointF, Signal, QTimer
from PySide6.QtGui import QPainter, QColor, QPen, QFont, QPainterPath, QLinearGradient
import math

import core.matrix.ecosystems.motherBoard.globalComponents.icons.clock as icon_clock
import core.matrix.ecosystems.motherBoard.globalComponents.icons.weather as icon_weather
import core.matrix.ecosystems.motherBoard.globalComponents.icons.globe as icon_globe
import core.matrix.ecosystems.motherBoard.globalComponents.icons.settings as icon_settings
import core.matrix.ecosystems.motherBoard.globalComponents.icons.close as icon_close

class InfoWidget(QWidget):
    close_requested = Signal()
    config_requested = Signal()
    tasks_requested = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedSize(250, 250)
        self.time_text = "00:00"
        self.date_text = "--/--/----"
        self.weather_text = "Calculando..."
        
        self.base_bg = QColor("#121212")
        self.panel_bg = QColor("#161616")
        self.ring_color = QColor("#444444")
        self.wave_color = QColor("#222222")
        self.text_color = QColor("#FFFFFF")
        self.sub_text_color = QColor("#A0A0A0")
        
        # 5 Opciones -> Separación de 72 grados
        # 90 es abajo.
        self.options = [
            {'id': 'clock',   'module': icon_clock, 'base_angle': 90},
            {'id': 'weather', 'module': icon_weather, 'base_angle': 162},
            {'id': 'tasks',   'module': icon_globe, 'base_angle': 234},
            {'id': 'config',  'module': icon_settings, 'base_angle': 306},
            {'id': 'close',   'module': icon_close, 'base_angle': 18}
        ]
        
        self.current_rotation = 0.0
        self.target_rotation = 0.0
        self.is_dragging = False
        self.last_mouse_angle = 0.0
        
        self.anim_timer = QTimer(self)
        self.anim_timer.timeout.connect(self.animate_rotation)
        self.anim_timer.setInterval(16)
        
        self.active_mode = 'clock'
        self.setMouseTracking(True)
        self.icon_ring_radius = 105

    def get_angle(self, pos):
        dx = pos.x() - self.width() / 2
        dy = pos.y() - self.height() / 2
        deg = math.degrees(math.atan2(dy, dx))
        return deg % 360

    def update_time(self, t):
        self.time_text = t
        self.update()
        
    def update_date(self, d):
        self.date_text = d
        self.update()
        
    def update_weather(self, loc, temp):
        self.weather_text = f"{loc} | {temp}"
        self.update()

    def mousePressEvent(self, event):
        pos = event.pos()
        center = QPointF(self.width() / 2, self.height() / 2)
        dist = math.hypot(pos.x() - center.x(), pos.y() - center.y())
        
        if dist < 80: 
            self.execute_action()
        elif 80 <= dist <= 125: 
            self.is_dragging = True
            self.last_mouse_angle = self.get_angle(pos)
            self.anim_timer.stop()
            self.setCursor(Qt.ClosedHandCursor)
        else:
            if event.button() == Qt.LeftButton:
                self._is_moving = True
                self._drag_start_pos = pos

    def mouseMoveEvent(self, event):
        pos = event.pos()
        
        if getattr(self, '_is_moving', False):
            self._user_moved = True
            global_pos = event.globalPosition().toPoint()
            if self.parent():
                parent_pos = self.parent().mapFromGlobal(global_pos)
                self.move(parent_pos - self._drag_start_pos)
            else:
                self.move(global_pos - self._drag_start_pos)
            return
            
        center = QPointF(self.width() / 2, self.height() / 2)
        dist = math.hypot(pos.x() - center.x(), pos.y() - center.y())
        
        if self.is_dragging:
            current_angle = self.get_angle(pos)
            delta = current_angle - self.last_mouse_angle
            if delta > 180: delta -= 360
            elif delta < -180: delta += 360
            
            self.current_rotation = (self.current_rotation + delta) % 360
            self.last_mouse_angle = current_angle
            self.update_active_mode()
            self.update()
        else:
            if dist < 80:
                self.setCursor(Qt.PointingHandCursor)
            elif 80 <= dist <= 125:
                self.setCursor(Qt.OpenHandCursor)
            else:
                self.setCursor(Qt.ArrowCursor)

    def mouseReleaseEvent(self, event):
        if getattr(self, '_is_moving', False):
            self._is_moving = False
            return
            
        if self.is_dragging:
            self.is_dragging = False
            # Snapping a incrementos de 72 grados (360 / 5)
            snapped = round(self.current_rotation / 72.0) * 72.0
            self.target_rotation = snapped
            self.anim_timer.start()
            self.mouseMoveEvent(event)

    def animate_rotation(self):
        diff = self.target_rotation - self.current_rotation
        if diff > 180: diff -= 360
        elif diff < -180: diff += 360
        
        if abs(diff) < 0.5:
            self.current_rotation = self.target_rotation % 360
            self.anim_timer.stop()
        else:
            self.current_rotation = (self.current_rotation + diff * 0.15) % 360
            
        self.update_active_mode()
        self.update()
        
    def update_active_mode(self):
        min_dist = 999
        best_mode = 'clock'
        for opt in self.options:
            actual_angle = (opt['base_angle'] + self.current_rotation) % 360
            dist = abs(actual_angle - 90)
            dist = min(dist, 360 - dist)
            if dist < min_dist:
                min_dist = dist
                best_mode = opt['id']
        if self.active_mode != best_mode:
            self.active_mode = best_mode
            
    def execute_action(self):
        if self.active_mode == 'close':
            self.close_requested.emit()
        elif self.active_mode == 'config':
            self.config_requested.emit()
        elif self.active_mode == 'tasks':
            self.tasks_requested.emit()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        w = self.width()
        h = self.height()
        center = QPointF(w / 2, h / 2)
        
        # 1. Base Oscura
        outer_radius = 125
        painter.setPen(Qt.NoPen)
        painter.setBrush(self.base_bg)
        painter.drawEllipse(center, outer_radius, outer_radius)
        
        # 2. Anillo de rotación Sci-Fi (Más grueso)
        # Radio central 105, grosor 35. Bordes en 87.5 y 122.5
        track_thickness = 35
        pen_track = QPen(QColor("#1A1A1A"), track_thickness)
        painter.setPen(pen_track)
        painter.setBrush(Qt.NoBrush)
        painter.drawEllipse(center, self.icon_ring_radius, self.icon_ring_radius)
        
        # Destello de selección contenido exclusivamente dentro del anillo exterior
        # Usamos un gradiente cónico para un degradado suave hacia los lados
        from PySide6.QtGui import QConicalGradient
        grad = QConicalGradient(center, 270)
        grad.setColorAt(0.0, QColor(255, 255, 255, 45))
        grad.setColorAt(0.12, QColor(255, 255, 255, 0))
        grad.setColorAt(0.88, QColor(255, 255, 255, 0))
        grad.setColorAt(1.0, QColor(255, 255, 255, 45))
        
        pen_glow = QPen(grad, track_thickness)
        painter.setPen(pen_glow)
        painter.setBrush(Qt.NoBrush)
        painter.drawEllipse(center, self.icon_ring_radius, self.icon_ring_radius)
        
        # 3. Panel central interior
        panel_radius = 80
        painter.setPen(Qt.NoPen)
        painter.setBrush(self.panel_bg)
        painter.drawEllipse(center, panel_radius, panel_radius)
        
        # Borde sutil central
        pen = QPen(self.ring_color, 2)
        painter.setPen(pen)
        painter.setBrush(Qt.NoBrush)
        painter.drawEllipse(center, panel_radius, panel_radius)
        
        # 4. Relleno líquido/onda (Wave)
        path = QPainterPath()
        path.addEllipse(center, panel_radius, panel_radius)
        
        wave_path = QPainterPath()
        wave_path.moveTo(center.x() - panel_radius, center.y() + 25)
        wave_path.cubicTo(
            center.x() - 30, center.y() + 10, 
            center.x() + 30, center.y() + 40, 
            center.x() + panel_radius, center.y() + 25
        )
        wave_path.lineTo(center.x() + panel_radius, center.y() + panel_radius)
        wave_path.lineTo(center.x() - panel_radius, center.y() + panel_radius)
        wave_path.closeSubpath()
        
        intersected = path.intersected(wave_path)
        painter.setPen(Qt.NoPen)
        painter.setBrush(self.wave_color)
        painter.drawPath(intersected)
        
        # 5. Renderizado de iconos dinámico (Rotación) utilizando modulos globales
        for opt in self.options:
            actual_angle = (opt['base_angle'] + self.current_rotation) % 360
            rad = math.radians(actual_angle)
            x = center.x() + self.icon_ring_radius * math.cos(rad)
            y = center.y() + self.icon_ring_radius * math.sin(rad)
            
            if self.active_mode == opt['id']:
                color = QColor("#FFFFFF")
            else:
                color = QColor("#666666")
                
            opt['module'].draw(painter, QPointF(x, y), 0.625, color)

        # 6. UI Central basado en el modo activo
        painter.setPen(self.text_color)
        
        if self.active_mode == 'clock':
            font = QFont("Space Grotesk", 34, QFont.Bold)
            painter.setFont(font)
            painter.drawText(QRectF(center.x() - 70, center.y() - 35, 140, 45), Qt.AlignCenter, self.time_text)
            
            font = QFont("Space Grotesk", 10)
            painter.setFont(font)
            painter.drawText(QRectF(center.x() - 70, center.y() + 10, 140, 20), Qt.AlignCenter, self.date_text)
            
        elif self.active_mode == 'weather':
            loc, temp = self.weather_text.split(" | ") if " | " in self.weather_text else ("", self.weather_text)
            font = QFont("Space Grotesk", 28, QFont.Bold)
            painter.setFont(font)
            painter.drawText(QRectF(center.x() - 70, center.y() - 30, 140, 40), Qt.AlignCenter, temp)
            
            font = QFont("Space Grotesk", 8)
            painter.setFont(font)
            painter.setPen(self.sub_text_color)
            painter.drawText(QRectF(center.x() - 70, center.y() + 15, 140, 20), Qt.AlignCenter, loc)
            
        elif self.active_mode == 'config':
            font = QFont("Space Grotesk", 18, QFont.Bold)
            painter.setFont(font)
            painter.drawText(QRectF(center.x() - 70, center.y() - 25, 140, 30), Qt.AlignCenter, "AJUSTES")
            
            font = QFont("Space Grotesk", 8)
            painter.setFont(font)
            painter.setPen(self.sub_text_color)
            painter.drawText(QRectF(center.x() - 70, center.y() + 10, 140, 20), Qt.AlignCenter, "Clic para abrir")
            
        elif self.active_mode == 'tasks':
            font = QFont("Space Grotesk", 15, QFont.Bold)
            painter.setFont(font)
            painter.drawText(QRectF(center.x() - 70, center.y() - 25, 140, 30), Qt.AlignCenter, "ECOSISTEMAS")
            
            font = QFont("Space Grotesk", 8)
            painter.setFont(font)
            painter.setPen(self.sub_text_color)
            painter.drawText(QRectF(center.x() - 70, center.y() + 10, 140, 20), Qt.AlignCenter, "Clic para abrir")
            
        elif self.active_mode == 'close':
            font = QFont("Space Grotesk", 20, QFont.Bold)
            painter.setFont(font)
            painter.drawText(QRectF(center.x() - 70, center.y() - 25, 140, 30), Qt.AlignCenter, "CERRAR")
            
            font = QFont("Space Grotesk", 8)
            painter.setFont(font)
            painter.setPen(self.sub_text_color)
            painter.drawText(QRectF(center.x() - 70, center.y() + 10, 140, 20), Qt.AlignCenter, "Clic para salir")

from PySide6.QtWidgets import QWidget
from PySide6.QtCore import Qt, QPointF, QRectF, Signal, QTimer
from PySide6.QtGui import QPainter, QColor, QPen, QFont, QPainterPath, QRadialGradient
import math

import core.resources.icons.settings as icon_settings
import core.resources.icons.music as icon_music
import core.resources.icons.explorer as icon_explorer
import core.resources.icons.target as icon_target
import core.resources.icons.logbook as icon_logbook
import core.resources.icons.agenda as icon_agenda

class EcosystemLauncher(QWidget):
    ecosystem_selected = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMouseTracking(True)
        
        self.hex_size = 100
        self.grid_radius = 2 
        
        self.ecosystems = {
            (0, 0):  {"id": "CONFIG",   "title": "AJUSTES",  "module": icon_settings},
            (-1, 0): {"id": "MUSIC",    "title": "STUDIO",   "module": icon_music},
            (1, -1): {"id": "TASKS",    "title": "TAREAS",   "module": icon_target},
            (0, 1):  {"id": "EXPLORER", "title": "ARCHIVOS", "module": icon_explorer},
            (-1, 1): {"id": "LOGBOOK",  "title": "BITÁCORA", "module": icon_logbook},
            (1, 0):  {"id": "CALENDAR", "title": "CALENDARIO", "module": icon_agenda}
        }
        
        self.hovered_q_r = None
        self.scales = {}
        
        # Animador a 60 FPS
        self.anim_timer = QTimer(self)
        self.anim_timer.timeout.connect(self.update_animations)
        
        # Inicializamos todas las escalas en su tamaño base (0.95)
        for q in range(-self.grid_radius, self.grid_radius + 1):
            for r in range(-self.grid_radius, self.grid_radius + 1):
                if abs(q + r) <= self.grid_radius:
                    self.scales[(q, r)] = 0.95
        
    def get_hex_center(self, q, r, screen_center):
        x = self.hex_size * math.sqrt(3) * (q + r / 2.0)
        y = self.hex_size * 3.0 / 2.0 * r
        return QPointF(screen_center.x() + x, screen_center.y() + y)
        
    def get_hex_path(self, center, size):
        path = QPainterPath()
        for i in range(6):
            angle_deg = 60 * i - 30
            angle_rad = math.radians(angle_deg)
            px = center.x() + size * math.cos(angle_rad)
            py = center.y() + size * math.sin(angle_rad)
            if i == 0:
                path.moveTo(px, py)
            else:
                path.lineTo(px, py)
        path.closeSubpath()
        return path

    def update_animations(self):
        needs_update = False
        for coord in list(self.scales.keys()):
            is_hovered = (self.hovered_q_r == coord)
            is_active = coord in self.ecosystems
            
            # Tamaño meta: Más grande si es un ecosistema activo
            if is_hovered:
                target = 1.15 if is_active else 1.02
            else:
                target = 0.95
                
            current = self.scales[coord]
            if abs(current - target) > 0.001:
                # Suavizado de movimiento (Lerp), factor 0.15 para una subida fluida pero veloz
                self.scales[coord] = current + (target - current) * 0.15
                needs_update = True
            else:
                self.scales[coord] = target
                
        if needs_update:
            self.update()
        else:
            self.anim_timer.stop()

    def mouseMoveEvent(self, event):
        pos = event.pos()
        new_hovered = None
        
        w = self.width()
        h = self.height()
        screen_center = QPointF(w / 2, h / 2)
        
        # Usar hitbox estático de tamaño 1.0 para la detección, 
        # así evitamos el parpadeo (flicker) por cambios de tamaño dinámicos
        for q in range(-self.grid_radius, self.grid_radius + 1):
            for r in range(-self.grid_radius, self.grid_radius + 1):
                if abs(q + r) <= self.grid_radius:
                    center = self.get_hex_center(q, r, screen_center)
                    hitbox = self.get_hex_path(center, self.hex_size)
                    if hitbox.contains(pos):
                        new_hovered = (q, r)
                        break
                    
        if new_hovered != self.hovered_q_r:
            self.hovered_q_r = new_hovered
            is_active = new_hovered in self.ecosystems if new_hovered else False
            self.setCursor(Qt.PointingHandCursor if is_active else Qt.ArrowCursor)
            
            if not self.anim_timer.isActive():
                self.anim_timer.start(16) # ~60 fps

    def mousePressEvent(self, event):
        if self.hovered_q_r and self.hovered_q_r in self.ecosystems:
            self.ecosystem_selected.emit(self.ecosystems[self.hovered_q_r]["id"])

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        w = self.width()
        h = self.height()
        screen_center = QPointF(w / 2, h / 2)
        
        painter.fillRect(self.rect(), QColor("#121212"))
        
        # Ordenar dibujado (Z-Index) basándonos en la escala actual (profundidad).
        # Así, los más levantados siempre se sobreponen a sus vecinos.
        hex_list = []
        for q in range(-self.grid_radius, self.grid_radius + 1):
            for r in range(-self.grid_radius, self.grid_radius + 1):
                if abs(q + r) <= self.grid_radius:
                    scale = self.scales.get((q, r), 0.95)
                    hex_list.append((scale, q, r))
                    
        hex_list.sort(key=lambda item: item[0])
        
        for scale, q, r in hex_list:
            center = self.get_hex_center(q, r, screen_center)
            path = self.get_hex_path(center, self.hex_size * scale)
            is_active = (q, r) in self.ecosystems
            is_hovered = (self.hovered_q_r == (q, r))
            
            # Cálculo de elevación normalizada de 0.0 (reposo) a 1.0 (máxima altura)
            elevation = max(0.0, min(1.0, (scale - 0.95) / (1.15 - 0.95)))
            
            # Sombra dinámica en la parte inferior para acentuar la ilusión 3D
            if elevation > 0.02:
                shadow_offset = elevation * 15 # La sombra se desplaza hasta 15px hacia abajo
                shadow_path = self.get_hex_path(center + QPointF(0, shadow_offset), self.hex_size * scale)
                painter.setBrush(QColor(0, 0, 0, int(120 * elevation)))
                painter.setPen(Qt.NoPen)
                painter.drawPath(shadow_path)
            
            if is_active:
                eco = self.ecosystems[(q, r)]
                grad = QRadialGradient(center, self.hex_size * scale)
                
                # Transición de colores (Lerp) para el fondo, de #222 a #3D3D3D
                r1, g1, b1 = 34 + 27 * elevation, 34 + 27 * elevation, 34 + 27 * elevation
                r2, g2, b2 = 20 + 6 * elevation, 20 + 6 * elevation, 20 + 6 * elevation
                
                grad.setColorAt(0, QColor(int(r1), int(g1), int(b1)))
                grad.setColorAt(1, QColor(int(r2), int(g2), int(b2)))
                
                pen_color = QColor(int(42 + 60 * elevation), int(42 + 60 * elevation), int(42 + 60 * elevation))
                
                painter.setBrush(grad)
                painter.setPen(QPen(pen_color, 1.5 + (1.0 * elevation)))
                painter.drawPath(path)
                
                # Crecimiento e iluminación suave del Icono utilizando el componente global
                icon_scale = 1.0 + (0.25 * elevation)
                c_val = int(160 + (255 - 160) * elevation)
                icon_color = QColor(c_val, c_val, c_val)
                
                eco["module"].draw(painter, center, icon_scale, icon_color)
                
                # Transición de opacidad (fade-in) para el texto al hacer hover
                if elevation > 0.05:
                    alpha = int(255 * elevation)
                    font = QFont("Prototype", 10, QFont.Bold)
                    font.setLetterSpacing(QFont.AbsoluteSpacing, 2.0)
                    painter.setFont(font)
                    painter.setPen(QColor(255, 255, 255, alpha))
                    
                    # Desplazamiento dinámico hacia abajo para separarlo del icono a medida que crece
                    y_offset = 35 + (12 * elevation)
                    painter.drawText(QRectF(center.x()-60, center.y()+y_offset, 120, 30), Qt.AlignCenter, eco["title"])
                    
            else:
                # Hexágonos vacíos
                c_bg = int(17 + 9 * elevation)
                c_pen = int(22 + 20 * elevation)
                painter.setBrush(QColor(c_bg, c_bg, c_bg))
                painter.setPen(QPen(QColor(c_pen, c_pen, c_pen), 1 + elevation))
                painter.drawPath(path)

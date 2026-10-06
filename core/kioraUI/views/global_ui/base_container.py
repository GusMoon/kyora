from PySide6.QtWidgets import QFrame, QVBoxLayout, QHBoxLayout, QLabel, QPushButton
from PySide6.QtCore import Qt, Signal, QPoint
from PySide6.QtGui import QPainter, QColor, QPolygon, QBrush

class KioraBaseContainer(QFrame):
    """
    Contenedor base para KioraUI. 
    Aplica los estándares de diseño Sci-Fi: opacidad, cabecera con título 
    y botón de cierre, y funcionalidad de arrastre libre.
    """
    closed = Signal() # Señal emitida al cerrar el contenedor

    def __init__(self, title_text="KIORA CONTAINER", parent=None):
        super().__init__(parent)
        self.user_moved = False
        
        # Variables para redimensionar
        self.RESIZE_MARGIN = 8
        self._is_resizing = False
        self._resize_dir = None
        self._resize_start_pos = None
        self._resize_start_geometry = None
        self._drag_pos = None
        
        # Habilitar el rastreo del mouse para cambiar el cursor en los bordes
        self.setMouseTracking(True)
        
        # Propiedades base del contenedor (Fondo oscuro con transparencia y borde rojo)
        self.setStyleSheet("""
            KioraBaseContainer { 
                background-color: rgba(22, 22, 22, 0.95); 
                border: 1px solid #D96600; 
            }
        """)
        
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)
        
        # --- HEADER ---
        self.header = QFrame()
        self.header.setFixedHeight(35)
        # Header con rojo primario Kiora
        self.header.setStyleSheet("""
            QFrame { 
                background-color: rgba(217, 102, 0, 0.95); 
                border: none; 
                border-bottom: 2px solid #D48800; 
            }
        """)
        
        header_layout = QHBoxLayout(self.header)
        header_layout.setContentsMargins(15, 0, 10, 0)
        
        self.title_label = QLabel(title_text)
        self.title_label.setStyleSheet("""
            QLabel { 
                color: #FFFFFF; 
                font-family: 'Segoe UI', sans-serif; 
                font-size: 11px; 
                font-weight: 800; 
                letter-spacing: 2px; 
                border: none; 
                background: transparent; 
            }
        """)
        
        header_layout.addWidget(self.title_label)
        header_layout.addStretch()
        
        self.close_btn = QPushButton("✕")
        self.close_btn.setFixedSize(24, 24)
        self.close_btn.setCursor(Qt.PointingHandCursor)
        self.close_btn.setStyleSheet("""
            QPushButton { 
                background-color: transparent; 
                color: #FFFFFF; 
                font-weight: bold; 
                font-size: 14px; 
                border: none; 
            } 
            QPushButton:hover { 
                color: #060A0F; 
            }
        """)
        self.close_btn.clicked.connect(self._on_close)
        
        header_layout.addWidget(self.close_btn)
        
        # --- BODY ---
        self.body_frame = QFrame()
        self.body_frame.setStyleSheet("border: none; background-color: transparent;")
        self.body_frame.setMouseTracking(True)
        
        # Este layout será usado por las clases hijas para agregar contenido
        self.body_layout = QVBoxLayout(self.body_frame)
        self.body_layout.setContentsMargins(20, 20, 20, 20)
        
        # Ensamblar
        main_layout.addWidget(self.header)
        main_layout.addWidget(self.body_frame)
        
        # Habilitar rastreo en hijos para no perder eventos en los bordes
        self.header.setMouseTracking(True)
        self.title_label.setMouseTracking(True)
        
        # Limites mínimos
        self.setMinimumSize(200, 150)

    def set_title(self, text: str):
        """Actualiza dinámicamente el nombre de la sección o archivo en el header."""
        self.title_label.setText(text.upper())
        
    def _on_close(self):
        self.hide()
        self.closed.emit()

    # --- LÓGICA DE MOVIMIENTO Y REDIMENSION (DRAG & DROP / RESIZE) ---
    def _get_resize_dir(self, pos):
        x = pos.x()
        y = pos.y()
        w = self.width()
        h = self.height()
        margin = self.RESIZE_MARGIN
        
        dir_y = ""
        dir_x = ""
        
        if y < margin: dir_y = "top"
        elif y > h - margin: dir_y = "bottom"
            
        if x < margin: dir_x = "left"
        elif x > w - margin: dir_x = "right"
            
        if dir_y and dir_x: return f"{dir_y}-{dir_x}"
        return dir_y or dir_x or None

    def _update_cursor(self, pos):
        if self._is_resizing:
            return
            
        direction = self._get_resize_dir(pos)
        if direction in ("top-left", "bottom-right"):
            self.setCursor(Qt.SizeFDiagCursor)
        elif direction in ("top-right", "bottom-left"):
            self.setCursor(Qt.SizeBDiagCursor)
        elif direction in ("left", "right"):
            self.setCursor(Qt.SizeHorCursor)
        elif direction in ("top", "bottom"):
            self.setCursor(Qt.SizeVerCursor)
        else:
            self.unsetCursor()

    def mousePressEvent(self, event):
        # Traer al frente al hacer click
        self.raise_()
        if event.button() == Qt.LeftButton:
            direction = self._get_resize_dir(event.pos())
            if direction:
                self._is_resizing = True
                self._resize_dir = direction
                self._resize_start_pos = event.globalPosition().toPoint()
                self._resize_start_geometry = self.geometry()
            else:
                self._is_resizing = False
                self._drag_pos = event.globalPosition().toPoint()
            event.accept()

    def mouseMoveEvent(self, event):
        pos = event.pos()
        self._update_cursor(pos)
        
        if not (event.buttons() & Qt.LeftButton):
            return
            
        if self._is_resizing:
            global_pos = event.globalPosition().toPoint()
            diff = global_pos - self._resize_start_pos
            rect = self._resize_start_geometry
            
            new_x = rect.x()
            new_y = rect.y()
            new_w = rect.width()
            new_h = rect.height()
            
            if "left" in self._resize_dir:
                new_w = max(self.minimumWidth(), rect.width() - diff.x())
                if new_w > self.minimumWidth(): new_x = rect.x() + diff.x()
            elif "right" in self._resize_dir:
                new_w = max(self.minimumWidth(), rect.width() + diff.x())
                
            if "top" in self._resize_dir:
                new_h = max(self.minimumHeight(), rect.height() - diff.y())
                if new_h > self.minimumHeight(): new_y = rect.y() + diff.y()
            elif "bottom" in self._resize_dir:
                new_h = max(self.minimumHeight(), rect.height() + diff.y())
                
            self.setGeometry(new_x, new_y, new_w, new_h)
            event.accept()
            
        elif self._drag_pos is not None:
            self.user_moved = True
            new_pos = event.globalPosition().toPoint()
            diff = new_pos - self._drag_pos
            self._drag_pos = new_pos
            
            next_pos = self.pos() + diff
            
            if self.parent():
                parent_rect = self.parent().rect()
                x = max(0, min(next_pos.x(), parent_rect.width() - self.width()))
                y = max(0, min(next_pos.y(), parent_rect.height() - self.height()))
                self.move(x, y)
            else:
                self.move(next_pos)
            
            event.accept()
            
    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            self._is_resizing = False
            self._drag_pos = None
            self._update_cursor(event.pos())
            event.accept()

    def paintEvent(self, event):
        super().paintEvent(event)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        # Tamaño del indicador de la esquina
        size = 12
        w = self.width()
        h = self.height()
        
        # Puntos del triángulo en la esquina inferior derecha
        pts = [
            QPoint(w, h),
            QPoint(w - size, h),
            QPoint(w, h - size)
        ]
        polygon = QPolygon(pts)
        
        painter.setPen(Qt.NoPen)
        # Blanco para la esquina
        painter.setBrush(QBrush(QColor(255, 255, 255, 200)))
        painter.drawPolygon(polygon)

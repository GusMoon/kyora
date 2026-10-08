from PySide6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QScrollArea, 
                             QPushButton, QFrame, QScroller)
from PySide6.QtCore import Qt, Signal, QTimer, QEvent
from PySide6.QtGui import QPainter, QColor, QPainterPath, QPen, QFontMetrics
import os

class SlantedTab(QPushButton):
    def __init__(self, text, is_last=False, parent=None):
        super().__init__(text, parent)
        self.is_last = is_last
        self.setCursor(Qt.PointingHandCursor)
        self.slant = 12
        
        font = self.font()
        font.setFamily("Space Grotesk")
        font.setPointSize(9)
        font.setBold(True)
        self.setFont(font)
        
        fm = QFontMetrics(font)
        text_width = fm.horizontalAdvance(text)
        
        self.setMinimumHeight(30)
        self.setMinimumWidth(text_width + self.slant * 2 + 20)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        rect = self.rect()
        w = rect.width()
        h = rect.height()
        
        pen_width = 1.5
        offset = pen_width / 2.0
        
        path = QPainterPath()
        # Slant tipo / /
        path.moveTo(offset, h - offset)
        path.lineTo(self.slant + offset, offset)
        path.lineTo(w - offset, offset)
        path.lineTo(w - self.slant - offset, h - offset)
        path.closeSubpath()
        
        if self.is_last:
            bg_color = QColor(0, 153, 255, 35)
            border_color = QColor(255, 184, 77)
            text_color = QColor(255, 184, 77)
        else:
            bg_color = QColor(24, 37, 51, 240)
            border_color = QColor(0, 153, 255, 100)
            text_color = QColor(128, 191, 255)
            
        if self.underMouse() and not self.is_last:
            bg_color = QColor(0, 153, 255, 50)
            border_color = QColor(0, 153, 255, 200)
            text_color = QColor(255, 255, 255)
            
        painter.setBrush(bg_color)
        painter.setPen(QPen(border_color, pen_width))
        painter.drawPath(path)
        
        painter.setPen(text_color)
        painter.drawText(rect, Qt.AlignCenter, self.text())

class FadeOverlay(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAttribute(Qt.WA_TransparentForMouseEvents)
        self.opacity = 0.0
        self.fade_anim_timer = QTimer(self)
        self.fade_anim_timer.timeout.connect(self._animate_fade)
        self.hide_timer = QTimer(self)
        self.hide_timer.timeout.connect(self.start_fade_out)
        self.hide_timer.setSingleShot(True)
        self.is_fading_in = False
        
    def show_temporarily(self):
        self.is_fading_in = True
        self.fade_anim_timer.start(16)
        self.hide_timer.start(800)
        
    def start_fade_out(self):
        self.is_fading_in = False
        self.fade_anim_timer.start(16)
        
    def _animate_fade(self):
        if self.is_fading_in:
            self.opacity = min(1.0, self.opacity + 0.1)
            if self.opacity >= 1.0:
                self.fade_anim_timer.stop()
        else:
            self.opacity = max(0.0, self.opacity - 0.05)
            if self.opacity <= 0.0:
                self.fade_anim_timer.stop()
        self.update()

    def paintEvent(self, event):
        if self.opacity <= 0.0: return
        
        from PySide6.QtGui import QLinearGradient
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        
        w = self.width()
        h = self.height()
        fade_w = 30
        
        dark = QColor(10, 15, 20, int(255 * self.opacity))
        trans = QColor(10, 15, 20, 0)
        
        grad_l = QLinearGradient(0, 0, fade_w, 0)
        grad_l.setColorAt(0, dark)
        grad_l.setColorAt(1, trans)
        painter.fillRect(0, 0, fade_w, h, grad_l)
        
        grad_r = QLinearGradient(w - fade_w, 0, w, 0)
        grad_r.setColorAt(0, trans)
        grad_r.setColorAt(1, dark)
        painter.fillRect(w - fade_w, 0, fade_w, h, grad_r)

class PathView(QWidget):
    path_clicked = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedHeight(45)
        
        self.main_layout = QVBoxLayout(self)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(0)
        
        # Scroll Area para las pestañas (rutas)
        self.scroll_area = QScrollArea()
        self.scroll_area.setWidgetResizable(True)
        self.scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.scroll_area.setFrameShape(QFrame.NoFrame)
        self.scroll_area.setStyleSheet("background: transparent; border: none;")
        
        # Habilitar desplazamiento táctil y con clic izquierdo (arrastrar para scrollear)
        QScroller.grabGesture(self.scroll_area.viewport(), QScroller.LeftMouseButtonGesture)
        
        # Interceptar el scroll de ratón
        self.scroll_area.wheelEvent = self._handle_wheel_event
        
        self.tabs_container = QWidget()
        self.tabs_container.setStyleSheet("background: transparent;")
        self.tabs_layout = QHBoxLayout(self.tabs_container)
        self.tabs_layout.setContentsMargins(10, 5, 10, 0)
        self.tabs_layout.setSpacing(0) # Reducido a -14 para que las líneas inclinadas se superpongan y estén más cerca
        self.tabs_layout.setAlignment(Qt.AlignLeft | Qt.AlignBottom)
        
        self.scroll_area.setWidget(self.tabs_container)
        self.main_layout.addWidget(self.scroll_area)
        
        self.fade_overlay = FadeOverlay(self)
        
        h_bar = self.scroll_area.horizontalScrollBar()
        h_bar.valueChanged.connect(lambda: self.fade_overlay.show_temporarily())
        
        # Línea horizontal divisora
        self.bottom_line = QFrame()
        self.bottom_line.setFrameShape(QFrame.HLine)
        self.bottom_line.setFrameShadow(QFrame.Plain)
        self.bottom_line.setStyleSheet("background-color: #182533; max-height: 2px;")
        self.main_layout.addWidget(self.bottom_line)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, 'fade_overlay') and hasattr(self, 'scroll_area'):
            self.fade_overlay.setGeometry(self.scroll_area.geometry())

    def _handle_wheel_event(self, event):
        h_bar = self.scroll_area.horizontalScrollBar()
        # Soportar tanto rueda de ratón (y) como touchpads (x)
        delta = event.angleDelta().x() if abs(event.angleDelta().x()) > abs(event.angleDelta().y()) else event.angleDelta().y()
        h_bar.setValue(h_bar.value() - delta)
        event.accept()

    def set_path(self, path):
        # Limpiar pestañas actuales
        while self.tabs_layout.count():
            item = self.tabs_layout.takeAt(0)
            widget = item.widget()
            if widget:
                widget.deleteLater()

        if not path:
            self._add_tab("ESTE EQUIPO", "", is_last=True)
            return

        parts = path.replace('\\', '/').split('/')
        current_path = ""
        
        # Para Windows u otros sistemas
        for i, part in enumerate(parts):
            if not part: continue
            
            if current_path == "":
                # Si estamos en Windows (ej. C:), mantenemos el formato
                current_path = part + ("\\" if os.name == 'nt' else "/")
            else:
                current_path = os.path.join(current_path, part)
            
            self._add_tab(part.upper(), current_path, is_last=(i == len(parts) - 1))
            
        # Realizar auto-scroll al final después de que se rendericen los widgets
        QTimer.singleShot(50, self._scroll_to_end)

    def _scroll_to_end(self):
        h_bar = self.scroll_area.horizontalScrollBar()
        h_bar.setValue(h_bar.maximum())

    def _add_tab(self, text, path, is_last=False):
        btn = SlantedTab(text, is_last=is_last)
        btn.clicked.connect(lambda _, p=path: self.path_clicked.emit(p))
        self.tabs_layout.addWidget(btn)

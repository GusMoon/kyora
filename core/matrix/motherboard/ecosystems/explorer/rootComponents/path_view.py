from PySide6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QScrollArea,
                             QPushButton, QFrame, QScroller)
from PySide6.QtCore import Qt, Signal, QTimer, QRectF
from PySide6.QtGui import QPainter, QColor, QPen, QFont, QFontMetrics, QLinearGradient
import os

from core.matrix.motherboard.globalComponents import kyora_theme as kt


class PathTab(QPushButton):
    """
    Pestaña de un tramo de la ruta, con el estilo de chip de Kyora (globalKyoraUI):
    reposo gris, hover más claro y el tramo actual resaltado con el acento.
    """

    def __init__(self, text, is_last=False, parent=None):
        """
        Args:
            text: Nombre del tramo, en mayúsculas.
            is_last: True si es la carpeta actual.
            parent: Widget padre.
        """
        super().__init__(text, parent)
        self.is_last = is_last
        self.setCursor(Qt.PointingHandCursor)

        font = self.font()
        font.setFamily("Prototype")
        font.setPointSize(9)
        font.setBold(True)
        font.setLetterSpacing(QFont.AbsoluteSpacing, 0.6)
        self.setFont(font)

        text_width = QFontMetrics(font).horizontalAdvance(text)
        self.setMinimumHeight(28)
        self.setMinimumWidth(text_width + 28)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        rect = QRectF(self.rect()).adjusted(1, 1, -1, -1)

        if self.is_last:
            fill, stroke, text = kt.ACCENT_TINT, kt.ACCENT, kt.ACCENT
        elif self.underMouse():
            fill, stroke, text = kt.BG_BADGE, "#555555", kt.TEXT
        else:
            fill, stroke, text = kt.BG_BADGE, kt.BORDER_SOFT, kt.TEXT_SUB

        painter.setBrush(QColor(fill))
        painter.setPen(QPen(QColor(stroke), 1))
        painter.drawRoundedRect(rect, kt.RADIUS_CARD, kt.RADIUS_CARD)

        painter.setFont(self.font())
        painter.setPen(QColor(text))
        painter.drawText(self.rect(), Qt.AlignCenter, self.text())


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
        if self.opacity <= 0.0:
            return

        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        w = self.width()
        h = self.height()
        fade_w = 30

        dark = QColor(18, 18, 18, 255)
        trans = QColor(18, 18, 18, 0)

        grad_l = QLinearGradient(0, 0, fade_w, 0)
        grad_l.setColorAt(0, dark)
        grad_l.setColorAt(1, trans)
        painter.fillRect(0, 0, fade_w, h, grad_l)

        grad_r = QLinearGradient(w - fade_w, 0, w, 0)
        grad_r.setColorAt(0, trans)
        grad_r.setColorAt(1, dark)
        painter.fillRect(w - fade_w, 0, fade_w, h, grad_r)


class PathView(QWidget):
    """Barra de ruta del explorador: una pestaña por carpeta, con scroll horizontal."""

    path_clicked = Signal(str)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedHeight(45)

        self.main_layout = QVBoxLayout(self)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(0)

        self.scroll_area = QScrollArea()
        self.scroll_area.setWidgetResizable(True)
        self.scroll_area.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.scroll_area.setVerticalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.scroll_area.setFrameShape(QFrame.NoFrame)
        self.scroll_area.setStyleSheet("background: transparent; border: none;")

        # Desplazamiento táctil y con clic izquierdo (arrastrar para scrollear)
        QScroller.grabGesture(self.scroll_area.viewport(), QScroller.LeftMouseButtonGesture)
        self.scroll_area.wheelEvent = self._handle_wheel_event

        self.tabs_container = QWidget()
        self.tabs_container.setStyleSheet("background: transparent;")
        self.tabs_layout = QHBoxLayout(self.tabs_container)
        self.tabs_layout.setContentsMargins(10, 6, 10, 8)
        self.tabs_layout.setSpacing(6)
        self.tabs_layout.setAlignment(Qt.AlignLeft | Qt.AlignVCenter)

        self.scroll_area.setWidget(self.tabs_container)
        self.main_layout.addWidget(self.scroll_area)

        self.fade_overlay = FadeOverlay(self)

        h_bar = self.scroll_area.horizontalScrollBar()
        h_bar.valueChanged.connect(lambda: self.fade_overlay.show_temporarily())

        # Línea divisora inferior
        self.bottom_line = QFrame()
        self.bottom_line.setFrameShape(QFrame.HLine)
        self.bottom_line.setFrameShadow(QFrame.Plain)
        self.bottom_line.setStyleSheet(f"background-color: {kt.BORDER_FAINT}; max-height: 1px;")
        self.main_layout.addWidget(self.bottom_line)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if hasattr(self, 'fade_overlay') and hasattr(self, 'scroll_area'):
            self.fade_overlay.setGeometry(self.scroll_area.geometry())

    def _handle_wheel_event(self, event):
        h_bar = self.scroll_area.horizontalScrollBar()
        # Rueda de ratón (y) y touchpads (x)
        delta = event.angleDelta().x() if abs(event.angleDelta().x()) > abs(event.angleDelta().y()) \
            else event.angleDelta().y()
        h_bar.setValue(h_bar.value() - delta)
        event.accept()

    def set_path(self, path):
        while self.tabs_layout.count():
            item = self.tabs_layout.takeAt(0)
            widget = item.widget()
            if widget:
                widget.hide()
                widget.setParent(None)
                widget.deleteLater()

        if not path:
            self._add_tab("ESTE EQUIPO", "", is_last=True)
            return

        parts = path.replace('\\', '/').split('/')
        current_path = ""

        for i, part in enumerate(parts):
            if not part:
                continue

            if current_path == "":
                # En Windows (ej. C:) se conserva el formato de unidad
                current_path = part + ("\\" if os.name == 'nt' else "/")
            else:
                current_path = os.path.join(current_path, part)

            self._add_tab(part.upper(), current_path, is_last=(i == len(parts) - 1))

        # Auto-scroll al final después de que se rendericen los widgets
        QTimer.singleShot(50, self._scroll_to_end)

    def _scroll_to_end(self):
        h_bar = self.scroll_area.horizontalScrollBar()
        h_bar.setValue(h_bar.maximum())

    def _add_tab(self, text, path, is_last=False):
        btn = PathTab(text, is_last=is_last)
        btn.clicked.connect(lambda _, p=path: self.path_clicked.emit(p))
        self.tabs_layout.addWidget(btn)

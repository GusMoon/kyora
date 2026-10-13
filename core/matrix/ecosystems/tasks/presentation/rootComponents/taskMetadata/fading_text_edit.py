"""
Componentes Sci-Fi con efecto dinámico de desvanecimiento (Fade-out/Fade-in)
activo durante el desplazamiento (scroll) y con transición suave al detenerse.
"""
from typing import Optional
from PySide6.QtWidgets import QTextEdit, QScrollArea, QAbstractScrollArea, QWidget
from PySide6.QtCore import Qt, QTimer, QRect, QVariantAnimation, QAbstractAnimation
from PySide6.QtGui import QPainter, QLinearGradient, QColor
from core.matrix.ecosystems.motherBoard.globalComponents.styles import get_minimal_scrollbar_style


class ScrollFadeOverlay(QWidget):
    """
    Capa superpuesta transparente a eventos de ratón que proyecta un degradado
    de desvanecimiento sutil en los extremos superior e inferior mientras se realiza scroll,
    y desaparece con una transición suave de opacidad al detenerse.
    """
    def __init__(self, parent_scroll_area: QAbstractScrollArea, bg_color: Optional[QColor] = None):
        super().__init__(parent_scroll_area.viewport())
        self.scroll_area = parent_scroll_area
        self.bg_color = bg_color if bg_color is not None else QColor(10, 10, 10)
        self.setAttribute(Qt.WA_TransparentForMouseEvents, True)

        # Altura sutil y no invasiva para no cubrir excesivamente el contenido
        self.fade_height = 18
        self._opacity = 1.0

        # Animación para desvanecimiento suave al detener scroll
        self._anim = QVariantAnimation(self)
        self._anim.setDuration(240)
        self._anim.setStartValue(1.0)
        self._anim.setEndValue(0.0)
        self._anim.valueChanged.connect(self._on_opacity_changed)
        self._anim.finished.connect(self._on_fade_finished)

        self._fade_timer = QTimer(self)
        self._fade_timer.setSingleShot(True)
        self._fade_timer.setInterval(360)
        self._fade_timer.timeout.connect(self._start_fade_out)

        self.hide()

    def _on_opacity_changed(self, value):
        self._opacity = float(value)
        self.update()

    def _on_fade_finished(self):
        if self._opacity <= 0.05:
            self.hide()

    def _start_fade_out(self):
        """Inicia la desaparición sutil y gradual del degradado."""
        self._anim.stop()
        self._anim.setStartValue(self._opacity)
        self._anim.setEndValue(0.0)
        self._anim.start()

    def trigger_scroll_effect(self):
        """Muestra de inmediato el degradado y reinicia el temporizador de inactividad."""
        sb = self.scroll_area.verticalScrollBar()
        if not sb or sb.maximum() <= 0:
            self.hide()
            return

        if self._anim.state() == QAbstractAnimation.State.Running:
            self._anim.stop()

        self._opacity = 1.0
        self.setGeometry(0, 0, self.scroll_area.viewport().width(), self.scroll_area.viewport().height())
        self.show()
        self.raise_()
        self.update()
        self._fade_timer.start(360)

    def paintEvent(self, event):
        sb = self.scroll_area.verticalScrollBar()
        if not sb or sb.maximum() <= 0 or self._opacity <= 0.0:
            return

        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        w = self.width()
        h = self.height()

        r, g, b = self.bg_color.red(), self.bg_color.green(), self.bg_color.blue()
        c_opaque = QColor(r, g, b, int(230 * self._opacity))
        c_mid = QColor(r, g, b, int(110 * self._opacity))
        c_transp = QColor(r, g, b, 0)

        # 1. Degradado superior (solo si se ha desplazado hacia abajo)
        if sb.value() > 0:
            top_grad = QLinearGradient(0, 0, 0, self.fade_height)
            top_grad.setColorAt(0.0, c_opaque)
            top_grad.setColorAt(0.6, c_mid)
            top_grad.setColorAt(1.0, c_transp)
            painter.fillRect(QRect(0, 0, w, self.fade_height), top_grad)

        # 2. Degradado inferior (solo si aún queda contenido por desplazar)
        if sb.value() < sb.maximum():
            bot_y = max(0, h - self.fade_height)
            bot_grad = QLinearGradient(0, bot_y, 0, h)
            bot_grad.setColorAt(0.0, c_transp)
            bot_grad.setColorAt(0.4, c_mid)
            bot_grad.setColorAt(1.0, c_opaque)
            painter.fillRect(QRect(0, bot_y, w, self.fade_height), bot_grad)


class FadingScrollTextEdit(QTextEdit):
    """
    Editor de texto multilínea que activa un efecto de desvanecimiento sutil
    mientras el usuario se desplaza y lo oculta gradualmente cuando se detiene.
    """
    def __init__(self, parent=None, bg_color: Optional[QColor] = None):
        super().__init__(parent)
        self.setStyleSheet(
            get_minimal_scrollbar_style() + """
            QTextEdit {
                background-color: #0A0A0A;
                border: none;
                color: #FFFFFF;
                font-family: 'Space Grotesk';
                font-size: 13px;
                line-height: 1.5;
                padding: 4px;
            }
            """
        )

        effective_bg = bg_color if bg_color is not None else QColor(10, 10, 10)
        self._fade_overlay = ScrollFadeOverlay(self, bg_color=effective_bg)

        # Conectar cambios de desplazamiento
        self.verticalScrollBar().valueChanged.connect(self._trigger_scroll_effect)

    def _trigger_scroll_effect(self):
        self._fade_overlay.trigger_scroll_effect()

    def wheelEvent(self, event):
        self._trigger_scroll_effect()
        super().wheelEvent(event)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self._fade_overlay:
            self._fade_overlay.setGeometry(0, 0, self.viewport().width(), self.viewport().height())


class FadingScrollArea(QScrollArea):
    """
    QScrollArea Sci-Fi con efecto sutil y animado de desvanecimiento en los bordes.
    """
    def __init__(self, parent=None, bg_color: Optional[QColor] = None):
        super().__init__(parent)
        effective_bg = bg_color if bg_color is not None else QColor(20, 20, 20)
        self._fade_overlay = ScrollFadeOverlay(self, bg_color=effective_bg)
        self.verticalScrollBar().valueChanged.connect(self._trigger_scroll_effect)

    def _trigger_scroll_effect(self):
        self._fade_overlay.trigger_scroll_effect()

    def wheelEvent(self, event):
        self._trigger_scroll_effect()
        super().wheelEvent(event)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self._fade_overlay:
            self._fade_overlay.setGeometry(0, 0, self.viewport().width(), self.viewport().height())

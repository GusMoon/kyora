"""Ayudantes para las ventanas Qt de Kyora: estilo de ventana y conversión entre píxeles de Qt y de Windows."""
from PySide6.QtCore import QRectF, Qt


def make_tool_window(widget, click_through=False):
    """Ventana sin marco, siempre encima, fuera de Alt+Tab y con transparencia real por píxel.

    Con `click_through` los clics la atraviesan (y nunca recibe el foco).
    """
    flags = Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    if click_through:
        flags |= Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
    widget.setWindowFlags(flags)
    widget.setAttribute(Qt.WA_TranslucentBackground)
    widget.setAttribute(Qt.WA_ShowWithoutActivating)


def hwnd_of(widget):
    return int(widget.winId())


class ScreenMap:
    """Convierte entre píxeles físicos de Windows (los del gestor de ventanas) y lógicos de Qt."""

    def __init__(self, screen):
        self.geometry = screen.geometry()  # lógico
        self.dpr = screen.devicePixelRatio()

    def to_physical(self, logical):
        return round(logical * self.dpr)

    def rect_to_logical(self, left, top, right, bottom):
        """Rectángulo físico de la pantalla -> rectángulo lógico relativo a la ventana que cubre la pantalla."""
        ox, oy = self.geometry.x() * self.dpr, self.geometry.y() * self.dpr
        d = self.dpr
        return QRectF((left - ox) / d, (top - oy) / d, (right - left) / d, (bottom - top) / d)

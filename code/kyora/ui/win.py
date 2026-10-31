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


def place_under(widget, other):
    """Pone `widget` justo debajo de `other` en el orden de las ventanas (sin moverla, cambiarla de tamaño ni activarla)."""
    try:
        import win32con
        import win32gui

        win32gui.SetWindowPos(hwnd_of(widget), hwnd_of(other), 0, 0, 0, 0,
                              win32con.SWP_NOMOVE | win32con.SWP_NOSIZE | win32con.SWP_NOACTIVATE)
    except Exception:  # noqa: BLE001, S110 - sin Windows (las pruebas) o con una ventana que ya no existe: se queda donde esté
        pass


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



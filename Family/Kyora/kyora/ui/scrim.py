"""El velo: cuando sale un panel (arriba, izquierda o el buscador), todo lo demás de la pantalla se oscurece un poco para
darle importancia. Es una sola ventana negra que deja pasar los clics; lo único que se anima es su opacidad (Windows la
compone sin repintar nada), y cuando nadie la pide se esconde del todo.
"""
from PySide6.QtCore import QEasingCurve
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import QWidget

from kyora.ui.anim import Tween
from kyora.ui.win import make_tool_window, place_under


class Scrim(QWidget):
    def __init__(self, theme, screen_map):
        super().__init__()
        make_tool_window(self, click_through=True)
        self.setWindowTitle("KyoraScrim")
        self.theme = theme
        self.setGeometry(screen_map.geometry)
        self._owners = {}  # nombre -> la ventana del panel que lo pide (el velo queda justo debajo de la última)
        self._level = 0.0
        self._goal = 0.0
        self._fade = Tween(self, self._set_level, self._settled, frame_ms=16)
        self.setWindowOpacity(0.0)

    def want(self, name, panel, on):
        """El panel `name` pide (o deja de pedir) el velo."""
        if on:
            self._owners[name] = panel
        else:
            self._owners.pop(name, None)
        goal = self.theme.scrim_alpha if self._owners else 0.0
        if goal and not self.isVisible():
            self.show()
        if panel is not None and on:
            place_under(self, panel)  # el velo tapa las apps, nunca el panel
        if goal != self._goal:
            self._goal = goal
            self._fade.start(self._level, goal, self.theme.scrim_ms, QEasingCurve.OutCubic)

    def _set_level(self, value):
        self._level = float(value)
        self.setWindowOpacity(self._level)

    def _settled(self):
        if self._level <= 0.001 and not self._owners:
            self.hide()

    def paintEvent(self, _):
        QPainter(self).fillRect(self.rect(), QColor(0, 0, 0))

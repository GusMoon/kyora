"""Win+X: apagar, reiniciar o suspender, en el centro de la pantalla, con todo lo demás desenfocado.

Se captura la pantalla antes de mostrar nada (con las ventanas y paneles que haya), se desenfoca y se oscurece un
poco, y esa imagen cubre toda la pantalla con las tres opciones en el centro. El desenfoque aparece con un fundido sobre
la pantalla de verdad, así que se ve cómo todo se va desenfocando. 1, 2 y 3 (o las flechas y Enter) eligen; Esc, un clic
fuera o pasar a otra ventana lo cierran.
"""
from PySide6.QtCore import QEasingCurve, QEvent, QRectF, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QGuiApplication, QPainter
from PySide6.QtWidgets import QWidget

from kyora.system.win32 import force_foreground
from kyora.ui import backdrop
from kyora.ui.anim import Tween
from kyora.ui.bar import font
from kyora.ui.panels import POWER_OPTIONS, PowerTiles
from kyora.ui.win import hwnd_of, make_tool_window

FADE_MS = 170
VEIL = 120  # opacidad (0-255) del velo oscuro sobre lo desenfocado
BLUR_CHECK_MS = 200
TILES_W, TILES_H = 640, 210


class PowerScreen(QWidget):
    visibility = Signal(bool)  # se abrió o se cerró: los paneles de los bordes no saltan mientras está

    def __init__(self, theme, screen_map, invoke):
        super().__init__()
        make_tool_window(self)
        self.setAttribute(Qt.WA_TranslucentBackground, False)
        self.setAttribute(Qt.WA_OpaquePaintEvent, True)
        self.setWindowTitle("KyoraPower")
        self.setFocusPolicy(Qt.StrongFocus)
        self.theme, self.map, self._invoke = theme, screen_map, invoke
        self.opened = False
        self._blur = None
        self._opacity = 0.0
        self._fade = Tween(self, self._set_opacity, self._faded)
        self.tiles = PowerTiles(theme)
        self.tiles.setParent(self)
        self.tiles.setFixedSize(TILES_W, TILES_H)
        self.tiles.chosen.connect(self._choose)

    def toggle(self):
        self.close_screen() if self.opened else self.open()

    def open(self):
        if self.opened:
            return
        g = self.map.geometry
        shot = QGuiApplication.primaryScreen().grabWindow(0, g.x(), g.y(), g.width(), g.height())  # antes de mostrar nada
        self._blur = backdrop.blur_image(shot.toImage()) if not shot.isNull() else None
        self.opened = True
        self.visibility.emit(True)
        self.setGeometry(g)
        self.tiles.move((g.width() - TILES_W) // 2, (g.height() - TILES_H) // 2)
        self.tiles.selected = 0
        self.setWindowOpacity(0.0)
        self._opacity = 0.0
        self.show()
        self.raise_()
        self.activateWindow()
        force_foreground(hwnd_of(self))
        self.tiles.setFocus()
        self._fade.start(0.0, 1.0, FADE_MS, QEasingCurve.OutCubic)

    def close_screen(self, refocus=True):
        if not self.opened:
            return
        self.opened = False
        self.visibility.emit(False)
        self._fade.start(self._opacity, 0.0, FADE_MS - 40, QEasingCurve.InCubic)
        if refocus:
            self._invoke("wm.refocus")

    def _choose(self, index):
        self.close_screen(refocus=False)
        self._invoke(POWER_OPTIONS[index][2])

    def _set_opacity(self, value):
        self._opacity = float(value)
        self.setWindowOpacity(self._opacity)

    def _faded(self):
        if not self.opened:
            self.hide()
            self._blur = None

    # ---------- teclado, foco y ratón ----------

    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Escape:
            self.close_screen()
        else:
            super().keyPressEvent(event)

    def mousePressEvent(self, event):
        if not self.tiles.geometry().contains(event.position().toPoint()):
            self.close_screen()  # un clic fuera de las opciones

    def changeEvent(self, event):
        if event.type() == QEvent.ActivationChange and self.opened and not self.isActiveWindow():
            QTimer.singleShot(BLUR_CHECK_MS, self._check_blur)
        super().changeEvent(event)

    def _check_blur(self):
        if self.opened and not self.isActiveWindow():
            self.close_screen(refocus=False)

    def closeEvent(self, event):
        event.ignore()
        self.close_screen()

    # ---------- pintura ----------

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.SmoothPixmapTransform)
        if self._blur is not None:
            p.drawImage(QRectF(self.rect()), self._blur)
            p.fillRect(self.rect(), QColor(0, 0, 0, VEIL))
        else:
            p.fillRect(self.rect(), QColor(self.theme.frame_dark))
        t = self.theme
        p.setPen(QColor(t.dim))
        p.setFont(font(t, 15))
        below = QRectF(self.tiles.x(), self.tiles.y() + TILES_H + 14, TILES_W, 24)
        p.drawText(below, Qt.AlignCenter, "1 · 2 · 3  o  ← →  y  Enter        Esc  para salir")

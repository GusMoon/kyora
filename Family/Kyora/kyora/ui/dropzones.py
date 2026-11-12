"""Las opciones al arrastrar una ventana con el mosaico hecho: se ven los 4 sitios donde puede quedar (columna
izquierda o derecha, arriba o abajo) y se resalta el rectángulo donde quedaría de verdad según el sitio bajo el cursor;
al soltarla ahí, la ventana lo ocupa y las demás se acomodan solas. Con Mayús pulsado no se enseña nada y se suelta libre. Es una ventana transparente que deja pasar los clics
y solo existe mientras se arrastra (se repinta solo cuando cambia el hueco resaltado)."""
from PySide6.QtCore import QRectF, Qt
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import QWidget

from kyora.ui.win import make_tool_window


class DropZones(QWidget):
    def __init__(self, theme, screen_map):
        super().__init__()
        make_tool_window(self, click_through=True)
        self.setWindowTitle("KyoraDrop")
        self.theme, self.map = theme, screen_map
        self.setGeometry(screen_map.geometry)
        self._zones = None

    def show_zones(self, zones):
        """`zones` = {"quads": 4 rectángulos en px físicos, "hover": índice, "result": rectángulo}, o None para esconder."""
        if zones == self._zones:
            return
        self._zones = zones
        if zones is None:
            self.hide()
            return
        if not self.isVisible():
            self.show()
        self.update()

    def paintEvent(self, _):
        if not self._zones:
            return
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        line = QColor(t.drop_line)
        for i, quad in enumerate(self._zones["quads"]):  # los 4 sitios posibles, apenas insinuados
            rect = self.map.rect_to_logical(*quad).adjusted(2, 2, -2, -2)
            fill = QColor(t.drop_color)
            fill.setAlpha(34 if i == self._zones["hover"] else 0)
            edge = QColor(line)
            edge.setAlpha(110 if i == self._zones["hover"] else 60)
            p.setBrush(fill)
            p.setPen(QPen(edge, 1, Qt.DashLine))
            p.drawRoundedRect(QRectF(rect), t.drop_radius, t.drop_radius)
        result = self.map.rect_to_logical(*self._zones["result"]).adjusted(3, 3, -3, -3)  # dónde quedaría de verdad
        p.setBrush(QColor(t.drop_color))
        p.setPen(QPen(line, 2))
        p.drawRoundedRect(QRectF(result), t.drop_radius, t.drop_radius)

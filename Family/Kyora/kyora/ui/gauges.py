"""Piezas pequeñas de texto para los paneles."""
from PySide6.QtCore import QRectF, Qt
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import QWidget

from kyora.ui.bar import font


class Caption(QWidget):
    """Una línea de texto pintada con los colores del tema (cambia sola si cambian los colores)."""

    def __init__(self, theme, text="", px=15, bold=False, dim=False):
        super().__init__()
        self.theme, self.text, self.px, self.bold, self.dim = theme, text, px, bold, dim
        self.setFixedHeight(theme.font_px + 10)

    def set_text(self, text):
        if text != self.text:
            self.text = text
            self.setToolTip(text)
            self.update()

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setFont(font(t, self.px, bold=self.bold))
        p.setPen(QColor(t.dim if self.dim else t.ink))
        text = p.fontMetrics().elidedText(self.text, Qt.ElideRight, self.width())
        p.drawText(QRectF(self.rect()), Qt.AlignVCenter | Qt.AlignLeft, text)

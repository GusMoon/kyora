"""Navegación del explorador (que ya no se enseña, pero se conserva):

- PlacesList: los lugares (los de siempre y los anclados) en filas compactas, para la tarjeta "Lugares" de Archivos.
"""
import os

from PySide6.QtCore import QRectF, Qt, Signal
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import QAbstractButton, QMenu, QVBoxLayout, QWidget

from kyora.ui import glyphs
from kyora.ui.bar import font


class PlaceButton(QAbstractButton):
    """Fila compacta de un lugar: icono de carpeta y nombre."""

    def __init__(self, theme, text):
        super().__init__()
        self.theme = theme
        self.setText(text)
        self.setFixedHeight(32)
        self.setCursor(Qt.PointingHandCursor)
        self.setAttribute(Qt.WA_Hover)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        if self.underMouse():
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.hover))
            p.drawRoundedRect(QRectF(self.rect()), 8, 8)
        p.setPen(glyphs.pen(QColor(t.dim), 1.5))
        glyphs.folder(p, QRectF(8, (self.height() - 18) / 2, 18, 18))
        p.setPen(QColor(t.ink))
        p.setFont(font(t, t.explorer_font_px))
        text = p.fontMetrics().elidedText(self.text(), Qt.ElideRight, self.width() - 40)
        p.drawText(QRectF(34, 0, self.width() - 36, self.height()), Qt.AlignVCenter | Qt.AlignLeft, text)


class PlacesList(QWidget):
    place = Signal(str)
    unpin = Signal(str)

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.layout_ = QVBoxLayout(self)
        self.layout_.setContentsMargins(0, 0, 0, 0)
        self.layout_.setSpacing(1)
        self.by_name = {}  # nombre -> ruta, para los atajos (Ctrl+Shift+D: Descargas…)

    def set_places(self, places, pinned):
        while self.layout_.count():
            item = self.layout_.takeAt(0)
            if item.widget():
                item.widget().deleteLater()
        self.by_name = dict(places)
        entries = list(places) + [(os.path.basename(p.rstrip("\\/")) or p, p) for p in pinned]
        for name, path in entries:
            b = PlaceButton(self.theme, name)
            b.setToolTip(path)
            b.clicked.connect(lambda _=False, target=path: self.place.emit(target))
            if path in pinned:
                b.setContextMenuPolicy(Qt.CustomContextMenu)
                b.customContextMenuRequested.connect(lambda pos, target=path, w=b: self._pin_menu(w, pos, target))
            self.layout_.addWidget(b)

    def _pin_menu(self, widget, pos, path):
        menu = QMenu(self)
        menu.addAction("Desanclar", lambda: self.unpin.emit(path))
        menu.exec(widget.mapToGlobal(pos))

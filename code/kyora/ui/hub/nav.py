"""Navegación del panel de arriba.

- SectionBar: la mini barra de secciones (como la referencia): una cápsula oscura con un segmento por sección; la
  activa es una píldora clara con icono y nombre, las demás solo icono. Al cambiar, la píldora se desliza.
- PlacesList: los lugares (los de siempre y los anclados) en filas compactas, para la tarjeta "Lugares" de Archivos.
"""
import os

from PySide6.QtCore import QEasingCurve, QRectF, Qt, Signal
from PySide6.QtGui import QColor, QFontMetrics, QPainter, QPen
from PySide6.QtWidgets import QAbstractButton, QMenu, QVBoxLayout, QWidget

from kyora.core.animation import lerp
from kyora.ui import glyphs
from kyora.ui.anim import Tween
from kyora.ui.bar import font

SECTIONS = (
    ("lobby", "Lobby", glyphs.home),
    ("files", "Archivos", glyphs.folder),
    ("tasks", "Tareas", glyphs.task),
    ("brain", "Cerebro", glyphs.brain),
    ("kyora", "Kyora", glyphs.owl),
)
SLIDE_MS = 200
ICON_W = 46  # segmento de una sección no activa: solo su icono
PAD = 4


class SectionBar(QWidget):
    chosen = Signal(str)

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.keys = [key for key, _, _ in SECTIONS]
        self.active = self.keys[0]
        self._from = self._to = None
        self._t = 1.0
        self._slide = Tween(self, self._set_t)
        self.setFixedHeight(42)
        self.setCursor(Qt.PointingHandCursor)
        self.setMouseTracking(True)
        self.setFixedWidth(self._width())

    def _label_w(self, text):
        """Ancho del segmento activo: icono, nombre y sus márgenes."""
        return QFontMetrics(font(self.theme, 15, bold=True)).horizontalAdvance(text) + 58

    def _width(self):
        widest = max(self._label_w(text) for _, text, _ in SECTIONS)
        return 2 * PAD + widest + ICON_W * (len(SECTIONS) - 1)

    def _rects(self, active):
        """Rectángulo de cada segmento cuando `active` es la sección activa."""
        x, rects = PAD, {}
        for key, text, _ in SECTIONS:
            w = self._label_w(text) if key == active else ICON_W
            rects[key] = QRectF(x, PAD, w, self.height() - 2 * PAD)
            x += w
        return rects

    def set_active(self, key, animate=True):
        if key == self.active and self._from is not None:
            return
        self._from = self._rects(self.active)
        self._to = self._rects(key)
        self.active = key
        if animate and self.isVisible():
            self._slide.start(0.0, 1.0, SLIDE_MS, QEasingCurve.OutCubic)
        else:
            self._set_t(1.0)

    def _set_t(self, value):
        self._t = float(value)
        self.update()

    def _current(self):
        if self._from is None:
            return self._rects(self.active)
        return {k: QRectF(lerp(self._from[k].x(), self._to[k].x(), self._t), self._to[k].y(),
                          lerp(self._from[k].width(), self._to[k].width(), self._t), self._to[k].height())
                for k in self.keys}

    def mouseReleaseEvent(self, event):
        for key, rect in self._current().items():
            if rect.contains(event.position()) and event.button() == Qt.LeftButton:
                self.chosen.emit(key)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        h = self.height()
        p.setPen(QPen(QColor(t.glass_edge), 1))
        p.setBrush(QColor(t.card_inner))
        p.drawRoundedRect(QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5), h / 2, h / 2)
        rects = self._current()
        pill = rects[self.active]
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(t.pick_bg))
        p.drawRoundedRect(pill, pill.height() / 2, pill.height() / 2)
        for key, text, glyph in SECTIONS:
            r = rects[key]
            on = key == self.active
            color = QColor(t.pick_ink if on else "#cfcfcf")
            p.setPen(glyphs.pen(color, 1.6))
            p.setBrush(Qt.NoBrush)
            if on:
                glyph(p, QRectF(r.left() + 14, r.center().y() - 10, 20, 20))
                p.setPen(color)
                p.setFont(font(t, 15, bold=True))
                p.setOpacity(self._t)  # el nombre aparece cuando la píldora llega
                p.drawText(QRectF(r.left() + 40, r.top(), r.width() - 44, r.height()), Qt.AlignVCenter | Qt.AlignLeft,
                           text)
                p.setOpacity(1.0)
            else:
                glyph(p, QRectF(r.center().x() - 10, r.center().y() - 10, 20, 20))


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

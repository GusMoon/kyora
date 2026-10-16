"""Contenido de la carpeta elegida en el directorio: migas, título y tarjetas.

Todo se alinea en la esquina superior izquierda del panel. Cada subcarpeta y cada archivo
es una tarjeta (``contentCard``). El panel solo coloca, desplaza y reporta pulsaciones;
qué carpeta se muestra lo decide ``RootDirectory``.
"""
from PySide6.QtCore import QPointF, QRectF, Qt, QVariantAnimation, Signal
from PySide6.QtGui import QFontMetricsF, QPainter
from PySide6.QtWidgets import QWidget

from core.matrix.motherboard.modules import kyora_theme as kt
from core.matrix.motherboard.modules.directory.components import contentCard
from core.matrix.motherboard.modules.directory.components.contentCard import (
    CARD_DEPTH, CARD_HEIGHT, CARD_WIDTH, REFERENCE_HEIGHT, Entry, tinted, ui_font,
)

INTRO_MS = 600
SCROLL_STEP = 60        # píxeles por muesca de la rueda

# Disposición, en píxeles de referencia
MARGIN_LEFT = 40
MARGIN_TOP = 32
MARGIN_BOTTOM = 30
CRUMB_HEIGHT = 16
TITLE_HEIGHT = 40
COUNT_HEIGHT = 20
LIST_GAP = 18           # espacio entre la cuenta y la primera tarjeta


class ContentPanel(QWidget):
    """Migas, título y tarjetas de lo que contiene la carpeta elegida.

    Signals:
        entry_activated(str, bool): ruta y si es carpeta de la tarjeta pulsada.
        crumb_activated(int): nivel de la miga pulsada (0 = carpetas principales).
    """

    entry_activated = Signal(str, bool)
    crumb_activated = Signal(int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMouseTracking(True)
        self._crumbs = []
        self._title = ""
        self._entries = []
        self._scroll = 0.0
        self._hover = -1
        self._intro = 1.0
        self._card_rects = []    # (QRectF, índice) calculados al pintar
        self._crumb_rects = []   # (QRectF, nivel) calculados al pintar
        self._list_rect = QRectF()

        self._intro_anim = QVariantAnimation(self, startValue=0.0, endValue=1.0, duration=INTRO_MS)
        self._intro_anim.valueChanged.connect(self._on_intro)

    # ---- datos --------------------------------------------------------------
    def set_content(self, crumbs: list, title: str, entries: list) -> None:
        """Muestra una carpeta.

        Args:
            crumbs: nombres de las migas; todas menos la última son clicables.
            title: nombre de la carpeta.
            entries: lista de ``Entry``.
        """
        self._crumbs = crumbs
        self._title = title
        self._entries = entries
        self._scroll = 0.0
        self._hover = -1
        self.update()

    def play_intro(self) -> None:
        """Reproduce el fundido de entrada."""
        self._intro_anim.stop()
        self._intro_anim.start()

    def _on_intro(self, value) -> None:
        self._intro = float(value)
        self.update()

    # ---- eventos ------------------------------------------------------------
    def _scale(self) -> float:
        return self.height() / REFERENCE_HEIGHT

    def _card_at(self, pos: QPointF) -> int:
        """Índice de la tarjeta visible bajo ``pos``, o -1."""
        if not self._list_rect.contains(pos):
            return -1
        for rect, index in self._card_rects:
            if rect.contains(pos):
                return index
        return -1

    def mousePressEvent(self, event) -> None:
        """Resuelve un clic en una miga o en una tarjeta."""
        if event.button() != Qt.LeftButton:
            super().mousePressEvent(event)
            return
        pos = event.position()
        for rect, level in self._crumb_rects:
            if rect.contains(pos):
                self.crumb_activated.emit(level)
                return
        index = self._card_at(pos)
        if index >= 0:
            entry = self._entries[index]
            self.entry_activated.emit(entry.path, entry.is_dir)

    def mouseMoveEvent(self, event) -> None:
        """Levanta la tarjeta bajo el cursor."""
        pos = event.position()
        index = self._card_at(pos)
        crumb = any(rect.contains(pos) for rect, _ in self._crumb_rects)
        self.setCursor(Qt.PointingHandCursor if index >= 0 or crumb else Qt.ArrowCursor)
        if index != self._hover:
            self._hover = index
            self.update()

    def wheelEvent(self, event) -> None:
        """Desplaza las tarjetas."""
        steps = event.angleDelta().y() / 120.0
        limit = max(0.0, len(self._entries) * contentCard.pitch(self._scale()) - self._list_rect.height())
        self._scroll = max(0.0, min(limit, self._scroll - steps * SCROLL_STEP))
        self.update()
        event.accept()

    def leaveEvent(self, event) -> None:
        """Baja la tarjeta levantada al salir el cursor."""
        self._hover = -1
        self.update()
        super().leaveEvent(event)

    # ---- pintado ------------------------------------------------------------
    def paintEvent(self, event) -> None:
        """Dibuja las migas, el título y las tarjetas desde la esquina superior izquierda."""
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setOpacity(self._intro)
        s = self._scale()
        left = MARGIN_LEFT * s
        width = min(CARD_WIDTH * s, self.width() - left - 20 * s)
        self._crumb_rects = []
        self._card_rects = []
        if width < 200 * s or not self._crumbs:
            p.end()
            return

        top = self._draw_header(p, left, width, s)
        self._list_rect = QRectF(left, top, width, self.height() - top - MARGIN_BOTTOM * s)
        if not self._entries:
            p.setFont(ui_font(12 * s, False, 2))
            p.setPen(tinted(kt.TEXT_DIM))
            p.drawText(self._list_rect, Qt.AlignLeft | Qt.AlignTop, "CARPETA VACÍA")
            p.end()
            return
        p.setClipRect(self._list_rect.adjusted(0, -4 * s, 0, 0))
        for index, entry in enumerate(self._entries):
            y = top + index * contentCard.pitch(s) - self._scroll
            if y + (CARD_HEIGHT + CARD_DEPTH) * s < top or y > self._list_rect.bottom():
                continue
            row = QRectF(left, y, width, CARD_HEIGHT * s)
            self._card_rects.append((row.adjusted(0, 0, 0, CARD_DEPTH * s), index))
            contentCard.paint(p, entry, index, row, s, index == self._hover)
        p.end()

    def _draw_header(self, p: QPainter, left: float, width: float, s: float) -> float:
        """Migas (cada nivel superior es clicable), título y cuenta de elementos.

        Returns:
            La coordenada y donde empieza la lista de tarjetas.
        """
        crumb_font = ui_font(10 * s, False, 1.5)
        metrics = QFontMetricsF(crumb_font)
        x = left
        y = MARGIN_TOP * s
        p.setFont(crumb_font)
        last = len(self._crumbs) - 1
        for level, name in enumerate(self._crumbs):
            name_width = metrics.horizontalAdvance(name)
            rect = QRectF(x, y, name_width, CRUMB_HEIGHT * s)
            p.setPen(tinted(kt.TEXT_MUTED if level < last else kt.TEXT_SUB))
            p.drawText(rect, Qt.AlignLeft | Qt.AlignVCenter, name)
            if level < last:
                self._crumb_rects.append((rect.adjusted(-4, -4, 4, 4), level))
            x += name_width
            if level < last:
                sep = "  ›  "
                p.setPen(tinted(kt.TEXT_DIM))
                p.drawText(QRectF(x, y, metrics.horizontalAdvance(sep), CRUMB_HEIGHT * s),
                           Qt.AlignLeft | Qt.AlignVCenter, sep)
                x += metrics.horizontalAdvance(sep)

        title_rect = QRectF(left, y + CRUMB_HEIGHT * s + 4 * s, width, TITLE_HEIGHT * s)
        p.setFont(ui_font(30 * s, True, 1))
        p.setPen(tinted(kt.TEXT))
        p.drawText(title_rect, Qt.AlignLeft | Qt.AlignVCenter,
                   QFontMetricsF(ui_font(30 * s, True, 1)).elidedText(self._title, Qt.ElideRight, width))
        folders = sum(1 for entry in self._entries if entry.is_dir)
        count_rect = QRectF(left, title_rect.bottom(), width, COUNT_HEIGHT * s)
        p.setFont(ui_font(10 * s, False, 2))
        p.setPen(tinted(kt.TEXT_SUB))
        p.drawText(count_rect, Qt.AlignLeft | Qt.AlignVCenter,
                   f"{folders} CARPETAS · {len(self._entries) - folders} ARCHIVOS")
        return count_rect.bottom() + LIST_GAP * s

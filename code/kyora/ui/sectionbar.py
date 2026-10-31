"""La píldora de secciones de arriba: Buscar, Tareas, Notas, Chat y Música. Está en el panel superior y también
dentro del buscador, para que no desaparezca al entrar en una sección: la elegida queda destacada y su contenido se
despliega debajo.

Va en su propio módulo para que el buscador y el panel superior la compartan sin importarse el uno al otro.
"""
from PySide6.QtCore import QEasingCurve, QRectF, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QFontMetrics, QPainter
from PySide6.QtWidgets import QAbstractButton, QHBoxLayout, QWidget

from kyora.ui import glyphs
from kyora.ui.anim import Tween
from kyora.ui.bar import accent, font
from kyora.ui.hub.cards import paint_well

ROW_H = 38  # la fila de secciones
CHIP_H = 34  # cada sección
ROW_PAD = 2  # aire arriba y abajo
ROW_GAP = 4  # y entre ellas
CHIP_PAD = 8  # aire a cada lado del contenido de un dato
EXPAND_MS = 200  # lo que tarda la sección abierta en expandirse (o en encogerse)
HOVER_OPEN_MS = 45  # lo que el cursor debe quedarse sobre un icono de la fila para que abra su página
SECTIONS = ("search", "task", "notes", "chat", "music")


class Chip(QAbstractButton):
    """Una pieza de la fila: icono y/o texto. Las que se pulsan (hora, wifi, Bluetooth...) se resaltan al pasar el ratón,
    abren su página tras un instante de pasar por encima (`hover_open`, sin clic) y sobresalen en relieve mientras su
    página está abierta."""

    hover_open = Signal()  # el cursor se quedó un momento encima
    grown = Signal()  # cambió su ancho (se expande o se encoge)

    def __init__(self, theme, width, glyph=None, text="", clickable=False, tooltip="", slot=False, label=""):
        super().__init__()
        self.theme = theme
        self.label = label  # el nombre que aparece junto al icono cuando la sección está abierta (la píldora se expande)
        self._grow = 0.0  # 0 = solo el icono, 1 = expandida con su nombre
        self.fill_width = 0  # el ancho al que se expande (lo pone la fila)
        self._grow_anim = Tween(self, self._set_grow)
        self.slot = slot  # una sección de la píldora: círculo apagado y, al pasar o estar abierta, destacada
        self.glyph = glyph  # glyph(pintor, caja)
        self.text = text
        self.warn = False
        self.active = False
        self.bold_text = False
        self.setToolTip(tooltip)
        self.min_width = width  # el dato nunca es más estrecho que esto; si su texto no cabe, se ensancha
        self.setFixedSize(width, CHIP_H)
        self.setFocusPolicy(Qt.NoFocus)  # pulsarla no le quita el foco al campo del buscador
        self.setAttribute(Qt.WA_Hover)
        self.setCursor(Qt.PointingHandCursor if clickable else Qt.ArrowCursor)
        self.clickable = clickable
        self._dwell = QTimer(self)
        self._dwell.setSingleShot(True)
        self._dwell.setInterval(HOVER_OPEN_MS)
        self._dwell.timeout.connect(lambda: self.hover_open.emit() if self.underMouse() else None)

    def enterEvent(self, event):
        if self.clickable:
            self._dwell.start()
        super().enterEvent(event)

    def leaveEvent(self, event):
        self._dwell.stop()
        super().leaveEvent(event)

    def _fit(self):
        """Ancho justo para su icono y su texto: nada se corta ni se pisa con el dato de al lado."""
        t = self.theme
        text_w = QFontMetrics(font(t, bold=True)).horizontalAdvance(self.text) if self.text else 0
        icon_w = t.icon_px if self.glyph else 0
        content = icon_w + (5 if icon_w and text_w else 0) + text_w
        self.setFixedWidth(max(self.min_width, content + 2 * CHIP_PAD))

    def set_text(self, text, warn=False):
        if (text, warn) != (self.text, self.warn):
            self.text, self.warn = text, warn
            self._fit()
            self.update()

    def label_width(self):
        """Lo que mide la sección abierta con su nombre (el mínimo para que quepa)."""
        text_w = QFontMetrics(font(self.theme, bold=True)).horizontalAdvance(self.label)
        return max(self.min_width, self.theme.icon_px + 6 + text_w + 2 * CHIP_PAD + 4)

    def refresh(self):
        """El ancho de la sección cuando cambia aquello a lo que se expande."""
        self._set_grow(self._grow)

    def _expanded_width(self):
        if not self.label:
            return self.min_width
        if self.fill_width:  # se expande hasta ocupar el ancho que sobra en la fila
            return max(self.min_width, self.fill_width)
        return self.label_width()

    def _set_grow(self, value):
        self._grow = float(value)
        width = round(self.min_width + self._grow * (self._expanded_width() - self.min_width))
        if width != self.width():
            self.setFixedWidth(width)
            self.grown.emit()
        self.update()

    def set_active(self, on):
        if on != self.active:
            self.active = on
            if self.label:  # la píldora se expande y enseña el nombre; al dejar de estar abierta, se encoge
                self._grow_anim.start(self._grow, 1.0 if on else 0.0, EXPAND_MS, QEasingCurve.OutCubic)
            self.update()

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        r = QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5)
        lit = self.active or (self.clickable and self.underMouse())
        pressed = self.slot and self.active
        if pressed:  # la sección abierta, "pulsada" (skeumorfismo, ver DISEÑO.md): hundida, con el acento encendido por dentro
            paint_well(p, t, r, r.height() / 2)
            glow = QColor(t.gold)
            glow.setAlpha(36)
            p.setPen(Qt.NoPen)
            p.setBrush(glow)
            p.drawRoundedRect(r.adjusted(2, 3, -2, -2), r.height() / 2 - 2, r.height() / 2 - 2)
        elif self.slot or lit:  # plano: un velo claro, sin relieve
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(255, 255, 255, (40 if self.active else 28) if lit else 9))
            p.drawRoundedRect(r, r.height() / 2, r.height() / 2)
        color = accent(t, lit) if lit or not self.slot else QColor(t.dim)
        p.setFont(font(t, bold=self.bold_text or lit))
        metrics = p.fontMetrics()
        gap = 5
        text_w = metrics.horizontalAdvance(self.text) if self.text else 0
        icon_w = t.icon_px if self.glyph else 0
        total = icon_w + (gap if icon_w and text_w else 0) + text_w
        label_w = metrics.horizontalAdvance(self.label) * self._grow if self.label else 0
        if label_w:
            total += (6 * self._grow) + label_w
        x = (self.width() - total) / 2
        dy = 1.5 if pressed else 0  # pulsada: el contenido baja un poco, como el botón
        if self.glyph:
            p.setPen(glyphs.pen(color, 1.3))
            p.setBrush(Qt.NoBrush)
            self.glyph(p, QRectF(x, (self.height() - t.icon_px) / 2 + dy, t.icon_px, t.icon_px))
            x += icon_w + gap
            if label_w and self._grow > 0.15:  # el nombre aparece mientras la píldora se ensancha
                p.setOpacity(min((self._grow - 0.15) / 0.6, 1.0))
                p.setFont(font(t, bold=True))
                p.setPen(QColor(t.ink))
                p.drawText(QRectF(x - gap + 6, dy, label_w + 6, self.height()), Qt.AlignVCenter | Qt.AlignLeft, self.label)
                p.setOpacity(1.0)
        if self.text:
            p.setPen(QColor(t.warn) if self.warn else QColor(t.ink if lit else t.dim))  # letras en gris claro
            p.drawText(QRectF(x, 0, text_w + 2, self.height()), Qt.AlignVCenter | Qt.AlignLeft, self.text)


class StatusRow(QWidget):
    """La fila de secciones del panel de arriba, directo sobre el fondo del panel: Buscar, Tareas, Notas y Música. Sin líneas
    entre ellas: la sección bajo el cursor se aclara y la abierta se expande y ocupa todo el ancho que sobra (`set_fill`).
    Pulsar Música abre su página debajo (`go`); los demás piden su acción (`run`). Lo que suena no se ve aquí: está en la
    cápsula del panel de abajo (`musicpill.py`)."""

    go = Signal(str)
    resized = Signal()  # una sección se expandió o se encogió: la píldora cambió de ancho
    run = Signal(str)  # "search", "task" o "notes"
    hover = Signal(str)  # el cursor se quedó sobre el icono de una página: se abre sin pulsar

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self._fill = 0  # el ancho al que se expande la sección abierta (0: solo lo justo)
        t = theme
        self.search = Chip(t, 44, glyphs.magnifier, clickable=True, tooltip="Buscar", slot=True, label="Buscar")
        self.tasks = Chip(t, 44, glyphs.task, clickable=True, tooltip="Tareas", slot=True, label="Tareas")
        self.notes = Chip(t, 44, glyphs.rows, clickable=True, tooltip="Notas", slot=True, label="Notas")
        self.chat = Chip(t, 44, glyphs.bubble, clickable=True, tooltip="Chat", slot=True, label="Chat")
        self.music = Chip(t, 44, glyphs.music, clickable=True, tooltip="Música", slot=True, label="Música")
        self.chips = {"search": self.search, "task": self.tasks, "notes": self.notes, "chat": self.chat,
                      "music": self.music}
        for name, chip in (("search", self.search), ("task", self.tasks), ("notes", self.notes), ("chat", self.chat)):
            chip.clicked.connect(lambda _=False, n=name: self.run.emit(n))
        self.music.clicked.connect(lambda _=False: self.go.emit("music"))
        self.music.hover_open.connect(lambda: self.hover.emit("music"))
        for chip in self.chips.values():
            chip.grown.connect(self._grown)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, ROW_PAD, 0, ROW_PAD)
        layout.setSpacing(ROW_GAP)
        for chip in self.chips.values():
            layout.addWidget(chip)
        self.setFixedHeight(ROW_H)

    def _grown(self):
        self.updateGeometry()
        self.resized.emit()

    def needed_width(self, name):
        """Lo mínimo que mide la fila con la sección `name` abierta (con su nombre)."""
        chips = list(self.chips.items())
        width = sum(c.label_width() if key == name else c.min_width for key, c in chips)
        return width + (len(chips) - 1) * ROW_GAP

    def set_fill(self, total):
        """El ancho que ocupa la fila (el del panel): la sección abierta se expande hasta llenarlo; las demás, solo su
        círculo."""
        self._fill = total
        chips = list(self.chips.values())
        gaps = (len(chips) - 1) * ROW_GAP
        others = sum(c.min_width for c in chips[1:])
        for chip in chips:
            chip.fill_width = total - gaps - others
            chip.refresh()

    def set_active(self, name):
        for key, chip in self.chips.items():
            chip.set_active(key == name)

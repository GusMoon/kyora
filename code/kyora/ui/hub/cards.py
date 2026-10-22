"""Piezas del panel de arriba, al estilo de la referencia (placas de cristal oscuras, sin tramas).

- paint_glass: la placa de cristal: degradado suave de arriba abajo, borde casi invisible y un filete de luz arriba.
- Glass: un widget que es solo esa placa (para meter contenido dentro).
- Card: un título suelto encima (como "Explore" en la referencia) y debajo la placa, en `self.inner`. A la derecha
  del título se pueden poner controles con `self.header.addWidget(...)`.
- BarChart: barras redondeadas con la actual más clara; al pasar el ratón, una tarjetita con el valor.
- Pills: selector de dos o más opciones en forma de píldora.
"""
from PySide6.QtCore import QRectF, Qt, Signal
from PySide6.QtGui import QBrush, QColor, QLinearGradient, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget

from kyora.ui import glyphs
from kyora.ui.bar import font


def paint_glass(p, theme, rect, radius=None, hi=False, fill=None):
    """Placa de cristal en `rect`. `hi`: resaltada (más clara). `fill`: un color liso en lugar del cristal."""
    t = theme
    radius = t.card_radius if radius is None else radius
    box = QRectF(rect).adjusted(0.5, 0.5, -0.5, -0.5)
    shape = QPainterPath()
    shape.addRoundedRect(box, radius, radius)
    if fill is not None:
        p.fillPath(shape, QColor(fill))
        return
    grad = QLinearGradient(box.topLeft(), box.bottomLeft())
    grad.setColorAt(0, QColor(t.glass_top))
    grad.setColorAt(1, QColor(t.glass_bottom))
    p.fillPath(shape, grad)
    if hi:
        p.fillPath(shape, QColor(t.glass_hi))
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(QColor(t.glass_edge), 1))
    p.drawPath(shape)
    light = QLinearGradient(box.topLeft(), box.bottomLeft())  # el filete de luz: solo en el borde de arriba
    light.setColorAt(0, QColor(t.glass_hi))
    light.setColorAt(min(28 / max(box.height(), 1), 1), QColor(0, 0, 0, 0))
    p.setPen(QPen(QBrush(light), 1))
    p.drawPath(shape)


class Glass(QWidget):
    def __init__(self, theme, radius=None):
        super().__init__()
        self.theme, self.radius = theme, radius

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        paint_glass(p, self.theme, self.rect(), self.radius)


class Card(QWidget):
    """Título suelto (con un icono opcional) y debajo la placa de cristal con el contenido (`self.inner`)."""

    HEAD = 34

    def __init__(self, theme, title="", glyph=None):
        super().__init__()
        self.theme = theme
        self.glyph = glyph
        head = QWidget()
        head.setFixedHeight(self.HEAD)
        self.header = QHBoxLayout(head)
        self.header.setContentsMargins(4 + (26 if glyph else 0), 0, 2, 2)
        self.title = QLabel(title)
        self.title.setObjectName("CardTitle")
        self.header.addWidget(self.title)
        self.header.addStretch(1)
        self.inner = Glass(theme)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        layout.addWidget(head)
        layout.addWidget(self.inner, 1)

    def paintEvent(self, _):
        if self.glyph:
            p = QPainter(self)
            p.setRenderHint(QPainter.Antialiasing)
            p.setPen(glyphs.pen(QColor(self.theme.ink), 1.6))
            self.glyph(p, QRectF(4, (self.HEAD - 22) / 2, 20, 20))


class BarChart(QWidget):
    """Barras redondeadas de 0 a 100 (las más recientes a la derecha). La última va resaltada."""

    GAP = 10
    SHOW = 14

    def __init__(self, theme, unit="%", every_s=2, show=SHOW, gap=GAP, labels=True):
        super().__init__()
        self.theme, self.unit, self.every_s = theme, unit, every_s
        self.SHOW, self.GAP, self.labels = show, gap, labels
        self.values = []
        self.label = ""
        self._hover = -1
        self.setMouseTracking(True)
        self.setMinimumHeight(40)

    def set_values(self, values, label):
        self.values, self.label = list(values)[-self.SHOW:], label
        self.update()

    def _bars(self):
        n = max(len(self.values), 1)
        w = (self.width() - self.GAP * (self.SHOW - 1)) / self.SHOW
        start = self.width() - n * w - (n - 1) * self.GAP  # pegadas a la derecha: la más nueva al final
        return [QRectF(start + i * (w + self.GAP), 0, w, self.height()) for i in range(len(self.values))]

    def mouseMoveEvent(self, event):
        hit = next((i for i, r in enumerate(self._bars()) if r.contains(event.position())), -1)
        if hit != self._hover:
            self._hover = hit
            self.update()

    def leaveEvent(self, _):
        self._hover = -1
        self.update()

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        bars = self._bars()
        last = len(bars) - 1
        for i, (track, value) in enumerate(zip(bars, self.values)):
            radius = min(track.width() / 2.6, 14)
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(0, 0, 0, 70))  # el carril, hundido en el cristal
            p.drawRoundedRect(track, radius, radius)
            fill_h = max(track.height() * min(value, 100) / 100, 2 * radius)
            fill = QRectF(track.left(), track.bottom() - fill_h, track.width(), fill_h)
            lit = i == last or i == self._hover
            p.setBrush(QColor("#d6d6d6" if lit else t.bar_chart))
            p.drawRoundedRect(fill, radius, radius)
            if not self.labels:
                continue
            p.setPen(QColor(t.frame if lit else t.ink))
            p.setFont(font(t, t.font_px + 1, bold=True))
            p.drawText(QRectF(track.left(), track.bottom() - 30, track.width(), 26), Qt.AlignCenter, f"{value}{self.unit}")
        if 0 <= self._hover < len(bars):
            self._tip(p, bars[self._hover], self.values[self._hover], last - self._hover)

    def _tip(self, p, bar, value, age):
        """La tarjetita de la referencia ("Wednesday · Total Sales"): hace cuánto y el valor."""
        t = self.theme
        w, h = 150, 58
        x = min(max(bar.center().x() - w / 2, 0), self.width() - w)
        box = QRectF(x, 6, w, h)
        p.setPen(QPen(QColor(t.glass_hi), 1))
        p.setBrush(QColor(t.glass_top))
        p.drawRoundedRect(box, 10, 10)
        p.setPen(QColor(t.ink))
        p.setFont(font(t, t.font_px, bold=True))
        p.drawText(box.adjusted(12, 6, -12, -h / 2), Qt.AlignVCenter | Qt.AlignLeft,
                   "Ahora" if age == 0 else f"Hace {age * self.every_s} s")
        p.setFont(font(t, t.font_px))
        p.setPen(QColor(t.dim))
        p.drawText(box.adjusted(12, h / 2 - 2, -12, -6), Qt.AlignVCenter | Qt.AlignLeft, self.label)
        p.setPen(QColor(t.ink))
        p.drawText(box.adjusted(12, h / 2 - 2, -12, -6), Qt.AlignVCenter | Qt.AlignRight, f"{value}{self.unit}")


class Pills(QWidget):
    """Opciones en píldoras; la elegida resaltada. Avisa con `chosen(clave)`."""

    chosen = Signal(str)

    def __init__(self, options):
        """`options`: [(clave, texto)]."""
        super().__init__()
        row = QHBoxLayout(self)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(4)
        self.buttons = {}
        for key, text in options:
            b = QPushButton(text)
            b.setObjectName("Pill")
            b.setCheckable(True)
            b.setCursor(Qt.PointingHandCursor)
            b.clicked.connect(lambda _=False, k=key: self.choose(k))
            row.addWidget(b)
            self.buttons[key] = b
        self.choose(options[0][0], silent=True)

    def choose(self, key, silent=False):
        for k, b in self.buttons.items():
            b.setChecked(k == key)
        if not silent:
            self.chosen.emit(key)

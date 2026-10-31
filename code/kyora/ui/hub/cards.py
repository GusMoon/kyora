"""Piezas de superficie de Kyora, con la rúbrica de DISEÑO.md (skeumorfismo oscuro inspirado en Linux).

- paint_glass (el nombre es de antes): la placa elevada, opaca, con degradado suave (más clara arriba), filete de luz
  de 1 px arriba, línea oscura alrededor y una sombra corta debajo. `hi`: la elegida, más clara.
- paint_well: el hueco hundido (campos, carriles): más oscuro, sombra interior arriba y filete claro abajo.
- paint_flat / paint_flat_well: la excepción plana (tipo GNOME) de las tareas y las notas.
- Glass: un widget que es solo una placa (para meter contenido dentro).
- Card: un título suelto encima y debajo la placa, en `self.inner`.
- BarChart: barras redondeadas con la actual más clara; al pasar el ratón, una tarjetita con el valor.
- Pills: selector de dos o más opciones en forma de píldora.
"""
from PySide6.QtCore import QRectF, Qt, Signal
from PySide6.QtGui import QBrush, QColor, QLinearGradient, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget

from kyora.ui import glyphs
from kyora.ui.bar import font


def paint_glass(p, theme, rect, radius=None, hi=False, fill=None, shadow=True):
    """Placa elevada en `rect` (ver DISEÑO.md). `hi`: elegida (más clara). `fill`: un color liso (con el mismo
    relieve). `shadow`: la sombra corta de debajo."""
    t = theme
    radius = t.card_radius if radius is None else radius
    box = QRectF(rect).adjusted(1, 0.5, -1, -2.5 if shadow else -0.5)
    shape = QPainterPath()
    shape.addRoundedRect(box, radius, radius)
    p.save()
    if shadow:
        p.setPen(Qt.NoPen)
        for grow, alpha in ((2.0, 45), (1.0, 70)):  # la sombra corta, pegada debajo
            p.setBrush(QColor(0, 0, 0, alpha))
            p.drawRoundedRect(box.adjusted(-grow / 2, grow, grow / 2, grow), radius + grow / 2, radius + grow / 2)
    if fill is not None:
        top = QColor(fill)
        grad = QLinearGradient(box.topLeft(), box.bottomLeft())
        grad.setColorAt(0, top.lighter(106))
        grad.setColorAt(1, top.darker(108))
    else:
        grad = QLinearGradient(box.topLeft(), box.bottomLeft())
        grad.setColorAt(0, QColor(t.plate_pick if hi else t.plate_top))
        grad.setColorAt(1, QColor(t.plate_top if hi else t.plate_bottom))
    p.fillPath(shape, grad)
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(QColor(0, 0, 0, 170), 1))  # la línea oscura de fuera
    p.drawPath(shape)
    light = QLinearGradient(box.topLeft(), box.bottomLeft())  # el filete de luz: solo arriba
    light.setColorAt(0, QColor(t.plate_hi))
    light.setColorAt(min(12 / max(box.height(), 1), 1), QColor(0, 0, 0, 0))
    inner = QPainterPath()
    inner.addRoundedRect(box.adjusted(1, 1, -1, -1), max(radius - 1, 0), max(radius - 1, 0))
    p.setPen(QPen(QBrush(light), 1))
    p.drawPath(inner)
    p.restore()


def paint_well(p, theme, rect, radius=8):
    """Hueco hundido en `rect`: fondo más oscuro, sombra interior arriba y un filete claro abajo."""
    t = theme
    box = QRectF(rect).adjusted(0.5, 0.5, -0.5, -0.5)
    shape = QPainterPath()
    shape.addRoundedRect(box, radius, radius)
    p.save()
    grad = QLinearGradient(box.topLeft(), box.bottomLeft())
    grad.setColorAt(0, QColor(t.frame_dark))
    grad.setColorAt(1, QColor(t.frame))
    p.fillPath(shape, grad)
    p.setClipPath(shape)
    p.setPen(QPen(QColor(0, 0, 0, 140), 2))
    p.drawLine(box.topLeft(), box.topRight())  # la sombra interior de arriba
    p.setClipping(False)
    p.setBrush(Qt.NoBrush)
    edge = QLinearGradient(box.topLeft(), box.bottomLeft())
    edge.setColorAt(0, QColor(0, 0, 0, 160))
    edge.setColorAt(1, QColor(255, 255, 255, 28))
    p.setPen(QPen(QBrush(edge), 1))
    p.drawPath(shape)
    p.restore()


FLAT_EDGE = QColor(255, 255, 255, 20)  # el borde fino de las superficies planas


def paint_flat(p, theme, rect, radius=12, hi=False, fill=None):
    """Superficie plana (tareas y notas, por ahora; ver DISEÑO.md): relleno liso, esquinas redondeadas y un borde
    de 1 px. Sin degradado, filete ni sombra. `hi`: la elegida, algo más clara. `fill`: otro color liso."""
    t = theme
    box = QRectF(rect).adjusted(0.5, 0.5, -0.5, -0.5)
    p.save()
    p.setPen(QPen(FLAT_EDGE, 1))
    p.setBrush(QColor(fill) if fill is not None else QColor(t.plate_pick if hi else t.plate_top))
    p.drawRoundedRect(box, radius, radius)
    p.restore()


def paint_flat_well(p, theme, rect, radius=12):
    """Fondo plano más oscuro (columnas del Kanban, la píldora de la fecha), con el mismo borde fino."""
    paint_flat(p, theme, rect, radius, fill=theme.frame_dark)


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

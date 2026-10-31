"""La tarjeta de lo que suena, en el panel de la esquina de abajo a la derecha (el diseño de la referencia de Gustavo).

El contenedor es plano, con las esquinas de la tarjeta de información de arriba y un degradado con los colores del fondo de
pantalla (oscurecidos para que el texto se lea). Dentro hay dos partes:
- una **pantalla** hundida (`paint_well`) con las ondas, la línea de reproducción (en el acento, con un punto en cada
  extremo), el tiempo en grande y, debajo, el nombre del audio (si no cabe, se desliza) con la carátula como un avatar
  redondo al lado;
- abajo, una **fila de botones** redondos con el relieve de los de wifi, Bluetooth y ajustes: anterior, detener, pausa o
  seguir (el grande, con un puntito del acento) y siguiente.

La carátula es la miniatura de YouTube del vídeo (se baja sin bloquear nada y se guarda en memoria). Las ondas son de
verdad: cada barra es un trozo de la canción y su alto, lo fuerte que sonó ahí (se mide con el audio que sale del
reproductor de Kyora). Lo que ya sonó son barras claras; lo que falta, puntitos. La pieza no es un widget: la pinta
`QuickMain` (todo el panel se pinta a mano) y le pregunta dónde están los botones con `hits()`.
"""
import math
from collections import OrderedDict

from PySide6.QtCore import QObject, QPointF, QRectF, Qt, QUrl, Signal
from PySide6.QtGui import (
    QColor,
    QFontMetrics,
    QImage,
    QLinearGradient,
    QPainterPath,
    QPen,
)
from PySide6.QtNetwork import QNetworkAccessManager, QNetworkReply, QNetworkRequest

from kyora.ui import glyphs
from kyora.ui.bar import accent
from kyora.ui.bar import font as base_font
from kyora.ui.hub.cards import paint_glass, paint_well

WIDTH = 380  # el ancho del contenido del panel
PILL_H = 288
RADIUS = 14  # el mismo de la tarjeta de información
SIDE = 12  # el aire de la pantalla con el borde de la tarjeta
SCREEN_H = 176
SCREEN_R = 18
INNER = 14  # el aire dentro de la pantalla
WAVE_H = 64
HEAD_OVER = 8  # lo que la línea de reproducción sobresale de las ondas, arriba y abajo
TIME_PX = 36
TITLE_PX = 15
AVATAR = 24
AVATAR_GAP = 8
BTN = 52  # los botones redondos
BIG = 76  # el de pausa
BTN_GAP = 14
BARS = 60  # barras de la canción entera
BAR_GAP = 2.4
DOT_H = 3.0
MIN_BAR = 5.0
STEP_PX = 1
GAP = 36  # el hueco entre el final del nombre y su repetición al deslizar
FADE_W = 18
DARKEN = 230  # cuánto se oscurecen los colores del fondo de pantalla para el degradado (100 = nada, 200 = la mitad)
LEVEL_FLOOR = 0.08  # por debajo de esto no se estira la escala: el silencio no se ve como ruido
COVER_URL = "https://i.ytimg.com/vi/{id}/mqdefault.jpg"
COVER_CACHE = 12  # carátulas en memoria como mucho
COVER_PX = 160  # se guardan al doble de lo que se ven (pantallas con escala)


def title_width():
    """Lo que mide el hueco del nombre (el resto de la fila es el avatar)."""
    return WIDTH - 2 * (SIDE + INNER) - AVATAR - AVATAR_GAP


def clock(ms):
    seconds = max(int(ms), 0) // 1000
    return f"{seconds // 60:02d}:{seconds % 60:02d}"


class Covers(QObject):
    """Las carátulas: se piden a YouTube de una en una, sin bloquear, y se guardan las últimas ya recortadas a cuadrado."""

    ready = Signal(str, QImage)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._net = None  # el gestor de red se crea la primera vez que hace falta
        self._cache = OrderedDict()
        self._asked = set()

    def get(self, video_id):
        """La carátula si ya está (y entonces no pide nada); si no, None y se pide: llegará por `ready`."""
        if not video_id:
            return None
        if video_id in self._cache:
            self._cache.move_to_end(video_id)
            return self._cache[video_id]
        if video_id not in self._asked:
            self._asked.add(video_id)
            if self._net is None:
                self._net = QNetworkAccessManager(self)
            request = QNetworkRequest(QUrl(COVER_URL.format(id=video_id)))
            request.setAttribute(QNetworkRequest.RedirectPolicyAttribute, QNetworkRequest.NoLessSafeRedirectPolicy)
            reply = self._net.get(request)
            reply.finished.connect(lambda r=reply, v=video_id: self._done(r, v))
        return None

    def _done(self, reply, video_id):
        image = QImage()
        if reply.error() == QNetworkReply.NoError:
            image.loadFromData(reply.readAll())
        reply.deleteLater()
        self._asked.discard(video_id)
        if image.isNull():
            return
        side = min(image.width(), image.height())  # el centro, en cuadrado
        square = image.copy((image.width() - side) // 2, (image.height() - side) // 2, side, side)
        square = square.scaled(COVER_PX, COVER_PX, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
        self._cache[video_id] = square
        while len(self._cache) > COVER_CACHE:
            self._cache.popitem(last=False)
        self.ready.emit(video_id, square)


class Wave:
    """El nivel medio de cada trozo de la canción que ya sonó."""

    def __init__(self):
        self.reset()

    def reset(self):
        self.total = [0.0] * BARS
        self.count = [0] * BARS
        self.pos = self.dur = 0

    def moved(self, pos, dur):
        self.pos, self.dur = pos, dur

    def add(self, level):
        """El nivel (0 a 1) del audio que suena ahora: se suma a su trozo."""
        if self.dur > 0:
            i = self.index()
            self.total[i] += level
            self.count[i] += 1

    def index(self):
        """El trozo de la canción en el que está la reproducción."""
        return min(int(self.pos / self.dur * BARS), BARS - 1) if self.dur > 0 else 0

    def level(self, i):
        return self.total[i] / self.count[i] if self.count[i] else None

    def reference(self):
        """Con qué nivel se llena el alto: el más fuerte de los que ya sonaron (sin estirar el silencio)."""
        return max([LEVEL_FLOOR, *(v for v in map(self.level, range(BARS)) if v is not None)])


class MusicPill:
    def __init__(self, theme):
        self.theme = theme
        self.title, self.track_id, self.playing = "", "", False
        self.has_next = False  # hay otra canción después de esta
        self.cover = None  # QPixmap cuadrado, o None mientras llega (o si no hay)
        self.wave = Wave()
        self.offset = 0  # lo que se ha deslizado el nombre
        self._rects = {}

    # ---------- estado ----------

    def set_state(self, title, playing, track_id="", has_next=False):
        """Devuelve True si cambió la canción (las ondas y la carátula empiezan de cero)."""
        changed = (title, track_id) != (self.title, self.track_id)
        if changed:
            self.title, self.track_id, self.offset, self.cover = title, track_id, 0, None
            self.wave.reset()
        self.playing, self.has_next = playing, has_next
        return changed

    def overflows(self):
        return QFontMetrics(self._font(TITLE_PX)).horizontalAdvance(self.title) > title_width()

    def scrolling(self):
        """True si el nombre tiene que deslizarse ahora (no cabe y suena)."""
        return self.playing and self.overflows()

    def step(self):
        cycle = QFontMetrics(self._font(TITLE_PX)).horizontalAdvance(self.title) + GAP
        self.offset = (self.offset + STEP_PX) % cycle

    def _font(self, px, bold=False):
        f = base_font(self.theme, bold=bold)
        f.setPixelSize(px)
        return f

    # ---------- dónde están las cosas ----------

    def layout(self, box):
        """Las zonas de la tarjeta dentro de `box`: la pantalla (ondas, tiempo, nombre y avatar) y la fila de botones."""
        screen = QRectF(box.left() + SIDE, box.top() + SIDE, box.width() - 2 * SIDE, SCREEN_H)
        inner = screen.adjusted(INNER, INNER, -INNER, -INNER)
        wave = QRectF(inner.left(), inner.top() + HEAD_OVER, inner.width(), WAVE_H)
        time = QRectF(inner.left(), wave.bottom() + HEAD_OVER + 2, inner.width(), 40)
        text_w = min(QFontMetrics(self._font(TITLE_PX)).horizontalAdvance(self.title), title_width())
        row_w = text_w + AVATAR_GAP + AVATAR
        x = inner.center().x() - row_w / 2
        top = time.bottom() + 2
        title = QRectF(x, top, text_w, AVATAR)
        avatar = QRectF(title.right() + AVATAR_GAP, top, AVATAR, AVATAR)
        row_y = (screen.bottom() + box.bottom()) / 2 + 2  # el centro de la fila de botones
        sizes = [("prev", BTN), ("stop", BTN), ("toggle", BIG), ("next", BTN)]
        x = box.center().x() - (sum(size for _, size in sizes) + BTN_GAP * (len(sizes) - 1)) / 2
        self._rects = {"screen": screen, "wave": wave, "time": time, "title": title, "avatar": avatar}
        for name, size in sizes:
            self._rects[name] = QRectF(x, row_y - size / 2, size, size)
            x += size + BTN_GAP
        return self._rects

    def hits(self, box):
        """[(nombre, rect)] de lo que se pulsa (el de siguiente no cuenta si no hay otra canción)."""
        rects = self.layout(box)
        names = ["prev", "stop", "toggle"] + (["next"] if self.has_next else [])
        return [(f"music_{name}", rects[name]) for name in names]

    # ---------- colores: todos salen del fondo de pantalla ----------

    def _stops(self):
        """Los colores del degradado, de izquierda a derecha: el acento y el segundo y tercer color del fondo, oscurecidos."""
        t = self.theme
        return [QColor(c).darker(DARKEN) for c in (t.gold, t.second, t.third)]

    # ---------- pintura ----------

    def paint(self, p, box, hover=None):
        t = self.theme
        rects = self.layout(box)
        self._paint_back(p, box)
        paint_well(p, t, rects["screen"], SCREEN_R)
        self._paint_wave(p, rects["wave"])
        p.setFont(self._font(TIME_PX, True))
        p.setPen(QColor(t.ink))
        p.drawText(rects["time"], Qt.AlignCenter, clock(self.wave.pos))
        self._paint_title(p, rects["title"])
        self._paint_avatar(p, rects["avatar"])
        shapes = {"prev": "prev", "stop": "stop", "toggle": "pause" if self.playing else "play", "next": "next"}
        for name, shape in shapes.items():
            big = name == "toggle"
            self._paint_button(p, rects[name], shape, hover == f"music_{name}", enabled=name != "next" or self.has_next,
                               lift=6 if big else 0)
        self._paint_dot(p, rects["toggle"])

    def _paint_back(self, p, box):
        """Plano: un degradado horizontal con los colores del fondo, sin borde, sombra ni relieve."""
        fill = QLinearGradient(box.left(), 0, box.right(), 0)
        stops = self._stops()
        for i, color in enumerate(stops):
            fill.setColorAt(i / (len(stops) - 1), color)
        shape = QPainterPath()
        shape.addRoundedRect(box, RADIUS, RADIUS)
        p.fillPath(shape, fill)

    def _paint_avatar(self, p, rect):
        """La carátula como un avatar redondo con un aro fino; sin imagen, un círculo oscuro con una nota musical."""
        t = self.theme
        shape = QPainterPath()
        shape.addEllipse(rect)
        p.save()
        p.setClipPath(shape)
        p.setRenderHint(p.RenderHint.SmoothPixmapTransform)
        if self.cover is not None:
            p.drawPixmap(rect, self.cover, QRectF(self.cover.rect()))
        else:
            p.fillPath(shape, QColor(t.plate_top))
            p.setPen(glyphs.pen(accent(t, False), 1.4))
            p.setBrush(Qt.NoBrush)
            size = rect.width() * 0.56
            glyphs.music(p, QRectF(rect.center().x() - size / 2, rect.center().y() - size / 2, size, size))
        p.restore()
        p.setBrush(Qt.NoBrush)
        p.setPen(QPen(QColor(255, 255, 255, 60), 1))
        p.drawEllipse(rect.adjusted(0.5, 0.5, -0.5, -0.5))

    def _paint_button(self, p, rect, shape, hover, enabled=True, lift=0):
        """Un botón redondo con el relieve de los de wifi, Bluetooth y ajustes: placa elevada y el icono grabado (una sombra
        fina debajo), en el acento; más claro bajo el cursor. Sin acción (siguiente en la última canción): apagado."""
        t = self.theme
        hover = hover and enabled
        p.save()
        if not enabled:
            p.setOpacity(0.4)
        paint_glass(p, t, rect, rect.width() / 2, hi=hover)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(0, 0, 0, 150))
        self._glyph(p, shape, rect.translated(0, 0.5 - lift))
        p.setBrush(QColor(t.ink) if hover else accent(t, False))
        self._glyph(p, shape, rect.translated(0, -1 - lift))
        p.restore()

    def _paint_dot(self, p, rect):
        """El puntito bajo el icono de pausa: del acento si suena, apagado si está en pausa."""
        p.save()
        p.setPen(Qt.NoPen)
        color = QColor(accent(self.theme, True)) if self.playing else QColor(self.theme.dim)
        if not self.playing:
            color.setAlpha(110)
        p.setBrush(color)
        c = rect.center()
        p.drawEllipse(QPointF(c.x(), c.y() + rect.height() * 0.30), 3.2, 3.2)
        p.restore()

    @staticmethod
    def _glyph(p, shape, rect):
        """Anterior, siguiente, pausa (dos barras), seguir (triángulo) o detener (cuadrado), rellenos, centrados en `rect`."""
        c = rect.center()
        p.save()
        p.translate(c)
        scale = min(rect.width(), 60) / 46  # los dibujos se pensaron para un botón de 46; el grande no los estira tanto
        p.scale(scale, scale)
        if shape == "pause":
            for dx in (-6.5, 1.5):
                p.drawRoundedRect(QRectF(dx, -8, 5, 16), 1.8, 1.8)
        elif shape == "play":
            tri = QPainterPath()
            tri.moveTo(-5, -9)
            tri.lineTo(8, 0)
            tri.lineTo(-5, 9)
            tri.closeSubpath()
            p.drawPath(tri)
        elif shape in ("prev", "next"):
            sign = -1 if shape == "prev" else 1  # el triángulo mira hacia donde va y la barra queda en ese lado
            tri = QPainterPath()
            tri.moveTo(sign * 4, 0)
            tri.lineTo(sign * -8, -8.5)
            tri.lineTo(sign * -8, 8.5)
            tri.closeSubpath()
            p.drawPath(tri)
            p.drawRoundedRect(QRectF(5.5 if sign > 0 else -8.5, -8.5, 3, 17), 1.2, 1.2)
        else:
            p.drawRoundedRect(QRectF(-5.5, -5.5, 11, 11), 2.5, 2.5)
        p.restore()

    def _paint_title(self, p, area):
        t = self.theme
        p.save()
        p.setClipRect(area)
        p.setFont(self._font(TITLE_PX))
        p.setPen(QColor(t.dim))
        metrics = p.fontMetrics()
        if self.overflows():
            cycle = metrics.horizontalAdvance(self.title) + GAP
            for k in (0, 1):
                p.drawText(QRectF(area.left() - self.offset + k * cycle, area.top(), cycle, area.height()),
                           Qt.AlignVCenter | Qt.AlignLeft, self.title)
        else:
            p.drawText(area, Qt.AlignVCenter | Qt.AlignLeft, self.title)
        p.restore()
        if self.overflows():  # los extremos se funden con la pantalla para que el nombre no se corte en seco
            for left in (True, False):
                x = area.left() if left else area.right() - FADE_W
                self._fade(p, x, area, left)

    def _fade(self, p, x, area, left):
        edge = QColor(self.theme.frame)
        clear = QColor(edge)
        clear.setAlpha(0)
        fade = QLinearGradient(x, 0, x + FADE_W, 0)
        fade.setColorAt(0, edge if left else clear)
        fade.setColorAt(1, clear if left else edge)
        p.fillRect(QRectF(x, area.top(), FADE_W, area.height()), fade)

    def _paint_wave(self, p, area):
        """Las ondas de la canción: barras claras hasta la línea de reproducción (con su alto real) y puntitos después; la
        línea, en el acento, con un punto arriba y otro abajo."""
        t = self.theme
        wave = self.wave
        bar_w = (area.width() - (BARS - 1) * BAR_GAP) / BARS
        progress = min(max(wave.pos / wave.dur, 0.0), 1.0) if wave.dur > 0 else 0.0
        head = area.left() + progress * area.width()
        ref = wave.reference()
        mid = area.center().y()
        p.setPen(Qt.NoPen)
        for i in range(BARS):
            x = area.left() + i * (bar_w + BAR_GAP)
            if x + bar_w / 2 > head or wave.dur <= 0:
                color, height = QColor(t.ink), DOT_H
                color.setAlpha(90)
            else:
                level = wave.level(i)
                height = MIN_BAR + (area.height() - MIN_BAR) * math.sqrt(min((level or 0.0) / ref, 1.0))
                color = QColor(t.ink)
                color.setAlpha(235)
            p.setBrush(color)
            p.drawRoundedRect(QRectF(x, mid - height / 2, bar_w, height), bar_w / 2, bar_w / 2)
        line = QColor(accent(t, True))
        top, bottom = area.top() - HEAD_OVER, area.bottom() + HEAD_OVER
        p.setBrush(line)
        p.drawRoundedRect(QRectF(head - 1.25, top, 2.5, bottom - top), 1.25, 1.25)
        for y in (top, bottom):
            p.drawEllipse(QPointF(head, y), 4.0, 4.0)

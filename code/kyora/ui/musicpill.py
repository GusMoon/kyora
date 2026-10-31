"""La tarjeta de lo que suena, en el panel de la esquina de abajo a la derecha (el diseño de la referencia de Gustavo: un
reproductor de bolsillo, oscuro, con una pantallita y tres teclas).

- El **cuerpo** es una placa oscura de esquinas muy redondas (`paint_glass`).
- La **pantalla** es un hueco hundido (`paint_well`) con la carátula del vídeo vuelta pixeles, rayas de monitor antiguo y
  motas, teñida con los colores del fondo de pantalla; sin carátula, solo esa luz de colores. Encima van el nombre (arriba,
  si no cabe se desliza), el tiempo y las ondas de la canción (abajo) con la línea de reproducción en el acento.
- Debajo, **tres teclas** en relieve con el icono dibujado a línea: pausa o seguir, anterior y siguiente.
- Al pasar el cursor por la tarjeta sale una **✕** arriba a la derecha de la pantalla: detiene la música y cierra la tarjeta.

La carátula es la miniatura de YouTube del vídeo (se baja sin bloquear nada y se guarda en memoria). Las ondas son de
verdad: cada barra es un trozo de la canción y su alto, lo fuerte que sonó ahí (se mide con el audio que sale del
reproductor de Kyora). Lo que ya sonó son barras claras; lo que falta, puntitos. La pieza no es un widget: la pinta
`QuickMain` (todo el panel se pinta a mano) y le pregunta dónde están los botones con `hits()`.
"""
import math
import random
from collections import OrderedDict

from PySide6.QtCore import QObject, QPointF, QRectF, Qt, QUrl, Signal
from PySide6.QtGui import (
    QColor,
    QFontMetrics,
    QImage,
    QLinearGradient,
    QPainter,
    QPainterPath,
    QPen,
    QPixmap,
)
from PySide6.QtNetwork import QNetworkAccessManager, QNetworkReply, QNetworkRequest

from kyora.ui import glyphs
from kyora.ui.bar import accent
from kyora.ui.bar import font as base_font
from kyora.ui.hub.cards import paint_glass, paint_well

WIDTH = 380  # el ancho del contenido del panel
PILL_H = 288
RADIUS = 30  # las esquinas del cuerpo
SIDE = 14  # el aire de la pantalla con el borde de la tarjeta
SCREEN_H = 186
SCREEN_R = 20
BEZEL = 5  # el marco hundido de la pantalla
TEXT_PAD = 12  # el aire del texto con el borde de la pantalla
CLOSE = 24  # la ✕
CLOSE_ROOM = 8 + CLOSE + 8  # lo que se reserva a la derecha del nombre para la ✕
KEY_GAP = 10
KEY_GAP_TOP = 12  # entre la pantalla y las teclas
KEY_R = 16
WAVE_H = 30
HEAD_OVER = 7  # lo que la línea de reproducción sobresale de las ondas, arriba y abajo
TIME_PX = 24
TITLE_PX = 15
BARS = 60  # barras de la canción entera
BAR_GAP = 2.2
DOT_H = 3.0
MIN_BAR = 5.0
STEP_PX = 1
GAP = 36  # el hueco entre el final del nombre y su repetición al deslizar
FADE_W = 18
CELL = 3  # el tamaño de los "píxeles" de la carátula
LINE_STEP = 3  # una raya oscura de monitor cada tantos px
DOTS = 90  # motas de ruido
LEVEL_FLOOR = 0.08  # por debajo de esto no se estira la escala: el silencio no se ve como ruido
COVER_URL = "https://i.ytimg.com/vi/{id}/mqdefault.jpg"
COVER_CACHE = 12  # carátulas en memoria como mucho
COVER_PX = 160  # se guardan al doble de lo que se ven (pantallas con escala)
KEYS = ("toggle", "prev", "next")  # de izquierda a derecha


def title_width():
    """Lo que mide el hueco del nombre (el resto de la fila de arriba es para la ✕)."""
    return WIDTH - 2 * (SIDE + BEZEL + TEXT_PAD) - CLOSE_ROOM + TEXT_PAD


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
        self._baked = None  # (clave, QPixmap): la pantalla ya pintada, para no rehacerla con cada barra de las ondas

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
        return QFontMetrics(self._font(TITLE_PX, True)).horizontalAdvance(self.title) > title_width()

    def scrolling(self):
        """True si el nombre tiene que deslizarse ahora (no cabe y suena)."""
        return self.playing and self.overflows()

    def step(self):
        cycle = QFontMetrics(self._font(TITLE_PX, True)).horizontalAdvance(self.title) + GAP
        self.offset = (self.offset + STEP_PX) % cycle

    def _font(self, px, bold=False):
        f = base_font(self.theme, bold=bold)
        f.setPixelSize(px)
        return f

    # ---------- dónde están las cosas ----------

    def layout(self, box):
        """Las zonas de la tarjeta dentro de `box`: la pantalla (con su cristal, el nombre, la ✕, el tiempo y las ondas) y
        las tres teclas."""
        screen = QRectF(box.left() + SIDE, box.top() + SIDE, box.width() - 2 * SIDE, SCREEN_H)
        glass = screen.adjusted(BEZEL, BEZEL, -BEZEL, -BEZEL)
        left, right = glass.left() + TEXT_PAD, glass.right() - TEXT_PAD
        close = QRectF(glass.right() - 8 - CLOSE, glass.top() + 8, CLOSE, CLOSE)
        title = QRectF(left, glass.top() + 8, close.left() - 8 - left, CLOSE)
        wave = QRectF(left, glass.bottom() - 10 - HEAD_OVER - WAVE_H, right - left, WAVE_H)
        time = QRectF(left, wave.top() - HEAD_OVER - 4 - 30, 160, 30)
        self._rects = {"screen": screen, "glass": glass, "close": close, "title": title, "wave": wave, "time": time}
        key_w = (box.width() - 2 * SIDE - (len(KEYS) - 1) * KEY_GAP) / len(KEYS)
        top = screen.bottom() + KEY_GAP_TOP
        for i, name in enumerate(KEYS):
            self._rects[name] = QRectF(box.left() + SIDE + i * (key_w + KEY_GAP), top, key_w, box.bottom() - SIDE - top)
        return self._rects

    def hits(self, box):
        """[(nombre, rect)] de lo que se pulsa (el de siguiente no cuenta si no hay otra canción). La ✕ está siempre, pero
        solo se ve con el cursor sobre la tarjeta (para llegar a ella hay que pasar por encima)."""
        rects = self.layout(box)
        names = [n for n in KEYS if n != "next" or self.has_next] + ["close"]
        return [("music_stop" if n == "close" else f"music_{n}", rects[n]) for n in names]

    # ---------- colores: todos salen del fondo de pantalla ----------

    def _stops(self):
        """Los colores de la luz de la pantalla, de arriba abajo: el segundo, el acento y el tercer color del fondo."""
        t = self.theme
        return [QColor(c) for c in (t.second, t.gold, t.third)]

    # ---------- pintura ----------

    def paint(self, p, box, hover=None, over=False):
        """`hover`: el botón bajo el cursor; `over`: el cursor está sobre la tarjeta (sale la ✕)."""
        t = self.theme
        rects = self.layout(box)
        paint_glass(p, t, box, RADIUS, fill=QColor(t.plate_bottom), shadow=False)
        paint_well(p, t, rects["screen"], SCREEN_R)
        self._paint_screen(p, rects["glass"])
        self._paint_wave(p, rects["wave"])
        self._paint_text(p, rects["time"], clock(self.wave.pos), TIME_PX)
        self._paint_title(p, rects["title"])
        if over or hover == "music_stop":
            self._paint_close(p, rects["close"], hover == "music_stop")
        shapes = {"toggle": "pause" if self.playing else "play", "prev": "prev", "next": "next"}
        for name, shape in shapes.items():
            self._paint_key(p, rects[name], shape, hover == f"music_{name}", enabled=name != "next" or self.has_next,
                            lit=name == "toggle" and self.playing)

    # ---- la pantalla ----

    def _paint_screen(self, p, glass):
        """La carátula pixelada con sus rayas y motas, o solo la luz de colores. Se pinta una vez en un pixmap y se reusa."""
        dpr = p.device().devicePixelRatioF()
        t = self.theme
        key = (round(glass.width()), round(glass.height()), dpr, self.cover.cacheKey() if self.cover else 0,
               self.track_id, t.gold, t.second, t.third, t.ink)
        if self._baked is None or self._baked[0] != key:
            self._baked = (key, self._bake(glass.size(), dpr))
        p.drawPixmap(glass.topLeft(), self._baked[1])

    def _bake(self, size, dpr):
        t = self.theme
        w, h = size.width(), size.height()
        pix = QPixmap(round(w * dpr), round(h * dpr))
        pix.setDevicePixelRatio(dpr)
        pix.fill(Qt.transparent)
        q = QPainter(pix)
        q.setRenderHint(QPainter.Antialiasing)
        shape = QPainterPath()
        shape.addRoundedRect(QRectF(0, 0, w, h), SCREEN_R - BEZEL, SCREEN_R - BEZEL)
        q.setClipPath(shape)
        area = QRectF(0, 0, w, h)
        light = QLinearGradient(0, 0, 0, h)
        stops = self._stops()
        if self.cover is not None:
            self._draw_pixels(q, area)
            for i, color in enumerate(stops):  # la luz de colores sobre la imagen
                color.setAlpha(85)
                light.setColorAt(i / (len(stops) - 1), color)
            q.fillRect(area, light)
        else:
            for i, color in enumerate(stops):
                light.setColorAt(i / (len(stops) - 1), color.darker(150))
            q.fillRect(area, light)
            glow = QLinearGradient(0, h * 0.35, 0, h * 0.75)  # una franja de luz, como el horizonte de la referencia
            for pos, alpha in ((0, 0), (0.5, 70), (1, 0)):
                c = QColor(t.ink)
                c.setAlpha(alpha)
                glow.setColorAt(pos, c)
            q.fillRect(area, glow)
            q.setPen(glyphs.pen(QColor(t.ink), 1.6))
            q.setBrush(Qt.NoBrush)
            side = min(w, h) * 0.34
            glyphs.music(q, QRectF((w - side) / 2, (h - side) / 2 - 8, side, side))
        rnd = random.Random(self.track_id or "kyora")
        palette = [QColor(t.ink), QColor(t.gold), QColor(t.second), QColor(t.third)]
        q.setPen(Qt.NoPen)
        for _ in range(DOTS):  # motas de ruido
            c = QColor(rnd.choice(palette))
            c.setAlpha(rnd.randint(70, 150))
            side = rnd.choice((1, 2, 2, 3))
            q.fillRect(QRectF(int(rnd.uniform(0, w)), int(rnd.uniform(0, h)), side, side), c)
        for y in range(0, int(h), LINE_STEP):  # las rayas del monitor
            q.fillRect(QRectF(0, y, w, 1), QColor(0, 0, 0, 55))
        top = QLinearGradient(0, 0, 0, h * 0.35)  # el nombre y el tiempo se leen sobre sombra
        top.setColorAt(0, QColor(0, 0, 0, 140))
        top.setColorAt(1, QColor(0, 0, 0, 0))
        q.fillRect(area, top)
        bottom = QLinearGradient(0, h * 0.4, 0, h)
        bottom.setColorAt(0, QColor(0, 0, 0, 0))
        bottom.setColorAt(1, QColor(0, 0, 0, 215))
        q.fillRect(area, bottom)
        q.end()
        return pix

    def _draw_pixels(self, q, area):
        """La franja central de la carátula, hecha pixeles gordos (se reduce y se amplía sin suavizar)."""
        image = self.cover.toImage()
        w, h = area.width(), area.height()
        band = min(image.height(), max(round(image.width() * h / w), 1))
        image = image.copy(0, (image.height() - band) // 2, image.width(), band)
        small = image.scaled(max(int(w / CELL), 1), max(int(h / CELL), 1), Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
        q.save()
        q.setRenderHint(QPainter.SmoothPixmapTransform, False)
        q.drawImage(area, small)
        q.restore()

    # ---- texto ----

    def _paint_text(self, p, rect, text, px, flags=Qt.AlignVCenter | Qt.AlignLeft):
        """Texto claro con una sombra fina debajo, para que se lea sobre la imagen."""
        p.setFont(self._font(px, True))
        p.setPen(QColor(0, 0, 0, 170))
        p.drawText(rect.translated(0, 1), flags, text)
        p.setPen(QColor(self.theme.ink))
        p.drawText(rect, flags, text)

    def _paint_title(self, p, area):
        if not self.overflows():
            self._paint_text(p, area, self.title, TITLE_PX)
            return
        dpr = p.device().devicePixelRatioF()  # el nombre largo se pinta aparte para fundir sus extremos sin tocar la pantalla
        layer = QPixmap(round(area.width() * dpr), round(area.height() * dpr))
        layer.setDevicePixelRatio(dpr)
        layer.fill(Qt.transparent)
        q = QPainter(layer)
        q.setRenderHint(QPainter.TextAntialiasing)
        cycle = QFontMetrics(self._font(TITLE_PX, True)).horizontalAdvance(self.title) + GAP
        for k in (0, 1):
            self._paint_text(q, QRectF(-self.offset + k * cycle, 0, cycle, area.height()), self.title, TITLE_PX)
        q.setCompositionMode(QPainter.CompositionMode.CompositionMode_DestinationOut)
        for left in (True, False):
            x = 0 if left else area.width() - FADE_W
            fade = QLinearGradient(x, 0, x + FADE_W, 0)
            fade.setColorAt(0, QColor(0, 0, 0, 255 if left else 0))
            fade.setColorAt(1, QColor(0, 0, 0, 0 if left else 255))
            q.fillRect(QRectF(x, 0, FADE_W, area.height()), fade)
        q.end()
        p.drawPixmap(area.topLeft(), layer)

    # ---- ondas ----

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
        p.save()
        p.setPen(Qt.NoPen)
        for i in range(BARS):
            x = area.left() + i * (bar_w + BAR_GAP)
            if x + bar_w / 2 > head or wave.dur <= 0:
                color, height = QColor(t.ink), DOT_H
                color.setAlpha(110)
            else:
                level = wave.level(i)
                height = MIN_BAR + (area.height() - MIN_BAR) * math.sqrt(min((level or 0.0) / ref, 1.0))
                color = QColor(t.ink)
                color.setAlpha(240)
            p.setBrush(color)
            p.drawRoundedRect(QRectF(x, mid - height / 2, bar_w, height), bar_w / 2, bar_w / 2)
        line = QColor(accent(t, True))
        top, bottom = area.top() - HEAD_OVER, area.bottom() + HEAD_OVER
        p.setBrush(line)
        p.drawRoundedRect(QRectF(head - 1.25, top, 2.5, bottom - top), 1.25, 1.25)
        for y in (top, bottom):
            p.drawEllipse(QPointF(head, y), 4.0, 4.0)
        p.restore()

    # ---- la ✕ y las teclas ----

    def _paint_close(self, p, rect, hover):
        """Un círculo oscuro con una ✕ clara (en el acento si está bajo el cursor), arriba a la derecha de la pantalla."""
        p.save()
        p.setPen(QPen(QColor(255, 255, 255, 40), 1))
        p.setBrush(QColor(0, 0, 0, 215 if hover else 150))
        p.drawEllipse(rect.adjusted(0.5, 0.5, -0.5, -0.5))
        pen = QPen(accent(self.theme, True) if hover else QColor(self.theme.ink), 2)
        pen.setCapStyle(Qt.RoundCap)
        p.setPen(pen)
        c, d = rect.center(), rect.width() * 0.2
        p.drawLine(QPointF(c.x() - d, c.y() - d), QPointF(c.x() + d, c.y() + d))
        p.drawLine(QPointF(c.x() - d, c.y() + d), QPointF(c.x() + d, c.y() - d))
        p.restore()

    def _paint_key(self, p, rect, shape, hover, enabled=True, lit=False):
        """Una tecla en relieve con el icono a línea y una sombra fina debajo (grabado). El icono es claro; el acento si es
        el de pausa y suena; más claro bajo el cursor. Sin acción (siguiente en la última canción): apagada."""
        t = self.theme
        hover = hover and enabled
        p.save()
        if not enabled:
            p.setOpacity(0.4)
        paint_glass(p, t, rect, KEY_R, hi=hover)
        c = rect.center()
        spot = QRectF(c.x() - 15, c.y() - 15 - 1, 30, 30)
        p.setBrush(Qt.NoBrush)
        for dy, color in ((1.6, QColor(0, 0, 0, 150)),
                          (0, QColor(t.ink) if hover else accent(t, False) if lit else self._soft_ink())):
            pen = QPen(color, 2.2)
            pen.setCapStyle(Qt.RoundCap)
            pen.setJoinStyle(Qt.RoundJoin)
            p.setPen(pen)
            self._glyph(p, shape, spot.translated(0, dy))
        p.restore()

    def _soft_ink(self):
        color = QColor(self.theme.ink)
        color.setAlpha(205)
        return color

    @staticmethod
    def _glyph(p, shape, rect):
        """Seguir (triángulo), pausa (dos barras), anterior o siguiente (triángulo y barra), solo el contorno, centrados."""
        p.save()
        p.translate(rect.center())
        scale = rect.width() / 30
        p.scale(scale, scale)
        if shape == "pause":
            for dx in (-9, 3):
                p.drawRoundedRect(QRectF(dx, -9, 6, 18), 2, 2)
        elif shape == "play":
            tri = QPainterPath()
            tri.moveTo(-6, -10)
            tri.lineTo(10, 0)
            tri.lineTo(-6, 10)
            tri.closeSubpath()
            p.drawPath(tri)
        else:
            if shape == "prev":
                p.scale(-1, 1)  # el de anterior es el de siguiente al revés
            tri = QPainterPath()
            tri.moveTo(-9, -9)
            tri.lineTo(5, 0)
            tri.lineTo(-9, 9)
            tri.closeSubpath()
            p.drawPath(tri)
            p.drawLine(QPointF(10, -9), QPointF(10, 9))
        p.restore()

"""La tarjeta de lo que suena, en el panel de la esquina de abajo a la derecha (el diseño de la referencia de Gustavo: un
reproductor de bolsillo cuadrado, oscuro, con una pantallita).

- El **cuerpo** es una placa oscura, casi cuadrada y de esquinas muy redondas (`paint_glass`), con un grano fino.
- La **pantalla** no tiene marco aparte: es la carátula del vídeo vuelta pixeles, con rayas de monitor antiguo y motas,
  teñida con los colores del fondo de pantalla (sin carátula, solo esa luz de colores), y una **sombra interior** en sus
  bordes. Encima van el nombre (arriba, si no cabe se desliza), el tiempo y las ondas de la canción (abajo) con la línea de
  reproducción en el acento.
- Los botones solo salen **al pasar el cursor por la pantalla**: a cada lado, **‹** (anterior) y **›** (siguiente) y, en el
  medio, **tres botones**, todos planos y redondos, con el icono dibujado a línea: pausa o seguir, descargar la canción que suena y cerrar
  (detiene la música y cierra la tarjeta).

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
from kyora.ui.hub.cards import paint_glass

WIDTH = 380  # el ancho del contenido del panel
PILL_H = 340  # casi cuadrada, como el icono de la referencia; el panel la encoge si no cabe en la pantalla
MIN_H = 250  # menos que esto no cabrían el nombre, los botones, el tiempo y las ondas dentro de la pantalla
RADIUS = 44  # las esquinas del cuerpo
SIDE = 14  # el aire de la pantalla con el borde de la tarjeta
SCREEN_R = 26
SHADOW_W = 18  # lo que entra la sombra interior de la pantalla
TEXT_PAD = 14  # el aire del texto con el borde de la pantalla
ARROW = 44  # los botones (todos son círculos de este tamaño)
ARROW_PAD = 10
BTN_GAP = 12  # entre los tres botones del medio
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
DOTS = 110  # motas de ruido en la pantalla
GRAIN = 900  # granitos del cuerpo
LEVEL_FLOOR = 0.08  # por debajo de esto no se estira la escala: el silencio no se ve como ruido
COVER_URL = "https://i.ytimg.com/vi/{id}/mqdefault.jpg"
COVER_CACHE = 12  # carátulas en memoria como mucho
COVER_PX = 160  # se guardan al doble de lo que se ven (pantallas con escala)
KEYS = ("toggle", "download", "close")  # de izquierda a derecha
BUSY = ("queued", "doing")  # estados de la descarga de la canción que suena


def title_width():
    """Lo que mide el hueco del nombre (toda la fila de arriba de la pantalla)."""
    return WIDTH - 2 * (SIDE + TEXT_PAD)


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
        self.download = ""  # cómo va la descarga de la que suena: "", "pending", "queued", "doing", "done" o "error"
        self.cover = None  # QPixmap cuadrado, o None mientras llega (o si no hay)
        self.wave = Wave()
        self.offset = 0  # lo que se ha deslizado el nombre
        self._rects = {}
        self._baked = None  # (clave, QPixmap): la pantalla ya pintada, para no rehacerla con cada barra de las ondas
        self._grain = None  # (clave, QPixmap): el grano del cuerpo

    # ---------- estado ----------

    def set_state(self, title, playing, track_id="", has_next=False, download=""):
        """Devuelve True si cambió la canción (las ondas y la carátula empiezan de cero)."""
        changed = (title, track_id) != (self.title, self.track_id)
        if changed:
            self.title, self.track_id, self.offset, self.cover = title, track_id, 0, None
            self.wave.reset()
        self.playing, self.has_next, self.download = playing, has_next, download
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
        """Las zonas de la tarjeta dentro de `box`: la pantalla, que ocupa casi toda la tarjeta, con el nombre arriba, el
        tiempo y las ondas abajo y, en el hueco del medio, los tres botones entre los dos de los lados."""
        screen = QRectF(box.left() + SIDE, box.top() + SIDE, box.width() - 2 * SIDE, box.height() - 2 * SIDE)
        left, right = screen.left() + TEXT_PAD, screen.right() - TEXT_PAD
        title = QRectF(left, screen.top() + 10, right - left, 26)
        wave = QRectF(left, screen.bottom() - 12 - HEAD_OVER - WAVE_H, right - left, WAVE_H)
        time = QRectF(left, wave.top() - HEAD_OVER - 4 - 30, 160, 30)
        mid = (title.bottom() + time.top()) / 2  # el medio del hueco entre el nombre y el tiempo
        self._rects = {
            "screen": screen,
            "title": title,
            "wave": wave,
            "time": time,
            "prev": QRectF(screen.left() + ARROW_PAD, mid - ARROW / 2, ARROW, ARROW),
            "next": QRectF(screen.right() - ARROW_PAD - ARROW, mid - ARROW / 2, ARROW, ARROW),
        }
        row_w = len(KEYS) * ARROW + (len(KEYS) - 1) * BTN_GAP
        keys_left = screen.center().x() - row_w / 2
        for i, name in enumerate(KEYS):
            self._rects[name] = QRectF(keys_left + i * (ARROW + BTN_GAP), mid - ARROW / 2, ARROW, ARROW)
        return self._rects

    def hits(self, box):
        """[(nombre, rect)] de lo que se pulsa. Todos están sobre la pantalla y solo se ven con el cursor encima (el de
        siguiente no cuenta si no hay otra canción). «cerrar» es `music_stop`."""
        rects = self.layout(box)
        names = list(KEYS) + ["prev"] + (["next"] if self.has_next else [])
        return [("music_stop" if n == "close" else f"music_{n}", rects[n]) for n in names]

    # ---------- colores: todos salen del fondo de pantalla ----------

    def _stops(self):
        """Los colores de la luz de la pantalla, de arriba abajo: el segundo, el acento y el tercer color del fondo."""
        t = self.theme
        return [QColor(c) for c in (t.second, t.gold, t.third)]

    # ---------- pintura ----------

    def paint(self, p, box, hover=None, over=False):
        """`hover`: el botón bajo el cursor; `over`: el cursor está sobre la pantalla (salen los botones)."""
        t = self.theme
        rects = self.layout(box)
        paint_glass(p, t, box, RADIUS, fill=QColor(t.plate_bottom), shadow=False)
        self._paint_grain(p, box)
        self._paint_screen(p, rects["screen"])
        self._paint_wave(p, rects["wave"])
        self._paint_text(p, rects["time"], clock(self.wave.pos), TIME_PX)
        self._paint_title(p, rects["title"])
        if not over and not (hover or "").startswith("music_"):
            return  # los botones solo salen con el cursor sobre la pantalla
        shapes = {"toggle": "pause" if self.playing else "play", "download": self._download_shape(), "close": "close",
                  "prev": "prev", "next": "next"}
        for name, shape in shapes.items():
            if name == "next" and not self.has_next:
                continue
            self._paint_button(p, rects[name], shape, hover == ("music_stop" if name == "close" else f"music_{name}"),
                               self._key_color(name))

    def _download_shape(self):
        return "check" if self.download == "done" else "download"

    def _key_color(self, name):
        """El color del icono, o None para el normal: el acento en pausa si suena, y en descargar según cómo va."""
        t = self.theme
        if name == "toggle" and self.playing:
            return accent(t, False)
        if name == "download":
            if self.download in BUSY or self.download == "done":
                return accent(t, False)
            if self.download == "error":
                return QColor(t.warn)
        return None

    # ---- el cuerpo ----

    def _paint_grain(self, p, box):
        """Un grano fino sobre el cuerpo, como el de la referencia (se pinta una vez y se reusa)."""
        dpr = p.device().devicePixelRatioF()
        key = (round(box.width()), round(box.height()), dpr)
        if self._grain is None or self._grain[0] != key:
            pix = QPixmap(round(box.width() * dpr), round(box.height() * dpr))
            pix.setDevicePixelRatio(dpr)
            pix.fill(Qt.transparent)
            q = QPainter(pix)
            q.setRenderHint(QPainter.Antialiasing)
            shape = QPainterPath()
            shape.addRoundedRect(QRectF(1, 1, box.width() - 2, box.height() - 2), RADIUS - 1, RADIUS - 1)
            q.setClipPath(shape)
            rnd = random.Random(7)
            for _ in range(GRAIN):
                light = rnd.random() < 0.5
                c = QColor(255, 255, 255, rnd.randint(6, 16)) if light else QColor(0, 0, 0, rnd.randint(18, 40))
                q.fillRect(QRectF(int(rnd.uniform(0, box.width())), int(rnd.uniform(0, box.height())), 1, 1), c)
            q.end()
            self._grain = (key, pix)
        p.drawPixmap(box.topLeft(), self._grain[1])

    # ---- la pantalla ----

    def _paint_screen(self, p, screen):
        """La carátula pixelada con sus rayas, motas y sombra interior, o solo la luz de colores. Se pinta una vez en un
        pixmap y se reusa; alrededor, solo un filo oscuro fino (sin marco aparte) y un destello claro debajo."""
        dpr = p.device().devicePixelRatioF()
        t = self.theme
        key = (round(screen.width()), round(screen.height()), dpr, self.cover.cacheKey() if self.cover else 0,
               self.track_id, t.gold, t.second, t.third, t.ink)
        if self._baked is None or self._baked[0] != key:
            self._baked = (key, self._bake(screen.size(), dpr))
        p.save()
        p.setBrush(Qt.NoBrush)
        p.setPen(QPen(QColor(255, 255, 255, 26), 1))
        p.drawRoundedRect(screen.translated(0, 1.5), SCREEN_R, SCREEN_R)  # asoma solo el filo de abajo
        p.restore()
        p.drawPixmap(screen.topLeft(), self._baked[1])
        p.save()
        p.setBrush(Qt.NoBrush)
        p.setPen(QPen(QColor(0, 0, 0, 190), 1))
        p.drawRoundedRect(screen.adjusted(0.5, 0.5, -0.5, -0.5), SCREEN_R, SCREEN_R)
        p.restore()

    def _bake(self, size, dpr):
        t = self.theme
        w, h = size.width(), size.height()
        pix = QPixmap(round(w * dpr), round(h * dpr))
        pix.setDevicePixelRatio(dpr)
        pix.fill(Qt.transparent)
        q = QPainter(pix)
        q.setRenderHint(QPainter.Antialiasing)
        shape = QPainterPath()
        shape.addRoundedRect(QRectF(0, 0, w, h), SCREEN_R, SCREEN_R)
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
            side = min(w, h) * 0.3
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
        top = QLinearGradient(0, 0, 0, h * 0.3)  # el nombre y el tiempo se leen sobre sombra
        top.setColorAt(0, QColor(0, 0, 0, 130))
        top.setColorAt(1, QColor(0, 0, 0, 0))
        q.fillRect(area, top)
        bottom = QLinearGradient(0, h * 0.45, 0, h)
        bottom.setColorAt(0, QColor(0, 0, 0, 0))
        bottom.setColorAt(1, QColor(0, 0, 0, 215))
        q.fillRect(area, bottom)
        self._inner_shadow(q, area)
        q.end()
        return pix

    @staticmethod
    def _inner_shadow(q, area):
        """La sombra del marco por dentro: anillos que se aclaran hacia el centro, más fuertes arriba."""
        q.setBrush(Qt.NoBrush)
        for i in range(SHADOW_W):
            alpha = int(190 * (1 - i / SHADOW_W) ** 2)
            q.setPen(QPen(QColor(0, 0, 0, alpha), 1.4))
            q.drawRoundedRect(area.adjusted(i + 0.7, i + 0.7, -i - 0.7, -i - 0.7), max(SCREEN_R - i, 2), max(SCREEN_R - i, 2))
        down = QLinearGradient(0, 0, 0, SHADOW_W * 1.6)  # la luz viene de arriba: el borde de arriba, más oscuro
        down.setColorAt(0, QColor(0, 0, 0, 110))
        down.setColorAt(1, QColor(0, 0, 0, 0))
        q.fillRect(QRectF(area.left(), area.top(), area.width(), SHADOW_W * 1.6), down)

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

    # ---- los botones ----

    def _paint_button(self, p, rect, shape, hover, color=None):
        """Un botón plano y minimalista: un círculo oscuro con un filo fino y el icono a línea, claro (`color` si pide otro;
        el acento bajo el cursor). Sin relieve ni sombras. Lo usan los cinco: anterior, siguiente, pausa, descargar y cerrar."""
        t = self.theme
        p.save()
        p.setPen(QPen(QColor(255, 255, 255, 45), 1))
        p.setBrush(QColor(0, 0, 0, 200 if hover else 135))
        p.drawEllipse(rect.adjusted(0.5, 0.5, -0.5, -0.5))
        ink = accent(t, True) if hover else color if color is not None else QColor(t.ink)
        pen = QPen(ink, 2.4)
        pen.setCapStyle(Qt.RoundCap)
        pen.setJoinStyle(Qt.RoundJoin)
        p.setPen(pen)
        p.setBrush(Qt.NoBrush)
        self._glyph(p, shape, QRectF(rect.center().x() - 15, rect.center().y() - 15, 30, 30))
        p.restore()

    @staticmethod
    def _glyph(p, shape, rect):
        """Seguir (triángulo), pausa (dos barras), descargar (flecha sobre una bandeja), hecho (✓), cerrar (✕) o las flechas
        ‹ y ›: solo el contorno, centrados."""
        p.save()
        p.translate(rect.center())
        scale = rect.width() / 30
        p.scale(scale, scale)
        line = QPainterPath()
        if shape == "pause":
            for dx in (-9, 3):
                p.drawRoundedRect(QRectF(dx, -9, 6, 18), 2, 2)
        elif shape == "play":
            line.moveTo(-6, -10)
            line.lineTo(10, 0)
            line.lineTo(-6, 10)
            line.closeSubpath()
        elif shape == "download":
            line.moveTo(0, -11)
            line.lineTo(0, 4)
            line.moveTo(-6, -2)
            line.lineTo(0, 4)
            line.lineTo(6, -2)
            line.moveTo(-10, 3)
            line.lineTo(-10, 10)
            line.lineTo(10, 10)
            line.lineTo(10, 3)
        elif shape in ("prev", "next"):
            sign = -1 if shape == "prev" else 1  # la punta mira hacia donde va
            line.moveTo(-sign * 4, -9)
            line.lineTo(sign * 5, 0)
            line.lineTo(-sign * 4, 9)
        elif shape == "check":
            line.moveTo(-9, 1)
            line.lineTo(-3, 7)
            line.lineTo(9, -7)
        else:
            line.moveTo(-8, -8)
            line.lineTo(8, 8)
            line.moveTo(-8, 8)
            line.lineTo(8, -8)
        p.drawPath(line)
        p.restore()

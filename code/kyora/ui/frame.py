"""El contorno de las ventanas: cuatro ventanas finas por ventana transparentes que dejan pasar los clics (una por lado).

El borde lleva una línea fina del color del acento y se ilumina donde pasa el cursor: al acercarse a menos de `NEAR` px
del borde, la luz neón sube alrededor del cursor y lo sigue a lo largo del contorno; al alejarse se apaga. No hay luz
dando vueltas ni fotogramas con el cursor lejos: solo se repinta cuando el cursor está cerca o la luz aún se apaga.
Windows sube entera la parte de una ventana transparente que cambia: si viviera en la de pantalla completa, cada
fotograma movería casi toda la pantalla.
"""
import time

from PySide6.QtCore import QPointF, QRectF, Qt, QTimer
from PySide6.QtGui import (
    QColor,
    QConicalGradient,
    QCursor,
    QImage,
    QPainter,
    QPen,
    QRadialGradient,
)
from PySide6.QtWidgets import QWidget

from kyora.core.ring import RingMotion
from kyora.ui.win import make_tool_window

GLOW_STEPS = 5  # trazos del halo neón: del más ancho y tenue al más estrecho
CORE_TINT = 0.25  # cuánto acento lleva el núcleo casi blanco de la luz
FRAME_MS = 16  # ~60 fotogramas por segundo mientras el borde aparece (después, ninguno)
HOVER_MS = 30  # cada cuánto se mira dónde está el cursor
NEAR = 150  # px del borde a los que el cursor empieza a encender la luz
SPOT = 190  # radio de la mancha de luz alrededor del cursor
LINE_ALPHA = 0.75  # la línea fina del borde con el cursor lejos (sin halo)
EASE = 0.3  # cuánto se acerca la luz a su meta en cada vistazo (suaviza el encendido y el apagado)
START_ANGLE = 90  # la luz nace arriba (grados de Qt: 0 a las 3, en sentido antihorario)


def _tint(theme, amount):
    """El núcleo de la luz: casi blanco con un poco del acento."""
    core, accent = QColor(theme.focus_core), QColor(theme.focus_color)
    return QColor(*(round(a + (b - a) * amount) for a, b in zip(core.getRgb()[:3], accent.getRgb()[:3])))


def paint_ring(p, theme, rect, turn, length, opacity):
    """Luz neón del borde de la ventana activa: halo del color del acento que se difumina y un núcleo fino casi
    blanco. `turn` (0-1) es dónde va la cabeza del trazo y `length` (0-1) cuánto borde cubre; con 1, el borde
    entero y liso."""
    t = theme
    grow = t.focus_gap + t.focus_width / 2
    edge = QRectF(rect).adjusted(-grow, -grow, grow, grow)
    p.setOpacity(opacity)
    p.setBrush(Qt.NoBrush)
    # halo: trazos cada vez más estrechos; donde se suman todos (pegado al borde) brilla más, y hacia fuera se apaga
    per_step = 1 - (1 - t.focus_glow_alpha) ** (1 / GLOW_STEPS)
    for i in range(GLOW_STEPS):
        reach = t.focus_glow * ((GLOW_STEPS - i) / GLOW_STEPS) ** 1.6
        p.setPen(QPen(_light(edge, turn, length, per_step, QColor(t.focus_color)), t.focus_width + 2 * reach))
        p.drawRoundedRect(edge, t.focus_radius, t.focus_radius)
    # anillo del acento y núcleo claro encima, finos y nítidos
    p.setPen(QPen(_light(edge, turn, length, 0.85, QColor(t.focus_color)), t.focus_width + 2))
    p.drawRoundedRect(edge, t.focus_radius, t.focus_radius)
    p.setPen(QPen(_light(edge, turn, length, 1.0, _tint(t, CORE_TINT)), t.focus_width))
    p.drawRoundedRect(edge, t.focus_radius, t.focus_radius)


def paint_line(p, theme, rect):
    """Solo la línea fina del borde de la ventana activa, del color del acento y sin halo."""
    grow = theme.focus_gap + theme.focus_width / 2
    edge = QRectF(rect).adjusted(-grow, -grow, grow, grow)
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(QColor(theme.focus_color), theme.focus_width))
    p.drawRoundedRect(edge, theme.focus_radius, theme.focus_radius)


def _light(edge, turn, length, alpha, color):
    """Pincel de la luz: liso con el borde entero; si no, cónico, opaco en el tramo ya dibujado (detrás de la
    cabeza) con una punta corta que se difumina, y transparente en el resto."""
    head = QColor(color)
    head.setAlphaF(alpha)
    if length >= 0.999:
        return head
    clear = QColor(color)
    clear.setAlphaF(0.0)
    g = QConicalGradient(edge.center(), START_ANGLE - turn * 360)  # la cabeza avanza en sentido horario
    g.setColorAt(0.0, head)
    g.setColorAt(length * 0.85, head)
    g.setColorAt(length, clear)
    g.setColorAt(0.995, clear)
    g.setColorAt(1.0, head)
    return g


def _border_distance(rect, point):
    """Distancia de un punto al borde de un rectángulo (por dentro o por fuera)."""
    dx = max(rect.left() - point.x(), 0.0, point.x() - rect.right())
    dy = max(rect.top() - point.y(), 0.0, point.y() - rect.bottom())
    if dx or dy:
        return (dx * dx + dy * dy) ** 0.5
    return min(point.x() - rect.left(), rect.right() - point.x(), point.y() - rect.top(), rect.bottom() - point.y())


class RingStrip(QWidget):
    """Una de las cuatro ventanas finas del contorno: pinta solo el trozo del contorno que le cae dentro."""

    def __init__(self, ring):
        super().__init__()
        make_tool_window(self, click_through=True)
        self.setWindowTitle("KyoraRing")
        self.ring = ring
        self.local = QRectF()  # dónde está, en coordenadas de la pantalla (las del contorno)
        self._cache = {}  # tipo -> (clave, imagen): el trozo de borde ya pintado

    def _image(self, rect, kind):
        """El trozo de contorno de esta tira ya pintado, una sola vez: la línea sola ("line") o la luz entera con su
        halo ("glow", 7 trazos con degradado). En cada fotograma solo se compone, que cuesta muy poco."""
        theme, dpr = self.ring.theme, self.devicePixelRatioF()
        key = (kind, rect.x(), rect.y(), rect.width(), rect.height(), self.local.size().toTuple(), id(theme), dpr)
        if self._cache.get(kind, (None,))[0] != key:
            image = QImage((self.local.size() * dpr).toSize(), QImage.Format_ARGB32_Premultiplied)
            image.setDevicePixelRatio(dpr)
            image.fill(Qt.transparent)
            p = QPainter(image)
            p.setRenderHint(QPainter.Antialiasing)
            p.translate(-self.local.x(), -self.local.y())
            if kind == "line":
                paint_line(p, theme, rect)
            else:
                paint_ring(p, theme, rect, 0.0, 1.0, 1.0)
            p.end()
            self._cache[kind] = (key, image)
        return self._cache[kind][1]

    def paintEvent(self, _):
        if self.ring.current is None:
            return
        rect, opacity = self.ring.current
        p = QPainter(self)
        # la ventana con foco lleva siempre su línea fina; las demás solo se ven al acercarse el cursor
        p.setOpacity(opacity * LINE_ALPHA / 0.85 * (1.0 if self.ring.focused else self.ring.lit))
        p.drawImage(0, 0, self._image(rect, "line"))
        lit, cursor = self.ring.lit, self.ring.cursor
        if lit > 0.01 and cursor is not None:  # con el cursor cerca, una mancha de luz lo sigue por el borde
            glow = self._image(rect, "glow").copy()
            center = QPointF(cursor) - self.local.topLeft()
            spot = QRadialGradient(center, SPOT)
            for stop, amount in ((0.0, 1.0), (0.35, 0.55), (0.7, 0.15), (1.0, 0.0)):
                spot.setColorAt(stop, QColor(255, 255, 255, round(255 * lit * amount)))
            mask = QPainter(glow)
            mask.setCompositionMode(QPainter.CompositionMode_DestinationIn)
            mask.fillRect(QRectF(0, 0, self.local.width(), self.local.height()), spot)
            mask.end()
            p.setOpacity(min(1.0, opacity / 0.85))  # la luz encendida llega a su brillo pleno
            p.drawImage(0, 0, glow)


class Ring:
    """El contorno de una ventana repartido en cuatro tiras: arriba y abajo (con las esquinas) y los lados."""

    def __init__(self, theme, screen_map):
        self.theme = theme
        self.map = screen_map
        self.hwnd = None  # la ventana a la que rodea ahora
        self.focused = False  # la que tiene el foco lleva siempre su línea; las demás solo se ven con el cursor cerca
        self.strips = [RingStrip(self) for _ in range(4)]
        self.current = None  # (QRectF lógico, opacidad) del contorno en este fotograma
        self.lit = 0.0  # cuánto se ha encendido el borde (0-1) por la cercanía del cursor
        self.cursor = None  # dónde está el cursor, en coordenadas de la pantalla (las del contorno)
        self._drawn = None  # (lit, cursor) con lo que se pintó por última vez
        self._motion = RingMotion()
        self._placed = None  # rectángulo para el que están colocadas las tiras
        self._timer = QTimer()
        self._timer.setTimerType(Qt.PreciseTimer)  # el temporizador normal de Windows va a saltos de ~15 ms
        self._timer.setInterval(FRAME_MS)
        self._timer.timeout.connect(self._tick)
        self._hover = QTimer()
        self._hover.setInterval(HOVER_MS)
        self._hover.timeout.connect(self._look)

    def set_focus_target(self, target):
        """`target` = (hwnd, (izq, arriba, der, abajo) en px físicos) o None para ocultarlo."""
        hwnd, rect = target if target else (None, None)
        self._motion.retarget(hwnd, rect, time.monotonic())
        self._tick()
        if not self._timer.isActive():
            self._timer.start()

    def _tick(self):
        t = self.theme
        now = time.monotonic()
        frame = self._motion.frame(now, t.focus_rest, t.focus_fade_ms / 1000)
        if frame is None:
            self.current = None
            self._placed = None
            self.lit, self._drawn = 0.0, None
            for strip in self.strips:
                strip.hide()
            self._timer.stop()
            self._hover.stop()
            return
        (left, top, right, bottom), opacity = frame
        self.current = (self.map.rect_to_logical(left, top, right, bottom), opacity)
        if self.current[0] != self._placed:
            self._place(self.current[0])
        for strip in self.strips:
            strip.update()
        if not self._hover.isActive():
            self._hover.start()
        if self._motion.settled(now, t.focus_fade_ms / 1000):
            self._timer.stop()  # dibujada y quieta: no hacen falta más fotogramas hasta que algo cambie

    def _look(self):
        """Mira dónde está el cursor: cerca del borde enciende la luz a su alrededor; lejos, la apaga poco a poco."""
        if self.current is None:
            return
        rect = self.current[0]
        g = self.map.geometry
        pos = QCursor.pos()
        cursor = QPointF(pos.x() - g.x(), pos.y() - g.y())
        near = _border_distance(rect, cursor)
        goal = max(0.0, 1.0 - near / NEAR) if near < NEAR else 0.0
        lit = self.lit + (goal - self.lit) * EASE
        if abs(goal - lit) < 0.02:
            lit = goal
        shown = (round(lit, 2), (round(cursor.x()), round(cursor.y())) if lit > 0 else None)
        if shown == self._drawn:
            return  # nada cambió (cursor lejos y apagado, o quieto): ni un repintado
        self.lit, self._drawn = lit, shown
        self.cursor = cursor
        for strip in self.strips:
            if strip.isVisible():
                strip.update()

    def _place(self, rect):
        t = self.theme
        reach = abs(t.focus_gap) + t.focus_width + t.focus_glow + 2
        outer = rect.adjusted(-reach, -reach, reach, reach)
        bands = (
            QRectF(outer.left(), outer.top(), outer.width(), 2 * reach),  # arriba, con las dos esquinas
            QRectF(outer.left(), rect.bottom() - reach, outer.width(), 2 * reach),  # abajo, con las dos esquinas
            QRectF(outer.left(), rect.top() + reach, 2 * reach, rect.height() - 2 * reach),  # izquierda
            QRectF(rect.right() - reach, rect.top() + reach, 2 * reach, rect.height() - 2 * reach),  # derecha
        )
        g = self.map.geometry
        for strip, band in zip(self.strips, bands):
            aligned = band.toAlignedRect()
            strip.local = QRectF(aligned)
            if aligned.width() <= 0 or aligned.height() <= 0:
                strip.hide()
                continue
            strip.setGeometry(aligned.translated(g.x(), g.y()))
            strip.show()
        self._placed = rect


MAX_RINGS = 6  # ventanas que a la vez llevan contorno (3 del mosaico y algunas libres a la vista)


class RingOverlay:
    """Los contornos de todas las ventanas que se ven: un `Ring` por ventana, de una reserva fija (así sus tiras ya
    existen al arrancar y se registran como ventanas propias). Todos se encienden con la cercanía del cursor, tengan
    el foco o no."""

    def __init__(self, theme, screen_map, count=MAX_RINGS):
        self.rings = [Ring(theme, screen_map) for _ in range(count)]
        self._theme = theme

    def _get_theme(self):
        return self._theme

    def _set_theme(self, value):
        self._theme = value
        for ring in self.rings:
            ring.theme = value

    theme = property(_get_theme, _set_theme)

    @property
    def strips(self):
        return [strip for ring in self.rings for strip in ring.strips]

    def set_focus_target(self, targets):
        """`targets` = [(hwnd, (izq, arriba, der, abajo) en px físicos, con_foco)] de las ventanas a rodear, o None."""
        wanted = {hwnd: (rect, focused) for hwnd, rect, focused in targets or ()}
        for ring in self.rings:
            if ring.hwnd is not None and ring.hwnd not in wanted:
                ring.hwnd = None
                ring.set_focus_target(None)
        bound = {ring.hwnd: ring for ring in self.rings if ring.hwnd is not None}
        for hwnd, (rect, focused) in wanted.items():
            ring = bound.get(hwnd) or next((r for r in self.rings if r.hwnd is None), None)
            if ring is None:
                continue  # más ventanas que contornos: las que sobran no llevan
            ring.hwnd, ring.focused = hwnd, focused
            ring.set_focus_target((hwnd, rect))

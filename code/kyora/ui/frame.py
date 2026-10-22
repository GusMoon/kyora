"""El marco de la pantalla y el contorno de la ventana activa: ventanas transparentes que dejan pasar los clics.

El marco (con la franja ancha de la barra a la izquierda y el hueco de esquinas redondeadas), el borde de cada ventana
del mosaico (el mismo del marco: sombra corta, línea oscura y filete de luz) y el resaltado del hueco destino al
arrastrar se pintan en una ventana que cubre la pantalla y solo se repinta cuando algo de eso cambia.

El contorno animado de la ventana activa va aparte, en cuatro ventanas finas (una por lado). Su luz gira sin parar, y
Windows sube entera la parte de una ventana transparente que cambia: si viviera en la de pantalla completa, cada
fotograma movería casi toda la pantalla y le quitaría tiempo al resto de Kyora (también al teclado).
"""
import time

from PySide6.QtCore import QRectF, Qt, QTimer
from PySide6.QtGui import (
    QColor,
    QConicalGradient,
    QPainter,
    QPainterPath,
    QPen,
    QRegion,
)
from PySide6.QtWidgets import QWidget

from kyora.core.ring import RingMotion
from kyora.ui.relief import build_frame_image, paint_raised_edge
from kyora.ui.win import make_tool_window

GLOW_STEPS = 8  # trazos del halo neón: del más ancho y tenue al más estrecho
CORE_TINT = 0.25  # cuánto acento lleva el núcleo casi blanco de la luz
FRAME_MS = 8  # intervalo entre fotogramas mientras el contorno aparece con su fundido
SPIN_MS = 16  # fotogramas del giro de la luz (60 por segundo: las tiras son pequeñas y casi no consumen)


class FrameOverlay(QWidget):
    def __init__(self, theme, screen_map):
        super().__init__()
        make_tool_window(self, click_through=True)
        self.setWindowTitle("KyoraFrame")
        self.theme = theme
        self.map = screen_map
        self.setGeometry(screen_map.geometry)
        size = screen_map.geometry.size()
        self._relief = build_frame_image(theme, size.width(), size.height(), screen_map.dpr)  # una sola vez
        self._drop = None  # QRectF lógico del hueco destino de un arrastre
        self._tiles = []  # QRectF lógicos de las ventanas visibles del mosaico (llevan el borde del marco)

    # ---------- borde de las ventanas del mosaico ----------

    def set_tiles(self, rects):
        """`rects` = [(izq, arriba, der, abajo) en px físicos] de las ventanas visibles."""
        old = self._tiles
        self._tiles = [self.map.rect_to_logical(*r) for r in rects]
        reach = self.theme.edge_shadow_size + self.theme.edge_width * 2 + 2
        region = QRegion()
        for r in (*old, *self._tiles):
            outer = r.adjusted(-reach, -reach, reach, reach).toAlignedRect()
            inner = r.adjusted(reach, reach, -reach, -reach).toAlignedRect()
            band = QRegion(outer)
            region = region.united(band.subtracted(QRegion(inner)) if inner.isValid() else band)
        if not region.isEmpty():
            self.update(region)

    # ---------- hueco destino de un arrastre ----------

    def set_drop(self, rect):
        """`rect` = (izq, arriba, der, abajo) en px físicos o None."""
        old = self._drop
        self._drop = self.map.rect_to_logical(*rect) if rect else None
        for r in (old, self._drop):
            if r is not None:
                self.update(r.adjusted(-2, -2, 2, 2).toAlignedRect())

    # ---------- pintura ----------

    def paintEvent(self, event):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setClipRegion(event.region())
        p.drawImage(0, 0, self._relief)
        for rect in self._tiles:
            paint_window_edge(p, t, rect)
        if self._drop is not None:
            r = self._drop.adjusted(1, 1, -1, -1)
            p.setPen(QPen(QColor(t.drop_line), 1.5))
            p.setBrush(QColor(t.drop_color))
            p.drawRoundedRect(r, t.drop_radius, t.drop_radius)


def paint_window_edge(p, theme, rect):
    """Borde de una ventana del mosaico con el diseño del marco: sombra corta hacia fuera, línea oscura fina por fuera
    y filete de luz por dentro, siguiendo sus esquinas redondeadas (las de Windows 11)."""
    t = theme
    shape = QPainterPath()
    shape.addRoundedRect(QRectF(rect), t.focus_radius, t.focus_radius)
    reach = t.edge_shadow_size + t.edge_width * 2 + 1
    paint_raised_edge(p, shape, QRectF(rect).adjusted(-reach, -reach, reach, reach), t, shadow=True)


def _tint(theme, amount):
    """El núcleo de la luz: casi blanco con un poco del acento."""
    core, accent = QColor(theme.focus_core), QColor(theme.focus_color)
    return QColor(*(round(a + (b - a) * amount) for a, b in zip(core.getRgb()[:3], accent.getRgb()[:3])))


def paint_ring(p, theme, rect, spin, opacity):
    """Luz neón que gira por el borde de la ventana activa (`spin` 0-1): halo ancho del color del acento que se
    difumina y un núcleo fino casi blanco, los dos con la misma cola que se apaga."""
    t = theme
    grow = t.focus_gap + t.focus_width / 2
    edge = QRectF(rect).adjusted(-grow, -grow, grow, grow)
    p.setOpacity(opacity)
    p.setBrush(Qt.NoBrush)
    # halo: trazos cada vez más estrechos; donde se suman todos (pegado al borde) brilla más, y hacia fuera se apaga
    per_step = 1 - (1 - t.focus_glow_alpha) ** (1 / GLOW_STEPS)
    for i in range(GLOW_STEPS):
        reach = t.focus_glow * ((GLOW_STEPS - i) / GLOW_STEPS) ** 1.6
        p.setPen(QPen(_light(t, edge, spin, per_step, QColor(t.focus_color)), t.focus_width + 2 * reach))
        p.drawRoundedRect(edge, t.focus_radius, t.focus_radius)
    # anillo del acento y núcleo claro encima, finos y nítidos
    p.setPen(QPen(_light(t, edge, spin, 0.85, QColor(t.focus_color)), t.focus_width + 2))
    p.drawRoundedRect(edge, t.focus_radius, t.focus_radius)
    p.setPen(QPen(_light(t, edge, spin, 1.0, _tint(t, CORE_TINT)), t.focus_width))
    p.drawRoundedRect(edge, t.focus_radius, t.focus_radius)


def _light(theme, edge, spin, alpha, color):
    """Pincel cónico centrado en la ventana: opaco en la cabeza de la luz y desvaneciéndose en su cola."""
    head = QColor(color)
    head.setAlphaF(alpha)
    clear = QColor(color)
    clear.setAlphaF(0.0)
    g = QConicalGradient(edge.center(), 360 - spin * 360)  # gira en sentido horario
    g.setColorAt(0.0, head)
    g.setColorAt(theme.focus_tail, clear)
    g.setColorAt(0.97, clear)
    g.setColorAt(1.0, head)
    return g


class RingStrip(QWidget):
    """Una de las cuatro ventanas finas del contorno: pinta solo el trozo del contorno que le cae dentro."""

    def __init__(self, ring):
        super().__init__()
        make_tool_window(self, click_through=True)
        self.setWindowTitle("KyoraRing")
        self.ring = ring
        self.local = QRectF()  # dónde está, en coordenadas de la pantalla (las del contorno)

    def paintEvent(self, _):
        if self.ring.current is None:
            return
        rect, opacity = self.ring.current
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.translate(-self.local.x(), -self.local.y())
        paint_ring(p, self.ring.theme, rect, self.ring.spin, opacity)


class RingOverlay:
    """El contorno de la ventana activa repartido en cuatro tiras: arriba y abajo (con las esquinas) y los lados."""

    def __init__(self, theme, screen_map):
        self.theme = theme
        self.map = screen_map
        self.strips = [RingStrip(self) for _ in range(4)]
        self.current = None  # (QRectF lógico, opacidad) del contorno en este fotograma
        self.spin = 0.0  # vuelta de la luz que recorre el borde, de 0 a 1
        self._motion = RingMotion()
        self._placed = None  # rectángulo para el que están colocadas las tiras
        self._timer = QTimer()
        self._timer.setInterval(FRAME_MS)
        self._timer.timeout.connect(self._tick)

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
        self.spin = (now % (t.focus_spin_ms / 1000)) / (t.focus_spin_ms / 1000)
        frame = self._motion.frame(now, t.focus_rest, t.focus_fade_ms / 1000)
        if frame is None:
            self.current = None
            self._placed = None
            for strip in self.strips:
                strip.hide()
            self._timer.stop()
            return
        (left, top, right, bottom), opacity = frame
        self.current = (self.map.rect_to_logical(left, top, right, bottom), opacity)
        if self.current[0] != self._placed:
            self._place(self.current[0])
        for strip in self.strips:
            strip.update()
        # la luz sigue girando mientras haya contorno; solo el fundido pide fotogramas rápidos
        moving = not self._motion.settled(now, t.focus_fade_ms / 1000)
        self._timer.setInterval(FRAME_MS if moving else SPIN_MS)

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

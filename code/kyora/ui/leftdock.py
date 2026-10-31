"""El panel izquierdo: una tira estrecha que sale del borde izquierdo de la pantalla.

Tiene dos páginas. Al acercar el cursor al borde muestra solo los iconos de las ventanas en espera del eje que ves
(minimizadas o aparcadas): un clic trae una al mosaico y arrastrarla la deja donde se suelte (si se suelta sobre un
hueco del mosaico, ocupa ese hueco); el nombre sale como ayuda al pasar el ratón. Al crear un escritorio o cambiar
de uno a otro asoma solo un momento con otra página: una barra con los números de los escritorios, donde el nuevo se
ilumina. Pulsar un número va a ese escritorio.

Mientras se arrastra una ventana el panel se esconde y solo queda una tarjeta con la captura siguiendo al cursor.
"""
import time

from PySide6.QtCore import QEasingCurve, QPoint, QRect, QRectF, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QCursor, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QVBoxLayout, QWidget

from kyora.ui.anim import Tween
from kyora.ui.bar import font
from kyora.ui.dock import DockPage, PageDock
from kyora.ui.icons import app_icon
from kyora.ui.topdock import _button_down
from kyora.ui.transition import shot_pixmap
from kyora.ui.win import make_tool_window

STRIP_W = 46  # lo que sobresale la tira
ITEM = 38  # alto de cada icono o número
STRIP_PAD = 6  # el margen de la pieza (el mismo `pad` del panel)
MAX_ITEMS = 8
HOT_MS = 50
PEEK_MS = 1700  # lo que se queda el panel al asomar solo (cambio de escritorio)
ROLL_MS = 220
FOLLOW_WAIT_MS = 120  # lo que se espera a que empiece el deslizamiento de pantalla antes de mover la luz solos
DRAG_START = 8  # px que hay que mover una fila para que cuente como arrastre y no como clic
CANCEL_ZONE = 60  # soltar tan cerca del borde izquierdo cancela el arrastre
GHOST_W, GHOST_H = 190, 119


def strip_length(count):
    """Largo de la tira para `count` elementos."""
    return 2 * STRIP_PAD + ITEM * max(1, min(count, MAX_ITEMS))


class DesktopBar(DockPage):
    """Los números de los escritorios en una barra vertical; el activo se ilumina y al cambiar la luz se desliza."""

    size = (STRIP_W, strip_length(MAX_ITEMS))
    chosen = Signal(int)

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.count, self.active = 1, 0
        self._at = 0.0  # dónde está la luz (índice, con decimales mientras se desliza)
        self._slide = Tween(self, self._set_at)
        self.setCursor(Qt.PointingHandCursor)

    def set_state(self, count, active):
        self._slide.stop()
        self.count, self.active, self._at = count, active, float(active)
        self.size = (STRIP_W, strip_length(count))
        self.update()

    def roll_to(self, count, active):
        """La luz se desliza del escritorio de antes al nuevo."""
        self.count = count
        self.size = (STRIP_W, strip_length(count))
        self.active = active
        self._slide.start(self._at, float(active), ROLL_MS, QEasingCurve.OutQuint)

    def _set_at(self, value):
        self._at = float(value)
        self.update()

    def set_at(self, value):
        """La luz en una posición (con decimales mientras se desliza), sin animación propia."""
        self._slide.stop()
        self._set_at(value)

    def mouseReleaseEvent(self, event):
        index = int(event.position().y() // ITEM)
        if event.button() == Qt.LeftButton and 0 <= index < self.count:
            self.chosen.emit(index)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        side = ITEM - 8
        x = (self.width() - side) / 2
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(t.gold))
        p.setOpacity(0.9)
        p.drawRoundedRect(QRectF(x, self._at * ITEM + 4, side, side), 8, 8)  # la luz del escritorio activo
        p.setOpacity(1.0)
        p.setFont(font(t, bold=True))
        for i in range(self.count):
            near = max(0.0, 1.0 - abs(i - self._at))  # el número bajo la luz se oscurece para leerse sobre el acento
            ink, over = QColor(t.dim), QColor(t.frame)
            mix = tuple(round(a + (b - a) * near) for a, b in zip(ink.getRgb()[:3], over.getRgb()[:3]))
            p.setPen(QColor(*mix))
            p.drawText(QRectF(0, i * ITEM, self.width(), ITEM), Qt.AlignCenter, str(i + 1))


class WindowList(QWidget):
    """Los iconos de las ventanas que no se ven, uno debajo de otro. Pintados, sin un widget por fila."""

    picked = Signal(object)  # clic: se trae al centro
    dragged = Signal(object)  # arrastre: se suelta donde se quiera

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.items = []
        self._hover = -1
        self._press = None
        self.setMouseTracking(True)
        self.setCursor(Qt.PointingHandCursor)

    def set_items(self, items):
        self.items = items
        self.update()

    def _row_at(self, y):
        i = int(y) // ITEM
        return i if 0 <= i < len(self.items) else -1

    def leaveEvent(self, event):
        self._hover = -1
        self.update()

    def mouseMoveEvent(self, event):
        if self._press is not None and (event.position().toPoint() - self._press[1]).manhattanLength() > DRAG_START:
            item = self.items[self._press[0]]
            self._press = None
            self.dragged.emit(item)
            return
        row = self._row_at(event.position().y())
        if row != self._hover:
            self._hover = row
            self.setToolTip(f"{self.items[row]['app']} · {self.items[row]['title']}" if row >= 0 else "")
            self.update()

    def mousePressEvent(self, event):
        row = self._row_at(event.position().y())
        if event.button() == Qt.LeftButton and row >= 0:
            self._press = (row, event.position().toPoint())

    def mouseReleaseEvent(self, event):
        press, self._press = self._press, None
        if press is not None and event.button() == Qt.LeftButton:
            self.picked.emit(self.items[press[0]])

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        for i, item in enumerate(self.items[:MAX_ITEMS]):
            row = QRectF(0, i * ITEM, self.width(), ITEM).adjusted(2, 2, -2, -2)
            if i == self._hover:  # plano: un velo claro, sin relieve
                p.setPen(Qt.NoPen)
                p.setBrush(QColor(255, 255, 255, 26))
                p.drawRoundedRect(row, 8, 8)
            icon = app_icon(item.get("exe", ""), item["hwnd"], t.icon_px, self.devicePixelRatioF())
            p.drawPixmap(round(row.center().x() - t.icon_px / 2), round(row.center().y() - t.icon_px / 2), icon)


class LeftPage(DockPage):
    size = (STRIP_W, strip_length(MAX_ITEMS))

    def __init__(self, theme):
        super().__init__()
        self.list = WindowList(theme)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.list, 1)

    def fit(self, count):
        self.size = (STRIP_W, strip_length(count))


class DragGhost(QWidget):
    """La tarjeta que sigue al cursor mientras se arrastra una ventana del panel (captura, o su icono)."""

    def __init__(self, theme):
        super().__init__()
        make_tool_window(self, click_through=True)
        self.setWindowTitle("KyoraDrag")
        self.theme = theme
        self.item, self.shot = None, None
        self.resize(GHOST_W, GHOST_H)

    def show_for(self, item, shot):
        self.item, self.shot = item, shot
        self.show()
        self.raise_()

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setRenderHint(QPainter.SmoothPixmapTransform)
        rect = QRectF(self.rect()).adjusted(3, 3, -3, -3)
        shape = QPainterPath()
        shape.addRoundedRect(rect, t.focus_radius, t.focus_radius)
        p.setClipPath(shape)
        p.fillRect(rect, QColor(t.plate_top))
        if self.shot is not None:
            p.drawPixmap(rect, self.shot, QRectF(self.shot.rect()))
        elif self.item is not None:
            icon = app_icon(self.item.get("exe", ""), self.item["hwnd"], 48, self.devicePixelRatioF())
            p.drawPixmap(round(rect.center().x() - 24), round(rect.center().y() - 24), icon)
        p.setClipping(False)
        p.setPen(QPen(QColor(t.gold), 1.5))
        p.setBrush(Qt.NoBrush)
        p.drawRoundedRect(rect, t.focus_radius, t.focus_radius)


class LeftDock(PageDock):
    def __init__(self, theme, screen_map, invoke, thumb):
        page, bar = LeftPage(theme), DesktopBar(theme)
        super().__init__(theme, screen_map, {"main": page, "desktops": bar}, edge="bar", title="KyoraLeft",
                         pad=STRIP_PAD)
        self.page, self.bar = page, bar
        self._invoke, self._thumb = invoke, thumb
        self.suspended = False
        self._active, self._count = 0, 1
        self._peek_until = 0.0
        self._moving_to = None  # (de, a, cuántos): el cambio de escritorio que la luz de la barra sigue
        self._followed = False
        self._drag = None
        self.peeking = False  # asomó solo (no la pidió el cursor): no oscurece la pantalla
        self.ghost = DragGhost(theme)
        self.page_changed.connect(lambda name: None if name else setattr(self, "peeking", False))
        page.list.picked.connect(self._bring)
        page.list.dragged.connect(self._start_drag)
        bar.chosen.connect(lambda index: self._invoke("desktop.switch", index=index))
        self._hot = QTimer(self)
        self._hot.setInterval(HOT_MS)
        self._hot.timeout.connect(self._poll)
        self._hot.start()
        self._drag_timer = QTimer(self)
        self._drag_timer.setInterval(16)
        self._drag_timer.timeout.connect(self._drag_step)

    # ---------- datos del núcleo ----------

    def on_state(self, state):
        """Las ventanas que no se ven (fuera de la pantalla y minimizadas) y qué escritorio es este."""
        items = [{"hwnd": w["hwnd"], "app": w["app"], "title": w["title"], "exe": w["exe"]}
                 for w in state["waiting"]]
        if items != self.page.list.items:
            self.page.list.set_items(items)
            self.page.fit(len(items))
        desktops = state["desktops"]
        self._active, self._count = state["active"], len(desktops)
        if not self.opened:
            self.bar.set_state(self._count, self._active)

    def peek(self, desktops):
        """Asoma al crear un escritorio o cambiar de uno a otro: la barra de números, con la luz deslizándose al
        escritorio nuevo al mismo ritmo que la pantalla (ver `follow`); sin deslizamiento, rueda sola."""
        if self.suspended or self._drag is not None:
            return
        active = next((i for i, d in enumerate(desktops) if d["active"]), 0)
        count = len(desktops)
        before = min(self._active, count - 1)
        self._peek_until = time.monotonic() + PEEK_MS / 1000
        self._followed = False
        self._moving_to = (before, active, count)
        if self.opened and self.name == "desktops":
            self.bar.size = (STRIP_W, strip_length(count))
            self._piece = self._target("desktops")
            self.bar.count = count
            self.update()
        else:
            self.bar.set_state(count, before)  # sale con la luz donde estaba
            if not self.opened:
                self.peeking = True
            self.show_page("desktops", self._zone())
        self._active, self._count = active, count
        QTimer.singleShot(FOLLOW_WAIT_MS, self._roll_if_alone)

    def follow(self, progress):
        """El cambio de escritorio avanza (0 a 1): la luz de la barra se mueve con él, en tiempo real."""
        if self._moving_to is None or not self.opened:
            return
        self._followed = True
        before, active, count = self._moving_to
        self.bar.set_at(before + (active - before) * progress)
        if progress >= 1.0:
            self.bar.set_state(count, active)
            self._moving_to = None

    def _roll_if_alone(self):
        """Nadie movió la luz (no hubo deslizamiento de pantalla): rueda sola al escritorio nuevo."""
        if self._moving_to is not None and not self._followed and self.opened:
            _, active, count = self._moving_to
            self.bar.roll_to(count, active)
            self._moving_to = None

    def suspend(self, on):
        self.suspended = on
        if on:
            self.close_popout()

    # ---------- abrir con el cursor ----------

    def _zone(self):
        g = self.map.geometry
        height = min(self.theme.left_zone, g.height())
        return QRect(g.x(), round(g.y() + (g.height() - height) / 2), 6, height)

    def _poll(self):
        if self.opened or self.suspended or self._drag is not None or not self.page.list.items:
            return  # sin ventanas escondidas no hay nada que enseñar al pasar el cursor
        zone, pos = self._zone(), QCursor.pos()
        if pos.x() > zone.x() + 1 or not zone.top() <= pos.y() <= zone.bottom() or _button_down():
            return
        self.show_page("main", zone)

    def _check_blur(self):
        if time.monotonic() < self._peek_until:  # asomó solo: no se cierra porque otra ventana se active (la del deslizamiento)
            return
        super()._check_blur()

    def _check_leave(self):
        if time.monotonic() < self._peek_until:  # asomó solo: se esconde a su hora, esté el ratón donde esté
            return
        super()._check_leave()

    # ---------- traer una ventana ----------

    def _bring(self, item):
        self._invoke("wm.bring_to", hwnd=item["hwnd"])
        self.close_popout()

    def _start_drag(self, item):
        self._drag = item
        self.ghost.show_for(item, shot_pixmap(self._thumb(item["hwnd"])))
        self.close_popout()
        self._drag_timer.start()
        self._drag_step()

    def _drag_step(self):
        pos = QCursor.pos()
        self.ghost.move(pos - QPoint(GHOST_W // 2, GHOST_H // 2))
        if not _button_down():
            self._drop(pos)

    def _drop(self, pos):
        self._drag_timer.stop()
        self.ghost.hide()
        item, self._drag = self._drag, None
        g = self.map.geometry
        if item is None or pos.x() < g.x() + CANCEL_ZONE:
            return
        self._invoke("wm.bring_to", hwnd=item["hwnd"], x=self.map.to_physical(pos.x() - g.x()),
                     y=self.map.to_physical(pos.y() - g.y()))

    def retheme(self, theme):
        self.page.update()
        self.bar.update()

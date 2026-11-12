"""Las ventanas "fantasma": lo que se ve mientras las ventanas se mueven por la pantalla.

Mover de verdad una app a 60 fotogramas por segundo la obliga a repintarse en cada uno y se atora. Aquí se hace al
revés: primero se acomodan las ventanas detrás de este panel y luego cargan las apps.

Una sola ventana propia, opaca y a pantalla completa, con el fondo de pantalla nítido y una tarjeta por ventana:
- las que ya se veían son una captura de la pantalla hecha justo antes; las que aparecen son su última captura (o una
  tarjeta con su icono y su nombre si no hay);
- `start`: las ventanas del mosaico se deslizan a su nuevo hueco (la nueva entra desde el borde derecho);
- `slide`: al cambiar de escritorio la pantalla se encoge hacia el centro, se desliza al escritorio de al lado (los dos
  se ven a la vez, con un hueco entre ellos) y vuelve a su tamaño, todo seguido y sin parar;
En todos los casos el núcleo coloca las apps reales debajo mientras tanto y, al terminar, el panel se desvanece y
deja ver las apps ya colocadas. No recibe clics ni foco.
"""
from PySide6.QtCore import QEasingCurve, QPointF, QRectF, Qt, QTimer, Signal
from PySide6.QtGui import (
    QColor,
    QGuiApplication,
    QImage,
    QPainter,
    QPainterPath,
    QPen,
    QPixmap,
)
from PySide6.QtWidgets import QWidget

from kyora.system import wallpaper
from kyora.ui.anim import Tween
from kyora.ui.bar import font
from kyora.ui.icons import app_icon
from kyora.ui.wallpaper_bg import WallpaperBg
from kyora.ui.win import make_tool_window

SLIDE_MS = 260  # lo que tardan las tarjetas en llegar a su sitio
DESKTOP_MS = 560  # el cambio de escritorio entero: encoger, deslizar y volver a crecer
SHRINK = 0.28  # cuánto se encoge la pantalla al deslizar (queda al 72 %)
DESKTOP_GAP = 0.12  # el hueco entre los dos escritorios, como fracción de una pantalla
SETTLE_MS = 140  # con las apps ya colocadas, lo que se espera a que se pinten antes de desvanecer el panel
FADE_MS = 130
FRAME_MS = 16  # 60 fotogramas por segundo: el panel es grande y no necesita más
ICON = 56


def shot_pixmap(shot):
    """(ancho, alto, bytes BGRX) de una captura -> QPixmap, o None. El cuarto byte no es alfa: RGB32."""
    if not shot:
        return None
    return QPixmap.fromImage(QImage(shot[2], shot[0], shot[1], shot[0] * 4, QImage.Format_RGB32))


class Card:
    """Una ventana en el panel: de dónde sale, a dónde va y qué se dibuja (su captura, o su icono y su nombre)."""

    def __init__(self, hwnd, start, end, pixmap=None, name="", exe=""):
        self.hwnd, self.start, self.end, self.pixmap, self.name, self.exe = hwnd, start, end, pixmap, name, exe

    def rect(self, t):
        a, b = self.start, self.end
        return QRectF(a.left() + (b.left() - a.left()) * t, a.top() + (b.top() - a.top()) * t,
                      a.width() + (b.width() - a.width()) * t, a.height() + (b.height() - a.height()) * t)


def _smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def desktop_phases(u):
    """(escala, avance) del cambio de escritorio en el instante `u` (0 a 1): primero la pantalla se encoge, mientras
    se desliza al otro escritorio (los dos solapan un poco) y al final vuelve a crecer. `avance` va de 0 a 1."""
    shrink = _smooth(u / 0.3) - _smooth((u - 0.7) / 0.3)
    return 1.0 - SHRINK * shrink, _smooth((u - 0.12) / 0.76)


class WindowTransition(QWidget):
    slid = Signal(float)  # cuánto va del cambio de escritorio (0 a 1): el panel izquierdo mueve su luz con él

    def __init__(self, theme, screen_map):
        super().__init__()
        make_tool_window(self, click_through=True)
        self.setAttribute(Qt.WA_TranslucentBackground, False)  # opaco: la pantalla entera cambia de golpe, sin capas
        self.setAttribute(Qt.WA_OpaquePaintEvent, True)
        self.setWindowTitle("KyoraTransition")
        self.theme, self.map = theme, screen_map
        self.cards = {}  # hwnd -> Card
        self._t = 1.0  # avance (ya suavizado) de las tarjetas hacia su sitio
        self._opacity = 0.0
        self._done = None  # threading.Event: se activa al llegar las tarjetas, para que el núcleo coloque las apps
        self._ending = False  # el núcleo ya colocó las apps: toca desvanecer el panel
        self._scene = None  # el cambio de escritorio en marcha: {offset, scale, move}
        self._wall = WallpaperBg(screen_map)
        self._bg = None  # el fondo nítido que se pinta (se toma al salir el panel: no se pregunta a Windows en cada fotograma)
        self.setGeometry(screen_map.geometry)
        self._slide = Tween(self, self._set_t, self._arrived, frame_ms=FRAME_MS)
        self._fade = Tween(self, self._set_opacity, self._faded, frame_ms=FRAME_MS)
        self._hold = QTimer(self)
        self._hold.setSingleShot(True)
        self._hold.timeout.connect(self._fade_out)
        self.refresh_wallpaper()

    def refresh_wallpaper(self):
        """El fondo cambió (o va a hacer falta): se lee en un hilo para tenerlo listo."""
        self._wall.prepare(wallpaper.current())

    # ---------- utilidades ----------

    def _logical(self, rect):
        """Rectángulo físico (izq, arriba, der, abajo) -> rectángulo del panel, en píxeles lógicos."""
        return self.map.rect_to_logical(*rect)

    def _grab(self):
        """Una captura de lo que hay ahora en pantalla (con las apps como están), antes de mover nada."""
        g = self.map.geometry
        pixmap = QGuiApplication.primaryScreen().grabWindow(0, g.x(), g.y(), g.width(), g.height())
        return None if pixmap.isNull() else pixmap

    @staticmethod
    def _crop(grab, rect):
        if grab is None:
            return None
        dpr = grab.devicePixelRatio()
        shot = grab.copy(round(rect.x() * dpr), round(rect.y() * dpr), round(rect.width() * dpr), round(rect.height() * dpr))
        shot.setDevicePixelRatio(dpr)
        return shot

    def _show_panel(self):
        self._hold.stop()
        self._fade.stop()
        self._ending = False
        self.setWindowOpacity(1.0)
        self._opacity = 1.0
        self._bg = self._wall.pixmap(wallpaper.current())
        if not self.isVisible():
            self.show()
        self.raise_()

    # ---------- escritorios: toda la pantalla se desliza ----------

    def slide(self, payload):
        """Llega del núcleo: {old, new, offset, done}. `old` son las ventanas que se ven (con su rectángulo en px
        físicos), `new` las que se verán en el otro escritorio y `offset` (dx, dy) lo que se desplaza todo, en px físicos."""
        grab = self._grab()
        dx, dy = payload["offset"][0] / self.map.dpr, payload["offset"][1] / self.map.dpr
        offset = QPointF(dx, dy) * (1 + DESKTOP_GAP)  # con un hueco entre los dos escritorios
        cards = {}
        for card in payload["old"]:
            rect = self._logical(card["rect"])
            cards[("old", card["hwnd"])] = Card(card["hwnd"], rect, rect, self._crop(grab, rect), card["name"], card["exe"])
        for card in payload["new"]:
            rect = self._logical(card["rect"]).translated(-offset)
            cards[("new", card["hwnd"])] = Card(card["hwnd"], rect, rect, shot_pixmap(card["shot"]), card["name"],
                                                card["exe"])
        screen = QRectF(0, 0, self.width(), self.height())
        self._scene = {"offset": offset, "scale": 1.0, "move": 0.0, "pages": [screen, screen.translated(-offset)]}
        self._begin(cards, payload.get("done"), DESKTOP_MS, False, QEasingCurve.Linear)

    def _begin(self, cards, done, ms, live, curve=QEasingCurve.OutCubic):
        self.cards = cards
        self._done = done
        if curve != QEasingCurve.Linear:
            self._scene = None
        self._t = 0.0
        if not live:
            self._show_panel()
        self._slide.start(0.0, 1.0, ms, curve)
        self.update()

    def finish(self):
        """El núcleo ya colocó las apps reales debajo: cuando las tarjetas lleguen, se desvanece el panel."""
        self._ending = True
        self._settle()

    # ---------- animación ----------

    def _set_t(self, value):
        self._t = float(value)
        if self._scene is not None:
            self._scene["scale"], self._scene["move"] = desktop_phases(self._t)
            self.slid.emit(self._scene["move"])
        self.update()

    def _arrived(self):
        self._t = 1.0
        if self._done is not None:
            self._done.set()  # el núcleo puede colocar las apps
        self._settle()

    def _settle(self):
        if self._ending and not self._slide.running() and not self._hold.isActive():
            self._hold.start(SETTLE_MS)

    def _fade_out(self):
        self._fade.start(self._opacity, 0.0, FADE_MS, QEasingCurve.InCubic)

    def _set_opacity(self, value):
        self._opacity = float(value)
        self.setWindowOpacity(self._opacity)

    def _faded(self):
        if self._opacity <= 0.01:
            self.hide()
            self.cards = {}
            self._scene = None

    # ---------- pintura ----------

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.SmoothPixmapTransform)
        if self._bg is not None:
            p.drawPixmap(0, 0, self._bg)
        else:
            p.fillRect(self.rect(), QColor(self.theme.frame_dark))
        p.setRenderHint(QPainter.Antialiasing)
        scene = self._scene
        if scene is not None:
            self._paint_desktops(p, scene)
            return
        # las que ya estaban, debajo; la nueva (la que entra, sin captura) por encima
        for card in sorted(self.cards.values(), key=lambda c: c.pixmap is None):
            rect = card.rect(self._t)
            if rect.intersects(QRectF(self.rect())):
                self._paint_card(p, card, rect)

    def _to_screen(self, rect, scene):
        """Un rectángulo del "mundo" de los dos escritorios -> pantalla: se desliza y se encoge hacia el centro."""
        center = QPointF(self.width(), self.height()) / 2
        s = scene["scale"]
        moved = rect.translated(scene["offset"] * scene["move"])
        return QRectF(center + (moved.topLeft() - center) * s, moved.size() * s)

    def _paint_desktops(self, p, scene):
        view = QRectF(self.rect())
        for page in scene["pages"]:  # el marco de cada pantalla, para que se vean como dos escritorios
            rect = self._to_screen(page, scene)
            if rect.intersects(view):
                p.setBrush(QColor(0, 0, 0, 70))
                p.setPen(QPen(QColor(255, 255, 255, 36), 1))
                p.drawRoundedRect(rect, self.theme.hole_radius, self.theme.hole_radius)
        for card in sorted(self.cards.values(), key=lambda c: c.pixmap is None):
            rect = self._to_screen(card.end, scene)
            if rect.intersects(view):
                self._paint_card(p, card, rect)

    def _paint_card(self, p, card, rect):
        t = self.theme
        shape = QPainterPath()
        shape.addRoundedRect(rect, t.focus_radius, t.focus_radius)
        p.save()
        p.setClipPath(shape, Qt.IntersectClip)
        if card.pixmap is not None:  # su captura, estirada al hueco por el que pasa
            p.drawPixmap(rect, card.pixmap, QRectF(card.pixmap.rect()))
        else:  # sin captura: una tarjeta con su icono y su nombre, mientras la app carga o vuelve
            p.fillRect(rect, QColor(t.plate_top))
            icon = app_icon(card.exe, card.hwnd, ICON, self.devicePixelRatioF())
            p.drawPixmap(round(rect.center().x() - ICON / 2), round(rect.center().y() - ICON - 6), icon)
            p.setFont(font(t, 16, bold=True))
            p.setPen(QColor(t.ink))
            p.drawText(QRectF(rect.left() + 12, rect.center().y() + 8, rect.width() - 24, 24), Qt.AlignHCenter | Qt.AlignTop,
                       p.fontMetrics().elidedText(card.name, Qt.ElideRight, round(rect.width() - 24)))
        p.restore()
        p.setPen(QPen(QColor(255, 255, 255, 38), 1))  # un filete fino alrededor, como el borde de las ventanas
        p.setBrush(Qt.NoBrush)
        p.drawRoundedRect(rect.adjusted(0.5, 0.5, -0.5, -0.5), t.focus_radius, t.focus_radius)

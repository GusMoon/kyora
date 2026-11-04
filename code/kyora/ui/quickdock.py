"""El panel de la esquina de abajo a la derecha: todo lo del sistema, sin tarjetas, directo sobre el fondo del panel.

Arriba, una sola tarjeta con la información en grande: la hora y la fecha, el clima de ahora, y la RAM y la batería.
Abajo, en otra, solo los iconos de wifi, Bluetooth y ajustes. Si suena música, encima de todo sale la cápsula de lo que
suena (`musicpill.py`) y el panel crece para dejarle sitio; al parar, se encoge.

Sale al llevar el cursor a la esquina (como los paneles de arriba y de la izquierda) y se esconde al quitarlo. La página
principal enseña los datos; pulsar la hora, el wifi, el Bluetooth o los ajustes abre su página en el mismo panel, con una
flechita para volver.
"""
import datetime
import logging

from PySide6.QtCore import QEasingCurve, QRect, QRectF, QSize, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QCursor, QFontMetrics, QPainter, QPixmap
from PySide6.QtWidgets import QAbstractButton, QHBoxLayout, QVBoxLayout

from kyora.core.animation import lerp
from kyora.core.calendar_grid import long_date
from kyora.ui import glyphs
from kyora.ui.anim import Tween
from kyora.ui.bar import LOW_BATTERY, accent
from kyora.ui.bar import font as base_font
from kyora.ui.configpage import ConfigPage
from kyora.ui.dock import DockPage, PageDock
from kyora.ui.hub.cards import paint_glass, paint_well
from kyora.ui.musicpill import MIN_H as MUSIC_MIN
from kyora.ui.musicpill import PILL_H as MUSIC_H
from kyora.ui.musicpill import Covers, MusicPill
from kyora.ui.panels import BluetoothPage, ClockPage
from kyora.ui.topdock import _button_down
from kyora.ui.wifi_panel import WifiPage

log = logging.getLogger("kyora.ui")

PAD = 8  # el margen de la pieza (el mismo `pad` del panel)
WIDTH = 380
PAD_X = 16  # el aire a los lados del contenido
INFO_H = 178  # la tarjeta de la información
DOCK_H = 62  # los iconos de abajo
PILL_W, PILL_H = 50, 50  # cuadrados con las esquinas redondeadas
PILL_R = 14
DOCK_ICON = 26  # los iconos de abajo, más grandes que el resto
BIG, MEDIUM, TEXT = 40, 28, 14  # la hora, la temperatura y los porcentajes; el texto de lo demás
INFO_R = 30  # las esquinas de la tarjeta de la información (el reproductor, más alto, las tiene más grandes)
GAP = 8  # entre las dos tarjetas
GROW_MS = 220  # lo que tarda el panel en crecer (o encogerse) al empezar (o acabar) la música
MARQUEE_MS = 33  # el nombre de lo que suena, cuando no cabe, se desliza


def font(theme, px=None, bold=False):
    """La letra del panel: a diferencia de `bar.font` (un solo tamaño), aquí la información va en grande."""
    f = base_font(theme, bold=bold)
    if px:
        f.setPixelSize(px)
    return f


HEAD_H = 30  # la fila con la flecha de volver de las páginas de detalle
HOT_MS = 50
ZONE_H = 6
EDGE_BAND = 3  # los px de abajo de la pantalla donde Windows hace salir su barra de tareas
TICK_MS = 15000
TITLES = {"clock": "Calendario", "wifi": "Wi-Fi", "bluetooth": "Bluetooth", "config": "Configuración"}


class QuickMain(DockPage):
    """La página principal: la hora y el clima, las fichas de ajustes rápidos y los medidores de RAM y batería."""

    go = Signal(str)  # "clock", "wifi", "bluetooth" o "config"
    music_control = Signal(str)  # "toggle", "download", "stop", "prev" o "next" de lo que suena
    size = (INFO_H + DOCK_H + GAP + 2 * PAD, WIDTH + 2 * PAD)  # con música, más alto (ver `set_music`)

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.pill = MusicPill(theme)
        self.covers = Covers(self)  # las carátulas llegan solas y la cápsula se repinta
        self.covers.ready.connect(self._cover_ready)
        self.pill_h = MUSIC_H  # lo que mide la tarjeta de lo que suena (el panel la encoge si no cabe: ver `QuickDock`)
        self._music_on = False  # suena (o está en pausa) algo: el panel es más alto
        self._shown = False  # la cápsula se pinta (sigue un momento tras parar, mientras el panel se encoge)
        self._second = -1
        self._marquee = QTimer(self)
        self._marquee.setInterval(MARQUEE_MS)
        self._marquee.timeout.connect(self._slide)
        self._wifi = {}
        self._bluetooth = False  # hay al menos un dispositivo conectado
        self._weather = None
        self._ram = None
        self._battery = None  # (porcentaje, enchufada)
        self._hover = None
        self._over_screen = False  # el cursor está sobre la pantalla del reproductor (salen anterior y siguiente)
        self._hits = []
        self.refresh = None  # lo que pide el estado del Bluetooth (lo pone el panel)
        self.setMouseTracking(True)
        self._tick = QTimer(self)
        self._tick.setInterval(TICK_MS)
        self._tick.timeout.connect(self.update)

    # ---------- datos del núcleo ----------

    def apply(self, model):
        d = model.get("devices", {})
        if "ram" in d:
            self._ram = (d["ram"], d.get("ram_used"), d.get("ram_total"))
        self._battery = (d["battery"], bool(d.get("plugged"))) if "battery" in d else None
        if model.get("weather") is not None:
            self._weather = model["weather"]
        self._wifi = model.get("wifi") or {}
        self._bluetooth = bool(model.get("bluetooth"))
        self.update()

    # ---------- lo que suena ----------

    def retheme(self, theme):
        """Al cambiar el fondo de pantalla: la cápsula no es un widget, así que no recibe el tema sola."""
        self.pill.theme = theme
        self.update()

    def set_music(self, info):
        """`info` = {title, playing} o None. Devuelve True si la cápsula apareció o se fue: el panel cambia de alto."""
        on = info is not None
        if on:
            if self.pill.set_state(info["title"], info["playing"], info.get("id", ""), bool(info.get("next")),
                                   info.get("download", "")):
                self._set_cover(self.covers.get(info.get("id", "")))
            self._shown = True
        changed = on != self._music_on
        self._music_on = on
        extra = self.pill_h + GAP if on else 0
        self.size = (INFO_H + DOCK_H + GAP + 2 * PAD + extra, WIDTH + 2 * PAD)
        self._sync_marquee()
        self.update()
        return changed

    def _set_cover(self, image):
        self.pill.cover = QPixmap.fromImage(image) if image is not None else None

    def _cover_ready(self, video_id, image):
        if video_id == self.pill.track_id:
            self._set_cover(image)
            self._repaint_pill()

    def release_music(self):
        """El panel ya se encogió: la cápsula deja de pintarse."""
        if not self._music_on:
            self._shown = False
            self._sync_marquee()
            self.update()

    def on_progress(self, pos, dur):
        self.pill.wave.moved(pos, dur)
        if pos // 1000 != self._second:  # el tiempo cambia una vez por segundo
            self._second = pos // 1000
            self._repaint_pill()

    def on_level(self, level):
        self.pill.wave.add(level)  # se guarda siempre (las ondas de lo que ya sonó), se pinta solo si se ve
        self._repaint_pill()

    def _pill_rect(self):
        top = self.height() - (INFO_H + GAP + DOCK_H) - GAP - self.pill_h
        return QRectF(0, top, self.width(), self.pill_h)

    def _repaint_pill(self):
        if self._shown and self.isVisible():
            self.update(self._pill_rect().toAlignedRect())

    def _sync_marquee(self):
        run = self._shown and self.isVisible() and self.pill.scrolling()
        if run != self._marquee.isActive():
            self._marquee.start() if run else self._marquee.stop()
        if not run:
            self.pill.offset = 0

    def _slide(self):
        self.pill.step()
        self._repaint_pill()

    def activate(self):
        """Al mostrarse la página principal: se pregunta de nuevo cómo está el Bluetooth (para el icono)."""
        if self.refresh is not None:
            self.refresh()

    def showEvent(self, event):
        self._tick.start()
        self._sync_marquee()
        super().showEvent(event)

    def hideEvent(self, event):
        self._tick.stop()
        self._marquee.stop()
        super().hideEvent(event)

    # ---------- ratón ----------

    def _name_at(self, pos):
        return next((name for name, rect in self._hits if rect.contains(pos)), None)

    def mouseMoveEvent(self, event):
        name = self._name_at(event.position())
        over = self._shown and self.pill.layout(self._pill_rect())["screen"].contains(event.position())
        if name != self._hover or over != self._over_screen:
            self._hover, self._over_screen = name, over
            self.setCursor(Qt.PointingHandCursor if name else Qt.ArrowCursor)
            self.setToolTip(self._tip(name))
            self.update()

    def _tip(self, name):
        if name == "wifi":
            return f"Wi-Fi: {self._wifi['ssid']}" if self._wifi.get("connected") else "Wi-Fi: sin conexión"
        if name == "music_toggle":
            return "Pausa" if self.pill.playing else "Seguir"
        if name == "music_download":
            return {"done": "Ya enviada (pulsa para mandarla otra vez a la última persona elegida)",
                    "queued": "En cola para descargar", "doing": "Descargando…",
                    "sending": "Enviándola…"}.get(self.pill.download, "Mandar esta canción a la última persona elegida (por defecto, tú)")
        return {"bluetooth": "Bluetooth", "config": "Configuración", "clock": "Calendario", "music_stop": "Detener y cerrar",
                "music_prev": "Anterior", "music_next": "Siguiente"}.get(name, "")

    def leaveEvent(self, _):
        self._hover, self._over_screen = None, False
        self.update()

    def mouseReleaseEvent(self, event):
        name = self._name_at(event.position())
        if name and event.button() == Qt.LeftButton:
            if name.startswith("music_"):
                self.music_control.emit(name.removeprefix("music_"))
            else:
                self.go.emit(name)

    # ---------- pintura ----------

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        self._hits = []
        w = self.width()
        y = self.height() - (INFO_H + GAP + DOCK_H)  # lo de siempre queda pegado abajo: al crecer, la cápsula sale arriba
        if self._shown:
            box = QRectF(0, y - GAP - self.pill_h, w, self.pill_h)
            self.pill.paint(p, box, self._hover, self._over_screen)
            self._hits.extend(self.pill.hits(box))
        for paint, height in ((self._paint_info, INFO_H), (self._paint_dock, DOCK_H)):
            card = QRectF(0, y, w, height)
            if paint == self._paint_info:  # la tarjeta de la información, con el cuerpo del reproductor; los iconos de abajo van sin fondo
                paint_glass(p, self.theme, card, INFO_R, fill=QColor(self.theme.plate_bottom), shadow=False)
            paint(p, card)
            y += height + GAP

    def _lit(self, name):
        return self._hover == name

    def _paint_info(self, p, box):
        """Toda la información en una tarjeta: la hora y la fecha (pulsar: el calendario), el clima de ahora y, debajo,
        la RAM y la batería."""
        t = self.theme
        left, right = box.left() + PAD_X, box.right() - PAD_X
        clock = QRectF(box.left(), box.top(), box.width() * 0.55, 84)
        self._hits.append(("clock", clock))
        if self._lit("clock"):
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(255, 255, 255, 12))
            p.drawRoundedRect(clock.adjusted(6, 6, -4, -2), 12, 12)
        now = datetime.datetime.now()
        p.setFont(font(t, BIG, bold=True))
        p.setPen(QColor(t.ink))
        p.drawText(QRectF(left, box.top() + 10, 170, 50), Qt.AlignVCenter, f"{now:%H:%M}")
        p.setFont(font(t, TEXT))
        p.setPen(QColor(t.dim))
        p.drawText(QRectF(left, box.top() + 58, box.width() * 0.5 - left, 24), Qt.AlignVCenter,
                   QFontMetrics(font(t, TEXT)).elidedText(long_date(now.date()).capitalize(), Qt.ElideRight, int(box.width() * 0.5 - left)))
        # el clima de ahora, a la derecha
        weather = self._weather
        if weather is None or "error" in weather:
            p.drawText(QRectF(box.center().x(), box.top() + 10, right - box.center().x(), 72), Qt.AlignVCenter | Qt.AlignRight
                       | Qt.TextWordWrap, (weather or {}).get("error", "Buscando el clima…"))
        else:
            p.setFont(font(t, MEDIUM, bold=True))
            p.setPen(QColor(t.ink))
            width = QFontMetrics(font(t, MEDIUM, bold=True)).horizontalAdvance(f"{weather['temp']}°")
            p.drawText(QRectF(right - width, box.top() + 14, width, 42), Qt.AlignVCenter | Qt.AlignRight, f"{weather['temp']}°")
            p.setPen(glyphs.pen(accent(t, True), 1.4))
            p.setBrush(Qt.NoBrush)
            (glyphs.WEATHER.get(weather.get("icon")) or glyphs.cloud)(
                p, QRectF(right - width - 10 - t.icon_px, box.top() + 14 + (42 - t.icon_px) / 2, t.icon_px, t.icon_px))
            p.setFont(font(t, TEXT))
            p.setPen(QColor(t.dim))
            text = f"{weather.get('text', '')} · {weather.get('place', '')}".strip(" ·")
            p.drawText(QRectF(box.center().x() + 4, box.top() + 58, right - box.center().x() - 4, 24),
                       Qt.AlignVCenter | Qt.AlignRight,
                       QFontMetrics(font(t, TEXT)).elidedText(text, Qt.ElideRight, int(right - box.center().x() - 4)))
        line = QColor(t.ink)
        line.setAlpha(22)
        p.fillRect(QRectF(left, box.top() + 92, right - left, 1), line)
        self._paint_meters(p, QRectF(box.left(), box.top() + 100, box.width(), box.height() - 100))

    def _paint_meters(self, p, box):
        """La RAM y la batería, una al lado de la otra: el porcentaje grande y debajo un detalle."""
        t = self.theme
        items = []
        if self._ram is not None:
            percent, used, total = self._ram
            detail = f"{used / 1e9:.1f} de {total / 1e9:.1f} GB" if used and total else "Memoria"
            items.append((glyphs.memory, f"{percent}%", detail, percent >= t.warn_at))
        if self._battery is not None:
            level, plugged = self._battery
            items.append((lambda q, r: glyphs.battery(q, r, level / 100, plugged), f"{level}%",
                          "Cargando" if plugged else "Con batería", level < LOW_BATTERY and not plugged))
        half = (box.width() - 2 * PAD_X) / 2
        for i, (glyph, value, detail, warn) in enumerate(items):
            x = box.left() + PAD_X + i * half
            p.setPen(glyphs.pen(QColor(t.warn) if warn else accent(t, True), 1.4))
            p.setBrush(Qt.NoBrush)
            glyph(p, QRectF(x, box.top() + 12, t.icon_px, t.icon_px))
            p.setFont(font(t, MEDIUM - 4, bold=True))
            p.setPen(QColor(t.warn if warn else t.ink))
            p.drawText(QRectF(x + t.icon_px + 10, box.top() + 4, half - t.icon_px - 14, 34), Qt.AlignVCenter, value)
            p.setFont(font(t, TEXT))
            p.setPen(QColor(t.dim))
            p.drawText(QRectF(x + t.icon_px + 10, box.top() + 38, half - t.icon_px - 14, 22), Qt.AlignVCenter, detail)

    def _paint_dock(self, p, box):
        """Abajo, solo los iconos: wifi, Bluetooth y ajustes en píldoras (la del wifi con red se enciende)."""
        t = self.theme
        connected = bool(self._wifi.get("connected"))
        items = (
            ("wifi", lambda q, r: glyphs.wifi(q, r, connected), connected),
            ("bluetooth", glyphs.bluetooth, self._bluetooth),
            ("config", glyphs.gear, False),
        )
        for i, (name, glyph, on) in enumerate(items):
            pill = QRectF(box.left() + PAD_X + i * (PILL_W + 10), box.top() + (box.height() - PILL_H) / 2, PILL_W, PILL_H)
            self._hits.append((name, pill))
            lit = self._lit(name)
            # skeumorfismo (ver DISEÑO.md): placa elevada con filete de luz arriba y sombra corta debajo. Lo que ya está
            # conectado se ve pulsado: el efecto inverso, hundido, con sombra por dentro y el acento encendido
            icon = QRectF(pill.center().x() - DOCK_ICON / 2, pill.center().y() - DOCK_ICON / 2 - 1, DOCK_ICON, DOCK_ICON)
            p.setBrush(Qt.NoBrush)
            if on:
                paint_well(p, t, pill, PILL_R)
                glow = QColor(t.gold)
                glow.setAlpha(46 if lit else 34)
                p.setPen(Qt.NoPen)
                p.setBrush(glow)
                p.drawRoundedRect(pill.adjusted(2, 3, -2, -2), PILL_R - 2, PILL_R - 2)
                p.setBrush(Qt.NoBrush)
                p.setPen(glyphs.pen(accent(t, True), 1.6))
                glyph(p, icon.translated(0, 1.5))  # el icono baja un poco, como el botón
            else:
                paint_glass(p, t, pill, PILL_R, hi=lit)
                p.setPen(glyphs.pen(QColor(0, 0, 0, 150), 1.5))
                glyph(p, icon.translated(0, 1.5))  # el icono, grabado con una sombra fina debajo
                p.setPen(glyphs.pen(QColor(t.ink) if lit else accent(t, False), 1.5))
                glyph(p, icon)


class Back(QAbstractButton):
    """La flechita de volver con el nombre de la página."""

    def __init__(self, theme, title):
        super().__init__()
        self.theme, self.title = theme, title
        self.setCursor(Qt.PointingHandCursor)
        self.setAttribute(Qt.WA_Hover)
        self.setFixedHeight(HEAD_H)
        self.setFocusPolicy(Qt.NoFocus)

    def sizeHint(self):
        return QSize(QFontMetrics(font(self.theme, bold=True)).horizontalAdvance(self.title) + 56, HEAD_H)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        if self.underMouse():
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(255, 255, 255, 18))
            p.drawRoundedRect(QRectF(self.rect()).adjusted(0, 2, 0, -2), 8, 8)
        p.setPen(glyphs.pen(accent(t, True), 1.4))
        p.setBrush(Qt.NoBrush)
        glyphs.arrow(p, QRectF(8, (HEAD_H - t.icon_px) / 2, t.icon_px, t.icon_px), "left")
        p.setFont(font(t, bold=True))
        p.setPen(QColor(t.ink))
        p.drawText(QRectF(36, 0, self.width() - 40, HEAD_H), Qt.AlignVCenter, self.title)


class QuickPage(DockPage):
    """Una página de detalle (wifi, Bluetooth, calendario, ajustes) con la flechita para volver arriba."""

    back = Signal()

    def __init__(self, theme, name, sub):
        super().__init__()
        self.sub = sub
        w, h = sub.size[0] - 2 * PAD, sub.size[1] - 2 * PAD  # las páginas se pensaron con su propio margen
        sub.setFixedSize(w, h)
        sub.close_requested.connect(self.close_requested)
        self.button = Back(theme, TITLES[name])
        self.button.clicked.connect(self.back)
        head = QHBoxLayout()
        head.setContentsMargins(0, 0, 0, 0)
        head.addWidget(self.button)
        head.addStretch(1)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(4)
        layout.addLayout(head)
        layout.addWidget(sub, 0, Qt.AlignHCenter)
        layout.addStretch(1)
        self.size = (2 * PAD + HEAD_H + 4 + h, w + 2 * PAD)

    def activate(self):
        self.sub.activate()

    def focus_first(self):
        self.sub.focus_first()


class QuickDock(PageDock):
    def __init__(self, theme, screen_map, invoke, config_data=dict, guard=None):
        main = QuickMain(theme)
        wifi, bluetooth = WifiPage(theme, invoke), BluetoothPage(theme, invoke)
        pages = {
            "main": main,
            "wifi": QuickPage(theme, "wifi", wifi),
            "bluetooth": QuickPage(theme, "bluetooth", bluetooth),
            "clock": QuickPage(theme, "clock", ClockPage(theme)),
            "config": QuickPage(theme, "config", ConfigPage(theme, invoke, config_data)),
        }
        super().__init__(theme, screen_map, pages, edge="bottom", title="KyoraQuick", extra=theme.dock_tab)
        self.main, self.wifi, self.bluetooth = main, wifi, bluetooth
        self._invoke = invoke
        main.refresh = lambda: invoke("bluetooth.status")
        self.model = {}
        self.suspended = False
        self._grow = Tween(self, self._set_grow, self._grown)  # el panel crece o se encoge con la música
        self._grow_from = self._grow_to = self._piece
        self._guard = guard  # esconde la barra de Windows si el cursor la hace salir por el borde de abajo
        main.go.connect(self.show_sub)
        main.music_control.connect(self._music_control)
        for name, page in pages.items():
            if name != "main":
                page.back.connect(lambda: self.show_sub("main"))
        self._hot = QTimer(self)
        self._hot.setInterval(HOT_MS)
        self._hot.timeout.connect(self._poll)
        self._hot.start()

    # ---------- datos del núcleo ----------

    def on_devices(self, data):
        self.model["devices"] = data
        self.main.apply(self.model)

    def on_weather(self, data):
        self.model["weather"] = data
        self.main.apply(self.model)

    def on_bluetooth(self, data):
        """El Bluetooth está conectado si está encendido y hay algún dispositivo conectado."""
        connected = bool(data.get("on")) and any(d.get("connected") for d in data.get("devices", []))
        if connected != self.model.get("bluetooth"):
            self.model["bluetooth"] = connected
            self.main.apply(self.model)

    def on_state(self, state):
        if state["wifi"] != self.model.get("wifi"):
            self.model["wifi"] = state["wifi"]
            self.main.apply(self.model)
        self.wifi.on_state(state)

    # ---------- lo que suena: la cápsula y el alto del panel ----------

    def on_playing(self, info):
        """`info` = {title, playing} o None (nada suena). Al empezar o acabar, el panel crece o se encoge."""
        if info is not None:
            self.main.pill_h = self._pill_fit()
        if self.main.set_music(info):
            self._fit_main()

    def _pill_fit(self):
        """Lo que puede medir la tarjeta de lo que suena para que el panel entero quepa: el alto de la pieza (el de su página
        más alta) y de la pantalla, menos lo de siempre (información e iconos). Nunca más que su alto normal ni menos que
        el mínimo con el que aún se ve todo."""
        room = min(self.depth, self.map.geometry.height() - self._shadow - PAD)
        return max(min(room - (INFO_H + DOCK_H + GAP + 2 * PAD) - GAP, MUSIC_H), MUSIC_MIN)

    def on_progress(self, pos, dur):
        self.main.on_progress(pos, dur)

    def on_level(self, level):
        self.main.on_level(level)

    def _music_control(self, what):
        """Detener: la cápsula se va y el panel se encoge dejando el cursor fuera de la pieza, y abierto por el ratón se
        cerraría. Como al pulsar una ficha, ya se usó el panel: se queda abierto hasta que se pulse fuera o Esc."""
        if what == "stop":
            self.show_page("main", None)

    def _fit_main(self):
        """Lleva la pieza al alto que pide la página principal: con animación si se está viendo; si no, al abrir ya estará."""
        on = self.main._music_on
        self._grow.stop()
        if not (self.opened and self.name == "main"):
            if not on:
                self.main.release_music()
            return
        target = self._target("main")
        if self._shot is not None or self._morph.running():  # se está abriendo o cambiando de página: sin animar
            self._piece = target
            if not on:
                self.main.release_music()
            return
        self._grow_from, self._grow_to = self._piece, target
        self._grow.start(0.0, 1.0, GROW_MS, QEasingCurve.OutCubic)

    def _set_grow(self, value):
        a, b = self._grow_from, self._grow_to
        self._piece = (lerp(a[0], b[0], value), lerp(a[1], b[1], value), lerp(a[2], b[2], value), False)
        self.body.setGeometry(self.body_rect().toAlignedRect())
        self.update()

    def _grown(self):
        self._piece = self._grow_to
        self.body.setGeometry(self.body_rect().toAlignedRect())
        if not self.main._music_on:
            self.main.release_music()
        self.update()

    def close_popout(self):
        if self._grow.running():  # se cierra a mitad de crecer: la pieza ya se queda en su alto final
            self._grow.stop()
            self._piece = self._grow_to
            if not self.main._music_on:
                self.main.release_music()
        super().close_popout()

    # ---------- geometría: a ras del borde derecho ----------

    def _target(self, name):
        depth, length = self.pages[name].size
        return self._along - length, self._along, depth, False

    # ---------- abrir con el cursor ----------

    def suspend(self, on):
        """Con el buscador, el modo de fondos o apagar abiertos, el panel no salta (y se esconde si estaba)."""
        self.suspended = on
        if on:
            self.close_popout()

    def _zone(self):
        g = self.map.geometry
        width = min(self.theme.top_zone, g.width())
        return QRect(g.x() + g.width() - width, g.y() + g.height() - ZONE_H, width, ZONE_H)

    def _poll(self):
        pos = QCursor.pos()
        g = self.map.geometry
        if self._guard is not None and pos.y() >= g.y() + g.height() - EDGE_BAND:
            self._guard()
        if self.opened or self.suspended:
            return
        zone = self._zone()
        if pos.y() < zone.bottom() - 1 or not zone.left() <= pos.x() <= zone.right() or _button_down():
            return
        self.show_page("main", zone)

    def show_sub(self, name):
        """Pulsar una ficha (o la flecha de volver): la pieza se transforma hacia su página. Ya se pulsó algo, así que el
        panel deja de cerrarse al quitar el cursor (si no, al volver a la principal, más pequeña, el cursor quedaría fuera
        y se cerraría): se queda hasta que se pulse fuera o Esc."""
        self.show_page(name, None)

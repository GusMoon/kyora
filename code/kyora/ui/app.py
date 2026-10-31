"""Arranque de la interfaz Qt: crea el contorno de la ventana activa, el panel superior y el buscador (que lleva dentro
las tareas, el Kanban y las notas), y los conecta con el núcleo. No hay marco: las ventanas usan toda la pantalla."""
import logging
import threading
import time

from PySide6.QtCore import QObject, QPoint, QTimer, Signal, Slot
from PySide6.QtWidgets import QApplication, QToolTip, QWidget

from kyora.ui.accent import palette_from_path, wallpaper_palette
from kyora.ui.dropzones import DropZones
from kyora.ui.frame import RingOverlay
from kyora.ui.leftdock import LeftDock
from kyora.ui.powerscreen import PowerScreen
from kyora.ui.quickdock import QuickDock
from kyora.ui.scrim import Scrim
from kyora.ui.search import SearchPopout, _css
from kyora.ui.switcher import WaitingStack
from kyora.ui.theme import THEME, Theme
from kyora.ui.topdock import ACTIONS, TopDock
from kyora.ui.transition import WindowTransition
from kyora.ui.wallpaper_mode import WallpaperMode
from kyora.ui.win import ScreenMap, hwnd_of

log = logging.getLogger("kyora.ui")

SIGNAL_POLL_MS = 300  # deja que Python atienda Ctrl+C aunque Qt tenga el control (y es el latido de la interfaz)
STALL_MS = 150  # un latido que llega más tarde que esto: la interfaz estuvo trabada
STALL_LOG_SECONDS = 10


class UiBridge(QObject):
    """Señales del núcleo a la interfaz. Se pueden emitir desde cualquier hilo: Qt las entrega en el suyo."""

    state_changed = Signal(object)
    search_open = Signal(str)  # con el modo: "", "task" o "notes"
    search_close = Signal()
    toast = Signal(str)
    drop_rect = Signal(object)
    focus_target = Signal(object)
    tiles_changed = Signal(object)
    switcher_toggle = Signal(object)
    power_toggle = Signal()
    devices_changed = Signal(object)
    weather_changed = Signal(object)
    wifi_result = Signal(object)
    music_panel = Signal()  # Win+M: la página de Música del panel de arriba
    music_result = Signal(object)
    chat_event = Signal(object)  # lo que pasa en el chat: mensajes, estados y conexión
    bluetooth_result = Signal(object)
    directory_event = Signal(object)
    desktops_overview = Signal(object)  # Win+Alt+↑/↓: los números de los escritorios
    transition_end = Signal()  # las apps ya están en su sitio
    slide = Signal(object)  # cambio de escritorio: {old, new, offset, done}
    wallpaper_mode = Signal(object)  # Win+W: {images, folder, current}
    desktops_hide = Signal()  # al soltar Win+Alt
    wallpaper_changed = Signal(str)  # el carrusel puso un fondo: se recolorea Kyora
    palette_ready = Signal(object)  # (turno, colores) calculados en un hilo
    quit = Signal()

    def __init__(self):
        super().__init__()
        self.quit.connect(self._quit_app)  # método de un objeto del hilo de Qt: la señal llega en ese hilo

    @Slot()
    def _quit_app(self):
        # exit() y no quit(): en Qt 6 quit() intenta cerrar todas las ventanas y la barra lo rechaza a propósito
        # (Alt+F4 sobre ella pide la salida ordenada), así que quit() se anulaba y el proceso seguía vivo.
        QApplication.exit(0)


def _app_style(t):
    return (
        f"QToolTip {{ background: {t.frame}; color: {t.ink}; border: 1px solid {_css(t.gold_line)};"
        f" border-radius: 6px; padding: 5px 8px; font: {t.font_px}px '{t.font_family}'; }}"
        f"QMenu {{ background: {t.frame}; color: {t.ink}; border: 1px solid {_css(t.line)}; padding: 4px;"
        f" font: {t.font_px}px '{t.font_family}'; }}"
        f"QMenu::item {{ padding: 6px 14px; border-radius: 6px; }}"
        f"QMenu::item:selected {{ background: {_css(t.gold_soft)}; color: {t.gold}; }}"
        f"QInputDialog, QInputDialog QLabel {{ background: {t.frame}; color: {t.ink}; font: {t.font_px}px '{t.font_family}'; }}"
        f"QInputDialog QLineEdit {{ background: {_css(t.field)}; color: {t.ink}; border: 1px solid {_css(t.line)};"
        f" border-radius: 8px; padding: 4px 8px; }}"
        f"QInputDialog QPushButton {{ background: {_css(t.hover)}; color: {t.ink}; border: 0; border-radius: 6px;"
        f" padding: 5px 14px; }}"
    )


def apply_theme(app, roots, theme):
    """Pone colores nuevos en marcha: cada pieza que guarda `theme` recibe el nuevo, las que rehacen hojas de estilo
    lo hacen (`retheme`), y todo se repinta. Los tamaños no cambian, así que nada se recoloca."""
    app.setStyleSheet(_app_style(theme))
    for root in roots:
        objects = [root] + (root.findChildren(QObject) if isinstance(root, QObject) else [])
        objects += getattr(root, "strips", [])  # el contorno de la ventana activa son cuatro ventanas sueltas
        for obj in objects:
            if isinstance(getattr(obj, "theme", None), Theme):
                obj.theme = theme
            hook = getattr(obj, "retheme", None)
            if callable(hook):
                hook(theme)
        for obj in objects:
            if isinstance(obj, QWidget):
                obj.update()


def build_ui(kyora, app, theme=THEME):
    """Crea las ventanas y las conecta; devuelve (puente, contorno, panel superior, buscador, selector de Win+R, otras
    ventanas propias)."""
    app.setQuitOnLastWindowClosed(False)
    base_theme = theme
    colors = wallpaper_palette()  # colores sacados del fondo de pantalla; sin él se quedan los del tema por defecto
    if colors:
        theme = base_theme.with_palette(colors)
        log.info("Colores tomados del fondo de pantalla (acento %s)", colors.get("accent"))
    app.setStyleSheet(_app_style(theme))
    screen_map = ScreenMap(app.primaryScreen())
    kyora.cfg["insets"] = tuple(screen_map.to_physical(v) for v in theme.insets())
    gap, single, multi = (screen_map.to_physical(v) for v in theme.margins())
    kyora.cfg.update(gap=gap, outer_gap=single, outer_gap_multi=multi)

    bridge = UiBridge()

    def call(action, **payload):  # acciones rápidas del núcleo, en el hilo de Qt (SQLite, una carpeta…)
        return kyora.registry.invoke(action, payload)

    def children(path):
        result = call("files.children", path=path)
        return result["data"] if result["ok"] else []

    ring = RingOverlay(theme, screen_map)
    top = TopDock(theme, screen_map, kyora.invoke_async)
    guard = kyora.taskbar.keep_hidden if kyora.cfg.get("hide_taskbar") else None
    quick = QuickDock(theme, screen_map, kyora.invoke_async, kyora.config_data, guard)
    search = SearchPopout(
        theme, screen_map,
        query=kyora.search_query,
        launch=lambda r, files=False: kyora.invoke_async("search.launch", kind=r["kind"], id=r["id"], files=files),
        close=lambda refocus: kyora.invoke_async("search.close", refocus=refocus),
        set_wallpaper=lambda path: kyora.invoke_async("wallpaper.set", path=path),
        children=children,
        act=lambda kind, id: call("search.launch", kind=kind, id=id),
        call=call,
    )
    def open_section(name):
        """Una sección de la píldora que está dentro del buscador: Música cierra el buscador y abre su página arriba; las
        demás piden lo mismo que su atajo (el buscador cambia de modo sin cerrarse)."""
        if name == "music":
            kyora.invoke_async("search.close", refocus=False)
            kyora.invoke_async("music.panel")
        else:
            action, payload = ACTIONS[name]
            kyora.invoke_async(action, **payload)

    search.on_section = open_section
    switcher = WaitingStack(
        theme, screen_map,
        items=kyora.switcher_items,
        thumb=kyora.manager.thumbnail,
        invoke=kyora.invoke_async,
    )
    left = LeftDock(theme, screen_map, kyora.invoke_async, kyora.manager.thumbnail)
    drops = DropZones(theme, screen_map)  # los huecos del mosaico mientras se arrastra una ventana
    bridge.drop_rect.connect(drops.show_zones)
    bridge.music_panel.connect(lambda: top.close_popout() if top.opened and top.name == "music" else top.show_page("music"))
    scrim = Scrim(theme, screen_map)  # oscurece la pantalla mientras hay un panel fuera
    top.page_changed.connect(lambda name: scrim.want("top", top, bool(name)))
    quick.page_changed.connect(lambda name: scrim.want("quick", quick, bool(name)))
    left.page_changed.connect(lambda name: scrim.want("left", left, bool(name) and not left.peeking))
    power = PowerScreen(theme, screen_map, kyora.invoke_async)
    wallpapers = WallpaperMode(theme, screen_map, kyora.invoke_async, lambda path: bridge.wallpaper_changed.emit(path))
    # panel superior (accesos y música) al acercar el cursor al borde de arriba; el de la esquina de abajo a la derecha
    # lleva lo del sistema: hora, clima, wifi, Bluetooth, RAM, batería y ajustes
    bridge.music_result.connect(top.music.on_result)
    # lo que suena se ve en la cápsula del panel de abajo (no en el de arriba): título, tiempo, ondas y sus dos botones
    top.music.playing_changed.connect(quick.on_playing)
    top.music.progress_changed.connect(quick.on_progress)
    top.music.level_changed.connect(quick.on_level)
    music_controls = {"toggle": top.music.toggle_playback, "stop": top.music.stop_playback,
                      "prev": top.music.previous_track, "next": top.music.next_track}
    quick.main.music_control.connect(lambda what: music_controls[what]())
    bridge.state_changed.connect(quick.on_state)
    bridge.wifi_result.connect(quick.wifi.on_result)
    bridge.bluetooth_result.connect(quick.bluetooth.on_result)
    bridge.bluetooth_result.connect(quick.on_bluetooth)
    bridge.devices_changed.connect(quick.on_devices)
    bridge.weather_changed.connect(quick.on_weather)
    # las ventanas fantasma: se acomodan primero y las apps se colocan debajo
    transition = WindowTransition(theme, screen_map)
    bridge.transition_end.connect(transition.finish)
    bridge.slide.connect(transition.slide)  # el cambio de escritorio desliza la pantalla
    bridge.slide.connect(lambda _: QTimer.singleShot(0, lambda: left.raise_() if left.opened else None))  # el panel va por encima
    transition.slid.connect(left.follow)  # y su luz se mueve con el deslizamiento, en tiempo real
    bridge.switcher_toggle.connect(switcher.toggle)
    # panel izquierdo: las ventanas que no se ven y el número del escritorio (asoma al cambiar de escritorio)
    bridge.state_changed.connect(left.on_state)
    bridge.desktops_overview.connect(left.peek)

    def suspend_docks(on):
        """Con el buscador, apagar o los fondos abiertos, los paneles de los bordes no saltan."""
        top.suspend(on)
        quick.suspend(on)
        left.suspend(on)

    # el buscador ocupa el sitio del panel superior
    bridge.search_open.connect(lambda mode: suspend_docks(True))
    bridge.search_open.connect(search.open)
    bridge.search_open.connect(lambda mode: scrim.want("search", search, True))
    bridge.search_close.connect(search.close_popout)
    bridge.search_close.connect(lambda: scrim.want("search", search, False))
    bridge.search_close.connect(lambda: suspend_docks(False))
    bridge.power_toggle.connect(power.toggle)  # Win+X
    power.visibility.connect(suspend_docks)
    bridge.wallpaper_mode.connect(wallpapers.open)  # Win+W
    wallpapers.visibility.connect(suspend_docks)

    def toast(message):
        g = screen_map.geometry
        QToolTip.showText(QPoint(g.center().x(), g.y() + 90), message)

    bridge.toast.connect(toast)
    bridge.chat_event.connect(search.chat.on_event)  # el chat: mensajes nuevos, estados y conexión
    search.chat.notify.connect(toast)
    bridge.focus_target.connect(ring.set_focus_target)

    # colores en marcha: el carrusel de fondos pone un fondo -> se sacan sus colores en un hilo -> se aplican
    roots = [ring, top, quick, left, search, switcher, transition, power, wallpapers, drops]  # el velo es negro: no tiene colores
    turn = {"n": 0}  # solo vale la última petición (varias flechas seguidas)

    def wallpaper_changed(path):
        turn["n"] += 1
        n = turn["n"]
        threading.Thread(target=lambda: bridge.palette_ready.emit((n, palette_from_path(path))), daemon=True,
                         name="kyora-palette").start()

    def palette_ready(item):
        n, colors = item
        if n == turn["n"] and colors:
            apply_theme(app, roots, base_theme.with_palette(colors))
            transition.refresh_wallpaper()  # el fondo nítido de las pantallas de arrastre, por si cambió

    bridge.wallpaper_changed.connect(wallpaper_changed)
    bridge.palette_ready.connect(palette_ready)
    kyora.ui = bridge
    return bridge, ring, top, search, switcher, (transition, left, left.ghost, power, wallpapers, scrim, drops, quick)


def run_ui(kyora):
    app = QApplication.instance() or QApplication([])
    _, ring, top, search, switcher, panels = build_ui(kyora, app)
    own = [hwnd_of(w) for w in (*ring.strips, top, search, switcher, *panels)]

    def start_core():
        try:
            kyora.start(own)
        except Exception:
            log.exception("Kyora no pudo arrancar")
            kyora.release()

    QTimer.singleShot(0, lambda: threading.Thread(target=start_core, daemon=True, name="kyora-start").start())
    keepalive = QTimer()
    keepalive.timeout.connect(watchdog(time.monotonic))
    keepalive.start(SIGNAL_POLL_MS)
    return app.exec()


def watchdog(clock, log_every=STALL_LOG_SECONDS):
    """El latido de la interfaz: si un tic llega con mucho retraso, la interfaz estuvo trabada; se anota en kyora.log
    (como mucho un aviso cada `log_every` segundos) para saber qué la alenta."""
    state = {"last": clock(), "worst": 0.0, "count": 0, "logged": float("-inf")}

    def beat():
        now = clock()
        late = (now - state["last"]) * 1000 - SIGNAL_POLL_MS
        state["last"] = now
        if late > STALL_MS:
            state["count"] += 1
            state["worst"] = max(state["worst"], late)
        if state["count"] and now - state["logged"] > log_every:
            log.info("La interfaz se trabó %s veces (la peor, %.0f ms)", state["count"], state["worst"])
            state.update(count=0, worst=0.0, logged=now)

    return beat

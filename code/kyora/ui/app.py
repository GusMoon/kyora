"""Arranque de la interfaz Qt: crea el marco, el contorno, la barra, sus paneles, el panel de arriba y el buscador, y
los conecta con el núcleo."""
import logging
import threading

from PySide6.QtCore import QObject, QTimer, Signal, Slot
from PySide6.QtWidgets import QApplication

from kyora.ui.accent import wallpaper_accent
from kyora.ui.bar import SideBar
from kyora.ui.dock import BarDock
from kyora.ui.frame import FrameOverlay, RingOverlay
from kyora.ui.hub.panel import KyoraHub
from kyora.ui.panels import BluetoothPage, CalendarPage, PowerPage
from kyora.ui.search import SearchPopout, _css
from kyora.ui.switcher import WaitingStack
from kyora.ui.theme import THEME
from kyora.ui.wifi_panel import WifiPage
from kyora.ui.win import ScreenMap, hwnd_of

log = logging.getLogger("kyora.ui")

SIGNAL_POLL_MS = 300  # deja que Python atienda Ctrl+C aunque Qt tenga el control


class UiBridge(QObject):
    """Señales del núcleo a la interfaz. Se pueden emitir desde cualquier hilo: Qt las entrega en el suyo."""

    state_changed = Signal(object)
    search_open = Signal()
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
    bluetooth_result = Signal(object)
    hub_toggle = Signal(str)
    directory_event = Signal(object)
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


def build_ui(kyora, app, theme=THEME):
    """Crea las ventanas y las conecta; devuelve (puente, marco, contorno, barra, buscador, panel de espera, paneles)."""
    app.setQuitOnLastWindowClosed(False)
    accent = wallpaper_accent()  # el color principal del fondo de pantalla; sin él se queda el acento por defecto
    if accent:
        theme = theme.with_accent(accent)
        log.info("Acento tomado del fondo de pantalla: %s", accent)
    app.setStyleSheet(_app_style(theme))
    screen_map = ScreenMap(app.primaryScreen())
    kyora.cfg["insets"] = tuple(screen_map.to_physical(v) for v in theme.insets())
    gap, single, multi = (screen_map.to_physical(v) for v in theme.margins())
    kyora.cfg.update(gap=gap, outer_gap=single, outer_gap_multi=multi)

    bridge = UiBridge()
    frame = FrameOverlay(theme, screen_map)
    ring = RingOverlay(theme, screen_map)
    bar = SideBar(theme, screen_map, kyora.invoke_async)
    search = SearchPopout(
        theme, screen_map,
        query=kyora.search_query,
        launch=lambda r: kyora.invoke_async("search.launch", kind=r["kind"], id=r["id"]),
        close=lambda refocus: kyora.invoke_async("search.close", refocus=refocus),
    )
    switcher = WaitingStack(
        theme, screen_map,
        items=kyora.switcher_items,
        thumb=kyora.manager.thumbnail,
        invoke=kyora.invoke_async,
    )
    # paneles de la barra: se abren al pasar el ratón por su icono (y el de apagar también con Win+X)
    wifi = WifiPage(theme, kyora.invoke_async)
    bluetooth = BluetoothPage(theme, kyora.invoke_async)
    dock = BarDock(theme, screen_map, {
        "power": PowerPage(theme, kyora.invoke_async), "wifi": wifi, "bluetooth": bluetooth, "calendar": CalendarPage(theme),
    })
    bar.panel_hover.connect(dock.show_page)  # el mismo panel: se abre o se transforma hacia la página nueva

    def power_key():
        if dock.opened and dock.name == "power" and not dock.hover:
            dock.close_popout()
        else:
            dock.show_page("power", bar.power_anchor())

    bridge.power_toggle.connect(power_key)
    bridge.state_changed.connect(wifi.on_state)
    bridge.wifi_result.connect(wifi.on_result)
    bridge.bluetooth_result.connect(bluetooth.on_result)
    # panel de arriba: Archivos, Sistema y Kyora
    hub = KyoraHub(theme, screen_map, call=lambda action, **payload: kyora.registry.invoke(action, payload),
                   invoke=kyora.invoke_async)
    bridge.hub_toggle.connect(hub.toggle_section)
    bridge.directory_event.connect(hub.on_directory)
    bridge.devices_changed.connect(hub.on_devices)
    bridge.weather_changed.connect(hub.on_weather)
    bridge.switcher_toggle.connect(switcher.toggle)
    bridge.state_changed.connect(bar.on_state)
    bridge.search_open.connect(search.open)
    bridge.search_close.connect(search.close_popout)
    bridge.toast.connect(bar.toast)
    bridge.drop_rect.connect(frame.set_drop)
    bridge.focus_target.connect(ring.set_focus_target)
    bridge.tiles_changed.connect(frame.set_tiles)
    kyora.ui = bridge
    return bridge, frame, ring, bar, search, switcher, (dock, hub)


def run_ui(kyora):
    app = QApplication.instance() or QApplication([])
    _, frame, ring, bar, search, switcher, panels = build_ui(kyora, app)
    frame.show()
    bar.show()
    own = [hwnd_of(w) for w in (frame, *ring.strips, bar, search, switcher, *panels)]

    def start_core():
        try:
            kyora.start(own)
        except Exception:
            log.exception("Kyora no pudo arrancar")
            kyora.release()

    QTimer.singleShot(0, lambda: threading.Thread(target=start_core, daemon=True, name="kyora-start").start())
    keepalive = QTimer()
    keepalive.timeout.connect(lambda: None)
    keepalive.start(SIGNAL_POLL_MS)
    return app.exec()

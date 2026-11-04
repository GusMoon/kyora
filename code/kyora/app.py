"""Arranque de Kyora: junta la interfaz (Qt), el gestor de ventanas, los atajos y las acciones.

La interfaz vive en el hilo principal (Qt). Los hilos de Windows (avisos, atajos, wifi...) le hablan
solo con señales de `UiBridge`, que Qt entrega en el hilo principal.
"""
import argparse
import atexit
import ctypes
import logging
import logging.handlers
import os
import queue
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

import pythoncom
import pywintypes
import win32api
import win32event
import winerror

from kyora import config as config_module
from kyora.brain.service import BrainService
from kyora.chat.service import ChatService
from kyora.music.sync import MusicSync
from kyora.core.actions import ActionError, ActionRegistry
from kyora.core.commands import (
    KYORA_OPTIONS,
    config_data,
)
from kyora.core.hotkey_edit import normalize as normalize_combo
from kyora.directory.service import DirectoryService
from kyora.music.service import MusicService
from kyora.notes.service import NotesService
from kyora.search import folders, web
from kyora.search.apps import AppIndex, score
from kyora.search.files_index import FileIndex, default_roots
from kyora.system import (
    audio,
    bluetooth,
    browsers,
    display,
    launch,
    shell,
    snap,
    stats,
    wallpaper,
    weather,
    wifi,
    wlan,
)
from kyora.system.events import EVENT_MOVESIZEEND, EVENT_MOVESIZESTART, EventHook
from kyora.system.hotkeys import Hotkeys, split_bindings
from kyora.system.keys import KeyHookProcess
from kyora.system.win32 import Taskbar, Win32System, make_dpi_aware
from kyora.tasks.service import TaskService
from kyora.wm.manager import RESIZE_THRESHOLD, WindowManager

log = logging.getLogger("kyora")

SYNC_DEBOUNCE = 0.12
PUSH_DEBOUNCE = 0.05
WIFI_INTERVAL = 30
TASKBAR_INTERVAL = 0.2  # Explorer la muestra con la tecla Windows: se vuelve a ocultar enseguida
DRAG_TIMEOUT = 30
TRACK_INTERVAL = 0.03  # seguimiento del cursor mientras se arrastra
FOCUS_INTERVAL = 0.1  # foco con el ratón: el cursor debe quedarse quieto 2 pasos
RING_INTERVAL = 0.04  # cada cuánto se mira qué ventana tiene el foco para rodearla
RING_IDLE_INTERVAL = 0.15  # lo mismo cuando lleva un rato sin cambiar nada
RING_QUIET_AFTER = 1.0  # segundos sin cambios para pasar al intervalo lento
TRANSITION_WAIT = 0.7  # lo máximo que se espera a que las ventanas fantasma lleguen a su hueco
WINDOWS_CACHE_SECONDS = 1.0  # el buscador reutiliza la lista de ventanas mientras se escribe
SEARCH_RESULTS = 6
MIXED_FOLDERS = 3  # sin prefijo, las carpetas y archivos que se suman a las ventanas y apps
MIXED_FILES = 4
MIXED_PATHS = MIXED_FOLDERS + MIXED_FILES
RESTART_WAIT = 15  # segundos que una Kyora nueva (--restart) espera a que se cierre la anterior
DEVICES_INTERVAL = 2  # segundos entre lecturas de CPU, RAM y volumen
DISK_EVERY = 30  # el disco, cada tantas lecturas (1 minuto)
BRIGHTNESS_EVERY = 5  # el brillo (WMI, más lento), cada tantas lecturas
WEATHER_INTERVAL = 30 * 60
WEATHER_RETRY = 5 * 60


def setup_logging():
    handler = logging.handlers.RotatingFileHandler(
        config_module.data_dir() / "kyora.log", maxBytes=500_000, backupCount=2, encoding="utf-8"
    )
    handlers = [handler]
    if sys.stderr:  # con pythonw (sin consola) no hay salida de error: solo se escribe el archivo
        handlers.append(logging.StreamHandler())
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s", handlers=handlers)


def _volume(state):
    return {"volume": state["level"], "muted": state["muted"]}


def _as_tuple(rect):
    return (rect.left, rect.top, rect.right, rect.bottom) if rect else None


OPTIONS = ("light_mode",)  # los ajustes que la página de configuración puede cambiar


class Kyora:
    def __init__(self, cfg):
        self.cfg = cfg
        self.system = Win32System(cfg)
        self.taskbar = Taskbar()
        self.manager = WindowManager(self.system, cfg, notify=self._request_push)
        self.system.transition_done = self._transition_done
        self.system.slide = self._slide
        self.index = AppIndex()
        self.files = FileIndex(lambda: default_roots(folders.drives))  # "/carpeta" y "@archivo" del buscador
        self.registry = ActionRegistry()
        self.ui = None  # UiBridge: se crea al arrancar la interfaz
        self.hook = None
        self.hotkeys = None
        self.winkey = None
        self.wifi = dict(wifi.OFF)
        self.search_open = False
        self._search_mode = ""  # "", "task" o "notes": cómo se abrió el buscador
        self.devices = {}  # CPU, RAM, disco, volumen y brillo: lo que muestra la barra
        self._device_jobs = queue.Queue()  # cambios de volumen y brillo: los hace el hilo de dispositivos (COM)
        self._history = stats.History()  # CPU y RAM de los últimos minutos, para la gráfica de Sistema
        self._moving = 0  # ventana (con el mosaico hecho) que el usuario está arrastrando
        self._ffm_on = threading.Event()
        if cfg["focus_follows_mouse"]:
            self._ffm_on.set()
        self._ui_lock = threading.Lock()
        self._stop = threading.Event()
        self._sync_needed = threading.Event()
        self._ring_wake = threading.Event()  # un aviso de Windows: el contorno mira ya, sin esperar su turno
        self._windows_cache = (0.0, [])  # (cuándo, lista de ventanas) para el buscador
        self._push_needed = threading.Event()
        self._down = False
        self._down_lock = threading.Lock()
        self._wallpaper_lock = threading.Lock()
        self.directory = DirectoryService(
            config_module.data_dir(), lambda event: self._emit("directory_event", event),
            shell.known_folder, shell.recycle, shell.open_with,
        )
        self.tasks = TaskService(config_module.data_dir())
        self.brain = BrainService(config_module.data_dir(), shell.recycle, documents=shell.known_folder("documents"))
        self.notes = NotesService(shell.known_folder("documents"), shell.recycle)
        # «Descargar» ya no guarda en la carpeta Música: baja a una carpeta temporal y lo manda a quien elijas
        self.music = MusicService(
            config_module.data_dir(), Path(tempfile.gettempdir()) / "Kyora" / "music",
            lambda: self.cfg.get("music"), lambda result: self._emit("music_result", result),
        )
        self.chat = ChatService(config_module.data_dir(), lambda event: self._emit("chat_event", event),
                                lambda: self.cfg.get("chat"))
        # lo que se baja en Música sube solo a tu cuenta de Supabase, y la app del móvil lo ve (con la sesión del chat)
        self.music_sync = MusicSync(config_module.data_dir(), self.chat, lambda result: self._emit("music_result", result),
                                    lambda: self.cfg.get("music"))
        self.music.on_done = self.music_sync.enqueue
        self.music.can_send = self.music_sync.enabled
        self.music.uploaded = self.music_sync.is_uploaded
        self.music.fetch_recipients = self.music_sync.recipients
        self.music_sync.on_sent = self.music.mark_sent
        self.music_sync.on_failed = self.music.mark_failed
        self._register_actions()

    # ---------- acciones ----------

    def _register_actions(self):
        r, m = self.registry, self.manager
        r.register("state.get", self.get_state)
        r.register("wm.focus", lambda dir: m.focus_dir(dir))
        r.register("wm.move", lambda dir: m.move_dir(dir))
        r.register("wm.orientation_toggle", m.orientation_toggle)
        r.register("wm.flip", m.flip)
        r.register("wm.zoom_toggle", m.zoom_toggle)
        r.register("wm.focus_next", m.focus_next)
        r.register("wm.rotate", m.rotate)
        r.register("wm.arrange", lambda dir: m.arrange(dir))  # Win+Alt+flechas
        r.register("wm.bring_to", lambda hwnd, x=None, y=None: m.bring_to(int(hwnd), x, y))  # desde el panel izquierdo
        r.register("wm.park", m.park)
        r.register("wm.close", m.close_focused, destructive=True)
        r.register("wm.float_toggle", m.float_toggle)
        r.register("wm.retile", m.retile)
        r.register("wm.unpark", lambda hwnd: m.unpark(hwnd))
        r.register("wm.activate", lambda hwnd: m.activate(hwnd))
        r.register("wm.drag", self.drag)
        r.register("wm.move_to_slot", lambda slot, hwnd=0: m.move_to_slot(slot, hwnd))
        r.register("wm.resize", lambda dir: m.resize(dir))
        r.register("wm.close_window", lambda hwnd: m.close_window(hwnd), destructive=True)
        r.register("wm.close_all", self.close_all, destructive=True)
        r.register("wm.refocus", m.refocus)
        r.register("wm.solo", m.solo)
        r.register("wm.show_count", lambda n: m.show_count(n))
        r.register("wm.unpark_next", m.unpark_next)
        r.register("wm.park_last", m.park_last)
        r.register("switcher.toggle", self.toggle_switcher)
        r.register("switcher.pick", self.switcher_pick)
        r.register("wm.swap_into_focused", lambda hwnd: m.swap_into_focused(hwnd))
        r.register("wm.send_to_desktop", lambda index: m.send_to_desktop(index))
        r.register("desktop.switch", self.desktop_switch)
        r.register("desktop.step", self.desktop_step)
        r.register("desktop.overview_hide", lambda: self._emit("desktops_hide"))
        r.register("desktop.create", self.desktop_create)
        r.register("desktop.rename", lambda index, name: m.desktop_rename(index, name))
        r.register("desktop.close", lambda index: m.desktop_close(index))
        r.register("desktop.close_current", lambda: m.desktop_close(m.active))
        r.register("power.menu", self.toggle_power)
        r.register("system.shutdown", lambda: self.power_off(restart=False), destructive=True)
        r.register("system.restart", lambda: self.power_off(restart=True), destructive=True)
        r.register("system.sleep", self.sleep)
        r.register("app.restart", self.restart)
        self.directory.register(r)
        self.tasks.register(r)
        self.brain.register(r)
        self.notes.register(r)
        self.music.register(r)
        self.chat.register(r)
        r.register("music.panel", lambda: self._emit("music_panel"))
        r.register("bluetooth.status", self.bluetooth_status)
        r.register("bluetooth.set", self.bluetooth_set)
        r.register("wifi.networks", self.wifi_networks)
        r.register("wifi.connect", self.wifi_connect)
        r.register("wifi.disconnect", self.wifi_disconnect)
        r.register("audio.set", self.set_audio)
        r.register("display.set_brightness", self.set_brightness)
        r.register("system.stats", lambda: dict(self.devices))
        r.register("app.run_script", self.run_script)
        r.register("search.open", self.open_search)
        r.register("search.close", self.close_search)
        r.register("search.toggle", self.toggle_search)
        r.register("search.open_mode", lambda mode: self.toggle_search(mode))
        r.register("search.query", self.search_query)
        r.register("search.launch", self.search_launch)
        r.register("wallpaper.set", self.set_wallpaper)
        r.register("wallpaper.mode", self.wallpaper_mode)  # Win+W
        r.register("files.children", self.files_children)
        r.register("files.roots", self.files_roots)
        r.register("app.focus_follows_mouse", self.focus_follows_mouse)
        r.register("app.release", self.release, destructive=True)
        r.register("app.quit", self.quit)
        r.register("config.set_hotkeys", self.set_hotkeys)
        r.register("config.reset_hotkeys", self.reset_hotkeys)
        r.register("config.set_option", self.set_option)
        r.register("config.set_web_shortcuts", self.set_web_shortcuts)
        r.register("config.set_default_browser", self.set_default_browser)

    def invoke_async(self, action, **payload):
        """Lo usan los botones de la interfaz: la acción corre fuera del hilo de Qt para no congelarla."""

        def run():
            result = self.registry.invoke(action, payload)
            if not result["ok"]:
                log.warning("Acción %s: %s", action, result["error"]["message"])
                self._emit("toast", result["error"]["message"])

        threading.Thread(target=run, daemon=True, name="kyora-action").start()

    def _emit(self, name, *args):
        if self.ui is not None:
            getattr(self.ui, name).emit(*args)

    def _transition_done(self):
        self._emit("transition_end")

    def _slide(self, payload):
        """Desliza lo que hay en pantalla al escritorio de al lado (ver ui/transition.py) y espera a que llegue; las
        ventanas del escritorio nuevo se muestran después, debajo. False si no hay interfaz o tardó demasiado."""
        if self.ui is None:
            return False
        done = threading.Event()
        self._emit("slide", {**payload, "done": done})
        return done.wait(TRANSITION_WAIT)

    def get_state(self):
        state = self.manager.snapshot()
        state.update(
            wifi=self.wifi,
            search_open=self.search_open,
            indexing=not self.index.ready.is_set(),
            hotkey_failures=self.hotkeys.failed if self.hotkeys else [],
            focus_follows_mouse=self._ffm_on.is_set(),
        )
        return state

    def desktop_step(self, delta):
        """Ctrl+Shift+RePág/AvPág: va al escritorio de al lado. Los números salen antes de que la pantalla se deslice, para que se
        vean mientras tanto."""
        target = self.manager.active + delta
        if 0 <= target < len(self.manager.desktops):
            self._emit("desktops_overview", self.desktops_overview(target))
        self.manager.desktop_step(delta)

    def desktop_switch(self, index):
        index = int(index)
        if 0 <= index < len(self.manager.desktops) and index != self.manager.active:
            self._emit("desktops_overview", self.desktops_overview(index))
        self.manager.desktop_switch(index)

    def desktop_create(self):
        """Ctrl+Shift+E: un escritorio nuevo (y se va a él); sus números salen mientras la pantalla se desliza."""
        count = len(self.manager.desktops)
        self._emit("desktops_overview", [{"index": i, "active": i == count} for i in range(count + 1)])
        return self.manager.desktop_create()

    def desktops_overview(self, active=None):
        """[{index, active}] de cada escritorio, para sus números (con `active`, como quedarán tras el cambio)."""
        rows = self.manager.snapshot()["desktops"]
        return [{"index": d["index"], "active": (d["index"] == active) if active is not None else d["active"]}
                for d in rows]

    def close_all(self):
        """Cierra todas las ventanas de todos los escritorios (Ctrl+Shift+Alt+X)."""
        return self.manager.close_all()

    # ---------- wifi: las respuestas llegan a la interfaz con la señal wifi_result ----------

    def wifi_networks(self, scan=True):
        try:
            if scan:
                wlan.scan()
            result = {"kind": "networks", "networks": wlan.networks()}
        except wlan.LocationDenied:
            result = {"kind": "networks", "networks": [], "location": True,
                      "error": "Windows solo deja ver las redes si las apps de escritorio pueden usar la ubicación"}
        except OSError as err:
            result = {"kind": "networks", "networks": [], "error": str(err)}
        self._emit("wifi_result", result)

    def wifi_connect(self, ssid, password=None):
        try:
            state = wlan.connect(ssid, password or None)
            result = {"kind": "connect", "ok": True, "ssid": ssid, "message": f"Conectado a {ssid}"}
            self.wifi = state
        except (OSError, ValueError) as err:
            result = {"kind": "connect", "ok": False, "ssid": ssid, "message": str(err)}
        self._emit("wifi_result", result)
        self._request_push()
        self.wifi_networks(scan=False)

    def wifi_disconnect(self):
        wlan.disconnect()
        self.wifi = wifi.status()
        self._request_push()
        self.wifi_networks(scan=False)

    # ---------- Bluetooth: la respuesta llega a la interfaz con la señal bluetooth_result ----------

    def bluetooth_status(self):
        try:
            self._emit("bluetooth_result", bluetooth.status())
        except OSError as err:
            self._emit("bluetooth_result", {"available": False, "on": False, "devices": [], "error": str(err)})

    def bluetooth_set(self, on):
        try:
            self._emit("bluetooth_result", bluetooth.set_radio(bool(on)))
        except OSError as err:
            self._emit("toast", str(err))
            self.bluetooth_status()

    # ---------- datos del equipo: CPU, RAM, disco, volumen, brillo y clima ----------

    def set_audio(self, level=None, muted=None, delta=None):
        """Volumen 0-100 (`level`, o `delta` sobre el actual) y/o silencio. Lo aplica el hilo de dispositivos."""
        self._device_jobs.put(("audio", level, muted, delta))

    def set_brightness(self, level=None, delta=None):
        if self.devices.get("brightness") is None:
            raise ActionError("no_brightness", "Esta pantalla no deja cambiar el brillo")
        self._device_jobs.put(("brightness", level, None, delta))

    def _device_job(self, job):
        kind, level, muted, delta = job
        if kind == "audio":
            if delta is not None:
                level = self.devices.get("volume", 0) + delta
            self.devices.update(_volume(audio.set_volume(level=level, muted=muted)))
        else:
            if delta is not None:
                level = (self.devices.get("brightness") or 0) + delta
            self.devices["brightness"] = display.set_brightness(level)

    def _devices_loop(self):
        """Lee el equipo cada pocos segundos y aplica los cambios pedidos. Es el único hilo que usa COM para esto."""
        pythoncom.CoInitialize()
        tick = 0
        while not self._stop.is_set():
            try:
                job = self._device_jobs.get(timeout=DEVICES_INTERVAL)
            except queue.Empty:
                job = None
            if self._stop.is_set():
                return
            before = dict(self.devices)
            try:
                if job:
                    self._device_job(job)
                else:
                    usage = stats.usage(disk=tick % DISK_EVERY == 0)
                    self._history.add(usage)
                    self.devices.update(usage, history=self._history.as_dict())
                    self.devices.update(_volume(audio.get()))
                    if tick % BRIGHTNESS_EVERY == 0:
                        self.devices["brightness"] = display.get()
                    tick += 1
            except (OSError, ValueError, pywintypes.com_error) as err:
                log.warning("Lectura del equipo: %s", err)
                if job:
                    self._emit("toast", f"No se pudo cambiar: {err}")
            if self.devices != before:
                self._emit("devices_changed", dict(self.devices))

    def _weather_loop(self):
        city = (self.cfg.get("weather") or {}).get("city", "").strip()  # vacía: se usa la ubicación de la IP
        cache = config_module.data_dir() / "weather.json"
        while not self._stop.is_set():
            try:
                self._emit("weather_changed", weather.current(city, cache))
                wait = WEATHER_INTERVAL
            except (OSError, LookupError, ValueError) as err:  # sin red, ciudad desconocida o respuesta rara
                log.warning("Clima: %s", err)
                if not city and isinstance(err, LookupError):
                    text = 'No se pudo saber dónde estás: pon tu ciudad en config.json ("weather": {"city": "…"})'
                else:
                    text = f"Sin clima: {err}"
                self._emit("weather_changed", {"error": text})
                wait = WEATHER_RETRY
            self._stop.wait(wait)

    # ---------- energía y la propia Kyora ----------

    def toggle_power(self):
        self._emit("power_toggle")

    def power_off(self, restart):
        """Devuelve todo a Windows (así los avisos de "¿guardar?" se ven) y apaga o reinicia el equipo."""
        self.shutdown()
        subprocess.Popen(["shutdown", "/r" if restart else "/s", "/t", "0"], creationflags=launch.CREATE_NO_WINDOW)
        self._emit("quit")

    @staticmethod
    def sleep():
        ctypes.windll.powrprof.SetSuspendState(False, False, False)  # vuelve cuando el equipo despierta

    def restart(self):
        launch.relaunch()  # la nueva espera a que esta suelte el mutex
        self.release()

    def run_script(self, name):
        if name not in launch.SCRIPTS:
            raise ActionError("unknown_script", f"No existe el script {name}")
        if launch.closes_kyora(name):
            self.shutdown()
            launch.run_script(name)
            self._emit("quit")
        else:
            launch.run_script(name)

    # ---------- búsqueda ----------

    def open_search(self, mode=""):
        """Abre el buscador; con `mode` ("task" o "notes", de Ctrl+Shift+T y Ctrl+Shift+N) se abre directamente en ese modo."""
        with self._ui_lock:
            if self.search_open and mode == self._search_mode:
                return
            self.search_open = True
            self._search_mode = mode
        self._emit("search_open", mode)
        self._request_push()

    def close_search(self, refocus=True):
        with self._ui_lock:
            if not self.search_open:
                return
            self.search_open = False
            self._search_mode = ""
        self._emit("search_close")
        if refocus:
            self.manager.refocus()
        self._request_push()

    def toggle_search(self, mode=""):
        """Ctrl+Shift+Espacio, T o N: abre el buscador o el modo pedido; el mismo atajo otra vez lo cierra."""
        if self.search_open and mode == self._search_mode:
            self.close_search()
        else:
            self.open_search(mode)

    def config_data(self):
        """Lo que enseña la página de configuración (el botón de la barra de arriba): los atajos, por secciones o por su
        tecla principal, y los ejecutables."""
        data = config_data(self.cfg["hotkeys"])
        folder, images = folders.wallpapers(shell.known_folder)
        current = os.path.normcase(wallpaper.current())
        rows = [{"keys": os.path.basename(path), "text": path, "action": "wallpaper.set", "payload": {"path": path},
                 "current": os.path.normcase(path) == current} for path in images]
        data["wallpapers"] = [{"title": r"Imágenes\wallpapers", "info": folder, "rows": rows}] if rows else []
        data["options"] = [{"title": "Rendimiento", "info": "Para equipos con poca RAM; se aplica al momento.", "rows": [
            {"keys": "Modo ligero", "option": "light_mode", "value": bool(self.cfg.get("light_mode", True)),
             "text": "Sin deslizamiento al cambiar de escritorio ni borde luminoso en las ventanas."}]}]
        data["web"] = {"shortcuts": list(self.cfg.get("web_shortcuts") or []), "browser": self._browser_exe(),
                       "chosen": self._chosen_browser(), "default": browsers.default_exe(),
                       "browsers": browsers.installed()}
        return data

    def _chosen_browser(self):
        """El navegador que eligió Gustavo, o "" si no eligió ninguno o ya no existe."""
        exe = (self.cfg.get("defaults") or {}).get("browser") or ""
        return exe if exe and os.path.isfile(exe) else ""

    def _browser_exe(self):
        """El navegador de las páginas web: el elegido o, si no, el predeterminado de Windows (da el icono y abre)."""
        return self._chosen_browser() or browsers.default_exe()

    def set_web_shortcuts(self, items):
        """Desde la configuración: guarda las páginas web del buscador (nombre y dirección)."""
        try:
            cleaned = web.clean(items)
        except ValueError as err:
            raise ActionError("bad_web", str(err)) from err
        self.cfg["web_shortcuts"] = cleaned
        config_module.save_option("web_shortcuts", cleaned)
        self._request_push()

    def set_default_browser(self, exe):
        """Desde la configuración: el navegador con el que se abren las páginas web ("" = el predeterminado de Windows)."""
        exe = (exe or "").strip()
        if exe and os.path.normcase(exe) not in {os.path.normcase(b["exe"]) for b in browsers.installed()}:
            raise ActionError("bad_browser", "Ese navegador no está instalado")
        defaults = {**(self.cfg.get("defaults") or {}), "browser": exe}
        self.cfg["defaults"] = defaults
        config_module.save_option("defaults", defaults)
        self._request_push()

    def set_option(self, key, value):
        """Desde la configuración: cambia un ajuste y lo guarda en config.json."""
        if key not in OPTIONS:
            raise ActionError("bad_option", f"Ajuste desconocido: {key}")
        self.cfg[key] = bool(value)
        config_module.save_option(key, bool(value))
        self._request_push()

    def search_query(self, text="", mode=""):
        """Lo que enseña el buscador para `text`: en los modos de Ctrl+Shift+T y Ctrl+Shift+N ("task", "notes"), las tareas o las
        notas; si no, solo apps ("<"), solo carpetas ("/"), solo archivos ("@") o, sin prefijo, ventanas, apps,
        carpetas y archivos juntos."""
        text = (text or "").strip()
        if mode in ("task", "notes", "chat"):
            return self._kyora_command(mode, text)
        if text.startswith("<"):  # solo aplicaciones
            rest = text[1:].strip()
            return {"results": self._app_rows(rest, SEARCH_RESULTS * 2) if rest else [],
                    "indexing": not self.index.ready.is_set()}
        if text == "/":  # la barra sola: el árbol con el acceso rápido y Equipos
            return {"mode": "tree", "results": [], "indexing": False, **self.files_roots()}
        if text.startswith(("/", "@")):
            only = "dir" if text[0] == "/" else "file"
            rows = [self._path_row(e) for e in self.files.search(text[1:], only=only)]
            return {"results": rows, "indexing": not self.files.ready.is_set(), "indexing_text":
                    f"Indexando archivos… ({len(self.files)})"}
        windows = []
        for w in self._window_list():
            scores = [s for s in (score(text, w["app"]), score(text, w["title"])) if s is not None] if text else [0]
            if scores:
                windows.append((min(scores), w))
        windows.sort(key=lambda t: t[0])
        results = [
            {
                "kind": "window", "id": w["hwnd"], "name": w["app"], "exe": w["exe"], "hwnd": w["hwnd"],
                "detail": f"{w['title']} · escritorio {w['desktop']}",
            }
            for _, w in windows[: 3 if text else SEARCH_RESULTS]
        ]
        indexing = not self.index.ready.is_set()
        if text:
            results += self._web_rows(text)
            results += self._app_rows(text, SEARCH_RESULTS - len(results))
            found = self.files.search(text, limit=MIXED_PATHS * 6)  # un solo recorrido: carpetas y archivos a la vez
            dirs = [e for e in found if e["is_dir"]][:MIXED_FOLDERS]
            files = [e for e in found if not e["is_dir"]][:MIXED_FILES]
            results += [self._path_row(e) for e in dirs + files]
            indexing = indexing and not results  # si ya hay algo que enseñar, no se avisa de que se está indexando
        return {"results": results, "indexing": indexing}

    def _app_rows(self, text, limit):
        return [
            {
                "kind": "app", "id": a["target"], "name": a["name"], "detail": "Abrir aplicación",
                "exe": a["target"] if a["kind"] == "lnk" else rf"shell:AppsFolder\{a['target']}", "hwnd": 0,
            }
            for a in self.index.search(text, limit)
        ]

    def _web_rows(self, text):
        """Las páginas web guardadas cuyo nombre coincide; llevan el icono del navegador elegido."""
        exe = self._browser_exe()
        return [{"kind": "web", "id": w["url"], "name": w["name"], "detail": w["url"], "exe": exe, "hwnd": 0}
                for w in web.search(self.cfg.get("web_shortcuts"), text)]

    def _window_list(self):
        """Las ventanas para el buscador. Se reutilizan un momento: al escribir, cada letra no vuelve a pedir el
        título de todas a Windows ni espera al candado del gestor."""
        stamp, windows = getattr(self, "_windows_cache", (0.0, []))
        now = time.monotonic()
        if now - stamp > WINDOWS_CACHE_SECONDS:
            fresh = self.manager.window_list(blocking=False)  # si el gestor está acomodando ventanas, sirve la anterior
            if fresh is not None:
                windows = fresh
                self._windows_cache = (now, windows)
        return windows

    def _kyora_command(self, word, rest):
        """Los modos del buscador de Ctrl+Shift+T ("task": el tablero Kanban) y Ctrl+Shift+N ("notes")."""
        if word == "task":  # el tablero Kanban; lo escrito solo sirve para crear una tarea nueva (lo resuelve la interfaz)
            return {"mode": "tasks", "results": [], "indexing": False}
        if word == "chat":  # el chat con tus otros dispositivos (Supabase)
            return {"mode": "chat", "results": [], "indexing": False}
        return {"mode": "notes", "results": [], "indexing": False}  # se abren en el mismo buscador, más ancho

    @staticmethod
    def _path_row(entry):
        if entry.get("computer"):
            detail = ""
        elif entry.get("drive"):
            detail = "Unidad"
            try:
                detail = f"Unidad · {folders.human_size(shutil.disk_usage(entry['path']).free)} libres"
            except OSError:
                pass
        elif entry["is_dir"]:
            detail = folders.short_path(os.path.dirname(entry["path"]))
        else:
            size = entry.get("size")
            if size is None:
                try:
                    size = os.path.getsize(entry["path"])
                except OSError:
                    size = 0
            detail = f"{folders.human_size(size)} · {folders.short_path(os.path.dirname(entry['path']))}"
        return {"kind": "path", "id": entry["path"], "name": entry["name"], "detail": detail, "hwnd": 0, "exe": "",
                "is_dir": entry["is_dir"], "drive": bool(entry.get("drive"))}

    def files_roots(self):
        """Las raíces del árbol de archivos (el de "/" y el del chat): {roots, expanded}. Documentos y Equipos salen abiertos."""
        rows = [self._path_row(e) for e in folders.tree_roots(shell.known_folder)]
        return {"roots": rows, "expanded": [r["id"] for r in rows if r["name"] in ("Documentos", "Equipos")]}

    def files_children(self, path):
        """Los hijos de una carpeta para el árbol de "/" (carpetas primero); de Equipos, las unidades."""
        if path == folders.THIS_PC:
            return [self._path_row(e) for e in folders.pc_entries()]
        if not os.path.isdir(path):
            raise ActionError("missing", "Esa carpeta ya no existe")
        return [self._path_row(e) for e in folders.listing(path)]

    def wallpaper_mode(self):
        """Ctrl+Shift+W: la interfaz enseña solo los fondos y el escritorio (ver ui/wallpaper_mode.py); ←/→ los prueban y
        Enter deja el elegido (con `wallpaper.set`)."""
        folder, images = folders.wallpapers(shell.known_folder)
        self._emit("wallpaper_mode", {"images": images, "folder": folder, "current": wallpaper.current()})

    def set_wallpaper(self, path):
        """Pone el fondo de pantalla (">wallpaper"); la interfaz cambia sus colores al recibir el aviso."""
        with self._wallpaper_lock:  # varias flechas seguidas: los cambios van en orden
            try:
                wallpaper.set_wallpaper(path)
            except OSError as err:
                raise ActionError("wallpaper", f"No se pudo poner el fondo: {err}") from err
        self._emit("wallpaper_changed", path)

    def search_launch(self, kind, id, files=False):
        if kind == "window":
            self.close_search(refocus=False)
            self.manager.activate(int(id))
        elif kind == "app":
            entry = next((e for e in self.index.entries if e["target"] == id), None)
            if entry is None:
                raise ActionError("unknown_app", "Esa aplicación ya no está en el índice")
            self.manager.expect_launch()
            self.close_search(refocus=False)
            self.index.launch(entry)
        elif kind == "path":  # un archivo se abre con su programa; una carpeta (Ctrl+Enter), en el Explorador
            self.close_search(refocus=False)
            self.directory.open(id)
        elif kind == "web":  # `id` es la dirección
            self.manager.expect_launch()
            self.close_search(refocus=False)
            browsers.open_url(id, self._chosen_browser())
        elif kind == "config":
            _, _, action, payload = KYORA_OPTIONS[int(id)]
            self.close_search(refocus=False)
            self.invoke_async(action, **payload)
        # las tareas se manejan dentro del buscador: nada de esto lo cierra
        elif kind == "task_new":  # devuelve el id: el buscador enseña la tarea nueva
            return self.tasks.create(id)
        else:
            raise ActionError("bad_kind", f"Tipo de resultado desconocido: {kind}")

    # ---------- panel de Win+E: las ventanas en espera ----------

    def toggle_switcher(self):
        """Abre (o cierra) el panel de espera encima del hueco de la ventana enfocada."""
        self._emit("switcher_toggle", _as_tuple(self.manager.switcher_rect()))

    def switcher_items(self):
        """Ventanas de este escritorio que no se ven: las que esperan en el panel izquierdo."""
        snapshot = self.manager.snapshot()
        items = [
            {"hwnd": w["hwnd"], "name": w["app"], "title": w["title"], "exe": w["exe"]}
            for w in snapshot["waiting"]
        ]
        current = self.manager.focused_window()
        if current:  # la que se va a reemplazar, pequeña arriba de la pila
            name, title = self.system.describe(current)
            items.insert(0, {"hwnd": current, "name": name, "title": title, "exe": self.system.exe_path(current),
                             "current": True})
        return items

    def switcher_pick(self, hwnd):
        """La ventana elegida ocupa el sitio de la enfocada y la que estaba ahí pasa a esperar en el panel izquierdo."""
        self.manager.swap_into_focused(int(hwnd))

    # ---------- arrastrar una ventana en espera hasta un hueco ----------

    def _zones(self, hwnd):
        """Los sitios donde puede quedar la ventana que se arrastra."""
        return self.manager.drop_zones(hwnd, *self.system.cursor_pos())

    def drag(self, hwnd):
        threading.Thread(target=self._drag_loop, args=(hwnd,), daemon=True, name="kyora-drag").start()

    def _drag_loop(self, hwnd):
        deadline = time.monotonic() + DRAG_TIMEOUT
        try:
            while self.system.left_button_down() and time.monotonic() < deadline:
                self._emit("drop_rect", self._zones(hwnd))
                time.sleep(TRACK_INTERVAL)
        finally:
            self._emit("drop_rect", None)
        x, y = self.system.cursor_pos()
        try:
            self.manager.drop(hwnd, x, y)
        finally:
            self._request_push()

    # ---------- el usuario arrastra una ventana del mosaico ----------

    def _on_window_event(self, event, hwnd):
        """Se ejecuta en el hilo de avisos de Windows: debe ser rápido."""
        if event == EVENT_MOVESIZESTART:
            if not self._moving and self.manager.is_draggable_here(hwnd):
                self._moving = hwnd
                threading.Thread(target=self._track_move, args=(hwnd,), daemon=True, name="kyora-move").start()
        elif event == EVENT_MOVESIZEEND:
            if hwnd == self._moving:
                self._moving = 0  # el hilo de seguimiento lo ve, termina y reparte
        else:
            self._request_sync()
        self._ring_wake.set()

    @staticmethod
    def _resized(before, after):
        return abs(after.width - before.width) > RESIZE_THRESHOLD or abs(after.height - before.height) > RESIZE_THRESHOLD

    def _track_move(self, hwnd):
        """Mientras dura el arrastre resalta el hueco destino; al soltar intercambia o conserva el nuevo tamaño."""
        start = self.system.frame_rect(hwnd)
        try:
            while self._moving == hwnd and not self._stop.is_set():
                if self._resized(start, self.system.frame_rect(hwnd)):
                    self._emit("drop_rect", None)  # está cambiando el tamaño, no moviendo
                else:
                    self._emit("drop_rect", self._zones(hwnd))
                time.sleep(TRACK_INTERVAL)
        finally:
            self._emit("drop_rect", None)
        try:
            if self._resized(start, self.system.frame_rect(hwnd)):
                if self.manager.is_tiled(hwnd):
                    self.manager.resize_from_drag(hwnd)
            else:
                self.manager.drop(hwnd, *self.system.cursor_pos())
        except Exception:
            log.exception("Fallo al terminar el arrastre de una ventana")
        finally:
            self._moving = 0
            self._request_sync()

    # ---------- foco con el ratón ----------

    def focus_follows_mouse(self, enabled=None):
        enable = (not self._ffm_on.is_set()) if enabled is None else bool(enabled)
        if enable:
            self._ffm_on.set()
        else:
            self._ffm_on.clear()
        self._emit("toast", "Foco con el ratón: " + ("activado" if enable else "desactivado"))
        self._request_push()
        return enable

    def _focus_follows_loop(self):
        last, rested = None, 0
        while not self._stop.is_set():
            self._ffm_on.wait()
            if self._stop.is_set():
                return
            pos = self.system.cursor_pos()
            rested = rested + 1 if pos == last else 0
            last = pos
            if rested == 2 and not (self.search_open or self._moving or self.system.left_button_down()):
                self.manager.focus_at(*pos)
            self._stop.wait(FOCUS_INTERVAL)

    # ---------- contorno de la ventana activa ----------

    def _ring_targets(self):
        if self.cfg.get("light_mode", True):
            return ()  # modo ligero: sin borde luminoso (ahorra ventanas, temporizadores y memoria)
        """Las ventanas que se ven con su rectángulo y si tienen el foco: todas llevan contorno, para que el borde
        se encienda con el cursor cerca estén en uso o no."""
        focused = self.manager.focused_window(keep_last=self.search_open)
        targets = []
        for hwnd in self.manager.visible_windows():
            rect = _as_tuple(self.system.frame_rect(hwnd))
            if rect[2] > rect[0] and rect[3] > rect[1]:  # una ventana que acaba de cerrarse no cuenta
                targets.append((hwnd, rect, hwnd == focused))
        if focused and focused not in {t[0] for t in targets}:
            rect = _as_tuple(self.system.frame_rect(focused))
            if rect[2] > rect[0] and rect[3] > rect[1]:
                targets.append((focused, rect, True))
        return tuple(sorted(targets))

    def _ring_loop(self):
        """Mira cada poco qué ventana tiene el foco, para rodearla con su luz."""
        shown = None
        quiet_since = time.monotonic()
        while not self._stop.is_set():
            changed = bool(self._moving)
            target = () if self._moving else self._ring_targets()
            if target != shown:
                shown, changed = target, True
                self._emit("focus_target", target)
            now = time.monotonic()
            if changed:
                quiet_since = now
            # mientras algo cambia, deprisa; tras un rato quieto, más despacio (menos trabajo para Python)
            self._ring_wake.wait(RING_INTERVAL if now - quiet_since < RING_QUIET_AFTER else RING_IDLE_INTERVAL)
            self._ring_wake.clear()

    # ---------- hilos de trabajo ----------

    def _request_sync(self):
        self._sync_needed.set()

    def _request_push(self):
        self._push_needed.set()

    def _worker(self, trigger, delay, fn, name):
        while True:
            trigger.wait()
            if self._stop.is_set():
                return
            time.sleep(delay)  # agrupa ráfagas de eventos en una sola pasada
            trigger.clear()
            try:
                fn()
            except Exception:
                log.exception("Fallo en el trabajo %s", name)

    def _sync(self):
        if not self._moving:  # durante un arrastre, Kyora no pelea con el usuario
            self.manager.sync()

    def _push(self):
        self._emit("state_changed", self.get_state())

    def _wifi_loop(self):
        while not self._stop.is_set():
            current = wifi.status()
            if current != self.wifi:
                self.wifi = current
                self._request_push()
            self._stop.wait(WIFI_INTERVAL)

    def _taskbar_loop(self):
        while not self._stop.wait(TASKBAR_INTERVAL):
            self.taskbar.keep_hidden()

    def _start_threads(self):
        for trigger, delay, fn, name in (
            (self._sync_needed, SYNC_DEBOUNCE, self._sync, "sync"),
            (self._push_needed, PUSH_DEBOUNCE, self._push, "push"),
        ):
            threading.Thread(target=self._worker, args=(trigger, delay, fn, name), daemon=True, name=f"kyora-{name}").start()
        threading.Thread(target=self._wifi_loop, daemon=True, name="kyora-wifi").start()
        threading.Thread(target=self._focus_follows_loop, daemon=True, name="kyora-focus").start()
        threading.Thread(target=self._ring_loop, daemon=True, name="kyora-ring").start()
        threading.Thread(target=self._devices_loop, daemon=True, name="kyora-devices").start()
        threading.Thread(target=self._weather_loop, daemon=True, name="kyora-weather").start()
        self.chat.start()  # sin credenciales en supabase/.env, solo avisa de que faltan
        self.music_sync.start()  # retoma las canciones que quedaron sin mandar al móvil
        self.files.start(self._stop)
        if self.cfg["hide_taskbar"]:
            threading.Thread(target=self._taskbar_loop, daemon=True, name="kyora-taskbar").start()

    # ---------- ciclo de vida ----------

    def _hotkey_call(self, spec):
        action, payload = spec[0], (spec[1] if len(spec) > 1 else {})

        def call():
            result = self.registry.invoke(action, payload)
            if not result["ok"]:
                log.warning("Atajo %s: %s", action, result["error"]["message"])

        return call

    def _bind_hotkeys(self, hotkeys):
        """Registra los atajos normales de `hotkeys` (los de dos teclas con Alt los lleva el gancho del teclado). Devuelve
        los que Windows no dejó registrar."""
        normal, _chords, _taps, bad = split_bindings(hotkeys)
        fresh = Hotkeys({combo: self._hotkey_call(spec) for combo, spec in normal.items()})
        fresh.start()
        fresh.ready.wait(5)
        fresh.failed.extend(bad)
        self.hotkeys = fresh
        return fresh.failed

    def set_hotkeys(self, hotkeys):
        """Desde la configuración: cambia los atajos al momento y los guarda en config.json. Si Windows rechaza alguno,
        se deja todo como estaba."""
        if not isinstance(hotkeys, dict) or not hotkeys:
            raise ActionError("bad_hotkeys", "Los atajos no son válidos")
        hotkeys = {normalize_combo(c): spec for c, spec in hotkeys.items()}
        previous = self.cfg["hotkeys"]
        old = self.hotkeys
        if old is not None:
            old.stop()
            old.join(2)  # sus combinaciones se sueltan al terminar el hilo: así no chocan con las nuevas
        failed = self._bind_hotkeys(hotkeys)
        if failed:
            self._bind_hotkeys(previous)
            raise ActionError("hotkey_failed", "Windows no deja usar: " + ", ".join(failed[:3]))
        self.cfg["hotkeys"] = hotkeys
        config_module.save_hotkeys(hotkeys)
        self._request_push()

    def reset_hotkeys(self):
        """Vuelve a los atajos por defecto."""
        self.set_hotkeys(config_module.default_hotkeys())

    def start(self, own_windows):
        """Arranca la parte de Windows; la interfaz ya está a la vista y fijó el hueco del marco (insets)."""
        for hwnd in own_windows:
            self.system.add_own_window(hwnd)
        if self.cfg["hide_taskbar"]:
            self.taskbar.hide()
        if self.cfg.get("disable_snap", True):
            snap.disable()  # Windows no acopla ni encoge las ventanas al arrastrarlas: las coloca Kyora
        normal, chords, taps, bad = split_bindings(self.cfg["hotkeys"])
        self.hotkeys = Hotkeys({combo: self._hotkey_call(spec) for combo, spec in normal.items()})
        self.hotkeys.start()
        self.hotkeys.ready.wait(5)
        self.hotkeys.failed.extend(bad)
        # gancho del teclado: bloquea la tecla Windows (y resuelve las combinaciones de dos teclas con Alt)
        self.winkey = KeyHookProcess(  # en su propio proceso: las teclas nunca esperan a Kyora
            {key: self._hotkey_call(spec) for key, spec in chords.items()},
            {key: self._hotkey_call(spec) for key, spec in taps.items()},
        )
        self.winkey.start()
        self.winkey.ready.wait(3)
        if self.winkey.failed:
            self._emit("toast", "No se pudo desactivar la tecla Windows")
        self.manager.adopt_existing()
        self.hook = EventHook(self._on_window_event)
        self.hook.start()
        self._start_threads()
        self._request_push()
        if self.hotkeys.failed:
            self._emit("toast", "Atajos no disponibles: " + ", ".join(self.hotkeys.failed[:3]))
        log.info("Kyora listo. Atajos que fallaron: %s", self.hotkeys.failed or "ninguno")

    def shutdown(self):
        """Deja Windows como estaba: ventanas visibles y barra de tareas restaurada. Se puede llamar varias veces."""
        with self._down_lock:
            if self._down:
                return
            self._down = True
        self._stop.set()
        self.chat.stop()
        self.music_sync.stop()
        self._ring_wake.set()
        self._sync_needed.set()
        self._push_needed.set()
        self._ffm_on.set()  # despierta el hilo del foco para que vea que hay que terminar
        self._device_jobs.put(None)
        for part in (self.hook, self.hotkeys, self.winkey):
            if part:
                part.stop()
        shown = self.manager.release_all()
        self.taskbar.restore()
        snap.restore()
        self.system.recover()
        log.info("Kyora cerrado; ventanas devueltas: %s", shown)

    def release(self):
        """Emergencia y salida: devuelve todo a Windows y cierra Kyora."""
        self.shutdown()
        self._emit("quit")

    def quit(self):
        threading.Timer(0.1, self.release).start()

    def run(self):
        from kyora.ui.app import (
            run_ui,  # Qt se importa aquí para que --rescue funcione aunque falle
        )

        atexit.register(self.shutdown)
        try:
            win32api.SetConsoleCtrlHandler(lambda _: self.shutdown() or False, True)
        except Exception:
            log.debug("No se pudo registrar el cierre de consola", exc_info=True)
        try:
            return run_ui(self)
        finally:
            self.shutdown()


def main(argv=None):
    parser = argparse.ArgumentParser(prog="kyora", description="Kyora, tu entorno de ventanas")
    parser.add_argument("--rescue", action="store_true", help="devuelve ventanas ocultas y la barra de tareas, y sale")
    parser.add_argument("--no-taskbar", action="store_true", help="no oculta la barra de tareas de Windows")
    parser.add_argument("--restart", action="store_true", help="espera a que se cierre la Kyora abierta y arranca")
    args = parser.parse_args(argv)

    setup_logging()
    # el gancho de teclado es Python: con un relevo de hilos más corto, cada tecla espera menos a que le toque
    sys.setswitchinterval(0.002)
    cfg = config_module.load()
    if args.no_taskbar:
        cfg["hide_taskbar"] = False

    if args.rescue:
        make_dpi_aware()
        restored = Win32System(cfg).recover()
        Taskbar().restore(force=True)
        print(f"Listo: barra de tareas restaurada y {restored} ventana(s) devuelta(s).")
        return 0

    deadline = time.monotonic() + (RESTART_WAIT if args.restart else 0)
    while True:
        mutex = win32event.CreateMutex(None, False, "Local\\KyoraSingleInstance")
        if win32api.GetLastError() != winerror.ERROR_ALREADY_EXISTS:
            break
        mutex.Close()
        if time.monotonic() >= deadline:
            print("Kyora ya está en marcha.")
            return 1
        time.sleep(0.25)  # --restart: la anterior todavía se está cerrando
    recovered = Win32System(cfg).recover()
    if recovered:
        log.info("Recuperadas %s ventanas de una sesión anterior", recovered)
    kyora = Kyora(cfg)
    signal.signal(signal.SIGINT, lambda *_: kyora.release())
    try:
        return kyora.run()
    finally:
        del mutex

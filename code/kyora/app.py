"""Arranque de Kyora: junta la interfaz (Qt), el gestor de ventanas, los atajos y las acciones.

La interfaz vive en el hilo principal (Qt). Los hilos de Windows (avisos, atajos, wifi...) le hablan
solo con señales de `UiBridge`, que Qt entrega en el hilo principal.
"""
import argparse
import atexit
import ctypes
import logging
import logging.handlers
import queue
import signal
import subprocess
import sys
import threading
import time

import pythoncom
import pywintypes
import win32api
import win32event
import winerror

from kyora import config as config_module
from kyora.brain.service import BrainService
from kyora.core.actions import ActionError, ActionRegistry
from kyora.core.commands import COMMANDS_WORD, command_rows
from kyora.directory.service import DirectoryService
from kyora.search.apps import AppIndex, score
from kyora.system import (
    audio,
    bluetooth,
    display,
    launch,
    shell,
    stats,
    weather,
    wifi,
    wlan,
)
from kyora.system.events import EVENT_MOVESIZEEND, EVENT_MOVESIZESTART, EventHook
from kyora.system.hotkeys import Hotkeys, split_bindings
from kyora.system.keys import KeyboardHook
from kyora.system.win32 import Taskbar, Win32System, make_dpi_aware
from kyora.tasks.service import TaskService
from kyora.wm.manager import RESIZE_THRESHOLD, WindowManager

log = logging.getLogger("kyora")

SYNC_DEBOUNCE = 0.12
PUSH_DEBOUNCE = 0.05
WIFI_INTERVAL = 30
TASKBAR_INTERVAL = 1
DRAG_TIMEOUT = 30
TRACK_INTERVAL = 0.03  # seguimiento del cursor mientras se arrastra
FOCUS_INTERVAL = 0.1  # foco con el ratón: el cursor debe quedarse quieto 2 pasos
RING_INTERVAL = 0.04  # cada cuánto se mira qué ventana tiene el foco para rodearla
SEARCH_RESULTS = 6
CLOSE_ALL_CONFIRM = 3  # segundos para volver a pulsar Win+Esc y cerrar todas las ventanas
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


class Kyora:
    def __init__(self, cfg):
        self.cfg = cfg
        self.system = Win32System(cfg)
        self.taskbar = Taskbar()
        self.manager = WindowManager(self.system, cfg, notify=self._request_push)
        self.index = AppIndex()
        self.registry = ActionRegistry()
        self.ui = None  # UiBridge: se crea al arrancar la interfaz
        self.hook = None
        self.hotkeys = None
        self.winkey = None
        self.wifi = dict(wifi.OFF)
        self.search_open = False
        self.devices = {}  # CPU, RAM, disco, volumen y brillo: lo que muestra la barra
        self._device_jobs = queue.Queue()  # cambios de volumen y brillo: los hace el hilo de dispositivos (COM)
        self._history = stats.History()  # CPU y RAM de los últimos minutos, para la gráfica de Sistema
        self._moving = 0  # ventana del mosaico que el usuario está arrastrando
        self._ffm_on = threading.Event()
        if cfg["focus_follows_mouse"]:
            self._ffm_on.set()
        self._ui_lock = threading.Lock()
        self._stop = threading.Event()
        self._sync_needed = threading.Event()
        self._push_needed = threading.Event()
        self._down = False
        self._down_lock = threading.Lock()
        self._close_all_armed = 0.0  # hasta cuándo una segunda pulsación de Win+Esc cierra todo
        self.directory = DirectoryService(
            config_module.data_dir(), lambda event: self._emit("directory_event", event),
            shell.known_folder, shell.recycle, shell.open_with,
        )
        self.tasks = TaskService(config_module.data_dir())
        self.brain = BrainService(config_module.data_dir(), shell.recycle, documents=shell.known_folder("documents"))
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
        r.register("desktop.switch", lambda index: m.desktop_switch(index))
        r.register("desktop.step", lambda delta: m.desktop_step(delta))
        r.register("desktop.create", m.desktop_create)
        r.register("desktop.rename", lambda index, name: m.desktop_rename(index, name))
        r.register("desktop.close", lambda index: m.desktop_close(index))
        r.register("desktop.close_current", lambda: m.desktop_close(m.active))
        r.register("power.menu", self.toggle_power)
        r.register("system.shutdown", lambda: self.power_off(restart=False), destructive=True)
        r.register("system.restart", lambda: self.power_off(restart=True), destructive=True)
        r.register("system.sleep", self.sleep)
        r.register("app.restart", self.restart)
        r.register("hub.toggle", lambda section="lobby": self._emit("hub_toggle", section))
        self.directory.register(r)
        self.tasks.register(r)
        self.brain.register(r)
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
        r.register("search.query", self.search_query)
        r.register("search.launch", self.search_launch)
        r.register("app.focus_follows_mouse", self.focus_follows_mouse)
        r.register("app.release", self.release, destructive=True)
        r.register("app.quit", self.quit)

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

    def close_all(self):
        """La primera vez solo avisa; si se repite enseguida, cierra todas las ventanas de todos los escritorios."""
        now = time.monotonic()
        if now > self._close_all_armed:
            self._close_all_armed = now + CLOSE_ALL_CONFIRM
            self._emit("toast", "Pulsa Win+Esc otra vez para cerrar todas las ventanas")
            return 0
        self._close_all_armed = 0.0
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
        city = (self.cfg.get("weather") or {}).get("city", "").strip()
        if not city:
            self._emit("weather_changed", {"error": 'Pon tu ciudad en config.json: "weather": {"city": "…"}'})
            return
        cache = config_module.data_dir() / "weather.json"
        while not self._stop.is_set():
            try:
                self._emit("weather_changed", weather.current(city, cache))
                wait = WEATHER_INTERVAL
            except (OSError, LookupError, ValueError) as err:  # sin red, ciudad desconocida o respuesta rara
                log.warning("Clima: %s", err)
                self._emit("weather_changed", {"error": f"Sin clima: {err}"})
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

    def open_search(self):
        with self._ui_lock:
            if self.search_open:
                return
            self.search_open = True
        self._emit("search_open")
        self._request_push()

    def close_search(self, refocus=True):
        with self._ui_lock:
            if not self.search_open:
                return
            self.search_open = False
        self._emit("search_close")
        if refocus:
            self.manager.refocus()
        self._request_push()

    def toggle_search(self):
        if self.search_open:
            self.close_search()
        else:
            self.open_search()

    def search_query(self, text=""):
        text = (text or "").strip()
        if text.lower() == COMMANDS_WORD:  # la lista de atajos, para no tener que mirar COMANDOS.md
            rows = command_rows(self.cfg["hotkeys"])
            return {
                "results": [{"kind": "command", "id": r["keys"], "name": r["keys"], "detail": r["text"]} for r in rows],
                "indexing": False,
            }
        windows = []
        for w in self.manager.window_list():
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
        if text:
            results += [
                {
                    "kind": "app", "id": a["target"], "name": a["name"], "detail": "Abrir aplicación",
                    "exe": a["target"] if a["kind"] == "lnk" else rf"shell:AppsFolder\{a['target']}", "hwnd": 0,
                }
                for a in self.index.search(text, SEARCH_RESULTS - len(results))
            ]
        return {"results": results, "indexing": not self.index.ready.is_set()}

    def search_launch(self, kind, id):
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
        else:
            raise ActionError("bad_kind", f"Tipo de resultado desconocido: {kind}")

    # ---------- panel de Alt+E: las ventanas en espera ----------

    def toggle_switcher(self):
        """Abre (o cierra) el panel de espera encima del hueco de la ventana enfocada."""
        self._emit("switcher_toggle", _as_tuple(self.manager.switcher_rect()))

    def switcher_items(self):
        """Ventanas en espera de este escritorio: las que no caben en el mosaico (y las minimizadas)."""
        return [
            {"hwnd": w["hwnd"], "name": w["app"], "title": w["title"], "exe": w["exe"]}
            for w in self.manager.snapshot()["waiting"]
        ]

    def switcher_pick(self, hwnd):
        """La ventana elegida ocupa el hueco enfocado y la que estaba ahí pasa a espera."""
        self.manager.swap_into_focused(int(hwnd))

    # ---------- arrastrar una ventana en espera hasta un hueco ----------

    def drag(self, hwnd):
        threading.Thread(target=self._drag_loop, args=(hwnd,), daemon=True, name="kyora-drag").start()

    def _drag_loop(self, hwnd):
        deadline = time.monotonic() + DRAG_TIMEOUT
        try:
            while self.system.left_button_down() and time.monotonic() < deadline:
                self._emit("drop_rect", _as_tuple(self.manager.slot_rect_at(*self.system.cursor_pos())))
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
            if not self._moving and self.manager.is_tiled(hwnd):
                self._moving = hwnd
                threading.Thread(target=self._track_move, args=(hwnd,), daemon=True, name="kyora-move").start()
        elif event == EVENT_MOVESIZEEND:
            if hwnd == self._moving:
                self._moving = 0  # el hilo de seguimiento lo ve, termina y reparte
        else:
            self._request_sync()

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
                    self._emit("drop_rect", _as_tuple(self.manager.slot_rect_at(*self.system.cursor_pos())))
                time.sleep(TRACK_INTERVAL)
        finally:
            self._emit("drop_rect", None)
        try:
            if self._resized(start, self.system.frame_rect(hwnd)):
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

    def _ring_loop(self):
        """Mira cada poco qué ventana tiene el foco (para su luz) y dónde están las del mosaico (para su borde)."""
        shown, tiles = None, None
        while not self._stop.is_set():
            current = tuple(
                rect for rect in (_as_tuple(self.system.frame_rect(h)) for h in self.manager.visible_windows()
                                  if h != self._moving)  # la que se arrastra no lleva borde mientras se mueve
                if rect and rect[2] > rect[0] and rect[3] > rect[1]
            )
            if current != tiles:
                tiles = current
                self._emit("tiles_changed", list(tiles))
            hwnd = 0 if self._moving else self.manager.focused_window(keep_last=self.search_open)
            target = (hwnd, _as_tuple(self.system.frame_rect(hwnd))) if hwnd else None
            if target and (target[1][2] <= target[1][0] or target[1][3] <= target[1][1]):
                target = None  # la ventana acaba de cerrarse
            if target != shown:
                shown = target
                self._emit("focus_target", target)
            self._stop.wait(RING_INTERVAL)

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

    def start(self, own_windows):
        """Arranca la parte de Windows; la interfaz ya está a la vista y fijó el hueco del marco (insets)."""
        for hwnd in own_windows:
            self.system.add_own_window(hwnd)
        if self.cfg["hide_taskbar"]:
            self.taskbar.hide()
        normal, chords, taps, wins, bad = split_bindings(self.cfg["hotkeys"])
        self.hotkeys = Hotkeys({combo: self._hotkey_call(spec) for combo, spec in normal.items()})
        self.hotkeys.start()
        self.hotkeys.ready.wait(5)
        self.hotkeys.failed.extend(bad)
        # gancho del teclado: la tecla Windows suelta no abre el menú de inicio (y resuelve las combinaciones de dos teclas)
        self.winkey = KeyboardHook(
            {key: self._hotkey_call(spec) for key, spec in chords.items()},
            {key: self._hotkey_call(spec) for key, spec in taps.items()},
            {key: self._hotkey_call(spec) for key, spec in wins.items()},
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
        self._sync_needed.set()
        self._push_needed.set()
        self._ffm_on.set()  # despierta el hilo del foco para que vea que hay que terminar
        self._device_jobs.put(None)
        for part in (self.hook, self.hotkeys, self.winkey):
            if part:
                part.stop()
        shown = self.manager.release_all()
        self.taskbar.restore()
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

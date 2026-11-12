"""Gancho global del teclado (WH_KEYBOARD_LL): bloquea la tecla Windows y resuelve las combinaciones de dos teclas con Alt.

- La tecla Windows (y Ctrl+Esc) se traga entera: no abre el menú de inicio ni dispara ningún atajo de Windows (ver
  kyora/core/winkey.py). Los atajos de Kyora usan Ctrl+Shift+tecla (RegisterHotKey, ver hotkeys.py).
- Alt+F+flechas, Alt+M+flechas… (ver kyora/core/chords.py): se tragan sus teclas y su acción se ejecuta en otro hilo,
  para que el gancho nunca haga esperar al teclado.
Si una tecla llega tarde al gancho (Python ocupado en otra cosa), se anota en kyora.log.
Las demás pulsaciones pasan sin tocarse.

Kyora lo lanza en su propio proceso (KeyHookProcess, ver keyproc.py): así nunca espera a la interfaz.
"""
import ctypes
import logging
import os
import queue
import subprocess
import sys
import threading
import time
from ctypes import wintypes

from kyora.core.chords import ChordGuard
from kyora.core.winkey import WinBlock

log = logging.getLogger("kyora.keys")

user32 = ctypes.WinDLL("user32", use_last_error=True)
kernel32 = ctypes.WinDLL("kernel32")

WH_KEYBOARD_LL = 13
WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP = 0x0100, 0x0101, 0x0104, 0x0105
WM_QUIT = 0x0012
LLKHF_INJECTED = 0x10
INPUT_KEYBOARD = 1
KEYEVENTF_KEYUP = 0x0002
VK_MASK = 0xE8  # sin asignar: no hace nada, pero cuenta como "otra tecla" para Windows
SLOW_KEY_MS = 30  # una tecla que tarda más que esto en llegar al gancho se nota al escribir
SLOW_LOG_SECONDS = 10  # como mucho un aviso de teclas lentas cada tantos segundos

LRESULT = ctypes.c_ssize_t


class KBDLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [
        ("vkCode", wintypes.DWORD), ("scanCode", wintypes.DWORD), ("flags", wintypes.DWORD),
        ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t),
    ]


class MSLLHOOKSTRUCT(ctypes.Structure):
    _fields_ = [
        ("pt", wintypes.POINT), ("mouseData", wintypes.DWORD), ("flags", wintypes.DWORD),
        ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t),
    ]


class _KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD), ("wScan", wintypes.WORD), ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t),
    ]


class _MOUSEINPUT(ctypes.Structure):
    _fields_ = [
        ("dx", wintypes.LONG), ("dy", wintypes.LONG), ("mouseData", wintypes.DWORD),
        ("dwFlags", wintypes.DWORD), ("time", wintypes.DWORD), ("dwExtraInfo", ctypes.c_size_t),
    ]


class _INPUTUNION(ctypes.Union):
    _fields_ = [("ki", _KEYBDINPUT), ("mi", _MOUSEINPUT)]  # mi fija el tamaño correcto de INPUT (el mayor de la unión)


class INPUT(ctypes.Structure):
    _anonymous_ = ("u",)
    _fields_ = [("type", wintypes.DWORD), ("u", _INPUTUNION)]


HOOKPROC = ctypes.WINFUNCTYPE(LRESULT, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM)
user32.SetWindowsHookExW.restype = wintypes.HHOOK
user32.SetWindowsHookExW.argtypes = [ctypes.c_int, HOOKPROC, wintypes.HINSTANCE, wintypes.DWORD]
user32.CallNextHookEx.restype = LRESULT
user32.CallNextHookEx.argtypes = [wintypes.HHOOK, ctypes.c_int, wintypes.WPARAM, wintypes.LPARAM]
user32.UnhookWindowsHookEx.argtypes = [wintypes.HHOOK]
user32.SendInput.argtypes = [wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int]
kernel32.GetModuleHandleW.restype = wintypes.HMODULE
kernel32.GetModuleHandleW.argtypes = [wintypes.LPCWSTR]
kernel32.GetTickCount.restype = wintypes.DWORD


def send_mask():
    """Pulsa y suelta la tecla sin asignar."""
    events = (INPUT * 2)()
    for event, flags in zip(events, (0, KEYEVENTF_KEYUP), strict=True):
        event.type = INPUT_KEYBOARD
        event.ki = _KEYBDINPUT(VK_MASK, 0, flags, 0, 0)
    user32.SendInput(2, events, ctypes.sizeof(INPUT))


def _down(vk):
    return bool(user32.GetAsyncKeyState(vk) & 0x8000)


class KeyboardHook(threading.Thread):
    """Hilo con el gancho. `ready` se activa cuando está instalado; `failed` indica si no se pudo instalar.

    `chords` = {(capa, tecla): función} y `taps` = {capa: función}: las combinaciones de dos teclas con Alt.
    """

    def __init__(self, chords=None, taps=None):
        super().__init__(daemon=True, name="kyora-keys")
        self.ready = threading.Event()
        self.failed = False
        self._thread_id = 0
        self._block = WinBlock()
        self._chords = ChordGuard(chords or {}, taps or {})
        self._slow = (0, 0, 0.0)  # (teclas lentas, peor retraso en ms, cuándo se avisó la última vez)
        self._actions = queue.Queue()
        self._proc = HOOKPROC(self._callback)  # se guarda: si Python lo recoge, Windows llamaría a memoria liberada
        self._hook = None

    def _callback(self, code, wparam, lparam):
        try:
            if code >= 0:
                info = ctypes.cast(lparam, ctypes.POINTER(KBDLLHOOKSTRUCT)).contents
                if not info.flags & LLKHF_INJECTED:
                    self._measure(info.time)
                    down = wparam in (WM_KEYDOWN, WM_SYSKEYDOWN)
                    if self._block.feed(info.vkCode, down):
                        return 1  # la tecla Windows (y Ctrl+Esc) no llegan a nadie
                    swallow, action, mask = self._chords.feed(info.vkCode, down)
                    if action is not None:
                        self._actions.put(action)
                    if mask:
                        send_mask()
                    if swallow:
                        return 1
        except Exception:
            log.exception("Fallo en el gancho del teclado")
        return user32.CallNextHookEx(self._hook, code, wparam, lparam)

    def _measure(self, stamp):
        """Anota las teclas que llegan tarde; avisa en el registro como mucho cada SLOW_LOG_SECONDS."""
        delay = (kernel32.GetTickCount() - stamp) & 0xFFFFFFFF
        count, worst, last = self._slow
        if delay > SLOW_KEY_MS and delay < 60_000:
            count, worst = count + 1, max(worst, delay)
        now = time.monotonic()
        if count and now - last > SLOW_LOG_SECONDS:
            log.info("Teclas lentas: %s (la peor tardó %s ms en llegar a Kyora)", count, worst)
            count, worst, last = 0, 0, now
        self._slow = (count, worst, last)

    def _run_actions(self):
        while True:
            action = self._actions.get()
            if action is None:
                return
            try:
                action()
            except Exception:
                log.exception("Fallo en una combinación de teclas")

    def run(self):
        threading.Thread(target=self._run_actions, daemon=True, name="kyora-chords").start()
        self._thread_id = kernel32.GetCurrentThreadId()
        self._hook = user32.SetWindowsHookExW(WH_KEYBOARD_LL, self._proc, kernel32.GetModuleHandleW(None), 0)
        if not self._hook:
            log.error("No se pudo instalar el gancho del teclado (error %s)", ctypes.get_last_error())
            self.failed = True
            self.ready.set()
            return
        self.ready.set()
        msg = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
        user32.UnhookWindowsHookEx(self._hook)
        self._hook = None

    def stop(self):
        self._actions.put(None)
        if self._thread_id:
            user32.PostThreadMessageW(self._thread_id, WM_QUIT, 0, 0)


CREATE_NO_WINDOW = 0x08000000
CHILD_READY_SECONDS = 5


class KeyHookProcess:
    """El mismo gancho, pero en su propio proceso (kyora/system/keyproc.py): las teclas nunca esperan a Kyora.

    Se usa igual que KeyboardHook (`start`, `ready`, `failed`, `stop`). Si el proceso no se puede lanzar, usa el
    gancho de dentro, como antes.
    """

    def __init__(self, chords=None, taps=None):
        self._groups = {"chords": chords, "taps": taps}
        self.ready = threading.Event()
        self.failed = False
        self._child = None
        self._inside = None  # el gancho de dentro, si el proceso no arrancó
        self._actions = queue.Queue()

    def start(self):
        from kyora.system.keyproc import encode_bindings

        text, self._codes = encode_bindings(**self._groups)
        package_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        try:
            self._child = subprocess.Popen(
                [sys.executable, "-m", "kyora.system.keyproc"], cwd=package_root,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                text=True, encoding="utf-8", creationflags=CREATE_NO_WINDOW,
            )
            self._child.stdin.write(text + "\n")
            self._child.stdin.flush()
        except OSError as err:
            log.warning("El gancho del teclado no pudo ir en su propio proceso (%s): va dentro de Kyora", err)
            self._fallback()
            return
        threading.Thread(target=self._read, daemon=True, name="kyora-keys-pipe").start()
        threading.Thread(target=self._run_actions, daemon=True, name="kyora-chords").start()
        if not self.ready.wait(CHILD_READY_SECONDS):
            log.warning("El proceso del teclado no respondió: va dentro de Kyora")
            self._kill()
            self._fallback()

    def _fallback(self):
        g = self._groups
        self._inside = KeyboardHook(g["chords"], g["taps"])
        self._inside.start()
        self._inside.ready.wait(3)
        self.failed = self._inside.failed
        self.ready.set()

    def _read(self):
        for line in self._child.stdout:
            line = line.strip()
            if line in ("ready", "failed"):
                self.failed = line == "failed"
                self.ready.set()
            elif line.startswith("log "):
                log.info("%s", line[4:])
            elif line in self._codes:
                self._actions.put(self._codes[line])
        self._actions.put(None)  # el hijo terminó

    def _run_actions(self):
        while True:
            action = self._actions.get()
            if action is None:
                return
            try:
                action()
            except Exception:
                log.exception("Fallo en una combinación de teclas")

    def _kill(self):
        child, self._child = self._child, None
        if child is None:
            return
        try:
            child.stdin.close()  # el hijo lo nota, quita el gancho y termina
            child.wait(2)
        except (OSError, ValueError, subprocess.TimeoutExpired):
            child.kill()

    def stop(self):
        self._kill()
        if self._inside is not None:
            self._inside.stop()

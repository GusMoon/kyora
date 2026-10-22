"""Gancho global del teclado (WH_KEYBOARD_LL): la tecla Windows suelta y las combinaciones de dos teclas con Alt.

- Cuando se suelta Windows sin combinación, inyecta una tecla sin asignar justo antes y Windows entiende que se usó
  en una combinación: el menú de inicio no se abre.
- Alt+F+flechas, Alt+M+flechas… (ver kyora/core/chords.py): se tragan sus teclas y su acción se ejecuta en otro hilo,
  para que el gancho nunca haga esperar al teclado.
- Win+↑/↓, Win+Esc (ver WinComboGuard): igual, en vez de lo que haría Windows con ellas.
Si una tecla llega tarde al gancho (Python ocupado en otra cosa), se anota en kyora.log.
Las demás pulsaciones pasan sin tocarse.
"""
import ctypes
import logging
import queue
import threading
import time
from ctypes import wintypes

from kyora.core.chords import ChordGuard
from kyora.core.winkey import WIN_KEYS, WinComboGuard, WinKeyGuard

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


class KeyboardHook(threading.Thread):
    """Hilo con el gancho. `ready` se activa cuando está instalado; `failed` indica si no se pudo instalar.

    `chords` = {(capa, tecla): función} y `taps` = {capa: función}: las combinaciones de dos teclas con Alt.
    `wins` = {tecla: función}: Win+tecla que resuelve Kyora.
    """

    def __init__(self, chords=None, taps=None, wins=None):
        super().__init__(daemon=True, name="kyora-keys")
        self.ready = threading.Event()
        self.failed = False
        self._thread_id = 0
        self._guard = WinKeyGuard()
        self._chords = ChordGuard(chords or {}, taps or {})
        self._wins = WinComboGuard(wins or {})
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
                    if (info.vkCode in WIN_KEYS or down) and self._guard.feed(info.vkCode, down):
                        send_mask()
                    swallow, action = self._wins.feed(info.vkCode, down)
                    if action is not None:
                        self._actions.put(action)
                        send_mask()  # Windows no vio la tecla: sin esto, al soltar Win se abriría el menú de inicio
                    if swallow:
                        return 1
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

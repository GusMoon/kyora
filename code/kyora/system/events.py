"""Avisos de Windows cuando cambian las ventanas (sin consultar cada poco tiempo)."""
import ctypes
import logging
import threading
from ctypes import wintypes

log = logging.getLogger("kyora.events")

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32

WINEVENT_OUTOFCONTEXT = 0x0000
WINEVENT_SKIPOWNPROCESS = 0x0002
WM_QUIT = 0x0012
OBJID_WINDOW = 0
EVENT_MOVESIZESTART = 0x000A
EVENT_MOVESIZEEND = 0x000B

# (mínimo, máximo) de los eventos que interesan
EVENT_RANGES = (
    (0x0003, 0x0003),  # EVENT_SYSTEM_FOREGROUND
    (0x000A, 0x000B),  # MOVESIZESTART / MOVESIZEEND (el usuario arrastra una ventana)
    (0x0016, 0x0017),  # MINIMIZESTART / MINIMIZEEND
    (0x8001, 0x8003),  # OBJECT_DESTROY / SHOW / HIDE
    (0x8017, 0x8018),  # OBJECT_CLOAKED / UNCLOAKED
)

WinEventProc = ctypes.WINFUNCTYPE(
    None, wintypes.HANDLE, wintypes.DWORD, wintypes.HWND, wintypes.LONG, wintypes.LONG, wintypes.DWORD, wintypes.DWORD
)

user32.SetWinEventHook.restype = wintypes.HANDLE
user32.SetWinEventHook.argtypes = [
    wintypes.DWORD, wintypes.DWORD, wintypes.HMODULE, WinEventProc, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD,
]
user32.UnhookWinEvent.argtypes = [wintypes.HANDLE]


class EventHook(threading.Thread):
    """Hilo con su propio bucle de mensajes que llama a `on_event(evento, hwnd)` cuando algo cambia."""

    def __init__(self, on_event):
        super().__init__(daemon=True, name="kyora-events")
        self._on_event = on_event
        self._thread_id = 0
        self._callback = None  # se guarda para que Python no lo libere mientras Windows lo usa

    def _handle(self, hook, event, hwnd, id_object, id_child, thread, time):
        if hwnd and id_object == OBJID_WINDOW and id_child == 0:
            try:
                self._on_event(event, hwnd)
            except Exception:
                log.exception("Fallo en el aviso de eventos")

    def run(self):
        self._callback = WinEventProc(self._handle)
        self._thread_id = kernel32.GetCurrentThreadId()
        hooks = []
        for low, high in EVENT_RANGES:
            hook = user32.SetWinEventHook(
                low, high, None, self._callback, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
            )
            if hook:
                hooks.append(hook)
            else:
                log.error("No se pudo registrar el aviso de eventos %s-%s", hex(low), hex(high))
        msg = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
        for hook in hooks:
            user32.UnhookWinEvent(hook)

    def stop(self):
        if self._thread_id:
            user32.PostThreadMessageW(self._thread_id, WM_QUIT, 0, 0)

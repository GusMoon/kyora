"""Todo lo específico de Windows: ventanas ajenas y barra de tareas (la interfaz de Kyora es Qt, en kyora/ui).

El resto del programa solo conoce estas clases; para otro sistema operativo bastaría
con escribir un equivalente.
"""
import ctypes
import json
import logging
from ctypes import wintypes

import psutil
import pywintypes
import win32api
import win32con
import win32gui
import win32process

from kyora.config import data_dir
from kyora.core.layout import Rect

log = logging.getLogger("kyora.win32")

dwmapi = ctypes.windll.dwmapi
user32 = ctypes.windll.user32
DWMWA_CLOAKED = 14
DWMWA_EXTENDED_FRAME_BOUNDS = 9
DWMWA_TRANSITIONS_FORCEDISABLED = 3  # sin las animaciones de Windows al mostrar, ocultar o mover
MIN_WINDOW_SIZE = (100, 50)


_gdi32 = ctypes.WinDLL("gdi32")
_gdi32.CreateCompatibleDC.restype = wintypes.HDC
_gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
_gdi32.CreateCompatibleBitmap.restype = wintypes.HBITMAP
_gdi32.CreateCompatibleBitmap.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int]
_gdi32.SelectObject.restype = wintypes.HGDIOBJ
_gdi32.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
_gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]
_gdi32.DeleteDC.argtypes = [wintypes.HDC]
_gdi32.SetStretchBltMode.argtypes = [wintypes.HDC, ctypes.c_int]
_gdi32.StretchBlt.argtypes = [
    wintypes.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
    wintypes.HDC, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, wintypes.DWORD,
]
_gdi32.GetDIBits.argtypes = [wintypes.HDC, wintypes.HBITMAP, wintypes.UINT, wintypes.UINT, ctypes.c_void_p, ctypes.c_void_p, wintypes.UINT]
user32.GetDC.restype = wintypes.HDC
user32.GetDC.argtypes = [wintypes.HWND]
user32.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
user32.PrintWindow.argtypes = [wintypes.HWND, wintypes.HDC, wintypes.UINT]
PW_RENDERFULLCONTENT = 0x2
SRCCOPY = 0x00CC0020
HALFTONE = 4
THUMB_MAX_SIDE = 640  # px físicos del lado mayor de una captura guardada (sobra para el panel de espera y gasta 4 veces menos)


class _BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG), ("biHeight", wintypes.LONG),
        ("biPlanes", wintypes.WORD), ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", wintypes.LONG), ("biYPelsPerMeter", wintypes.LONG),
        ("biClrUsed", wintypes.DWORD), ("biClrImportant", wintypes.DWORD),
    ]


def make_dpi_aware():
    """Hay que llamarlo antes de crear ninguna ventana, o las coordenadas salen escaladas."""
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(2)
    except OSError:
        pass


def _primary_monitor():
    return win32api.MonitorFromPoint((0, 0), win32con.MONITOR_DEFAULTTOPRIMARY)


def _is_cloaked(hwnd):
    value = wintypes.DWORD()
    dwmapi.DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, ctypes.byref(value), ctypes.sizeof(value))
    return value.value != 0


def _frame_bounds(hwnd):
    """Rectángulo realmente visible (sin el borde invisible que Windows 10/11 añade)."""
    rect = wintypes.RECT()
    dwmapi.DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, ctypes.byref(rect), ctypes.sizeof(rect))
    return rect.left, rect.top, rect.right, rect.bottom


def force_foreground(hwnd):
    if win32gui.IsIconic(hwnd):
        win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
    # Windows deja pasar al frente a quien acaba de recibir una entrada: una tecla sin asignar (que no hace nada)
    # pulsada y soltada desde Kyora le da ese derecho aunque la tecla que lo abrió la leyera el otro proceso
    win32api.keybd_event(0xE8, 0, 0, 0)
    win32api.keybd_event(0xE8, 0, win32con.KEYEVENTF_KEYUP, 0)
    try:
        win32gui.SetForegroundWindow(hwnd)
        return
    except pywintypes.error:
        pass
    # Windows solo deja pasar al primer plano al proceso que lo tiene: se engancha su hilo de entrada.
    current = win32api.GetCurrentThreadId()
    foreground = win32process.GetWindowThreadProcessId(win32gui.GetForegroundWindow())[0]
    try:
        win32process.AttachThreadInput(current, foreground, True)
        win32gui.SetForegroundWindow(hwnd)
    except pywintypes.error as err:
        log.warning("No se pudo dar el foco a %s: %s", hwnd, err)
    finally:
        try:  # también puede negarse (ventana con otros permisos): nunca debe romper a quien llama
            win32process.AttachThreadInput(current, foreground, False)
        except pywintypes.error:
            pass


class Win32System:
    def __init__(self, config):
        self.cfg = config
        self._ignored = {name.lower() for name in config["ignore_processes"]}
        self._own = set()
        self._names = {}
        # hwnd -> (pid, valor): abrir el proceso con psutil cuesta, y se consulta en cada sync y en cada tecla del
        # buscador. El pid se comprueba siempre (es barato) por si el número de ventana se reutiliza.
        self._process_names = {}
        self._exe_paths = {}
        self._warned = set()
        self._registry_path = data_dir() / "hidden.json"
        self._hidden = {}
        self._dirty = False  # hidden.json está por guardar (se escribe una vez por pasada del gestor, en flush)
        self._quiet = set()  # ventanas a las que se les quitaron las animaciones de Windows

    # ---------- consulta ----------

    def add_own_window(self, hwnd):
        self._own.add(hwnd)

    def work_area(self):
        info = win32api.GetMonitorInfo(_primary_monitor())
        left, top, right, bottom = info["Monitor"] if self.cfg["hide_taskbar"] else info["Work"]
        return Rect(left, top, right, bottom)

    def is_alive(self, hwnd):
        return bool(win32gui.IsWindow(hwnd))

    def is_shown(self, hwnd):
        return bool(win32gui.IsWindowVisible(hwnd))

    def is_minimized(self, hwnd):
        return bool(win32gui.IsIconic(hwnd))

    @staticmethod
    def is_resizable(hwnd):
        """True si la ventana tiene borde para cambiar de tamaño (las calculadoras y los avisos fijos, no) y no está
        maximizada."""
        style = win32gui.GetWindowLong(hwnd, win32con.GWL_STYLE)
        return bool(style & win32con.WS_THICKFRAME) and not user32.IsZoomed(hwnd)

    def is_manageable(self, hwnd):
        return self.is_alive(hwnd) and self.is_shown(hwnd) and not _is_cloaked(hwnd)

    def foreground(self):
        return win32gui.GetForegroundWindow()

    @staticmethod
    def frame_rect(hwnd):
        """Rectángulo realmente visible de una ventana."""
        return Rect(*_frame_bounds(hwnd))

    @staticmethod
    def window_at(x, y):
        """Ventana de nivel superior que hay bajo el punto (x, y) de la pantalla."""
        hwnd = win32gui.WindowFromPoint((x, y))
        return win32gui.GetAncestor(hwnd, win32con.GA_ROOT) if hwnd else 0

    @staticmethod
    def _cached(cache, hwnd, read):
        """Dato del proceso de la ventana (`read(proceso)`), guardado por ventana y pid ('' si no se puede saber)."""
        try:
            pid = win32process.GetWindowThreadProcessId(hwnd)[1]
        except pywintypes.error:
            return ""
        hit = cache.get(hwnd)
        if hit and hit[0] == pid:
            return hit[1]
        try:
            value = read(psutil.Process(pid))
        except psutil.Error:
            return ""
        cache[hwnd] = (pid, value)
        return value

    def _process_name(self, hwnd):
        return self._cached(self._process_names, hwnd, lambda proc: proc.name())

    def _candidate(self, hwnd):
        """Ventanas de aplicación que Kyora debe gestionar."""
        if hwnd in self._own or not win32gui.IsWindowVisible(hwnd) or win32gui.IsIconic(hwnd):
            return False
        if _is_cloaked(hwnd) or not win32gui.GetWindowText(hwnd):
            return False
        if win32gui.GetWindow(hwnd, win32con.GW_OWNER):
            return False
        ex_style = win32gui.GetWindowLong(hwnd, win32con.GWL_EXSTYLE)
        if ex_style & win32con.WS_EX_TOOLWINDOW and not ex_style & win32con.WS_EX_APPWINDOW:
            return False
        if win32gui.GetClassName(hwnd) in ("Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd"):
            return False
        left, top, right, bottom = win32gui.GetWindowRect(hwnd)
        if right - left < MIN_WINDOW_SIZE[0] or bottom - top < MIN_WINDOW_SIZE[1]:
            return False
        if win32api.MonitorFromWindow(hwnd, win32con.MONITOR_DEFAULTTONEAREST) != _primary_monitor():
            return False
        return self._process_name(hwnd).lower() not in self._ignored

    def list_windows(self):
        """Ventanas gestionables, de la más cercana a la más lejana (el orden de Windows)."""
        found = []
        win32gui.EnumWindows(lambda hwnd, _: found.append(hwnd) if self._candidate(hwnd) else None, None)
        return found

    def exe_path(self, hwnd):
        """Ruta del programa al que pertenece la ventana ('' si no se puede saber)."""
        return self._cached(self._exe_paths, hwnd, lambda proc: proc.exe())

    @staticmethod
    def capture(hwnd):
        """Captura reducida de una ventana visible: (ancho, alto, bytes BGRX) o None si no se pudo.

        El cuarto byte de cada píxel no vale nada (PrintWindow lo deja a 0): hay que leerla como RGB32, sin alfa.
        """
        if win32gui.IsIconic(hwnd) or not win32gui.IsWindowVisible(hwnd):
            return None
        left, top, right, bottom = win32gui.GetWindowRect(hwnd)
        width, height = right - left, bottom - top
        if width < 16 or height < 16:
            return None
        scale = min(1.0, THUMB_MAX_SIDE / max(width, height))
        tw, th = max(int(width * scale), 1), max(int(height * scale), 1)
        screen = user32.GetDC(None)
        full_dc, small_dc = _gdi32.CreateCompatibleDC(screen), _gdi32.CreateCompatibleDC(screen)
        full_bmp = _gdi32.CreateCompatibleBitmap(screen, width, height)
        small_bmp = _gdi32.CreateCompatibleBitmap(screen, tw, th)
        try:
            old_full, old_small = _gdi32.SelectObject(full_dc, full_bmp), _gdi32.SelectObject(small_dc, small_bmp)
            if not user32.PrintWindow(hwnd, full_dc, PW_RENDERFULLCONTENT):
                return None
            _gdi32.SetStretchBltMode(small_dc, HALFTONE)
            _gdi32.StretchBlt(small_dc, 0, 0, tw, th, full_dc, 0, 0, width, height, SRCCOPY)
            _gdi32.SelectObject(small_dc, old_small)
            _gdi32.SelectObject(full_dc, old_full)
            header = _BITMAPINFOHEADER(ctypes.sizeof(_BITMAPINFOHEADER), tw, -th, 1, 32, 0, 0, 0, 0, 0, 0)  # -alto: de arriba a abajo
            buf = ctypes.create_string_buffer(tw * th * 4)
            if not _gdi32.GetDIBits(small_dc, small_bmp, 0, th, buf, ctypes.byref(header), 0):
                return None
            return tw, th, buf.raw
        finally:
            _gdi32.DeleteObject(full_bmp)
            _gdi32.DeleteObject(small_bmp)
            _gdi32.DeleteDC(full_dc)
            _gdi32.DeleteDC(small_dc)
            user32.ReleaseDC(None, screen)

    def describe(self, hwnd):
        title = win32gui.GetWindowText(hwnd) if self.is_alive(hwnd) else ""
        app = self._names.get(hwnd)
        if app is None:
            process = self._process_name(hwnd)
            name = process[:-4] if process.lower().endswith(".exe") else process
            app = title if name.lower() == "applicationframehost" else name[:1].upper() + name[1:]
            self._names[hwnd] = app or "Ventana"
        return self._names[hwnd], title

    # ---------- acciones sobre ventanas ----------

    def _guarded(self, hwnd, action, fn):
        try:
            return fn()
        except pywintypes.error as err:
            key = (hwnd, action)
            if key not in self._warned:
                self._warned.add(key)
                log.warning("No se pudo %s la ventana %s (¿se ejecuta como administrador?): %s", action, hwnd, err)

    def _silence(self, hwnd, quiet=True):
        """Quita (o devuelve) las transiciones de Windows: el relevo de ventanas en un hueco es instantáneo."""
        value = ctypes.c_int(1 if quiet else 0)
        dwmapi.DwmSetWindowAttribute(hwnd, DWMWA_TRANSITIONS_FORCEDISABLED, ctypes.byref(value), ctypes.sizeof(value))
        (self._quiet.add if quiet else self._quiet.discard)(hwnd)

    def place(self, hwnd, rect, keep=False):
        """Coloca la ventana en `rect` y devuelve dónde quedó de verdad (None si falló). Con `keep`, una ventana
        maximizada sigue maximizada (solo se mueve: las ventanas libres no cambian de tamaño).

        Una app con tamaño mínimo (Calculadora, Fotos…) no se deja encoger: queda más grande que `rect`.
        """

        def run():
            if hwnd not in self._quiet:
                self._silence(hwnd)
            if win32gui.IsIconic(hwnd) or (user32.IsZoomed(hwnd) and not keep):
                win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
            fl, ft, fr, fb = _frame_bounds(hwnd)
            wl, wt, wr, wb = win32gui.GetWindowRect(hwnd)
            pad_l, pad_t, pad_r, pad_b = fl - wl, ft - wt, wr - fr, wb - fb
            if (fl, ft, fr, fb) == (rect.left, rect.top, rect.right, rect.bottom):
                return rect
            flags = win32con.SWP_NOZORDER | win32con.SWP_NOACTIVATE
            if (fr - fl, fb - ft) == (rect.width, rect.height):
                # solo se mueve: sin avisar del tamaño (la app no recompone su contenido, no se deforma ni se
                # pausa) y sin esperarla (si la app tarda en responder, Kyora no se queda parado con ella)
                win32gui.SetWindowPos(hwnd, 0, rect.left - pad_l, rect.top - pad_t, 0, 0,
                                      flags | win32con.SWP_NOSIZE | win32con.SWP_ASYNCWINDOWPOS)
                return rect
            win32gui.SetWindowPos(
                hwnd, 0, rect.left - pad_l, rect.top - pad_t,
                rect.width + pad_l + pad_r, rect.height + pad_t + pad_b, flags,
            )
            # SetWindowPos espera a la app, así que el rectángulo ya es el definitivo (con los mismos bordes invisibles)
            wl, wt, wr, wb = win32gui.GetWindowRect(hwnd)
            return Rect(wl + pad_l, wt + pad_t, wr - pad_r, wb - pad_b)

        return self._guarded(hwnd, "colocar", run)

    def hide(self, hwnd):
        def run():
            pid = win32process.GetWindowThreadProcessId(hwnd)[1]
            self._hidden[hwnd] = (pid, win32gui.GetClassName(hwnd))
            self._dirty = True
            win32gui.ShowWindow(hwnd, win32con.SW_HIDE)

        self._guarded(hwnd, "ocultar", run)

    def show(self, hwnd):
        def run():
            if hwnd not in self._quiet:
                self._silence(hwnd)
            win32gui.ShowWindow(hwnd, win32con.SW_SHOWNOACTIVATE)
            if self._hidden.pop(hwnd, None):
                self._dirty = True

        self._guarded(hwnd, "mostrar", run)

    def raise_(self, hwnd):
        """Pone la ventana por encima de las demás sin darle el foco (la ventana en grande de Alt+C)."""
        flags = win32con.SWP_NOMOVE | win32con.SWP_NOSIZE | win32con.SWP_NOACTIVATE
        self._guarded(hwnd, "subir", lambda: win32gui.SetWindowPos(hwnd, win32con.HWND_TOP, 0, 0, 0, 0, flags))

    def focus(self, hwnd):
        self._guarded(hwnd, "enfocar", lambda: force_foreground(hwnd))

    def close(self, hwnd):
        self._guarded(hwnd, "cerrar", lambda: win32gui.PostMessage(hwnd, win32con.WM_CLOSE, 0, 0))

    # ---------- ratón (para arrastrar ventanas en espera) ----------

    @staticmethod
    def cursor_pos():
        return win32api.GetCursorPos()

    @staticmethod
    def shift_down():
        return bool(win32api.GetAsyncKeyState(win32con.VK_SHIFT) & 0x8000)

    @staticmethod
    def left_button_down():
        return bool(win32api.GetAsyncKeyState(win32con.VK_LBUTTON) & 0x8000)

    # ---------- registro de ventanas ocultas (recuperación tras un cierre brusco) ----------

    def flush(self):
        """Guarda hidden.json si cambió: una escritura por pasada del gestor y no una por ventana."""
        if self._dirty:
            self._save_registry()

    def _save_registry(self):
        self._dirty = False
        data = [{"hwnd": h, "pid": pid, "cls": cls} for h, (pid, cls) in self._hidden.items()]
        try:
            self._registry_path.write_text(json.dumps(data), encoding="utf-8")
        except OSError as err:
            log.warning("No se pudo guardar hidden.json: %s", err)

    def recover(self):
        """Vuelve a mostrar las ventanas que una sesión anterior dejó ocultas. Devuelve cuántas."""
        try:
            entries = json.loads(self._registry_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return 0
        count = 0
        for entry in entries:
            hwnd = entry.get("hwnd", 0)
            try:
                same = (
                    win32gui.IsWindow(hwnd)
                    and not win32gui.IsWindowVisible(hwnd)
                    and win32process.GetWindowThreadProcessId(hwnd)[1] == entry.get("pid")
                    and win32gui.GetClassName(hwnd) == entry.get("cls")
                )
                if same:
                    win32gui.ShowWindow(hwnd, win32con.SW_SHOWNOACTIVATE)
                    count += 1
            except pywintypes.error:
                continue
        self._hidden.clear()
        self._save_registry()
        for hwnd in list(self._quiet):  # las ventanas vuelven a Windows con sus animaciones
            if win32gui.IsWindow(hwnd):
                self._silence(hwnd, quiet=False)
        self._quiet.clear()
        return count


ABM_GETSTATE, ABM_SETSTATE = 0x4, 0xA
ABS_AUTOHIDE = 0x1


class _AppBarData(ctypes.Structure):
    _fields_ = [("cbSize", wintypes.DWORD), ("hWnd", wintypes.HWND), ("uCallbackMessage", wintypes.UINT),
                ("uEdge", wintypes.UINT), ("rc", wintypes.RECT), ("lParam", ctypes.c_ssize_t)]


def _appbar(message, hwnd, state=0):
    """SHAppBarMessage con el estado de la barra de tareas (ABM_GETSTATE / ABM_SETSTATE); devuelve lo que contesta."""
    data = _AppBarData(ctypes.sizeof(_AppBarData), hwnd, 0, 0, wintypes.RECT(), state)
    shell = ctypes.windll.shell32.SHAppBarMessage
    shell.restype = ctypes.c_size_t
    shell.argtypes = [wintypes.DWORD, ctypes.POINTER(_AppBarData)]
    return shell(message, ctypes.byref(data))


class Taskbar:
    CLASSES = ("Shell_TrayWnd", "Shell_SecondaryTrayWnd")

    def __init__(self):
        self._hidden_by_us = set()
        self._autohide_path = data_dir() / "taskbar_autohide.json"
        self._autohide_off = False

    def _find(self):
        found = []
        for cls in self.CLASSES:
            hwnd = 0
            while True:
                hwnd = win32gui.FindWindowEx(0, hwnd, cls, None)
                if not hwnd:
                    break
                found.append(hwnd)
        return found

    def _disable_autohide(self):
        """Con "ocultar automáticamente" activo, Windows la hace salir sola al llevar el cursor al borde de abajo, aunque
        esté escondida. Se apaga mientras Kyora corre (y se apunta para devolverlo al salir, aunque Kyora se cierre mal)."""
        if self._autohide_off:
            return
        main = win32gui.FindWindow("Shell_TrayWnd", None)
        if not main:
            return
        try:
            state = _appbar(ABM_GETSTATE, main)
            if state & ABS_AUTOHIDE:
                self._autohide_path.write_text(json.dumps({"autohide": True}), encoding="utf-8")
                _appbar(ABM_SETSTATE, main, state & ~ABS_AUTOHIDE)
            self._autohide_off = True
        except (OSError, AttributeError):
            log.warning("No se pudo apagar el ocultado automático de la barra de tareas", exc_info=True)

    def _restore_autohide(self):
        try:
            wanted = json.loads(self._autohide_path.read_text(encoding="utf-8")).get("autohide")
        except (OSError, ValueError):
            wanted = False
        main = win32gui.FindWindow("Shell_TrayWnd", None)
        if wanted and main:
            try:
                _appbar(ABM_SETSTATE, main, _appbar(ABM_GETSTATE, main) | ABS_AUTOHIDE)
            except (OSError, AttributeError):
                log.warning("No se pudo devolver el ocultado automático de la barra de tareas", exc_info=True)
        if wanted:
            try:
                self._autohide_path.unlink()
            except OSError:
                pass
        self._autohide_off = False

    def hide(self):
        self._disable_autohide()
        for hwnd in self._find():
            if win32gui.IsWindowVisible(hwnd):
                self._hidden_by_us.add(hwnd)
                win32gui.ShowWindow(hwnd, win32con.SW_HIDE)

    def keep_hidden(self):
        """Explorer vuelve a mostrar la barra (por ejemplo con la tecla Windows); se vuelve a ocultar."""
        if self._hidden_by_us:
            self.hide()

    def restore(self, force=False):
        for hwnd in self._find():
            if force or hwnd in self._hidden_by_us:
                win32gui.ShowWindow(hwnd, win32con.SW_SHOWNA)
        self._hidden_by_us.clear()
        if self._autohide_off or force:
            self._restore_autohide()

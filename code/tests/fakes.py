from kyora.core.layout import Rect


class FakeSystem:
    """Sistema de ventanas simulado para probar WindowManager sin Windows."""

    def __init__(self, area=None):
        self.area = area or Rect(0, 0, 1920, 1200)
        self.alive = set()
        self.shown = set()
        self.minimized = set()
        self.rects = {}
        self.fg = 0
        self.focused = []
        self.closed = []
        self.calls = []
        self.under = 0  # ventana que hay bajo el cursor en las pruebas
        self.min_sizes = {}  # hwnd -> (ancho, alto): apps que no se dejan encoger

    # ---- manipulación desde las pruebas ----
    def open(self, hwnd):
        self.alive.add(hwnd)
        self.shown.add(hwnd)
        self.fg = hwnd

    def kill(self, hwnd):
        self.alive.discard(hwnd)
        self.shown.discard(hwnd)

    # ---- interfaz que usa WindowManager ----
    def work_area(self):
        return self.area

    def list_windows(self):
        return [h for h in sorted(self.alive, reverse=True) if h in self.shown and h not in self.minimized]

    def is_alive(self, hwnd):
        return hwnd in self.alive

    def is_manageable(self, hwnd):
        return hwnd in self.alive and hwnd in self.shown

    def is_minimized(self, hwnd):
        return hwnd in self.minimized

    def is_shown(self, hwnd):
        return hwnd in self.shown

    def foreground(self):
        return self.fg

    def show(self, hwnd):
        self.calls.append(("show", hwnd))
        self.shown.add(hwnd)

    def hide(self, hwnd):
        self.calls.append(("hide", hwnd))
        self.shown.discard(hwnd)

    def place(self, hwnd, rect):
        self.minimized.discard(hwnd)
        min_w, min_h = self.min_sizes.get(hwnd, (0, 0))
        self.rects[hwnd] = Rect(rect.left, rect.top, rect.left + max(rect.width, min_w), rect.top + max(rect.height, min_h))
        return self.rects[hwnd]

    def focus(self, hwnd):
        self.fg = hwnd
        self.focused.append(hwnd)

    def close(self, hwnd):
        self.closed.append(hwnd)

    def describe(self, hwnd):
        return f"App{hwnd}", f"Ventana {hwnd}"

    def exe_path(self, hwnd):
        return f"C:/fake/App{hwnd}.exe"

    def capture(self, hwnd):
        return (2, 1, bytes([hwnd % 256]) * 8) if hwnd in self.shown else None

    def frame_rect(self, hwnd):
        return self.rects[hwnd]

    def window_at(self, x, y):
        return self.under

"""El panel superior: sale del borde de arriba de la pantalla al acercar el cursor y se esconde al quitarlo.

Es una sola pieza suelta (sin marco) con la fila de accesos: Buscar, Tareas, Notas, Música y Fondos (lo de sistema, como
la hora, el wifi o la batería, está en el panel de la esquina de abajo, `quickdock.py`). Música se abre debajo de la fila;
los demás piden su acción. Al cerrarse (el cursor se va) no se queda nada en pantalla.

El cursor se mira con un temporizador de 50 ms en vez de con una ventana fina en el borde: así no estorba a los botones
que las apps tienen pegados al borde de arriba y no gasta nada mientras el panel está abierto.
"""
import ctypes

from PySide6.QtCore import QRect, Qt, QTimer, Signal
from PySide6.QtGui import QCursor
from PySide6.QtWidgets import QVBoxLayout

from kyora.ui.dock import DockPage, PageDock
from kyora.ui.musicpage import MusicPage
from kyora.ui.sectionbar import ROW_H, StatusRow

PAD = 8  # el margen de la pieza (el mismo que `EdgePopout.pad`)
SUB_GAP = 6
HOT_MS = 50  # cada cuánto se mira si el cursor está en el borde de arriba
VK_LBUTTON = 0x01


def _button_down():
    """True si el botón izquierdo está pulsado (se arrastra una ventana hacia arriba: el panel no debe saltar)."""
    return bool(ctypes.windll.user32.GetAsyncKeyState(VK_LBUTTON) & 0x8000)


class TopPage(DockPage):
    """Una página del panel superior: la fila de estado y, debajo, la página de la hora, el wifi o el Bluetooth."""

    go = Signal(str)
    hover_go = Signal(str)  # el cursor se quedó sobre un icono: cambiar de página al instante
    run = Signal(str)  # un acceso que no es una página (buscar, tareas, notas, fondos)

    def __init__(self, theme, name, sub=None, width=420):
        super().__init__()
        self.theme, self.name = theme, name
        self.sub = sub
        self.row = StatusRow(theme)
        self.row.set_active(name)
        self.row.go.connect(self._row_go)
        self.row.run.connect(self.run)
        self.row.hover.connect(self._row_hover)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(SUB_GAP)
        layout.addWidget(self.row, 0, Qt.AlignHCenter)
        height = 2 * PAD + ROW_H
        if sub is not None:
            w, h = sub.size[0] - 2 * PAD, sub.size[1] - 2 * PAD  # las páginas se pensaron con su propio margen
            sub.setFixedSize(w, h)
            sub.close_requested.connect(self.close_requested)
            layout.addWidget(sub, 0, Qt.AlignHCenter)
            height += SUB_GAP + h
        layout.addStretch(1)
        self.sub_width = sub.width() + 2 * PAD if sub is not None else 0
        self.height_ = height
        self.fit()

    def fit(self):
        """El ancho justo: el de la fila o el de la página de debajo, el que sea mayor."""
        row = self.row.sizeHint().width()
        if self.name in self.row.chips:  # con su nombre, la sección abierta tiene que caber
            row = max(row, self.row.needed_width(self.name))
        self.size = (self.height_, max(row, self.sub_width) + 2 * PAD)
        if self.sub is not None:  # la sección abierta ocupa el ancho de la página de debajo
            self.row.set_fill(self.size[1] - 2 * PAD)

    def _row_hover(self, name):
        if name != self.name:  # pasar por encima del icono de la página que ya está abierta no la cierra
            self.hover_go.emit(name)

    def _row_go(self, name):
        self.go.emit("main" if name == self.name else name)  # pulsar el icono de la página abierta la repliega

    def activate(self):
        if self.sub is not None:
            self.sub.activate()

    def focus_first(self):
        if self.sub is not None:
            self.sub.focus_first()
        else:
            self.setFocus()


ACTIONS = {  # lo que pide cada acceso de la fila (el mismo atajo que ya existe)
    "search": ("search.toggle", {}),
    "task": ("search.open_mode", {"mode": "task"}),
    "notes": ("search.open_mode", {"mode": "notes"}),
    "chat": ("search.open_mode", {"mode": "chat"}),
}


class TopDock(PageDock):
    def __init__(self, theme, screen_map, invoke):
        width = theme.top_width
        music = MusicPage(theme, invoke)
        pages = {
            "main": TopPage(theme, "main", width=width),
            "music": TopPage(theme, "music", music, width),
        }
        super().__init__(theme, screen_map, pages, edge="top", title="KyoraTop")
        self.music = music
        self._invoke = invoke
        self.suspended = False
        for page in pages.values():
            page.go.connect(self.show_sub)
            page.hover_go.connect(self.switch_now)
            page.run.connect(self._run)
        self._hot = QTimer(self)
        self._hot.setInterval(HOT_MS)
        self._hot.timeout.connect(self._poll)
        self._hot.start()

    def _run(self, name):
        """Buscar, Tareas, Notas o Fondos: la misma acción que su atajo (el panel se esconde: lo que se abre ocupa su sitio)."""
        action, payload = ACTIONS[name]
        self.close_popout()
        self._invoke(action, **payload)

    # ---------- abrir con el cursor ----------

    def suspend(self, on):
        """Con el buscador, el modo de fondos o apagar abiertos, el panel no salta (y se esconde si estaba)."""
        self.suspended = on
        if on:
            self.close_popout()

    def _zone(self):
        g = self.map.geometry
        width = min(self.theme.top_zone, g.width())
        return QRect(round(g.x() + (g.width() - width) / 2), g.y(), width, 6)

    def _poll(self):
        if self.opened or self.suspended:
            return
        zone = self._zone()
        pos = QCursor.pos()
        if pos.y() > zone.y() + 1 or not zone.left() <= pos.x() <= zone.right() or _button_down():
            return
        self.show_page("main", zone)

    def show_sub(self, name):
        """Pulsar la hora, el wifi o el Bluetooth: la pieza se transforma hacia su página (o vuelve a la fila)."""
        self.show_page(name, self._zone() if self.hover else None)

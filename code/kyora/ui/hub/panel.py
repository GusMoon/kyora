"""El panel de arriba de Kyora: sale del borde superior del marco con Lobby, Archivos, Tareas, Segundo Cerebro y
Kyora.

Se parece a la referencia: arriba a la izquierda las migas de pan y, centrada, la mini barra de secciones (la activa
es una píldora clara que se desliza); debajo, una línea y el contenido en placas de cristal.

Atajos: Win+I / Win+E / Win+T / Win+B / Win+K abren cada sección (desde cualquier sitio); dentro, Ctrl+1…5 y
Ctrl+Tab (Ctrl+Mayús+Tab hacia atrás). Se cierra al perder el foco o con Esc (que antes cierra lo que haya abierto
dentro).
"""
from PySide6.QtCore import QRectF, Qt
from PySide6.QtGui import QColor, QKeySequence, QPainter, QShortcut
from PySide6.QtWidgets import (
    QFrame,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QSizePolicy,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from kyora.ui import glyphs
from kyora.ui.explorer.panel import FilesPage
from kyora.ui.explorer.style import stylesheet
from kyora.ui.hub.brain_page import BrainPage
from kyora.ui.hub.kyora_page import KyoraPage
from kyora.ui.hub.lobby_page import LobbyPage
from kyora.ui.hub.nav import SECTIONS, SectionBar
from kyora.ui.hub.tasks_page import TasksPage
from kyora.ui.popout import EdgePopout

ORDER = [key for key, _, _ in SECTIONS]
LEAVES = {"lobby": "Lobby", "tasks": "Tareas", "brain": "Segundo Cerebro", "kyora": "Kyora"}


class HomeIcon(QWidget):
    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.setFixedSize(24, 24)

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(glyphs.pen(QColor(self.theme.dim), 1.7))
        glyphs.home(p, QRectF(self.rect()).adjusted(2, 2, -2, -2))


class KyoraHub(EdgePopout):
    def __init__(self, theme, screen_map, call, invoke):
        t = theme
        g = screen_map.geometry
        hole_w = g.width() - t.bar_width - t.frame_width
        hole_h = g.height() - 2 * t.frame_width
        super().__init__(theme, screen_map, "top", depth=round(hole_h * t.hub_height),
                         length=round(hole_w * t.hub_width), title="KyoraHub", pad=12)
        self.setStyleSheet(stylesheet(t))
        self.body.setObjectName("ExplorerBody")
        self.current = "lobby"

        self.lobby = LobbyPage(t, invoke)
        self.files = FilesPage(t, call)
        self.tasks = TasksPage(t, call)
        self.brain = BrainPage(t, call)
        self.kyora = KyoraPage(t, invoke, close=self.close_popout)
        self.by_key = {"lobby": self.lobby, "files": self.files, "tasks": self.tasks, "brain": self.brain,
                       "kyora": self.kyora}
        self.sections = SectionBar(t)
        self.sections.chosen.connect(self.show_section)

        # migas de pan: casa · sección / … (en Archivos, la ruta con sus tramos), y en el centro la mini barra
        self.section_label = QLabel("Archivos")
        self.section_label.setObjectName("CrumbRoot")
        self.slash = QLabel("/")
        self.slash.setObjectName("CrumbRoot")
        self.leaf = QLabel("")
        self.leaf.setObjectName("CrumbLeaf")
        self.crumb_tail = QStackedWidget()
        self.crumb_tail.addWidget(self.files.pathbar)
        self.crumb_tail.addWidget(self.leaf)
        crumbs = QWidget()
        crumbs.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)  # nunca empuja la mini barra del centro
        trail = QHBoxLayout(crumbs)
        trail.setContentsMargins(4, 0, 0, 0)
        trail.setSpacing(6)
        trail.addWidget(HomeIcon(t))
        trail.addWidget(self.section_label)
        trail.addWidget(self.slash)
        trail.addWidget(self.crumb_tail, 1)
        head = QGridLayout()
        head.setContentsMargins(0, 0, 0, 0)
        head.setHorizontalSpacing(12)
        head.addWidget(crumbs, 0, 0)
        head.addWidget(self.sections, 0, 1, Qt.AlignCenter)
        head.addWidget(QWidget(), 0, 2)  # la columna derecha, igual que la izquierda: la barra queda en el centro
        head.setColumnStretch(0, 1)
        head.setColumnStretch(2, 1)
        divider = QFrame()
        divider.setObjectName("Divider")
        divider.setFixedHeight(1)

        self.pages = QStackedWidget()
        for key in ORDER:
            self.pages.addWidget(self.by_key[key])
        layout = QVBoxLayout(self.body)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(10)
        layout.addLayout(head)
        layout.addWidget(divider)
        layout.addWidget(self.pages, 1)
        self._shortcuts()
        self.show_section("lobby")

    # ---------- secciones ----------

    def show_section(self, key):
        if key not in self.by_key:
            key = "lobby"
        changed = key != self.current
        self.current = key
        self.sections.set_active(key)
        page = self.by_key[key]
        self.pages.setCurrentWidget(page)
        self.section_label.setVisible(key != "files")  # en Archivos la ruta ocupa todo el sitio
        self.slash.setVisible(key != "files")
        if key == "files":
            self.crumb_tail.setCurrentWidget(self.files.pathbar)
        else:
            self.section_label.setText("Kyora")
            self.leaf.setText(LEAVES[key])
            self.crumb_tail.setCurrentWidget(self.leaf)
        if changed and self.opened and key in ("tasks", "brain"):
            page.activate()  # al entrar se vuelve a leer (al abrir el panel lo hace before_open)
        self.focus_first()

    def step_section(self, delta):
        self.show_section(ORDER[(ORDER.index(self.current) + delta) % len(ORDER)])

    def toggle_section(self, key="lobby"):
        """Win+I/E/T/B/K: abre en esa sección; si ya estaba abierto en ella, se cierra."""
        if self.opened and self.current == key:
            self.close_popout()
            return
        self.show_section(key)
        if not self.opened:
            self.open()

    def _shortcuts(self):
        keys = {f"Ctrl+{i + 1}": (lambda k=key: self.show_section(k)) for i, key in enumerate(ORDER)}
        keys["Ctrl+Tab"] = lambda: self.step_section(1)
        keys["Ctrl+Shift+Tab"] = lambda: self.step_section(-1)
        for key, fn in keys.items():
            QShortcut(QKeySequence(key), self, fn, context=Qt.WindowShortcut)

    # ---------- abrir y cerrar ----------

    def before_open(self):
        self.files.activate()
        if self.current in ("tasks", "brain"):
            self.by_key[self.current].activate()

    def after_close(self):
        self.files.deactivate()
        self.brain.deactivate()
        self.tasks.flush()

    def focus_first(self):
        page = self.by_key[self.current]
        if self.current == "files":
            self.files.focus_view()
        elif hasattr(page, "focus_first"):
            page.focus_first()
        else:
            page.setFocus()

    def escape(self):
        if self.current == "files" and self.files.escape():
            return
        self.close_popout()

    # ---------- datos del núcleo ----------

    def on_devices(self, d):
        self.lobby.on_devices(d)

    def on_weather(self, data):
        self.lobby.on_weather(data)

    def on_directory(self, event):
        self.files.on_event(event)

"""Ventana raíz de Kyora: la placa base sobre la que se montarán los ecosistemas.

Dibuja el fondo gris oscuro con iluminación suave, el reactor al centro (navegador de
módulos). Elegir Directorio en el reactor lo desliza al borde derecho, donde pasa a
navegar las carpetas, y muestra a su izquierda la vista raíz del directorio.
"""
import os

from PySide6.QtCore import QEasingCurve, QPointF, QPropertyAnimation, QRect, Qt
from PySide6.QtGui import QColor, QKeyEvent, QPainter, QRadialGradient
from PySide6.QtWidgets import QMainWindow, QWidget

from core.matrix.motherboard.artifacts.globalArtifacts.reactor import Reactor
from core.matrix.motherboard.ecosystems.calendar.infrastructure.sqlite_calendar_repository import (
    SqliteCalendarRepository,
)
from core.matrix.motherboard.ecosystems.calendar.infrastructure.tasks_adapter import (
    TasksEcosystemAdapter,
)
from core.matrix.motherboard.ecosystems.calendar.presentation.calendar_view import CalendarView
from core.matrix.motherboard.ecosystems.calendar.presentation.calendar_viewmodel import (
    CalendarViewModel,
)
from core.matrix.motherboard.ecosystems.calendar.use_cases.manage_calendar import CalendarUseCases
from core.matrix.motherboard.modules.directory.rootDirectory import RootDirectory
from core.matrix.motherboard.ecosystems.tasks.infrastructure.sqlite_task_repository import (
    SqliteTaskRepository,
)

BASE_COLOR = QColor("#101010")
# Paradas (posición 0..1, color) del halo, del centro hacia el borde.
GLOW_STOPS = (
    (0.0, QColor("#3c3c3c")),
    (0.3, QColor("#2c2c2c")),
    (0.65, QColor("#181818")),
    (1.0, QColor("#0e0e0e")),
)
GLOW_RADIUS_FACTOR = 0.6
REACTOR_SIZE_FACTOR = 0.5  # del lado menor de la ventana
REACTOR_SLIDE_MS = 450
CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "global_config.json")


class MotherboardRoot(QMainWindow):
    """Ventana principal sin marco que muestra el fondo de la placa base.

    Esc retrocede un nivel y, desde el reactor, cierra la ventana (no tiene barra de título).
    """

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Kyora")
        self.setWindowFlag(Qt.FramelessWindowHint)
        self.reactor = Reactor(self)
        self.reactor.option_selected.connect(self.open_module)
        self._panels = {}  # módulos ya construidos, por id; se crean al abrirse
        self._active_panel = None
        self._directory_mode = False   # el reactor está en el borde derecho o yendo hacia allí

        self.root_directory = RootDirectory(self)
        self.root_directory.hide()
        self.root_directory.back_requested.connect(self.show_reactor)
        self.root_directory.gaps_changed.connect(self.reactor.set_gaps)

        self._slide = QPropertyAnimation(self.reactor, b"geometry", self)
        self._slide.setDuration(REACTOR_SLIDE_MS)
        self._slide.setEasingCurve(QEasingCurve.OutCubic)
        self._slide.finished.connect(self._on_slide_finished)

        self.showMaximized()

    def _reactor_rect(self, at_right: bool) -> QRect:
        """Posición del reactor: centrado, o con su centro en el borde derecho (solo se ve la
        mitad izquierda) mientras se navega el directorio."""
        side = int(min(self.width(), self.height()) * REACTOR_SIZE_FACTOR)
        y = (self.height() - side) // 2
        if at_right:
            return QRect(self.width() - side // 2, y, side, side)
        return QRect((self.width() - side) // 2, y, side, side)

    def _layout_directory(self) -> None:
        """Extiende la vista del directorio a toda la ventana y le indica dónde queda el reactor."""
        self.root_directory.setGeometry(0, 0, self.width(), self.height())
        self.root_directory.set_reactor_rect(self._reactor_rect(True))

    def _slide_reactor(self) -> None:
        """Desliza el reactor a su sitio; mientras se mueve no recibe pulsaciones."""
        self.reactor.setEnabled(False)
        self._slide.stop()
        self._slide.setStartValue(self.reactor.geometry())
        self._slide.setEndValue(self._reactor_rect(self._directory_mode))
        self._slide.start()

    def _on_slide_finished(self) -> None:
        """Al llegar al borde derecho el reactor se fija y el directorio muestra su dial encima."""
        self.reactor.setEnabled(True)
        if self._directory_mode:
            self.reactor.set_pinned(True)
            self.root_directory.start_dial()

    def open_module(self, module_id: str) -> None:
        """Abre el módulo elegido en el reactor, o cierra la aplicación con ``CLOSE``.

        Args:
            module_id: ``DIRECTORY``, ``CALENDAR`` o ``CLOSE``.
        """
        if module_id == "CLOSE":
            self.close()
            return
        if module_id == "DIRECTORY":
            self.show_root_directory()
            return
        self._show_panel(module_id)

    def show_root_directory(self) -> None:
        """Desliza el reactor al borde derecho para que navegue las carpetas y muestra el directorio."""
        self.close_module()
        self._directory_mode = True
        self._layout_directory()
        self.root_directory.show()
        self._slide_reactor()

    def show_reactor(self) -> None:
        """Vuelve del directorio al reactor centrado, con el menú de módulos."""
        self.close_module()
        self._directory_mode = False
        self.root_directory.hide()
        self.reactor.set_gaps(None)
        self.reactor.set_pinned(False)
        self.reactor.show()
        self._slide_reactor()

    def _show_panel(self, module_id: str) -> None:
        """Muestra el panel de ``module_id`` (hoy solo ``CALENDAR``), construyéndolo si hace falta."""
        self.close_module()
        panel = self._panels.get(module_id)
        if panel is None:
            panel = self._panels[module_id] = self._build_module(module_id)
        self._active_panel = panel
        self._layout_active_panel()
        panel.show()
        panel.raise_()
        if module_id == "CALENDAR":
            panel.go_to_today()

    def close_module(self) -> bool:
        """Oculta el módulo abierto.

        Returns:
            True si había un módulo abierto.
        """
        if self._active_panel is None:
            return False
        self._active_panel.hide()
        self._active_panel = None
        return True

    def _build_module(self, module_id: str) -> QWidget:
        """Construye el panel de un módulo la primera vez que se abre."""
        task_repo = SqliteTaskRepository(CONFIG_PATH)
        use_cases = CalendarUseCases(SqliteCalendarRepository(), TasksEcosystemAdapter(task_repo))
        return CalendarView(CalendarViewModel(use_cases), self)

    def _layout_active_panel(self) -> None:
        """Ajusta el módulo abierto al tamaño actual de la ventana."""
        panel = self._active_panel
        if panel is None:
            return
        panel.resize(self.width(), self.height())
        panel.move(0, 0)

    def resizeEvent(self, event) -> None:
        """Mantiene el reactor centrado y proporcional a la ventana."""
        super().resizeEvent(event)
        self._layout_active_panel()
        self._layout_directory()
        self._slide.stop()
        self.reactor.setGeometry(self._reactor_rect(self._directory_mode))
        self.reactor.setEnabled(True)

    def keyPressEvent(self, event: QKeyEvent) -> None:
        """Esc cierra el módulo abierto; en el directorio sube un nivel y después vuelve al
        menú de módulos; por último cierra la ventana. En el directorio, arriba y abajo
        cambian de carpeta, derecha o Enter entran e izquierda o Retroceso suben."""
        if event.key() == Qt.Key_Escape:
            if self.close_module():
                return
            if self.root_directory.isVisible():
                if not self.root_directory.up():
                    self.show_reactor()
                return
            self.close()
            return
        if self._directory_mode and self.root_directory.isVisible():
            key = event.key()
            if key == Qt.Key_Up:
                self.root_directory.step(-1)
            elif key == Qt.Key_Down:
                self.root_directory.step(1)
            elif key in (Qt.Key_Right, Qt.Key_Return, Qt.Key_Enter):
                self.root_directory.activate_current()
            elif key in (Qt.Key_Left, Qt.Key_Backspace):
                self.root_directory.up()
            else:
                super().keyPressEvent(event)
                return
            event.accept()
            return
        super().keyPressEvent(event)

    def paintEvent(self, event) -> None:
        """Pinta el gris oscuro base y un halo de luz suave hacia el centro."""
        painter = QPainter(self)
        painter.fillRect(self.rect(), BASE_COLOR)

        center = QPointF(self.width() * 0.5, self.height() * 0.5)
        radius = max(self.width(), self.height()) * GLOW_RADIUS_FACTOR
        glow = QRadialGradient(center, radius)
        for position, color in GLOW_STOPS:
            glow.setColorAt(position, color)
        painter.fillRect(self.rect(), glow)
        painter.end()

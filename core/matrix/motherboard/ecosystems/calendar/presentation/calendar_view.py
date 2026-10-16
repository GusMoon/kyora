import calendar
from datetime import date, timedelta
from typing import List, Optional, Tuple

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import (
    QDialog, QHBoxLayout, QLabel, QPushButton, QStackedWidget, QVBoxLayout, QWidget,
)

from core.matrix.motherboard.ecosystems.calendar.domain.entities import AgendaItem
from core.matrix.motherboard.ecosystems.calendar.presentation.calendar_viewmodel import CalendarViewModel
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents import calendar_theme as theme
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents.day_panel import DayPanel
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents.day_strip import DayStrip
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents.day_timeline import DayTimeline
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents.dialogs import (
    EventDialog, ReminderDialog,
)
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents.item_detail import ItemDetail
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents.month_grid import MonthGrid
from core.matrix.motherboard.modules.simple_dialogs import SciFiConfirmDialog

DAY_MODE, MONTH_MODE = 0, 1


def shift_months(day: date, months: int) -> date:
    """
    Desplaza una fecha `months` meses, ajustando el día al último válido del mes destino.

    Args:
        day: Fecha de partida.
        months: Meses a mover; negativo para retroceder.

    Returns:
        date: Fecha resultante.
    """
    index = day.year * 12 + (day.month - 1) + months
    year, month = divmod(index, 12)
    month += 1
    year = max(1, min(9998, year))
    return date(year, month, min(day.day, calendar.monthrange(year, month)[1]))


class CalendarView(QWidget):
    """
    Vista principal del ecosistema de calendario, a pantalla completa.

    Modo DÍA: franja de días arriba y línea de tiempo del día con una columna por
    tipo de actividad. Modo MES: cuadrícula mensual. A la derecha, la lista del día
    o el detalle de la actividad elegida. Las tareas se muestran en solo lectura y
    se abren en el ecosistema Tareas.
    """

    open_task_requested = Signal(str)

    def __init__(self, viewmodel: CalendarViewModel, parent=None):
        """
        Args:
            viewmodel: ViewModel que provee el estado de la vista.
            parent: Widget padre (la ventana principal).
        """
        super().__init__(parent)
        self.viewmodel = viewmodel
        self._day_items: List[AgendaItem] = []
        self._selected_key: Optional[Tuple[str, str]] = None

        self.resize(850, 550)
        self.move(15, 15)
        self._setup_ui()
        self._connect_signals()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor(18, 18, 18, 240))

    # ------------------------------------------------------------------ UI
    def _setup_ui(self) -> None:
        """Construye el encabezado, la zona central y el panel derecho."""
        root = QVBoxLayout(self)
        root.setContentsMargins(28, 22, 28, 22)
        root.setSpacing(12)
        root.addLayout(self._build_header())

        self.day_strip = DayStrip()
        root.addWidget(self.day_strip)

        body = QHBoxLayout()
        body.setSpacing(18)

        self.center = QStackedWidget()
        self.timeline = DayTimeline()
        self.timeline.set_clock(self.viewmodel.now)
        self.center.addWidget(self.timeline)
        month_page = QWidget()
        month_layout = QVBoxLayout(month_page)
        month_layout.setContentsMargins(0, 0, 0, 0)
        self.grid = MonthGrid()
        month_layout.addWidget(self.grid, 1)
        month_layout.addLayout(self._build_legend())
        self.center.addWidget(month_page)
        body.addWidget(self.center, 1)

        self.right = QStackedWidget()
        self.right.setMinimumWidth(360)
        self.right.setMaximumWidth(440)
        self.day_panel = DayPanel()
        self.detail = ItemDetail()
        self.right.addWidget(self.day_panel)
        self.right.addWidget(self.detail)
        body.addWidget(self.right)
        root.addLayout(body, 1)

    def _build_header(self) -> QHBoxLayout:
        """Crea el encabezado: título, navegación de mes y año, modo y accesos de creación."""
        header = QHBoxLayout()
        header.setSpacing(8)
        title = QLabel("CALENDARIO")
        title.setStyleSheet(
            f"color: {theme.MUTED}; font-family: '{theme.FONT_FAMILY}'; font-size: 12px; "
            "font-weight: 700; letter-spacing: 4px; background: transparent;"
        )
        header.addWidget(title)
        header.addStretch()

        self.prev_year_btn = self._nav_button("«", "Año anterior")
        self.prev_month_btn = self._nav_button("‹", "Mes anterior")
        self.month_label = QLabel()
        self.month_label.setMinimumWidth(250)
        self.month_label.setAlignment(Qt.AlignCenter)
        self.month_label.setStyleSheet(
            f"color: {theme.TEXT}; font-family: '{theme.FONT_FAMILY}'; font-size: 19px; "
            "font-weight: 700; letter-spacing: 4px; background: transparent;"
        )
        self.next_month_btn = self._nav_button("›", "Mes siguiente")
        self.next_year_btn = self._nav_button("»", "Año siguiente")
        self.today_btn = QPushButton("HOY")
        self.today_btn.setCursor(Qt.PointingHandCursor)
        self.today_btn.setStyleSheet(theme.button_style("accent"))
        for widget in (self.prev_year_btn, self.prev_month_btn, self.month_label,
                       self.next_month_btn, self.next_year_btn, self.today_btn):
            header.addWidget(widget)
        header.addStretch()

        self.day_mode_btn = QPushButton("DÍA")
        self.month_mode_btn = QPushButton("MES")
        for btn in (self.day_mode_btn, self.month_mode_btn):
            btn.setCheckable(True)
            btn.setCursor(Qt.PointingHandCursor)
            btn.setStyleSheet(theme.chip_style())
            header.addWidget(btn)
        self.day_mode_btn.setChecked(True)

        self.add_event_btn = QPushButton("+ EVENTO")
        self.add_reminder_btn = QPushButton("+ RECORDATORIO")
        for btn, kind in ((self.add_event_btn, "primary"), (self.add_reminder_btn, "standard")):
            btn.setCursor(Qt.PointingHandCursor)
            btn.setStyleSheet(theme.button_style(kind))
            header.addWidget(btn)
        return header

    @staticmethod
    def _nav_button(text: str, tooltip: str) -> QPushButton:
        """Crea un botón de navegación cuadrado con el estilo del calendario."""
        btn = QPushButton(text)
        btn.setFixedSize(38, 34)
        btn.setCursor(Qt.PointingHandCursor)
        btn.setToolTip(tooltip)
        btn.setStyleSheet(theme.button_style("standard", padding="0", font_px=18))
        return btn

    @staticmethod
    def _build_legend() -> QHBoxLayout:
        """Crea la leyenda de colores por tipo de actividad."""
        row = QHBoxLayout()
        row.setSpacing(16)
        for name, color in theme.LEGEND:
            swatch = QLabel()
            swatch.setFixedSize(10, 10)
            swatch.setStyleSheet(f"background: {color};")
            text = QLabel(name.upper())
            text.setStyleSheet(
                f"color: {theme.MUTED}; font-family: '{theme.FONT_FAMILY}'; font-size: 10px; "
                "letter-spacing: 1px; background: transparent;"
            )
            row.addWidget(swatch)
            row.addWidget(text)
        row.addStretch()
        return row

    def _connect_signals(self) -> None:
        """Conecta la vista con el ViewModel y con los controles propios."""
        self.prev_year_btn.clicked.connect(lambda: self._shift(-12))
        self.prev_month_btn.clicked.connect(lambda: self._shift(-1))
        self.next_month_btn.clicked.connect(lambda: self._shift(1))
        self.next_year_btn.clicked.connect(lambda: self._shift(12))
        self.today_btn.clicked.connect(self.go_to_today)
        self.day_mode_btn.clicked.connect(lambda: self._set_mode(DAY_MODE))
        self.month_mode_btn.clicked.connect(lambda: self._set_mode(MONTH_MODE))
        self.add_event_btn.clicked.connect(self._new_event)
        self.add_reminder_btn.clicked.connect(self._new_reminder)

        self.day_strip.date_selected.connect(self._select_iso)
        self.day_strip.step_requested.connect(
            lambda days: self._select(self.viewmodel.selected + timedelta(days=days)))
        self.grid.date_clicked.connect(self._select_iso)
        self.grid.date_double_clicked.connect(lambda iso: (self._select_iso(iso), self._new_event()))
        self.grid.month_step.connect(self._shift)

        self.timeline.item_clicked.connect(self._select_item)
        self.day_panel.item_activated.connect(self._select_item)
        self.day_panel.delete_requested.connect(self._on_delete_requested)
        self.day_panel.add_event_requested.connect(self._new_event)
        self.day_panel.add_reminder_requested.connect(self._new_reminder)

        self.detail.back_requested.connect(self._clear_item)
        self.detail.open_task_requested.connect(self.open_task_requested)
        self.detail.edit_requested.connect(self._edit_item)
        self.detail.delete_requested.connect(self._on_delete_requested)

        self.viewmodel.agenda_loaded.connect(self._on_agenda_loaded)
        self.viewmodel.month_loaded.connect(self._on_month_loaded)
        self.viewmodel.calendar_error.connect(self._on_error)

    # --------------------------------------------------------------- navegación
    def go_to_today(self) -> None:
        """Selecciona el día de hoy y lo muestra."""
        self._select(self.viewmodel.today())

    def refresh(self) -> None:
        """Recarga el día seleccionado, por ejemplo tras cambios hechos en Tareas."""
        self.viewmodel.reload()

    def _select(self, day: date) -> None:
        """Selecciona un día y limpia la actividad abierta en el detalle."""
        if day != self.viewmodel.selected:
            self._selected_key = None
        self.viewmodel.select_date(day)

    def _select_iso(self, iso: str) -> None:
        """Selecciona un día dado como fecha ISO."""
        self._select(date.fromisoformat(iso))

    def _shift(self, months: int) -> None:
        """Mueve la fecha seleccionada `months` meses."""
        self._select(shift_months(self.viewmodel.selected, months))

    def _set_mode(self, mode: int) -> None:
        """Alterna entre la línea de tiempo del día y la cuadrícula mensual."""
        self.day_mode_btn.setChecked(mode == DAY_MODE)
        self.month_mode_btn.setChecked(mode == MONTH_MODE)
        self.center.setCurrentIndex(mode)
        self.day_strip.setVisible(mode == DAY_MODE)

    # ---------------------------------------------------------- slots del VM
    def _on_agenda_loaded(self, iso: str, items: list, counts: dict, today: date) -> None:
        """Actualiza franja, línea de tiempo, lista del día y detalle con el día recibido."""
        day = date.fromisoformat(iso)
        self._day_items = items
        self.month_label.setText(f"{theme.MONTHS_ES[day.month - 1]} {day.year}")
        self.day_strip.set_state(day, today, counts)
        self.timeline.set_day(day, items, today)
        self.grid.set_selected(day)
        self.day_panel.set_day(day, items)

        current = self._find_item(self._selected_key)
        if current is None:
            self._selected_key = None
            self.right.setCurrentIndex(0)
        else:
            self.detail.show_item(current)
        self.timeline.set_selected(self._selected_key)

    def _on_month_loaded(self, year: int, month: int, items: dict, today: date) -> None:
        """Actualiza la cuadrícula mensual."""
        self.grid.set_month(year, month, items, today)
        self.grid.set_selected(self.viewmodel.selected)

    def _on_error(self, message: str) -> None:
        """Muestra un error de lectura en el panel del día."""
        self.day_panel.count_label.setText(message.upper())

    # ------------------------------------------------------------- detalle
    def _find_item(self, key: Optional[Tuple[str, str]]) -> Optional[AgendaItem]:
        """Busca en el día actual la actividad identificada por `(tipo, id)`."""
        if key is None:
            return None
        for item in self._day_items:
            if (item.kind, item.source_id) == key:
                return item
        return None

    def _select_item(self, kind: str, source_id: str) -> None:
        """Abre el detalle de una actividad del día."""
        item = self._find_item((kind, source_id))
        if item is None:
            return
        self._selected_key = (kind, source_id)
        self.detail.show_item(item)
        self.right.setCurrentIndex(1)
        self.timeline.set_selected(self._selected_key)

    def _clear_item(self) -> None:
        """Vuelve del detalle a la lista del día."""
        self._selected_key = None
        self.right.setCurrentIndex(0)
        self.timeline.set_selected(None)

    # --------------------------------------------------------------- acciones
    def _new_event(self) -> None:
        """Abre el formulario para crear un evento en el día seleccionado."""
        dialog = EventDialog(self.window(), self.viewmodel.create_event,
                             self.viewmodel.selected.isoformat())
        dialog.exec()

    def _new_reminder(self) -> None:
        """Abre el formulario para crear un recordatorio en el día seleccionado."""
        dialog = ReminderDialog(self.window(), self.viewmodel.create_reminder,
                                self.viewmodel.selected.isoformat())
        dialog.exec()

    def _edit_item(self, kind: str, source_id: str) -> None:
        """Abre el formulario de edición del evento o recordatorio."""
        day = self.viewmodel.selected.isoformat()
        if kind in ("event", "birthday"):
            found = self.viewmodel.get_event(source_id)
            if found is None:
                return
            event, advance = found
            EventDialog(
                self.window(), lambda values: self.viewmodel.update_event(source_id, values),
                day, event=event, advance_minutes=advance,
            ).exec()
        elif kind == "reminder":
            reminder = self.viewmodel.get_reminder(source_id)
            if reminder is None:
                return
            ReminderDialog(
                self.window(), lambda values: self.viewmodel.update_reminder(source_id, values),
                day, reminder=reminder,
            ).exec()

    def _on_delete_requested(self, kind: str, source_id: str, title: str) -> None:
        """Elimina un evento o recordatorio tras confirmarlo."""
        noun = "recordatorio" if kind == "reminder" else "evento"
        confirm = SciFiConfirmDialog(self.window(), f"ELIMINAR {noun.upper()}", f"¿Eliminar «{title}»?")
        if confirm.exec() != QDialog.Accepted:
            return
        error = (self.viewmodel.delete_reminder(source_id) if kind == "reminder"
                 else self.viewmodel.delete_event(source_id))
        if error:
            self._on_error(error)

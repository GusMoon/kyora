from datetime import date
from typing import List

from PySide6.QtCore import QRectF, Qt, Signal
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import (
    QFrame, QHBoxLayout, QLabel, QPushButton, QScrollArea, QVBoxLayout, QWidget,
)

from core.matrix.motherboard.ecosystems.calendar.domain.entities import AgendaItem
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents import calendar_theme as theme

KIND_LABELS = {"task": "TAREA", "event": "EVENTO", "birthday": "FECHA ANUAL", "reminder": "RECORDATORIO"}


def _label(size: int, color: str, bold: bool = False, spacing: int = 0) -> QLabel:
    """Crea una etiqueta transparente con la tipografía del calendario."""
    label = QLabel()
    label.setStyleSheet(
        f"color: {color}; font-family: '{theme.FONT_FAMILY}'; font-size: {size}px; "
        f"font-weight: {'700' if bold else '400'}; letter-spacing: {spacing}px; background: transparent;"
    )
    return label


class AgendaRow(QFrame):
    """Fila de una actividad: marca de color, hora, título, tipo y acción de eliminar."""

    activated = Signal(str, str)               # kind, source_id
    delete_requested = Signal(str, str, str)   # kind, source_id, title

    def __init__(self, item: AgendaItem, parent=None):
        """
        Args:
            item: Actividad que representa la fila.
            parent: Widget padre.
        """
        super().__init__(parent)
        self.item = item
        self.setCursor(Qt.PointingHandCursor)
        self.setObjectName("agendaRow")
        self.setStyleSheet(
            f"#agendaRow {{ background: {theme.CARD}; border: 1px solid {theme.BORDER_SOFT}; "
            "border-radius: 4px; } "
            f"#agendaRow:hover {{ background: {theme.CARD_HOVER}; border: 1px solid {theme.BORDER_HOVER}; }}"
        )
        color = theme.item_color(item)

        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 8, 0)
        layout.setSpacing(10)

        bar = QFrame()
        bar.setFixedWidth(5)
        bar.setStyleSheet(f"background: {color}; border: none;")
        layout.addWidget(bar)

        when = _label(12, theme.MUTED, bold=True, spacing=1)
        when.setFixedWidth(104)
        when.setText(self._when_text(item))
        layout.addWidget(when)

        text = QVBoxLayout()
        text.setContentsMargins(0, 8, 0, 8)
        text.setSpacing(2)
        title = _label(14, theme.TEXT if item.status != "completed" else theme.MUTED, bold=True)
        title.setWordWrap(True)
        title.setText(item.title)
        sub = _label(11, color, bold=True, spacing=1)
        sub.setWordWrap(True)
        sub.setText(self._sub_text(item))
        text.addWidget(title)
        text.addWidget(sub)
        if item.detail:
            detail = _label(12, theme.MUTED)
            detail.setWordWrap(True)
            detail.setText(item.detail)
            text.addWidget(detail)
        layout.addLayout(text, 1)

        if item.kind != "task":
            delete = QPushButton("✕")
            delete.setFixedSize(26, 26)
            delete.setCursor(Qt.PointingHandCursor)
            delete.setToolTip("Eliminar")
            delete.setStyleSheet(
                f"QPushButton {{ background: transparent; color: {theme.MUTED}; border: none; font-size: 14px; }} "
                f"QPushButton:hover {{ color: {theme.ERROR}; }}"
            )
            delete.clicked.connect(lambda: self.delete_requested.emit(item.kind, item.source_id, item.title))
            layout.addWidget(delete)

    @staticmethod
    def _when_text(item: AgendaItem) -> str:
        """Texto de la columna de hora."""
        if item.kind == "task":
            return item.time or "LÍMITE"
        if item.kind == "birthday" or not item.time:
            return "TODO EL DÍA"
        return f"{item.time}–{item.end_time}" if item.end_time else item.time

    @staticmethod
    def _sub_text(item: AgendaItem) -> str:
        """Texto secundario: tipo y estado."""
        if item.kind == "task":
            if item.overdue:
                return "TAREA · VENCIDA"
            return f"TAREA · {theme.STATUS_LABELS.get(item.status, item.status.upper())}"
        label = KIND_LABELS.get(item.kind, item.kind.upper())
        if item.recurring:
            label += " · CADA AÑO"
        if item.status == "notified":
            label += " · NOTIFICADO"
        return label

    def mousePressEvent(self, event):
        self.activated.emit(self.item.kind, self.item.source_id)


class DayPanel(QWidget):
    """Panel con el detalle de las actividades del día seleccionado y accesos para crear."""

    item_activated = Signal(str, str)
    delete_requested = Signal(str, str, str)
    add_event_requested = Signal()
    add_reminder_requested = Signal()

    def __init__(self, parent=None):
        """
        Args:
            parent: Widget padre.
        """
        super().__init__(parent)
        self.setMinimumWidth(360)
        self.setMaximumWidth(440)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(20, 18, 20, 18)
        layout.setSpacing(12)

        self.weekday_label = _label(10, theme.ACCENT, bold=True, spacing=2)
        self.date_label = _label(22, theme.TEXT, bold=True)
        self.count_label = _label(11, theme.MUTED, spacing=1)
        layout.addWidget(self.weekday_label)
        layout.addWidget(self.date_label)
        layout.addWidget(self.count_label)

        buttons = QHBoxLayout()
        self.add_event_btn = QPushButton("+ EVENTO")
        self.add_reminder_btn = QPushButton("+ RECORDATORIO")
        for btn, kind in ((self.add_event_btn, "primary"), (self.add_reminder_btn, "standard")):
            btn.setCursor(Qt.PointingHandCursor)
            btn.setStyleSheet(theme.button_style(kind))
            buttons.addWidget(btn)
        layout.addLayout(buttons)
        self.add_event_btn.clicked.connect(self.add_event_requested)
        self.add_reminder_btn.clicked.connect(self.add_reminder_requested)

        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.scroll.setFrameShape(QFrame.NoFrame)
        self.scroll.setStyleSheet(
            "QScrollArea { background: transparent; border: none; } "
            "QScrollBar:vertical { width: 4px; background: transparent; } "
            "QScrollBar::handle:vertical { background: #444444; } "
            "QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }"
        )
        self.list_host = QWidget()
        self.list_host.setStyleSheet("background: transparent;")
        self.list_layout = QVBoxLayout(self.list_host)
        self.list_layout.setContentsMargins(0, 0, 4, 0)
        self.list_layout.setSpacing(6)
        self.list_layout.addStretch()
        self.scroll.setWidget(self.list_host)
        layout.addWidget(self.scroll, 1)

    def set_day(self, day: date, items: List[AgendaItem]) -> None:
        """
        Muestra el detalle de un día.

        Args:
            day: Fecha seleccionada.
            items: Actividades del día, ya ordenadas.
        """
        self.weekday_label.setText(theme.WEEKDAYS_FULL[day.weekday()])
        self.date_label.setText(f"{day.day} {theme.MONTHS_ES[day.month - 1].capitalize()} {day.year}")
        self.count_label.setText(
            "SIN ACTIVIDADES" if not items else f"{len(items)} ACTIVIDAD" + ("ES" if len(items) != 1 else ""))

        while self.list_layout.count() > 1:
            child = self.list_layout.takeAt(0)
            widget = child.widget()
            if widget is not None:
                widget.hide()
                widget.setParent(None)
                widget.deleteLater()
        for position, item in enumerate(items):
            row = AgendaRow(item)
            row.activated.connect(self.item_activated)
            row.delete_requested.connect(self.delete_requested)
            self.list_layout.insertWidget(position, row)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setPen(QPen(QColor(theme.BORDER), 1))
        painter.setBrush(QColor(theme.PANEL))
        painter.drawPath(theme.rounded_path(QRectF(self.rect()).adjusted(1, 1, -1, -1), 6))

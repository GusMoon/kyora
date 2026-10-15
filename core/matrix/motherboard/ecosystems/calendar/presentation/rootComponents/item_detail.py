from datetime import date

from PySide6.QtCore import QRectF, Qt, Signal
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import QFrame, QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget

from core.matrix.motherboard.ecosystems.calendar.domain.entities import AgendaItem
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents import calendar_theme as theme

KIND_NAMES = {"task": "TAREA", "event": "EVENTO", "birthday": "FECHA ANUAL", "reminder": "RECORDATORIO"}


def _text(size: int, color: str, bold: bool = False, spacing: int = 0) -> QLabel:
    """Crea una etiqueta transparente con la tipografía del calendario."""
    label = QLabel()
    label.setWordWrap(True)
    label.setStyleSheet(
        f"color: {color}; font-family: '{theme.FONT_FAMILY}'; font-size: {size}px; "
        f"font-weight: {'700' if bold else '400'}; letter-spacing: {spacing}px; background: transparent;"
    )
    return label


def _action_style(danger: bool = False) -> str:
    """Hoja de estilos de una acción de lista, plana y alineada a la izquierda."""
    hover = theme.ERROR if danger else theme.ACCENT
    return (
        f"QPushButton {{ background: transparent; color: {theme.ERROR if danger else theme.TEXT}; "
        f"border: none; text-align: left; padding: 9px 4px; font-family: '{theme.FONT_FAMILY}'; "
        "font-size: 13px; font-weight: 600; letter-spacing: 1px; } "
        f"QPushButton:hover {{ color: {hover}; }}"
    )


class ItemDetail(QWidget):
    """
    Detalle de una actividad seleccionada: tipo y estado, fecha y hora, descripción,
    lista de subtareas (solo lectura) y acciones.
    """

    back_requested = Signal()
    open_task_requested = Signal(str)
    edit_requested = Signal(str, str)           # kind, source_id
    delete_requested = Signal(str, str, str)    # kind, source_id, title

    def __init__(self, parent=None):
        """
        Args:
            parent: Widget padre.
        """
        super().__init__(parent)
        self.setMinimumWidth(360)
        self.setMaximumWidth(440)
        self._item = None

        root = QVBoxLayout(self)
        root.setContentsMargins(22, 18, 22, 18)
        root.setSpacing(10)

        top = QHBoxLayout()
        self.kind_label = _text(11, theme.ACCENT, bold=True, spacing=3)
        back = QPushButton("✕")
        back.setFixedSize(26, 26)
        back.setCursor(Qt.PointingHandCursor)
        back.setToolTip("Volver a la lista del día")
        back.setStyleSheet(
            f"QPushButton {{ background: transparent; color: {theme.MUTED}; border: none; font-size: 15px; }} "
            f"QPushButton:hover {{ color: {theme.TEXT}; }}"
        )
        back.clicked.connect(self.back_requested)
        top.addWidget(self.kind_label, 1)
        top.addWidget(back)
        root.addLayout(top)

        self.title_label = _text(20, theme.TEXT, bold=True)
        root.addWidget(self.title_label)
        self.status_label = _text(11, theme.MUTED, bold=True, spacing=2)
        root.addWidget(self.status_label)

        self.when_caption = self._caption("FECHA Y HORA")
        self.when_label = _text(14, theme.TEXT)
        self.desc_caption = self._caption("DESCRIPCIÓN")
        self.desc_label = _text(13, theme.MUTED)
        self.check_caption = self._caption("SUBTAREAS")
        self.check_host = QWidget()
        self.check_host.setStyleSheet("background: transparent;")
        self.check_layout = QVBoxLayout(self.check_host)
        self.check_layout.setContentsMargins(0, 0, 0, 0)
        self.check_layout.setSpacing(4)
        for widget in (self.when_caption, self.when_label, self.desc_caption, self.desc_label,
                       self.check_caption, self.check_host):
            root.addWidget(widget)
        root.addStretch()

        self.divider = QFrame()
        self.divider.setFixedHeight(1)
        self.divider.setStyleSheet(f"background: {theme.BORDER_SOFT};")
        root.addWidget(self.divider)
        self.open_btn = QPushButton("ABRIR EN TAREAS")
        self.edit_btn = QPushButton("EDITAR")
        self.delete_btn = QPushButton("ELIMINAR")
        for btn, danger in ((self.open_btn, False), (self.edit_btn, False), (self.delete_btn, True)):
            btn.setCursor(Qt.PointingHandCursor)
            btn.setStyleSheet(_action_style(danger))
            root.addWidget(btn)
        self.open_btn.clicked.connect(lambda: self.open_task_requested.emit(self._item.source_id))
        self.edit_btn.clicked.connect(lambda: self.edit_requested.emit(self._item.kind, self._item.source_id))
        self.delete_btn.clicked.connect(
            lambda: self.delete_requested.emit(self._item.kind, self._item.source_id, self._item.title))

    @staticmethod
    def _caption(text: str) -> QLabel:
        """Crea un subtítulo de sección."""
        label = _text(10, theme.MUTED, bold=True, spacing=3)
        label.setText(text)
        label.setContentsMargins(0, 10, 0, 0)
        return label

    def show_item(self, item: AgendaItem) -> None:
        """
        Muestra los datos de una actividad.

        Args:
            item: Actividad seleccionada.
        """
        self._item = item
        color = theme.item_color(item)
        self.kind_label.setText(KIND_NAMES.get(item.kind, item.kind.upper()))
        self.kind_label.setStyleSheet(
            f"color: {color}; font-family: '{theme.FONT_FAMILY}'; font-size: 11px; font-weight: 700; "
            "letter-spacing: 3px; background: transparent;"
        )
        self.title_label.setText(item.title)

        if item.kind == "task":
            status = theme.STATUS_LABELS.get(item.status, item.status.upper())
            self.status_label.setText(f"{status} · VENCIDA" if item.overdue else status)
        elif item.recurring:
            self.status_label.setText("SE REPITE CADA AÑO")
        elif item.status == "notified":
            self.status_label.setText("YA NOTIFICADO")
        else:
            self.status_label.setText("")
        self.status_label.setVisible(bool(self.status_label.text()))

        parsed = date.fromisoformat(item.item_date)
        day = f"{theme.WEEKDAYS_FULL[parsed.weekday()].capitalize()} {parsed.day} de " \
              f"{theme.MONTHS_ES[parsed.month - 1].lower()} de {parsed.year}"
        if item.kind == "task":
            when = f"{day} · límite {item.time}" if item.time else f"{day} · fecha límite"
        elif item.time:
            when = f"{day} · {item.time}" + (f" – {item.end_time}" if item.end_time else "")
        else:
            when = f"{day} · todo el día"
        self.when_label.setText(when)

        has_desc = bool(item.detail)
        self.desc_caption.setVisible(has_desc)
        self.desc_label.setVisible(has_desc)
        self.desc_label.setText(item.detail)

        while self.check_layout.count():
            widget = self.check_layout.takeAt(0).widget()
            if widget is not None:
                widget.hide()
                widget.setParent(None)
                widget.deleteLater()
        has_check = bool(item.checklist)
        self.check_caption.setVisible(has_check)
        self.check_host.setVisible(has_check)
        for title, done in item.checklist:
            row = _text(13, theme.MUTED if done else theme.TEXT)
            row.setText(("☑  " if done else "☐  ") + (f"<s>{title}</s>" if done else title))
            row.setTextFormat(Qt.RichText)
            self.check_layout.addWidget(row)

        is_task = item.kind == "task"
        self.open_btn.setVisible(is_task)
        self.edit_btn.setVisible(not is_task)
        self.delete_btn.setVisible(not is_task)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setPen(QPen(QColor(theme.BORDER), 1))
        painter.setBrush(QColor(theme.PANEL))
        painter.drawPath(theme.rounded_path(QRectF(self.rect()).adjusted(1, 1, -1, -1), 6))

from datetime import date
from typing import Callable, Optional

from PySide6.QtCore import QDate, QTime, Qt
from PySide6.QtWidgets import (
    QCheckBox, QComboBox, QDateEdit, QDialog, QFormLayout, QHBoxLayout, QLabel,
    QLineEdit, QPushButton, QTextEdit, QTimeEdit, QVBoxLayout,
)

from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents import calendar_theme as theme

ADVANCE_OPTIONS = [
    ("Sin recordatorio", 0),
    ("10 minutos antes", 10),
    ("30 minutos antes", 30),
    ("1 hora antes", 60),
    ("1 día antes", 1440),
]

DIALOG_STYLE = f"""
    QDialog {{ background-color: {theme.BG}; border: 1px solid {theme.BORDER}; border-radius: 6px; }}
    QLabel {{ color: {theme.TEXT}; font-family: '{theme.FONT_FAMILY}'; font-size: 13px;
        background: transparent; }}
    QLabel#title {{ font-size: 13px; font-weight: 900; letter-spacing: 2px; }}
    QLabel#field {{ font-size: 11px; font-weight: bold; color: #CCCCCC; }}
    QLabel#error {{ color: {theme.ERROR}; font-size: 11px; }}
    QLineEdit, QTextEdit, QDateEdit, QTimeEdit {{ background-color: #242424;
        border: 1px solid #3E3E3E; color: {theme.TEXT}; border-radius: 4px;
        font-family: '{theme.FONT_FAMILY}'; font-size: 12px; padding: 6px 10px; }}
    QComboBox {{ background-color: #171717; border: 1px solid #2A2A2A; border-radius: 4px;
        color: #E0E0E0; font-family: '{theme.FONT_FAMILY}'; font-size: 12px; padding: 6px 10px; }}
    QComboBox:hover {{ border-color: #3E3E3E; }}
    QLineEdit:focus, QTextEdit:focus, QDateEdit:focus, QTimeEdit:focus, QComboBox:focus {{
        border: 1px solid {theme.ACCENT}; }}
    QComboBox QAbstractItemView {{ background-color: #1A1A1A; border: 1px solid #333333;
        color: {theme.TEXT}; selection-background-color: #2D2D2D; outline: none; }}
    QCheckBox {{ color: {theme.TEXT}; font-family: '{theme.FONT_FAMILY}'; font-size: 12px; }}
    QCalendarWidget QWidget {{ background-color: #1A1A1A; color: #EEEEEE; }}
    QCalendarWidget QToolButton {{ background-color: #222222; color: {theme.TEXT};
        border: 1px solid #333333; border-radius: 3px; font-size: 11px; padding: 2px 4px; }}
    QCalendarWidget QToolButton:hover {{ border: 1px solid {theme.ACCENT}; }}
    QCalendarWidget QAbstractItemView:enabled {{ selection-background-color: #A04A2C;
        selection-color: {theme.TEXT}; }}
"""


class _FormDialog(QDialog):
    """Base de los diálogos del calendario: marco sci-fi, error en línea y botones."""

    def __init__(self, parent, title: str, on_submit: Callable[[dict], Optional[str]]):
        """
        Args:
            parent: Widget padre.
            title: Título del diálogo.
            on_submit: Recibe los valores del formulario y devuelve un mensaje de error,
                o None si guardó correctamente (el diálogo se cierra).
        """
        super().__init__(parent)
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.Dialog)
        self.setStyleSheet(DIALOG_STYLE)
        self.setMinimumWidth(460)
        self._on_submit = on_submit

        self.root = QVBoxLayout(self)
        self.root.setContentsMargins(24, 22, 24, 20)
        self.root.setSpacing(12)
        title_label = QLabel(title)
        title_label.setObjectName("title")
        self.root.addWidget(title_label)

        self.form = QFormLayout()
        self.form.setSpacing(10)
        self.form.setLabelAlignment(Qt.AlignLeft)
        self.root.addLayout(self.form)

        self.error_label = QLabel("")
        self.error_label.setObjectName("error")
        self.error_label.setWordWrap(True)
        self.root.addWidget(self.error_label)

        buttons = QHBoxLayout()
        buttons.addStretch()
        cancel = QPushButton("CANCELAR")
        save = QPushButton("GUARDAR")
        for btn, kind in ((cancel, "ghost"), (save, "primary")):
            btn.setCursor(Qt.PointingHandCursor)
            btn.setStyleSheet(theme.button_style(kind))
            buttons.addWidget(btn)
        cancel.clicked.connect(self.reject)
        save.clicked.connect(self._submit)
        self.root.addLayout(buttons)

    def values(self) -> dict:
        """Devuelve los valores del formulario; lo implementa cada diálogo."""
        raise NotImplementedError

    def _submit(self) -> None:
        """Valida mediante `on_submit`; si hay error lo muestra y deja el diálogo abierto."""
        error = self._on_submit(self.values())
        if error:
            self.error_label.setText(error)
            return
        self.accept()


def _to_qdate(iso: str) -> QDate:
    """Convierte una fecha ISO en QDate."""
    parsed = date.fromisoformat(iso)
    return QDate(parsed.year, parsed.month, parsed.day)


def _make_date_edit(iso: str) -> QDateEdit:
    """Crea un editor de fecha con calendario emergente."""
    edit = QDateEdit(_to_qdate(iso))
    edit.setCalendarPopup(True)
    edit.setDisplayFormat("dd/MM/yyyy")
    return edit


class EventDialog(_FormDialog):
    """Formulario para crear o editar un evento o una fecha importante anual."""

    def __init__(self, parent, on_submit, default_date: str, event=None, advance_minutes: int = 0):
        """
        Args:
            parent: Widget padre.
            on_submit: Función de guardado (ver `_FormDialog`).
            default_date: Fecha ISO inicial cuando se crea.
            event: CalendarEvent a editar; None para crear.
            advance_minutes: Anticipación actual del recordatorio del evento.
        """
        super().__init__(parent, "EDITAR EVENTO" if event else "NUEVO EVENTO", on_submit)

        self.kind_combo = QComboBox()
        self.kind_combo.addItem("Evento", "event")
        self.kind_combo.addItem("Cumpleaños / fecha anual", "birthday")
        self.title_edit = QLineEdit()
        self.title_edit.setPlaceholderText("Nombre del evento")
        self.date_edit = _make_date_edit(event.event_date if event else default_date)

        self.all_day_check = QCheckBox("Todo el día")
        self.start_edit = QTimeEdit(QTime(9, 0))
        self.start_edit.setDisplayFormat("HH:mm")
        self.has_end_check = QCheckBox("Hora de fin")
        self.end_edit = QTimeEdit(QTime(10, 0))
        self.end_edit.setDisplayFormat("HH:mm")
        time_row = QHBoxLayout()
        for widget in (self.all_day_check, self.start_edit, self.has_end_check, self.end_edit):
            time_row.addWidget(widget)

        self.description_edit = QTextEdit()
        self.description_edit.setFixedHeight(70)
        self.description_edit.setAcceptRichText(False)
        self.advance_combo = QComboBox()
        for label, minutes in ADVANCE_OPTIONS:
            self.advance_combo.addItem(label, minutes)

        self.form.addRow("Tipo", self.kind_combo)
        self.form.addRow("Nombre", self.title_edit)
        self.form.addRow("Fecha", self.date_edit)
        self.time_label = QLabel("Hora")
        self.form.addRow(self.time_label, time_row)
        self.form.addRow("Descripción", self.description_edit)
        self.form.addRow("Recordar", self.advance_combo)

        self.all_day_check.toggled.connect(self._refresh_time_controls)
        self.has_end_check.toggled.connect(self._refresh_time_controls)
        self.kind_combo.currentIndexChanged.connect(self._refresh_time_controls)

        if event:
            self.kind_combo.setCurrentIndex(self.kind_combo.findData(event.kind))
            self.title_edit.setText(event.title)
            self.description_edit.setPlainText(event.description)
            self.all_day_check.setChecked(event.start_time == "")
            if event.start_time:
                self.start_edit.setTime(QTime.fromString(event.start_time, "HH:mm"))
            self.has_end_check.setChecked(bool(event.end_time))
            if event.end_time:
                self.end_edit.setTime(QTime.fromString(event.end_time, "HH:mm"))
        else:
            self.all_day_check.setChecked(True)
        index = self.advance_combo.findData(advance_minutes)
        if index < 0 and advance_minutes > 0:
            self.advance_combo.addItem(f"{advance_minutes} minutos antes", advance_minutes)
            index = self.advance_combo.count() - 1
        self.advance_combo.setCurrentIndex(max(index, 0))
        self._refresh_time_controls()
        self.title_edit.setFocus()

    def _refresh_time_controls(self) -> None:
        """Habilita u oculta los controles de hora según el tipo y las casillas."""
        is_birthday = self.kind_combo.currentData() == "birthday"
        all_day = self.all_day_check.isChecked() or is_birthday
        for widget in (self.time_label, self.all_day_check, self.start_edit,
                       self.has_end_check, self.end_edit):
            widget.setVisible(not is_birthday)
        self.start_edit.setEnabled(not all_day)
        self.has_end_check.setEnabled(not all_day)
        self.end_edit.setEnabled(not all_day and self.has_end_check.isChecked())

    def values(self) -> dict:
        """Devuelve los datos del formulario listos para el caso de uso."""
        is_birthday = self.kind_combo.currentData() == "birthday"
        all_day = self.all_day_check.isChecked() or is_birthday
        return {
            "kind": self.kind_combo.currentData(),
            "title": self.title_edit.text(),
            "event_date": self.date_edit.date().toString("yyyy-MM-dd"),
            "start_time": "" if all_day else self.start_edit.time().toString("HH:mm"),
            "end_time": "" if all_day or not self.has_end_check.isChecked()
                        else self.end_edit.time().toString("HH:mm"),
            "description": self.description_edit.toPlainText(),
            "advance_minutes": self.advance_combo.currentData(),
        }


class ReminderDialog(_FormDialog):
    """Formulario para crear o editar un recordatorio independiente."""

    def __init__(self, parent, on_submit, default_date: str, reminder=None):
        """
        Args:
            parent: Widget padre.
            on_submit: Función de guardado (ver `_FormDialog`).
            default_date: Fecha ISO inicial cuando se crea.
            reminder: Reminder a editar; None para crear.
        """
        super().__init__(parent, "EDITAR RECORDATORIO" if reminder else "NUEVO RECORDATORIO", on_submit)
        self.text_edit = QLineEdit()
        self.text_edit.setPlaceholderText("¿Qué quieres recordar?")
        self.date_edit = _make_date_edit(reminder.remind_at[:10] if reminder else default_date)
        self.time_edit = QTimeEdit(QTime(9, 0))
        self.time_edit.setDisplayFormat("HH:mm")
        if reminder:
            self.text_edit.setText(reminder.text)
            self.time_edit.setTime(QTime.fromString(reminder.remind_at[11:16], "HH:mm"))

        self.form.addRow("Motivo", self.text_edit)
        self.form.addRow("Fecha", self.date_edit)
        self.form.addRow("Hora", self.time_edit)
        self.text_edit.setFocus()

    def values(self) -> dict:
        """Devuelve los datos del formulario listos para el caso de uso."""
        return {
            "text": self.text_edit.text(),
            "remind_date": self.date_edit.date().toString("yyyy-MM-dd"),
            "remind_time": self.time_edit.time().toString("HH:mm"),
        }

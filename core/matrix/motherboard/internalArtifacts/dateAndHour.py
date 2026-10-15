"""Hora grande y fecha actuales, actualizadas cada segundo."""
from datetime import datetime

from PySide6.QtCore import Qt, QTimer
from PySide6.QtWidgets import QVBoxLayout, QWidget

from core.matrix.motherboard.internalArtifacts.style import (
    TEXT_PRIMARY,
    InfoRow,
    make_label,
)
from core.resources.icons.information import calendar

TICK_MS = 1000


class DateAndHour(QWidget):
    """Hora (HH:MM) en grande y, debajo, la fecha (dd/mm/aaaa) como fila de icono."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._time = make_label(72, TEXT_PRIMARY, bold=True)
        self.date_row = InfoRow(calendar.draw)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)
        layout.addWidget(self._time, 0, Qt.AlignLeft)
        layout.addWidget(self.date_row)

        self._timer = QTimer(self, interval=TICK_MS)
        self._timer.timeout.connect(self.refresh)
        self._timer.start()
        self.refresh()  # evita mostrar texto vacío hasta el primer tick

    def refresh(self) -> None:
        """Actualiza los textos con la fecha y hora del sistema."""
        now = datetime.now()
        self._time.setText(now.strftime("%H:%M"))
        self.date_row.set_text(now.strftime("%d/%m/%Y"))

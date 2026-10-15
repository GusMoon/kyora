from datetime import date, timedelta
from typing import Dict

from PySide6.QtCore import QRectF, Qt, Signal
from PySide6.QtGui import QColor, QFont, QPainter, QPen
from PySide6.QtWidgets import QWidget

from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents import calendar_theme as theme

DAYS_SHOWN = 14
ARROW_W = 34
WHEEL_STEP = 120


class DayStrip(QWidget):
    """
    Franja horizontal con dos semanas de días (lunes a domingo).

    Marca el día seleccionado, el de hoy y, con un pequeño contador, los días que
    tienen actividades. Emite `date_selected` al elegir un día y `step_requested`
    al desplazar la rueda.
    """

    date_selected = Signal(str)
    step_requested = Signal(int)

    def __init__(self, parent=None):
        """
        Args:
            parent: Widget padre.
        """
        super().__init__(parent)
        today = date.today()
        self._start = today - timedelta(days=today.weekday())
        self._selected = today
        self._today = today
        self._counts: Dict[str, int] = {}
        self._wheel_accum = 0
        self.setFixedHeight(76)
        self.setCursor(Qt.PointingHandCursor)

    def set_state(self, selected: date, today: date, counts: Dict[str, int]) -> None:
        """
        Actualiza la franja.

        La ventana de días solo se reubica cuando el día seleccionado sale de ella.

        Args:
            selected: Día seleccionado.
            today: Fecha actual.
            counts: Cantidad de actividades por fecha ISO.
        """
        self._selected, self._today, self._counts = selected, today, counts
        if not self._start <= selected <= self._start + timedelta(days=DAYS_SHOWN - 1):
            self._start = selected - timedelta(days=selected.weekday())
        self.update()

    def _cell_rect(self, index: int) -> QRectF:
        """Rectángulo del día número `index` de la ventana."""
        cell_w = (self.width() - 2 * ARROW_W) / DAYS_SHOWN
        return QRectF(ARROW_W + index * cell_w, 6, cell_w, self.height() - 12)

    def mousePressEvent(self, event):
        pos = event.position()
        if pos.x() < ARROW_W:
            self._start -= timedelta(days=7)
            self.update()
            return
        if pos.x() > self.width() - ARROW_W:
            self._start += timedelta(days=7)
            self.update()
            return
        for index in range(DAYS_SHOWN):
            if self._cell_rect(index).contains(pos):
                self.date_selected.emit((self._start + timedelta(days=index)).isoformat())
                return

    def wheelEvent(self, event):
        delta = event.angleDelta()
        self._wheel_accum += delta.x() if delta.x() != 0 else -delta.y()
        while abs(self._wheel_accum) >= WHEEL_STEP:
            direction = 1 if self._wheel_accum > 0 else -1
            self._wheel_accum -= direction * WHEEL_STEP
            self.step_requested.emit(direction)
        event.accept()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        painter.setPen(QPen(QColor(theme.BORDER_SOFT), 1))
        painter.drawLine(0, self.height() - 1, self.width(), self.height() - 1)

        arrow_font = QFont(theme.FONT_FAMILY)
        arrow_font.setPixelSize(22)
        painter.setFont(arrow_font)
        painter.setPen(QColor(theme.MUTED))
        painter.drawText(QRectF(0, 0, ARROW_W, self.height()), Qt.AlignCenter, "‹")
        painter.drawText(QRectF(self.width() - ARROW_W, 0, ARROW_W, self.height()), Qt.AlignCenter, "›")

        weekday_font = QFont(theme.FONT_FAMILY)
        weekday_font.setPixelSize(10)
        weekday_font.setWeight(QFont.Bold)
        weekday_font.setLetterSpacing(QFont.AbsoluteSpacing, 1.5)
        number_font = QFont(theme.FONT_FAMILY)
        number_font.setPixelSize(17)
        number_font.setWeight(QFont.Bold)
        badge_font = QFont(theme.FONT_FAMILY)
        badge_font.setPixelSize(9)
        badge_font.setWeight(QFont.Bold)

        for index in range(DAYS_SHOWN):
            day = self._start + timedelta(days=index)
            rect = self._cell_rect(index)
            is_selected = day == self._selected
            if is_selected:
                painter.setPen(QPen(QColor(theme.ACCENT), 1))
                painter.setBrush(QColor(theme.ACCENT_TINT))
                painter.drawPath(theme.rounded_path(rect.adjusted(3, 0, -3, 0), 4))

            painter.setFont(weekday_font)
            painter.setPen(QColor(theme.MUTED))
            painter.drawText(QRectF(rect.left(), rect.top() + 6, rect.width(), 14),
                             Qt.AlignCenter, theme.WEEKDAYS_SHORT[day.weekday()])

            painter.setFont(number_font)
            if day == self._today:
                painter.setPen(QColor(theme.ACCENT))
            else:
                painter.setPen(QColor(theme.TEXT if day.month == self._selected.month else theme.MUTED))
            label = f"{day.day}" if day.day != 1 else f"1 {theme.MONTHS_ES[day.month - 1][:3]}"
            painter.drawText(QRectF(rect.left(), rect.top() + 22, rect.width(), 26), Qt.AlignCenter, label)

            count = self._counts.get(day.isoformat(), 0)
            if count:
                badge = QRectF(rect.right() - 22, rect.top() + 4, 16, 13)
                painter.setPen(Qt.NoPen)
                painter.setBrush(QColor(theme.ACCENT if is_selected else theme.BADGE_BG))
                painter.drawRect(badge)
                painter.setFont(badge_font)
                painter.setPen(QColor("#0A0A0A" if is_selected else theme.TEXT))
                painter.drawText(badge, Qt.AlignCenter, str(min(count, 99)))

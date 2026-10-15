from datetime import date, timedelta
from typing import Dict, List, Optional

from PySide6.QtCore import QRectF, Qt, Signal
from PySide6.QtGui import QColor, QFont, QFontMetrics, QPainter, QPen
from PySide6.QtWidgets import QWidget

from core.matrix.motherboard.ecosystems.calendar.domain.entities import AgendaItem
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents import calendar_theme as theme

HEADER_HEIGHT = 30
ROWS, COLS = 6, 7
CHIP_HEIGHT = 18
WHEEL_STEP = 120


class MonthGrid(QWidget):
    """
    Cuadrícula mensual (lunes a domingo) con las actividades de cada día.

    Cada celda muestra el número del día y, según su tamaño, una línea por
    actividad con el color de su tipo. Emite `date_clicked` al seleccionar un día,
    `date_double_clicked` para crear algo en ese día y `month_step` al desplazar.
    """

    date_clicked = Signal(str)
    date_double_clicked = Signal(str)
    month_step = Signal(int)

    def __init__(self, parent=None):
        """
        Args:
            parent: Widget padre.
        """
        super().__init__(parent)
        today = date.today()
        self._year, self._month = today.year, today.month
        self._today = today
        self._selected: Optional[date] = None
        self._items: Dict[str, List[AgendaItem]] = {}
        self._wheel_accum = 0
        self.setMinimumSize(560, 380)

    def set_month(self, year: int, month: int, items: Dict[str, List[AgendaItem]], today: date) -> None:
        """
        Muestra un mes con sus actividades.

        Args:
            year: Año.
            month: Mes (1 a 12).
            items: Actividades agrupadas por fecha ISO.
            today: Fecha actual, que se resalta.
        """
        self._year, self._month, self._items, self._today = year, month, items, today
        self.update()

    def set_selected(self, day: Optional[date]) -> None:
        """Marca el día seleccionado."""
        self._selected = day
        self.update()

    # -------------------------------------------------------------- geometría
    def _start(self) -> date:
        """Primer día mostrado: el lunes de la semana que contiene el día 1."""
        first = date(self._year, self._month, 1)
        return first - timedelta(days=first.weekday())

    def _cell_rect(self, index: int) -> QRectF:
        """Rectángulo de la celda número `index` (0 a 41)."""
        cell_w = self.width() / COLS
        cell_h = (self.height() - HEADER_HEIGHT) / ROWS
        row, col = divmod(index, COLS)
        return QRectF(col * cell_w, HEADER_HEIGHT + row * cell_h, cell_w, cell_h).adjusted(2, 2, -2, -2)

    def _date_at(self, pos) -> Optional[date]:
        """Devuelve la fecha de la celda bajo `pos`, o None si cae fuera de la cuadrícula."""
        for index in range(ROWS * COLS):
            if self._cell_rect(index).contains(pos):
                return self._start() + timedelta(days=index)
        return None

    # ----------------------------------------------------------------- eventos
    def mousePressEvent(self, event):
        day = self._date_at(event.position())
        if day is not None:
            self.date_clicked.emit(day.isoformat())

    def mouseDoubleClickEvent(self, event):
        day = self._date_at(event.position())
        if day is not None:
            self.date_double_clicked.emit(day.isoformat())

    def wheelEvent(self, event):
        delta = event.angleDelta()
        self._wheel_accum += delta.x() if delta.x() != 0 else -delta.y()
        while abs(self._wheel_accum) >= WHEEL_STEP:
            direction = 1 if self._wheel_accum > 0 else -1
            self._wheel_accum -= direction * WHEEL_STEP
            self.month_step.emit(direction)
        event.accept()

    # ------------------------------------------------------------------ pintado
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        font = QFont(theme.FONT_FAMILY)

        font.setPixelSize(11)
        font.setWeight(QFont.Bold)
        font.setLetterSpacing(QFont.AbsoluteSpacing, 2)
        painter.setFont(font)
        painter.setPen(QColor(theme.MUTED))
        cell_w = self.width() / COLS
        for col, name in enumerate(theme.WEEKDAYS_SHORT):
            painter.drawText(QRectF(col * cell_w, 0, cell_w, HEADER_HEIGHT), Qt.AlignCenter, name)

        start = self._start()
        for index in range(ROWS * COLS):
            day = start + timedelta(days=index)
            self._paint_cell(painter, day, self._cell_rect(index))

    def _paint_cell(self, painter: QPainter, day: date, rect: QRectF) -> None:
        """Dibuja una celda: fondo, número del día y sus actividades."""
        in_month = day.month == self._month
        is_today = day == self._today
        is_selected = day == self._selected

        painter.setPen(QPen(QColor(theme.ACCENT if is_selected else theme.BORDER_FAINT), 1))
        painter.setBrush(QColor(theme.ACCENT_TINT) if is_selected
                         else QColor(theme.CELL if in_month else theme.CELL_DIM))
        painter.drawPath(theme.rounded_path(rect, 4))

        number_font = QFont(theme.FONT_FAMILY)
        number_font.setPixelSize(14)
        number_font.setWeight(QFont.Bold)
        painter.setFont(number_font)
        number_rect = QRectF(rect.left() + 8, rect.top() + 6, 26, 20)
        if is_today:
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(theme.ACCENT))
            painter.drawRect(number_rect)
            painter.setPen(QColor("#0A0A0A"))
        else:
            painter.setPen(QColor(theme.TEXT if in_month else theme.DIM))
        painter.drawText(number_rect, Qt.AlignCenter, str(day.day))

        items = self._items.get(day.isoformat(), []) if in_month else []
        if not items:
            return
        chip_font = QFont(theme.FONT_FAMILY)
        chip_font.setPixelSize(11)
        painter.setFont(chip_font)
        metrics = QFontMetrics(chip_font)
        top = rect.top() + 32
        max_lines = max(1, int((rect.bottom() - top - 4) // CHIP_HEIGHT))
        shown = items if len(items) <= max_lines else items[:max_lines - 1]
        for line, item in enumerate(shown):
            y = top + line * CHIP_HEIGHT
            painter.setPen(Qt.NoPen)
            painter.setBrush(QColor(theme.item_color(item)))
            painter.drawRect(QRectF(rect.left() + 8, y + 2, 3, CHIP_HEIGHT - 6))
            label = f"{theme.item_glyph(item)}{item.time} {item.title}" if item.time \
                else f"{theme.item_glyph(item)}{item.title}"
            text_w = int(rect.width() - 22)
            painter.setPen(QColor(theme.TEXT if item.status != "completed" else theme.MUTED))
            painter.drawText(QRectF(rect.left() + 15, y, text_w, CHIP_HEIGHT),
                             Qt.AlignVCenter | Qt.AlignLeft,
                             metrics.elidedText(label, Qt.ElideRight, text_w))
        hidden = len(items) - len(shown)
        if hidden > 0:
            y = top + len(shown) * CHIP_HEIGHT
            painter.setPen(QColor(theme.MUTED))
            painter.drawText(QRectF(rect.left() + 15, y, rect.width() - 22, CHIP_HEIGHT),
                             Qt.AlignVCenter | Qt.AlignLeft, f"+{hidden} más")

from datetime import date
from typing import Optional

from PySide6.QtCore import QRectF, Qt, Signal
from PySide6.QtGui import QColor, QFont, QPainter, QPen
from PySide6.QtWidgets import QWidget

from core.matrix.motherboard.ecosystems.logbook.presentation.rootComponents import book_theme

WEEKDAYS_ES = ["LUNES", "MARTES", "MIÉRCOLES", "JUEVES", "VIERNES", "SÁBADO", "DOMINGO"]
MONTHS_ES = [
    "ENERO", "FEBRERO", "MARZO", "ABRIL", "MAYO", "JUNIO", "JULIO",
    "AGOSTO", "SEPTIEMBRE", "OCTUBRE", "NOVIEMBRE", "DICIEMBRE",
]
WHEEL_STEP = 120  # unidades de `angleDelta` que equivalen a una muesca


class DatePage(QWidget):
    """
    Contenido de la página izquierda: la fecha del día en tamaño grande.

    El día, el mes y el año responden al desplazamiento (scroll) para navegar
    rápido: emite `step_requested(unidad, dirección)` con unidad "day", "month"
    o "year" y dirección +1 (adelante) o -1 (atrás).
    """

    step_requested = Signal(str, int)

    def __init__(self, parent=None):
        """
        Args:
            parent: Widget padre.
        """
        super().__init__(parent)
        self._day = date.today()
        self._hover: Optional[str] = None
        self._wheel_accum = 0
        self.setMouseTracking(True)

    def set_date(self, day: date) -> None:
        """
        Cambia la fecha mostrada.

        Args:
            day: Fecha a mostrar.
        """
        self._day = day
        self.update()

    # --------------------------------------------------------------- layout
    def _bands(self) -> dict:
        """Calcula la caja de cada elemento de la fecha según el tamaño actual."""
        w, h = self.width(), self.height()
        weekday_px = max(16, int(h * 0.045))
        day_px = int(min(h * 0.46, w * 0.5))
        month_px = max(18, int(h * 0.05))
        year_px = max(14, int(h * 0.035))

        weekday_top = h * 0.14
        day_top = h * 0.24
        month_top = day_top + day_px * 1.15 + 8
        year_top = month_top + month_px * 1.6
        return {
            "weekday": (QRectF(0, weekday_top, w, weekday_px * 2), weekday_px),
            "day": (QRectF(0, day_top, w, day_px * 1.15), day_px),
            "month": (QRectF(0, month_top, w, month_px * 1.6), month_px),
            "year": (QRectF(0, year_top, w, month_px * 1.4), year_px),
        }

    def _unit_at(self, y: float) -> Optional[str]:
        """Devuelve la unidad ("day", "month" o "year") bajo la altura `y`, si hay una."""
        bands = self._bands()
        for unit, key in (("day", "weekday"), ("day", "day"), ("month", "month"), ("year", "year")):
            if bands[key][0].top() - 6 <= y <= bands[key][0].bottom() + 6:
                return unit
        return None

    # --------------------------------------------------------------- events
    def mouseMoveEvent(self, event):
        unit = self._unit_at(event.position().y())
        if unit != self._hover:
            self._hover = unit
            self.update()

    def leaveEvent(self, event):
        self._hover = None
        self.update()

    def wheelEvent(self, event):
        """Convierte el desplazamiento en pasos de día, mes o año según el elemento bajo el cursor."""
        delta = event.angleDelta()
        # Desplazamiento horizontal: derecha avanza. Rueda vertical: abajo avanza.
        amount = delta.x() if delta.x() != 0 else -delta.y()
        unit = self._unit_at(event.position().y()) or "day"
        self._wheel_accum += amount
        while abs(self._wheel_accum) >= WHEEL_STEP:
            direction = 1 if self._wheel_accum > 0 else -1
            self._wheel_accum -= direction * WHEEL_STEP
            self.step_requested.emit(unit, direction)
        event.accept()

    # ---------------------------------------------------------------- paint
    @staticmethod
    def _font(pixel_size: int, weight, spacing: float = 0) -> QFont:
        """Crea una fuente de la familia del proyecto con espaciado entre letras."""
        font = QFont(book_theme.FONT_FAMILY)
        font.setPixelSize(max(8, pixel_size))
        font.setWeight(weight)
        font.setLetterSpacing(QFont.AbsoluteSpacing, spacing)
        return font

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        w, h = self.width(), self.height()
        bands = self._bands()
        accent = QColor(book_theme.ACCENT)
        white = QColor(book_theme.TEXT)
        muted = QColor(book_theme.TEXT_MUTED)

        # Esquinas tipo visor, en gris
        bracket = 30
        painter.setPen(QPen(QColor(book_theme.BRACKET), 2))
        for x, y, dx, dy in ((0, 0, 1, 1), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)):
            painter.drawLine(x, y, x + dx * bracket, y)
            painter.drawLine(x, y, x, y + dy * bracket)

        rect, px = bands["weekday"]
        painter.setFont(self._font(px, QFont.Bold, 6))
        painter.setPen(accent)
        painter.drawText(rect, Qt.AlignHCenter | Qt.AlignVCenter, WEEKDAYS_ES[self._day.weekday()])

        painter.setPen(QPen(QColor(book_theme.PAPER_EDGE), 1))
        line_y = int(rect.bottom() + 6)
        painter.drawLine(int(w * 0.2), line_y, int(w * 0.8), line_y)

        rect, px = bands["day"]
        painter.setFont(self._font(px, QFont.Bold))
        painter.setPen(accent if self._hover == "day" else white)
        painter.drawText(rect, Qt.AlignCenter, str(self._day.day))

        rect, px = bands["month"]
        painter.setFont(self._font(px, QFont.DemiBold, 8))
        painter.setPen(accent if self._hover == "month" else white)
        painter.drawText(rect, Qt.AlignHCenter | Qt.AlignVCenter, MONTHS_ES[self._day.month - 1])

        rect, px = bands["year"]
        painter.setFont(self._font(px, QFont.Normal, 10))
        painter.setPen(accent if self._hover == "year" else muted)
        painter.drawText(rect, Qt.AlignHCenter | Qt.AlignVCenter, str(self._day.year))

        painter.setFont(self._font(12, QFont.Normal, 3))
        painter.setPen(QColor(book_theme.TEXT_DIM))
        painter.drawText(QRectF(0, h - 40, w, 28), Qt.AlignHCenter | Qt.AlignVCenter,
                         "DESPLAZA SOBRE EL DÍA, EL MES O EL AÑO")

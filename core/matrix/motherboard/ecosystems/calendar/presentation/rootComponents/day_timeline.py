from datetime import date, datetime
from typing import Callable, List, Optional, Tuple

from PySide6.QtCore import QRectF, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QFont, QFontMetrics, QPainter, QPen
from PySide6.QtWidgets import QWidget

from core.matrix.motherboard.ecosystems.calendar.domain.entities import AgendaItem
from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents import calendar_theme as theme

HOUR_H = 64
AXIS_W = 64
HEADER_H = 40
CHIP_H = 26
MIN_CARD_H = 36
LANES = [("task", "TAREAS"), ("event", "EVENTOS"), ("reminder", "RECORDATORIOS")]
DEFAULT_MINUTES = {"task": 45, "event": 60, "birthday": 60, "reminder": 30}
NOW_REFRESH_MS = 30_000


def _lane_index(item: AgendaItem) -> int:
    """Devuelve la columna (0 tareas, 1 eventos, 2 recordatorios) de una actividad."""
    if item.kind == "task":
        return 0
    return 2 if item.kind == "reminder" else 1


def _minutes(hhmm: str) -> int:
    """Convierte "HH:MM" en minutos desde medianoche."""
    return int(hhmm[:2]) * 60 + int(hhmm[3:5])


class DayTimeline(QWidget):
    """
    Línea de tiempo del día seleccionado, con una columna por tipo de actividad.

    Las actividades con hora se colocan según su horario y duración; las de todo
    el día o con solo fecha límite van en una banda superior. Si el día es hoy se
    dibuja la línea de la hora actual. La rueda desplaza verticalmente.
    """

    item_clicked = Signal(str, str)   # kind, source_id

    def __init__(self, parent=None):
        """
        Args:
            parent: Widget padre.
        """
        super().__init__(parent)
        self._items: List[AgendaItem] = []
        self._day = date.today()
        self._today = date.today()
        self._scroll = 0
        self._selected_key: Optional[Tuple[str, str]] = None
        self._cards: List[Tuple[QRectF, AgendaItem]] = []
        self._clock: Callable[[], datetime] = datetime.now
        self.setMinimumHeight(300)

        self._now_timer = QTimer(self)
        self._now_timer.setInterval(NOW_REFRESH_MS)
        self._now_timer.timeout.connect(self.update)
        self._now_timer.start()

    # ------------------------------------------------------------------ datos
    def set_clock(self, clock: Callable[[], datetime]) -> None:
        """Define la función que entrega el momento actual (por defecto `datetime.now`)."""
        self._clock = clock

    def set_day(self, day: date, items: List[AgendaItem], today: date) -> None:
        """
        Muestra las actividades de un día.

        Args:
            day: Día mostrado.
            items: Actividades del día.
            today: Fecha actual, para decidir si se dibuja la línea de "ahora".
        """
        changed_day = day != self._day
        self._day, self._items, self._today = day, items, today
        if changed_day or self._scroll == 0:
            self._scroll = self._initial_scroll()
        self._clamp_scroll()
        self.update()

    def set_selected(self, key: Optional[Tuple[str, str]]) -> None:
        """Marca la actividad seleccionada, identificada por `(tipo, id)`."""
        self._selected_key = key
        self.update()

    def _initial_scroll(self) -> int:
        """Calcula el desplazamiento inicial para dejar a la vista lo relevante del día."""
        starts = [_minutes(i.time) for i in self._items if i.time]
        if starts:
            target = min(starts)
        elif self._day == self._today:
            now = self._clock()
            target = max(0, now.hour * 60 + now.minute - 90)
        else:
            target = 7 * 60
        return max(0, int(target / 60 * HOUR_H) - 24)

    # ------------------------------------------------------------- geometría
    def _lane_width(self) -> float:
        """Ancho de cada columna."""
        return (self.width() - AXIS_W - 6) / len(LANES)

    def _allday_items(self) -> List[List[AgendaItem]]:
        """Actividades sin hora, agrupadas por columna."""
        lanes: List[List[AgendaItem]] = [[] for _ in LANES]
        for item in self._items:
            if not item.time:
                lanes[_lane_index(item)].append(item)
        return lanes

    def _band_height(self) -> int:
        """Altura de la banda de actividades sin hora."""
        most = max((len(lane) for lane in self._allday_items()), default=0)
        return 0 if most == 0 else most * (CHIP_H + 4) + 10

    def _time_top(self) -> int:
        """Coordenada superior del área con horas."""
        return HEADER_H + self._band_height()

    def _max_scroll(self) -> int:
        """Desplazamiento máximo permitido."""
        return max(0, 24 * HOUR_H - (self.height() - self._time_top()))

    def _clamp_scroll(self) -> None:
        """Mantiene el desplazamiento dentro de los límites."""
        self._scroll = max(0, min(self._scroll, self._max_scroll()))

    def _layout_timed(self) -> List[Tuple[QRectF, AgendaItem]]:
        """Calcula el rectángulo de cada actividad con hora, resolviendo solapamientos."""
        lane_w = self._lane_width()
        top = self._time_top()
        placed: List[Tuple[QRectF, AgendaItem]] = []
        for lane in range(len(LANES)):
            entries = []
            for item in self._items:
                if item.time and _lane_index(item) == lane:
                    start = _minutes(item.time)
                    end = _minutes(item.end_time) if item.end_time else start
                    if end <= start:
                        end = start + DEFAULT_MINUTES.get(item.kind, 45)
                    entries.append((start, end, item))
            entries.sort(key=lambda e: (e[0], e[1]))

            columns: List[int] = []   # fin (min) de cada subcolumna
            assigned = []
            for start, end, item in entries:
                for col, col_end in enumerate(columns):
                    if col_end <= start:
                        columns[col] = end
                        break
                else:
                    col = len(columns)
                    columns.append(end)
                assigned.append((start, end, item, col))
            count = max(1, len(columns))
            sub_w = (lane_w - 8) / count
            for start, end, item, col in assigned:
                y = top + start / 60 * HOUR_H - self._scroll
                h = max(MIN_CARD_H, (end - start) / 60 * HOUR_H - 3)
                x = AXIS_W + lane * lane_w + 4 + col * sub_w
                placed.append((QRectF(x, y, sub_w - 3, h), item))
        return placed

    def _layout_allday(self) -> List[Tuple[QRectF, AgendaItem]]:
        """Calcula el rectángulo de cada actividad sin hora."""
        lane_w = self._lane_width()
        placed = []
        for lane, items in enumerate(self._allday_items()):
            for row, item in enumerate(items):
                x = AXIS_W + lane * lane_w + 4
                y = HEADER_H + 5 + row * (CHIP_H + 4)
                placed.append((QRectF(x, y, lane_w - 11, CHIP_H), item))
        return placed

    # ----------------------------------------------------------------- eventos
    def wheelEvent(self, event):
        self._scroll -= event.angleDelta().y() // 2
        self._clamp_scroll()
        self.update()
        event.accept()

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self._clamp_scroll()

    def mousePressEvent(self, event):
        pos = event.position()
        for rect, item in reversed(self._cards):
            if rect.contains(pos):
                self.item_clicked.emit(item.kind, item.source_id)
                return

    # ------------------------------------------------------------------ pintado
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        lane_w = self._lane_width()
        top = self._time_top()
        self._paint_header(painter, lane_w)
        self._paint_band(painter, lane_w)

        painter.save()
        painter.setClipRect(QRectF(0, top, self.width(), self.height() - top))
        self._paint_grid(painter, lane_w, top)
        timed = self._layout_timed()
        for rect, item in timed:
            self._paint_card(painter, rect, item)
        self._paint_now(painter, lane_w, top)
        painter.restore()

        self._cards = self._layout_allday() + [
            (r, i) for r, i in timed if r.bottom() > top and r.top() < self.height()
        ]

    def _paint_header(self, painter: QPainter, lane_w: float) -> None:
        """Dibuja los títulos de las columnas con su cantidad de actividades."""
        title_font = QFont(theme.FONT_FAMILY)
        title_font.setPixelSize(12)
        title_font.setWeight(QFont.Bold)
        title_font.setLetterSpacing(QFont.AbsoluteSpacing, 2)
        painter.setFont(title_font)
        for lane, (_, title) in enumerate(LANES):
            count = sum(1 for i in self._items if _lane_index(i) == lane)
            rect = QRectF(AXIS_W + lane * lane_w, 0, lane_w, HEADER_H)
            painter.setPen(QColor(theme.TEXT))
            painter.drawText(rect.adjusted(8, 0, 0, 0), Qt.AlignVCenter | Qt.AlignLeft, title)
            painter.setPen(QColor(theme.MUTED))
            painter.drawText(rect.adjusted(0, 0, -8, 0), Qt.AlignVCenter | Qt.AlignRight, str(count))
        painter.setPen(QPen(QColor(theme.BORDER_SOFT), 1))
        painter.drawLine(0, HEADER_H - 1, self.width(), HEADER_H - 1)

    def _paint_band(self, painter: QPainter, lane_w: float) -> None:
        """Dibuja la banda de actividades de todo el día o con solo fecha límite."""
        band = self._band_height()
        if not band:
            return
        label_font = QFont(theme.FONT_FAMILY)
        label_font.setPixelSize(9)
        label_font.setWeight(QFont.Bold)
        label_font.setLetterSpacing(QFont.AbsoluteSpacing, 1)
        painter.setFont(label_font)
        painter.setPen(QColor(theme.MUTED))
        painter.drawText(QRectF(0, HEADER_H, AXIS_W - 6, band), Qt.AlignRight | Qt.AlignTop,
                         "TODO\nEL DÍA")
        for rect, item in self._layout_allday():
            self._paint_card(painter, rect, item, compact=True)
        painter.setPen(QPen(QColor(theme.BORDER_SOFT), 1))
        painter.drawLine(0, HEADER_H + band - 1, self.width(), HEADER_H + band - 1)

    def _paint_grid(self, painter: QPainter, lane_w: float, top: int) -> None:
        """Dibuja las líneas de hora, las etiquetas del eje y los separadores de columna."""
        hour_font = QFont(theme.FONT_FAMILY)
        hour_font.setPixelSize(10)
        painter.setFont(hour_font)
        for hour in range(25):
            y = top + hour * HOUR_H - self._scroll
            if y < top - HOUR_H or y > self.height() + HOUR_H:
                continue
            painter.setPen(QPen(QColor(theme.CARD), 1))
            painter.drawLine(AXIS_W, int(y), self.width(), int(y))
            if hour < 24:
                painter.setPen(QColor(theme.MUTED))
                painter.drawText(QRectF(0, y + 2, AXIS_W - 8, 14), Qt.AlignRight | Qt.AlignTop,
                                 f"{hour:02d}:00")
        painter.setPen(QPen(QColor(theme.CARD), 1))
        for lane in range(len(LANES) + 1):
            x = int(AXIS_W + lane * lane_w)
            painter.drawLine(x, top, x, self.height())

    def _paint_card(self, painter: QPainter, rect: QRectF, item: AgendaItem, compact: bool = False) -> None:
        """Dibuja la tarjeta de una actividad."""
        color = QColor(theme.item_color(item))
        selected = self._selected_key == (item.kind, item.source_id)
        painter.setPen(QPen(QColor(theme.ACCENT if selected else theme.BORDER_SOFT), 1))
        painter.setBrush(QColor(theme.CARD_HOVER if selected else theme.CARD))
        painter.drawPath(theme.rounded_path(rect, 4))
        painter.setPen(Qt.NoPen)
        painter.setBrush(color)
        painter.drawRect(QRectF(rect.left() + 1, rect.top() + 1, 5, rect.height() - 2))

        title_font = QFont(theme.FONT_FAMILY)
        title_font.setPixelSize(12)
        title_font.setWeight(QFont.Bold)
        metrics = QFontMetrics(title_font)
        text_w = int(rect.width() - 22)
        painter.setFont(title_font)
        painter.setPen(QColor(theme.MUTED if item.status == "completed" else theme.TEXT))
        title_rect = QRectF(rect.left() + 14, rect.top() + (0 if compact else 5), text_w,
                            rect.height() if compact else 16)
        title = f"{theme.item_glyph(item)}{item.title}".upper()
        painter.drawText(title_rect, (Qt.AlignVCenter if compact else Qt.AlignTop) | Qt.AlignLeft,
                         metrics.elidedText(title, Qt.ElideRight, text_w))
        if compact or rect.height() < 40:
            return

        sub_font = QFont(theme.FONT_FAMILY)
        sub_font.setPixelSize(10)
        painter.setFont(sub_font)
        painter.setPen(QColor(theme.MUTED))
        when = f"{item.time} – {item.end_time}" if item.end_time else item.time
        if item.kind == "task":
            when = f"LÍMITE {item.time}"
        sub = QFontMetrics(sub_font).elidedText(when, Qt.ElideRight, text_w)
        painter.drawText(QRectF(rect.left() + 14, rect.top() + 23, text_w, 14),
                         Qt.AlignTop | Qt.AlignLeft, sub)

    def _paint_now(self, painter: QPainter, lane_w: float, top: int) -> None:
        """Dibuja la línea y la etiqueta de la hora actual cuando el día mostrado es hoy."""
        if self._day != self._today:
            return
        now = self._clock()
        y = top + (now.hour * 60 + now.minute) / 60 * HOUR_H - self._scroll
        if y < top or y > self.height():
            return
        painter.setPen(QPen(QColor(theme.ACCENT), 1))
        painter.drawLine(AXIS_W - 4, int(y), self.width(), int(y))
        label = QRectF(2, y - 9, AXIS_W - 8, 18)
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor(theme.ACCENT))
        painter.drawRect(label)
        font = QFont(theme.FONT_FAMILY)
        font.setPixelSize(10)
        font.setWeight(QFont.Bold)
        painter.setFont(font)
        painter.setPen(QColor("#0A0A0A"))
        painter.drawText(label, Qt.AlignCenter, now.strftime("%H:%M"))

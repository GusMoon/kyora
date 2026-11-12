"""El selector de fecha de una tarea: un calendario del mes, propio (sin el desplegable de Qt, que robaría el foco al panel).

Marca el día de hoy con un aro; al elegir el día de entrega pinta todos los días desde hoy hasta él como una banda. Debajo,
la hora y los botones Cancelar y Aceptar. Se enseña dentro del recuadro de la descripción (`Well`).
"""
from datetime import date, datetime, time, timedelta

from PySide6.QtCore import QPointF, QRectF, Qt, Signal
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import QHBoxLayout, QLineEdit, QPushButton, QVBoxLayout, QWidget

from kyora.ui.bar import font

MONTHS = ("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre",
          "diciembre")
WEEKDAYS = ("L", "M", "X", "J", "V", "S", "D")


def _css(color):
    c = QColor(color)
    return f"rgba({c.red()}, {c.green()}, {c.blue()}, {c.alpha()})"


HEAD_H = 34
WEEK_H = 24
MAX_CELL_H = 38


def month_start(day):
    return day.replace(day=1)


def shift_month(day, delta):
    index = day.year * 12 + day.month - 1 + delta
    return date(index // 12, index % 12 + 1, 1)


def month_cells(first):
    """Las 42 fechas (6 semanas de lunes a domingo) que enseña el mes de `first`."""
    start = first - timedelta(days=first.weekday())
    return [start + timedelta(days=i) for i in range(42)]


def band(today, chosen):
    """(desde, hasta) de la banda de días entre hoy y el día elegido (en el orden que sea), o None si no hay elegido."""
    if chosen is None:
        return None
    return (today, chosen) if today <= chosen else (chosen, today)


class Grid(QWidget):
    """La cabecera del mes, los días de la semana y la cuadrícula de días."""

    picked = Signal(object)  # la fecha que se pulsó

    def __init__(self, theme, today):
        super().__init__()
        self.theme, self.today = theme, today
        self.view = month_start(today)
        self.chosen = None
        self._hit = {}  # fecha -> rectángulo
        self._arrows = {}
        self.setMouseTracking(True)

    def set_view(self, first):
        self.view = month_start(first)
        self.update()

    def cell(self):
        rows_h = self.height() - HEAD_H - WEEK_H
        return self.width() / 7, min(rows_h / 6, MAX_CELL_H)

    def mouseReleaseEvent(self, event):
        pos = event.position()
        for delta, rect in self._arrows.items():
            if rect.contains(pos):
                self.set_view(shift_month(self.view, delta))
                return
        for day, rect in self._hit.items():
            if rect.contains(pos):
                self.picked.emit(day)
                return

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        w, h = self.cell()
        # la cabecera: mes y año, con las flechas a la derecha
        p.setFont(font(t, bold=True))
        p.setPen(QColor(t.ink))
        p.drawText(QRectF(2, 0, self.width() - 80, HEAD_H), Qt.AlignVCenter,
                   f"{MONTHS[self.view.month - 1].capitalize()} {self.view.year}")
        self._arrows = {}
        for delta, x in ((-1, self.width() - 66), (1, self.width() - 34)):
            box = QRectF(x, 5, 28, HEAD_H - 10)
            self._arrows[delta] = box
            p.setPen(QPen(QColor(t.dim), 1.8, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin))
            c = box.center()
            tip, tail = c.x() + 3 * delta, c.x() - 3 * delta  # el pico de ‹ o › apunta hacia donde va
            p.drawLine(QPointF(tail, c.y() - 5), QPointF(tip, c.y()))
            p.drawLine(QPointF(tip, c.y()), QPointF(tail, c.y() + 5))
        p.setFont(font(t))
        p.setPen(QColor(t.dim))
        for i, name in enumerate(WEEKDAYS):
            p.drawText(QRectF(i * w, HEAD_H, w, WEEK_H), Qt.AlignCenter, name)
        span = band(self.today, self.chosen)
        self._hit = {}
        cells = month_cells(self.view)
        gold = QColor(t.gold)
        for row in range(6):
            top = HEAD_H + WEEK_H + row * h
            days = cells[row * 7:row * 7 + 7]
            run = [i for i, d in enumerate(days) if span and span[0] <= d <= span[1]]
            if run:  # la banda de esa semana: una píldora continua por detrás de los números
                fill = QColor(gold)
                fill.setAlpha(48)
                p.setPen(Qt.NoPen)
                p.setBrush(fill)
                p.drawRoundedRect(QRectF(run[0] * w + 2, top + 3, (run[-1] - run[0] + 1) * w - 4, h - 6), (h - 6) / 2,
                                  (h - 6) / 2)
            for i, day in enumerate(days):
                rect = QRectF(i * w, top, w, h)
                self._hit[day] = rect
                outside = day.month != self.view.month  # los de los meses de al lado, apagados (la banda los cruza)
                centre = rect.center()
                radius = min(w, h) / 2 - 3
                if day == self.chosen:
                    p.setPen(Qt.NoPen)
                    p.setBrush(gold)
                    p.drawEllipse(centre, radius, radius)
                elif day == self.today:
                    p.setPen(QPen(gold, 1.6))
                    p.setBrush(Qt.NoBrush)
                    p.drawEllipse(centre, radius, radius)
                p.setFont(font(t, bold=day in (self.today, self.chosen)))
                p.setPen(QColor(t.pick_ink) if day == self.chosen else QColor(t.dim if outside else t.ink))
                p.drawText(rect, Qt.AlignCenter, str(day.day))


class DatePicker(QWidget):
    accepted = Signal(object)  # "AAAA-MM-DDTHH:MM", o None si se quitó la fecha
    cancelled = Signal()

    def __init__(self, theme, default_hour=time(18, 0)):
        super().__init__()
        self.theme, self.default_hour = theme, default_hour
        self.today = date.today()
        self.grid = Grid(theme, self.today)
        self.grid.picked.connect(self._pick)
        self.hour = QLineEdit()
        self.hour.setInputMask("99:99")
        self.hour.setFixedWidth(64)
        self.hour.setAlignment(Qt.AlignCenter)
        self.clear_button = QPushButton("Quitar fecha")
        self.cancel_button = QPushButton("Cancelar")
        self.accept_button = QPushButton("Aceptar")
        self.accept_button.setObjectName("Accept")
        for button in (self.clear_button, self.cancel_button, self.accept_button):
            button.setCursor(Qt.PointingHandCursor)
            button.setFocusPolicy(Qt.NoFocus)
        self.clear_button.clicked.connect(self._clear)
        self.cancel_button.clicked.connect(self.cancelled)
        self.accept_button.clicked.connect(self._accept)
        foot = QHBoxLayout()
        foot.setSpacing(8)
        foot.addWidget(self.hour)
        foot.addWidget(self.clear_button)
        foot.addStretch(1)
        foot.addWidget(self.cancel_button)
        foot.addWidget(self.accept_button)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)
        layout.addWidget(self.grid, 1)
        layout.addLayout(foot)
        t = theme
        self.setFocusPolicy(Qt.StrongFocus)
        self.setStyleSheet(
            f"QLineEdit {{ background: transparent; color: {t.ink}; border: 1px solid {_css(t.line)}; border-radius: 8px;"
            f" padding: 5px 6px; font: {t.font_px}px '{t.font_family}'; }}"
            f"QLineEdit:focus {{ border-color: {t.gold}; }}"
            f"QPushButton {{ background: transparent; color: {t.dim}; border: 0; border-radius: 8px; padding: 6px 12px;"
            f" font: {t.font_px}px '{t.font_family}'; }}"
            f"QPushButton:hover {{ background: {_css(t.hover)}; color: {t.ink}; }}"
            f"QPushButton#Accept {{ background: {t.gold}; color: {t.pick_ink}; font-weight: bold; }}"
            f"QPushButton#Accept:hover {{ background: {t.gold}; color: {t.pick_ink}; }}"
        )

    # ---------- abrir y cerrar ----------

    def open(self, due=None):
        """Se abre en el mes de la fecha de la tarea (o en el de hoy) con ella elegida y con su hora (o la de siempre)."""
        self.today = date.today()
        self.grid.today = self.today
        moment = None
        if due:
            try:
                moment = datetime.fromisoformat(due)
            except ValueError:
                moment = None
        self.grid.chosen = moment.date() if moment else None
        self.grid.set_view(moment.date() if moment else self.today)
        self.hour.setText((moment.time() if moment else self.default_hour).strftime("%H:%M"))
        self.setFocus()

    def _pick(self, day):
        self.grid.chosen = day
        self.grid.update()
        self.setFocus()

    def _clear(self):
        self.grid.chosen = None
        self.grid.update()

    def _time(self):
        try:
            return datetime.strptime(self.hour.text(), "%H:%M").time()
        except ValueError:
            return self.default_hour

    def _accept(self):
        chosen = self.grid.chosen
        self.accepted.emit(datetime.combine(chosen, self._time()).strftime("%Y-%m-%dT%H:%M") if chosen else None)

    # ---------- teclado ----------

    def keyPressEvent(self, event):
        key = event.key()
        moves = {Qt.Key_Left: -1, Qt.Key_Right: 1, Qt.Key_Up: -7, Qt.Key_Down: 7}
        if key in moves:
            base = self.grid.chosen or self.today
            day = base + timedelta(days=moves[key])
            self.grid.chosen = day
            self.grid.set_view(day)
        elif key in (Qt.Key_PageUp, Qt.Key_PageDown):
            self.grid.set_view(shift_month(self.grid.view, -1 if key == Qt.Key_PageUp else 1))
        elif key in (Qt.Key_Return, Qt.Key_Enter):
            self._accept()
        elif key == Qt.Key_Escape:
            self.cancelled.emit()
        else:
            super().keyPressEvent(event)

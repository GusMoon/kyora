"""Lobby: la primera sección del panel de arriba, como la imagen de referencia.

Izquierda: la hora en grande con la fecha, el clima de las próximas horas, RAM y CPU (donde la referencia tiene
"Explore" y "Story"), volumen, brillo, disco y batería, y el usuario de Windows.
Derecha: la franja de la semana con hoy resaltado y, debajo, la zona de tareas (vacía por ahora).

Recibe los datos con `on_devices` (cada 2 s) y `on_weather`. El reloj solo corre mientras el Lobby se ve.
"""
from datetime import date, datetime

from PySide6.QtCore import QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import (
    QAbstractButton,
    QHBoxLayout,
    QLabel,
    QSizePolicy,
    QSlider,
    QVBoxLayout,
    QWidget,
)

from kyora.core.calendar_grid import MONTHS, SHORT, WEEKDAYS, week_days
from kyora.system.stats import gigabytes, user_info
from kyora.ui import glyphs
from kyora.ui.bar import font
from kyora.ui.hub.cards import BarChart, Card, Glass, paint_glass

SLIDER_MS = 60  # como mucho un cambio de volumen o brillo cada tanto mientras se arrastra
CELL_GAP = 8


class WeatherStrip(QWidget):
    """Celdas de cristal: ahora (resaltada) y las próximas horas, con su icono y su temperatura."""

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.cells = []  # [(texto de la hora, icono, temperatura)]
        self.message = "Cargando el clima…"
        self.setFixedHeight(104)

    def set_weather(self, data):
        if "error" in data:
            self.cells, self.message = [], data["error"]
        else:
            self.cells = [("Ahora", data["icon"], data["temp"])] + [
                (f"{h['hour']}:00", h["icon"], h["temp"]) for h in data.get("hours", ())]
            self.message = data.get("place", "")
        self.setToolTip(self.message)
        self.update()

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        if not self.cells:
            paint_glass(p, t, self.rect(), 16)
            p.setPen(QColor(t.dim))
            p.setFont(font(t, t.explorer_font_px))
            p.drawText(QRectF(self.rect()).adjusted(16, 0, -16, 0), Qt.AlignVCenter | Qt.TextWordWrap, self.message)
            return
        n = 7
        w = (self.width() - CELL_GAP * (n - 1)) / n
        for i, (label, icon, temp) in enumerate(self.cells[:n]):
            cell = QRectF(i * (w + CELL_GAP), 0, w, self.height())
            paint_glass(p, t, cell, 14, hi=i == 0)
            draw = glyphs.WEATHER.get(icon)
            if draw:
                p.setPen(glyphs.pen(QColor(t.ink), 1.6))
                p.setBrush(Qt.NoBrush)
                size = min(w * 0.5, 32)
                draw(p, QRectF(cell.center().x() - size / 2, cell.top() + 12, size, size))
            p.setPen(QColor(t.ink))
            p.setFont(font(t, 15, bold=True))
            p.drawText(QRectF(cell.left(), cell.top() + 50, w, 22), Qt.AlignCenter, f"{temp}°")
            p.setPen(QColor(t.ink if i == 0 else t.dim))
            p.setFont(font(t, 15, bold=i == 0))
            p.drawText(QRectF(cell.left(), cell.top() + 74, w, 22), Qt.AlignCenter, label)


class WeekStrip(QWidget):
    """Los días alrededor de hoy (como 22 23 24 [25] 26 27 28 de la referencia); hoy en claro."""

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.today = date.today()
        self.setFixedHeight(76)

    def set_today(self, today):
        if today != self.today:
            self.today = today
            self.update()

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        days = week_days(self.today)
        w = (self.width() - CELL_GAP * (len(days) - 1)) / len(days)
        for i, day in enumerate(days):
            cell = QRectF(i * (w + CELL_GAP), 0, w, self.height())
            today = day == self.today
            paint_glass(p, t, cell, 14, fill=t.pick_bg if today else None)
            p.setPen(QColor(t.pick_ink if today else t.ink))
            p.setFont(font(t, 22, bold=True))
            p.drawText(QRectF(cell.left(), cell.top() + 8, w, 34), Qt.AlignCenter, str(day.day))
            p.setPen(QColor(t.pick_ink if today else t.dim))
            p.setFont(font(t, 15, bold=today))
            p.drawText(QRectF(cell.left(), cell.top() + 42, w, 24), Qt.AlignCenter, SHORT[day.weekday()])


class MetricCard(Card):
    """RAM o CPU: número grande, una línea y su historial en barras."""

    def __init__(self, theme, title):
        super().__init__(theme, title)
        self.number = QLabel("—")
        self.number.setObjectName("MidNumber")
        self.line = QLabel("")
        self.line.setObjectName("Dim")
        self.chart = BarChart(theme, show=12, gap=5, labels=False)
        top = QHBoxLayout()
        top.addWidget(self.number)
        top.addStretch(1)
        top.addWidget(self.line, 0, Qt.AlignBottom)
        layout = QVBoxLayout(self.inner)
        layout.setContentsMargins(16, 10, 16, 14)
        layout.setSpacing(6)
        layout.addLayout(top)
        layout.addWidget(self.chart, 1)

    def set_value(self, value, line, history, warn):
        self.number.setText(f"{value} %")
        self.number.setStyleSheet(f"color: {self.theme.warn};" if warn else "")
        self.line.setText(line)
        self.chart.set_values(history or [value], self.title.text())


class IconToggle(QAbstractButton):
    """El icono de una fila de nivel: en el volumen, un clic silencia."""

    def __init__(self, theme, glyph, tip):
        super().__init__()
        self.theme, self.glyph = theme, glyph
        self.setCheckable(True)
        self.setToolTip(tip)
        self.setFixedSize(30, 30)
        self.setAttribute(Qt.WA_Hover)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        if self.underMouse() and self.isEnabled():
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.hover))
            p.drawRoundedRect(QRectF(self.rect()), 8, 8)
        p.setPen(glyphs.pen(QColor(t.dim if self.isChecked() else t.ink), 1.6))
        p.setBrush(Qt.NoBrush)
        self.glyph(p, QRectF(self.rect()).adjusted(5, 5, -5, -5), self.isChecked())


class LevelRow(QWidget):
    """Volumen o brillo: icono, deslizador y valor. Los movimientos se agrupan antes de mandarlos al núcleo."""

    def __init__(self, theme, invoke, kind):
        super().__init__()
        self._invoke, self.kind = invoke, kind
        self._value = None
        self._send = QTimer(self)
        self._send.setSingleShot(True)
        self._send.setInterval(SLIDER_MS)
        self._send.timeout.connect(self._apply)
        if kind == "volume":
            self.icon = IconToggle(theme, lambda p, b, muted: glyphs.speaker(p, b, muted=muted), "Silenciar")
            self.icon.setCursor(Qt.PointingHandCursor)
            self.icon.toggled.connect(lambda on: self._invoke("audio.set", muted=on))
        else:
            self.icon = IconToggle(theme, lambda p, b, _: glyphs.brightness(p, b), "Brillo")
            self.icon.setEnabled(False)
        self.slider = QSlider(Qt.Horizontal)
        self.slider.setRange(0, 100)
        self.slider.valueChanged.connect(self._moved)
        self.value = QLabel("—")
        self.value.setFixedWidth(52)
        self.value.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
        row = QHBoxLayout(self)
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(10)
        row.addWidget(self.icon)
        row.addWidget(self.slider, 1)
        row.addWidget(self.value)

    def set_devices(self, d):
        value = d.get(self.kind if self.kind == "volume" else "brightness")
        if value is None or self.slider.isSliderDown():
            return
        self.slider.blockSignals(True)
        self.slider.setValue(value)
        self.slider.blockSignals(False)
        self.value.setText(f"{value} %")
        if self.kind == "volume":
            self.icon.blockSignals(True)
            self.icon.setChecked(bool(d.get("muted")))
            self.icon.setToolTip("Quitar el silencio" if d.get("muted") else "Silenciar")
            self.icon.blockSignals(False)
            self.icon.update()

    def _moved(self, value):
        self._value = value
        self.value.setText(f"{value} %")
        self._send.start()

    def _apply(self):
        if self.kind == "volume":
            self._invoke("audio.set", level=self._value)
        else:
            self._invoke("display.set_brightness", level=self._value)


class Chip(QLabel):
    """Disco o batería en una pastilla de cristal."""

    def __init__(self, theme):
        super().__init__("—")
        self.theme = theme
        self.setTextFormat(Qt.RichText)
        self.setContentsMargins(12, 6, 12, 6)

    def paintEvent(self, event):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        paint_glass(p, self.theme, self.rect(), 12, hi=True)
        p.end()
        super().paintEvent(event)


class Avatar(QWidget):
    def __init__(self, theme, name):
        super().__init__()
        self.theme, self.initial = theme, (name.strip()[:1] or "?").upper()
        self.setFixedSize(44, 44)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(t.glass_top))
        p.drawEllipse(QRectF(self.rect()).adjusted(1, 1, -1, -1))
        p.setBrush(QColor(t.gold))
        p.drawEllipse(QRectF(self.rect()).adjusted(5, 5, -5, -5))
        p.setPen(QColor(t.pick_ink))
        p.setFont(font(t, 17, bold=True))
        p.drawText(QRectF(self.rect()), Qt.AlignCenter, self.initial)


class LobbyPage(QWidget):
    def __init__(self, theme, invoke):
        super().__init__()
        self.theme = theme
        # ---------- izquierda ----------
        self.clock = QLabel("--:--")
        self.clock.setObjectName("Clock")
        self.date_line = QLabel("")
        self.date_line.setObjectName("DateLine")
        self.weekday = QLabel("")
        self.weekday.setObjectName("Dim")
        when = QVBoxLayout()
        when.setSpacing(0)
        when.addWidget(self.clock)
        when.addWidget(self.date_line)
        when.addWidget(self.weekday)
        self.weather = WeatherStrip(theme)
        self.ram = MetricCard(theme, "RAM")
        self.cpu = MetricCard(theme, "CPU")
        metrics = QHBoxLayout()
        metrics.setSpacing(10)
        metrics.addWidget(self.ram)
        metrics.addWidget(self.cpu)
        self.volume = LevelRow(theme, invoke, "volume")
        self.brightness = LevelRow(theme, invoke, "brightness")
        self.brightness.hide()  # solo si la pantalla deja cambiarlo
        self.disk = Chip(theme)
        self.battery = Chip(theme)
        chips = QHBoxLayout()
        chips.setSpacing(8)
        chips.addWidget(self.disk)
        chips.addWidget(self.battery)
        chips.addStretch(1)
        self.device = Glass(theme)
        device = QVBoxLayout(self.device)
        device.setContentsMargins(14, 10, 14, 12)
        device.setSpacing(6)
        device.addWidget(self.volume)
        device.addWidget(self.brightness)
        device.addLayout(chips)
        name, computer = user_info()
        who = QLabel(name)
        who.setObjectName("Heading")
        where = QLabel(computer)
        where.setObjectName("Dim")
        names = QVBoxLayout()
        names.setSpacing(0)
        names.addWidget(who)
        names.addWidget(where)
        user = QHBoxLayout()
        user.setSpacing(12)
        user.addWidget(Avatar(theme, name))
        user.addLayout(names, 1)
        left_side = QWidget()
        left = QVBoxLayout(left_side)
        left.setContentsMargins(0, 0, 0, 0)
        left.setSpacing(12)
        left.addLayout(when)
        left.addWidget(self.weather)
        left.addLayout(metrics, 1)
        left.addWidget(self.device)
        left.addLayout(user)
        # ---------- derecha ----------
        self.week = WeekStrip(theme)
        self.tasks_area = Glass(theme)  # la zona de tareas: vacía por ahora
        right_side = QWidget()
        right = QVBoxLayout(right_side)
        right.setContentsMargins(0, 0, 0, 0)
        right.setSpacing(12)
        right.addWidget(self.week)
        right.addWidget(self.tasks_area, 1)
        for side in (left_side, right_side):  # el reparto 5:6 manda, no lo largo de los textos
            side.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        row = QHBoxLayout(self)
        row.setContentsMargins(4, 0, 0, 0)
        row.setSpacing(24)
        row.addWidget(left_side, 5)
        row.addWidget(right_side, 6)

        self._tick = QTimer(self)
        self._tick.setInterval(1000)
        self._tick.timeout.connect(self._clock)
        self._clock()

    def _clock(self):
        now = datetime.now()
        self.clock.setText(now.strftime("%H:%M"))
        self.date_line.setText(f"{now.day} de {MONTHS[now.month - 1]} de {now.year}")
        self.weekday.setText(WEEKDAYS[now.weekday()].capitalize())
        self.week.set_today(now.date())

    def showEvent(self, event):
        self._clock()
        self._tick.start()
        super().showEvent(event)

    def hideEvent(self, event):
        self._tick.stop()
        super().hideEvent(event)

    def on_devices(self, d):
        t = self.theme
        history = d.get("history") or {}
        if "cpu" in d:
            cpu_hist = history.get("cpu") or [d["cpu"]]
            average = round(sum(cpu_hist) / len(cpu_hist))
            self.cpu.set_value(d["cpu"], f"media {average} %", cpu_hist, d["cpu"] >= t.warn_at)
            self.ram.set_value(d["ram"], f"{gigabytes(d['ram_used'])} de {gigabytes(d['ram_total'])} GB",
                               history.get("ram"), d["ram"] >= t.warn_at)
        if "disk" in d:
            color = t.warn if d["disk"] >= t.warn_at else t.ink
            self.disk.setText(f"Disco C: <b style='color:{color}'>{d['disk']} %</b>")
            self.disk.setToolTip(f"{gigabytes(d['disk_used'])} de {gigabytes(d['disk_total'])} GB usados")
        if "battery" in d:
            state = "cargando" if d.get("plugged") else "con batería"
            self.battery.setText(f"Batería <b>{d['battery']} %</b> <span style='color:{t.dim}'>{state}</span>")
        self.battery.setVisible("battery" in d)
        self.volume.set_devices(d)
        self.brightness.setVisible(d.get("brightness") is not None)
        self.brightness.set_devices(d)

    def on_weather(self, data):
        self.weather.set_weather(data)

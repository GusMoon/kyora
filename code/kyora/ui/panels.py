"""Páginas del panel de la barra (kyora/ui/dock.py): apagar (también con Win+X), la hora con el calendario y el
Bluetooth (el wifi está en wifi_panel.py).

Aquí no hay reglas de negocio: cada opción pide una acción al núcleo con `invoke(acción, **datos)`.
"""
import os
from datetime import date, datetime

from PySide6.QtCore import QRectF, Qt, QTimer, Signal
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import (
    QAbstractButton,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from kyora.core.calendar_grid import (
    INITIALS,
    MONTHS,
    long_date,
    month_grid,
    shift_month,
)
from kyora.ui import glyphs
from kyora.ui.bar import font
from kyora.ui.dock import DockPage
from kyora.ui.gauges import Caption
from kyora.ui.search import _css

# (glifo, título, acción) de las opciones de energía, en el orden de las teclas 1, 2 y 3
POWER_OPTIONS = (
    (glyphs.power, "Apagar", "system.shutdown"),
    (glyphs.restart, "Reiniciar", "system.restart"),
    (glyphs.moon, "Suspender", "system.sleep"),
)

TILE_GAP = 10
ROW_H = 54


class PowerTiles(QWidget):
    """Tres opciones grandes, una al lado de otra. La elegida se resalta con el acento."""

    chosen = Signal(int)

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.selected = 0
        self.setMouseTracking(True)
        self.setCursor(Qt.PointingHandCursor)
        self.setFocusPolicy(Qt.StrongFocus)

    def _tile(self, i):
        w = (self.width() - TILE_GAP * (len(POWER_OPTIONS) - 1)) / len(POWER_OPTIONS)
        return QRectF(i * (w + TILE_GAP), 0, w, self.height())

    def _at(self, pos):
        return next((i for i in range(len(POWER_OPTIONS)) if self._tile(i).contains(pos)), None)

    def mouseMoveEvent(self, event):
        i = self._at(event.position())
        if i is not None and i != self.selected:
            self.selected = i
            self.update()

    def mouseReleaseEvent(self, event):
        i = self._at(event.position())
        if event.button() == Qt.LeftButton and i is not None:
            self.chosen.emit(i)

    def keyPressEvent(self, event):
        key = event.key()
        if key in (Qt.Key_Left, Qt.Key_Right):
            self.selected = (self.selected + (1 if key == Qt.Key_Right else -1)) % len(POWER_OPTIONS)
            self.update()
        elif Qt.Key_1 <= key <= Qt.Key_3:
            self.chosen.emit(key - Qt.Key_1)
        elif key in (Qt.Key_Return, Qt.Key_Enter):
            self.chosen.emit(self.selected)
        else:
            super().keyPressEvent(event)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        for i, (glyph, title, _) in enumerate(POWER_OPTIONS):
            r = self._tile(i).adjusted(0.5, 0.5, -0.5, -0.5)
            on = i == self.selected
            p.setPen(QPen(QColor(t.gold_line if on else t.line), 1))
            p.setBrush(QColor(t.gold_soft if on else t.capsule))
            p.drawRoundedRect(r, 12, 12)
            p.setPen(glyphs.pen(QColor(t.gold if on else t.ink), 2))
            p.setBrush(Qt.NoBrush)
            side = min(r.width(), r.height()) * 0.36
            glyph(p, QRectF(r.center().x() - side / 2, r.top() + r.height() * 0.18, side, side))
            p.setPen(QColor(t.ink))
            p.setFont(font(t, t.font_px + 2, bold=on))
            p.drawText(QRectF(r.left(), r.bottom() - 40, r.width(), 28), Qt.AlignCenter, f"{title}")
            p.setPen(QColor(t.dim))
            p.setFont(font(t, t.small_px))
            p.drawText(QRectF(r.left() + 8, r.top() + 6, 20, 16), Qt.AlignLeft, str(i + 1))


class PowerPage(DockPage):
    """Apagar, reiniciar o suspender (botón de apagar de la barra o Win+X)."""

    size = (390, 150)

    def __init__(self, theme, invoke):
        super().__init__()
        self.theme = theme
        self._invoke = invoke
        self.tiles = PowerTiles(theme)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(self.tiles)
        self.tiles.chosen.connect(self._choose)

    def activate(self):
        self.tiles.selected = 0

    def focus_first(self):
        self.tiles.setFocus()

    def _choose(self, index):
        self.close_requested.emit()
        self._invoke(POWER_OPTIONS[index][2])


class Switch(QAbstractButton):
    """Interruptor redondeado (encendido con el acento)."""

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.setCheckable(True)
        self.setFixedSize(44, 24)
        self.setCursor(Qt.PointingHandCursor)

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        on = self.isChecked()
        p.setPen(QPen(QColor(t.gold_line if on else t.line), 1))
        p.setBrush(QColor(t.gold_soft if on else t.capsule))
        p.drawRoundedRect(QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5), 12, 12)
        p.setPen(Qt.NoPen)
        p.setBrush(QColor(t.gold if on else t.dim))
        x = self.width() - 12 if on else 12
        p.drawEllipse(QRectF(x - 8, 4, 16, 16))


class MonthView(QWidget):
    """El mes en cuadrícula de lunes a domingo, con hoy resaltado y ‹ › para cambiar de mes."""

    HEAD = 40
    WEEK_H = 30

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.reset()

    def reset(self):
        self.today = date.today()
        self.year, self.month = self.today.year, self.today.month
        self.update()

    def _arrows(self):
        w = self.width()
        return QRectF(w - 64, 6, 28, 28), QRectF(w - 30, 6, 28, 28)

    def mousePressEvent(self, event):
        for rect, delta in zip(self._arrows(), (-1, 1)):
            if rect.contains(event.position()):
                self.year, self.month = shift_month(self.year, self.month, delta)
                self.update()

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setPen(QColor(t.ink))
        p.setFont(font(t, t.font_px + 5, bold=True))
        p.drawText(QRectF(4, 0, self.width(), self.HEAD), Qt.AlignVCenter | Qt.AlignLeft,
                   f"{MONTHS[self.month - 1].capitalize()} {self.year}")
        p.setPen(glyphs.pen(QColor(t.dim), 1.6))
        for rect, way in zip(self._arrows(), ("left", "right")):
            glyphs.arrow(p, rect.adjusted(6, 6, -6, -6), way)
        cell_w = self.width() / 7
        top = self.HEAD + 6
        p.setFont(font(t, t.small_px + 1, bold=True))
        p.setPen(QColor(t.dim))
        for i, letter in enumerate(INITIALS):
            p.drawText(QRectF(i * cell_w, top, cell_w, 20), Qt.AlignCenter, letter)
        top += 24
        p.setFont(font(t, t.font_px + 1))
        for row, week in enumerate(month_grid(self.year, self.month)):
            for col, day in enumerate(week):
                cell = QRectF(col * cell_w, top + row * self.WEEK_H, cell_w, self.WEEK_H)
                if day == self.today:
                    p.setPen(Qt.NoPen)
                    p.setBrush(QColor(t.gold))
                    side = min(cell.width(), cell.height()) - 4
                    p.drawEllipse(QRectF(cell.center().x() - side / 2, cell.center().y() - side / 2, side, side))
                    p.setPen(QColor(t.frame))
                else:
                    p.setPen(QColor(t.ink if day.month == self.month else t.line))
                p.drawText(cell, Qt.AlignCenter, str(day.day))


class ClockPage(DockPage):
    """La hora y el calendario juntos: sale de la hora de la barra al pasar el ratón. Arriba la hora en grande y la
    fecha; debajo el mes con hoy resaltado (‹ › cambian de mes)."""

    size = (340, 340)

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.time = Caption(theme, "", px=40, bold=True)
        self.date = Caption(theme, "", px=16, dim=True)
        self.view = MonthView(theme)
        self._tick = QTimer(self)
        self._tick.setInterval(1000)
        self._tick.timeout.connect(self._show_time)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(6, 4, 0, 0)
        layout.setSpacing(0)
        layout.addWidget(self.time)
        layout.addWidget(self.date)
        layout.addSpacing(8)
        layout.addWidget(self.view, 1)

    def _show_time(self):
        now = datetime.now()
        self.time.set_text(now.strftime("%H:%M"))
        self.date.set_text(long_date(now.date()).capitalize())

    def activate(self):
        self._show_time()
        self.view.reset()

    def showEvent(self, event):
        self._show_time()
        self._tick.start()
        super().showEvent(event)

    def hideEvent(self, event):
        self._tick.stop()
        super().hideEvent(event)


class BluetoothPage(DockPage):
    """Bluetooth: encender o apagar y los dispositivos emparejados (conectados primero)."""

    size = (380, 240)

    def __init__(self, theme, invoke):
        super().__init__()
        self.theme = theme
        self._invoke = invoke
        t = theme
        title = QLabel("Bluetooth")
        title.setFont(font(t, t.font_px + 3, bold=True))
        self.switch = Switch(t)
        self.switch.clicked.connect(self._toggle)
        head = QHBoxLayout()
        head.addWidget(title)
        head.addStretch(1)
        head.addWidget(self.switch)
        self.state = QLabel("")
        self.state.setFont(font(t, t.font_px))
        self.devices = QWidget()
        self.list = QVBoxLayout(self.devices)
        self.list.setContentsMargins(0, 6, 0, 0)
        self.list.setSpacing(4)
        settings = QPushButton("Configuración de Bluetooth…")
        settings.setCursor(Qt.PointingHandCursor)
        settings.clicked.connect(self._settings)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(2, 0, 2, 0)
        layout.addLayout(head)
        layout.addWidget(self.state)
        layout.addWidget(self.devices)
        layout.addStretch(1)
        layout.addWidget(settings, 0, Qt.AlignLeft)
        self.setStyleSheet(
            f"QLabel {{ color: {t.ink}; }} QLabel#Dim {{ color: {t.dim}; }} QLabel#On {{ color: {t.gold}; }}"
            f"QPushButton {{ color: {t.ink}; background: {_css(t.hover)}; border: 1px solid {_css(t.line)};"
            f" border-radius: 8px; padding: 6px 12px; font: {t.font_px}px '{t.font_family}'; }}"
            f"QPushButton:hover {{ border-color: {_css(t.gold_line)}; }}"
        )

    def activate(self):
        self.state.setText("Mirando el Bluetooth…")
        self._invoke("bluetooth.status")

    def on_result(self, data):
        self.switch.setChecked(bool(data.get("on")))
        self.switch.setEnabled(bool(data.get("available")))
        devices = data.get("devices", [])
        if data.get("error") or not data.get("available"):
            self.state.setText(data.get("error") or "Este equipo no tiene Bluetooth")
        elif not data["on"]:
            self.state.setText("Apagado")
        else:
            connected = sum(d["connected"] for d in devices)
            self.state.setText(f"Encendido · {connected} conectado{'' if connected == 1 else 's'}")
        for child in self.devices.findChildren(QWidget, options=Qt.FindDirectChildrenOnly):
            child.deleteLater()
        t = self.theme
        for device in devices:
            row = QWidget()
            line = QHBoxLayout(row)
            line.setContentsMargins(0, 0, 0, 0)
            name = QLabel(device["name"])
            name.setFont(font(t, t.font_px + 1, bold=device["connected"]))
            tag = QLabel("Conectado" if device["connected"] else "Emparejado")
            tag.setObjectName("On" if device["connected"] else "Dim")
            tag.setFont(font(t, t.font_px))
            line.addWidget(name, 1)
            line.addWidget(tag)
            self.list.addWidget(row)

    def _toggle(self, on):
        self.state.setText("Encendiendo…" if on else "Apagando…")
        self._invoke("bluetooth.set", on=on)

    def _settings(self):
        self.close_requested.emit()
        os.startfile("ms-settings:bluetooth")

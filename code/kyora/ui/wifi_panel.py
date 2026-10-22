"""Página del wifi del panel de la barra (kyora/ui/dock.py), junto al icono del wifi. Estado, redes disponibles, contraseña y conectar.

Buscar y conectar tardan unos segundos: se piden al núcleo con `invoke` (fuera del hilo de Qt) y la respuesta llega
por `on_result` (la señal wifi_result del puente).
"""
import os

from PySide6.QtCore import QRectF, Qt, Signal
from PySide6.QtGui import QColor, QPainter
from PySide6.QtWidgets import (
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QScrollArea,
    QVBoxLayout,
    QWidget,
)

from kyora.ui import glyphs
from kyora.ui.bar import font
from kyora.ui.dock import DockPage
from kyora.ui.search import _css

ROW_H = 44


class NetworkHeader(QWidget):
    """La fila de una red: barras de señal, candado, nombre y si está conectada o guardada."""

    clicked = Signal()

    def __init__(self, theme, network):
        super().__init__()
        self.theme, self.network = theme, network
        self.hover = False
        self.setFixedHeight(ROW_H)
        self.setCursor(Qt.PointingHandCursor)

    def enterEvent(self, _):
        self.hover = True
        self.update()

    def leaveEvent(self, _):
        self.hover = False
        self.update()

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.clicked.emit()

    def paintEvent(self, _):
        t, n = self.theme, self.network
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        if self.hover or n["connected"]:
            p.setPen(QColor(t.gold_line) if n["connected"] else Qt.NoPen)
            p.setBrush(QColor(t.gold_soft if n["connected"] else t.hover))
            p.drawRoundedRect(QRectF(self.rect()).adjusted(0.5, 0.5, -0.5, -0.5), 8, 8)
        lit = max(1, -(-n["signal"] // 25))
        for i in range(4):  # barras de señal
            h = 5 + i * 4
            p.setPen(Qt.NoPen)
            p.setBrush(QColor(t.ink if i < lit else t.line))
            p.drawRoundedRect(QRectF(12 + i * 5, ROW_H / 2 + 9 - h, 3, h), 1, 1)
        if n["secured"]:
            p.setPen(glyphs.pen(QColor(t.dim), 1.2))
            p.setBrush(Qt.NoBrush)
            glyphs.lock(p, QRectF(36, ROW_H / 2 - 8, 16, 16))
        p.setPen(QColor(t.ink))
        p.setFont(font(t, t.font_px + 2, bold=n["connected"]))
        name = p.fontMetrics().elidedText(n["ssid"], Qt.ElideRight, self.width() - 160)
        p.drawText(QRectF(60, 0, self.width() - 160, ROW_H), Qt.AlignVCenter | Qt.AlignLeft, name)
        tag = "Conectada" if n["connected"] else ("Guardada" if n["has_profile"] else "")
        if not n["supported"]:
            tag = "Empresa"
        p.setPen(QColor(t.gold if n["connected"] else t.dim))
        p.setFont(font(t, t.small_px + 1))
        p.drawText(QRectF(0, 0, self.width() - 12, ROW_H), Qt.AlignVCenter | Qt.AlignRight, tag)


class NetworkRow(QWidget):
    """Una red y, desplegado debajo, el campo de contraseña con su botón Conectar."""

    def __init__(self, theme, network, on_connect, on_open):
        super().__init__()
        self.network = network
        self._on_connect = on_connect
        self.header = NetworkHeader(theme, network)
        self.header.clicked.connect(lambda: on_open(self))
        self.password = QLineEdit()
        self.password.setEchoMode(QLineEdit.Password)
        self.password.setPlaceholderText("Contraseña")
        self.password.returnPressed.connect(self._connect)
        self.eye = QPushButton("Ver")
        self.eye.setCheckable(True)
        self.eye.setCursor(Qt.PointingHandCursor)
        self.eye.toggled.connect(self._show_password)
        self.go = QPushButton("Conectar")
        self.go.setCursor(Qt.PointingHandCursor)
        self.go.clicked.connect(self._connect)
        self.form = QWidget()
        form = QHBoxLayout(self.form)
        form.setContentsMargins(8, 2, 8, 8)
        form.addWidget(self.password, 1)
        form.addWidget(self.eye)
        form.addWidget(self.go)
        self.form.hide()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)
        layout.addWidget(self.header)
        layout.addWidget(self.form)

    def _show_password(self, on):
        self.password.setEchoMode(QLineEdit.Normal if on else QLineEdit.Password)
        self.eye.setText("Ocultar" if on else "Ver")

    def expand(self, on):
        self.form.setVisible(on)
        if on:
            self.password.setFocus()

    def _connect(self):
        self._on_connect(self.network["ssid"], self.password.text())


class WifiPage(DockPage):
    size = (420, 470)

    def __init__(self, theme, invoke):
        super().__init__()
        self.theme = theme
        self._invoke = invoke
        self.wifi = {}
        self.rows = []
        t = theme
        title = QLabel("Wi-Fi")
        title.setFont(font(t, t.font_px + 3, bold=True))
        self.state = QLabel("")
        self.state.setFont(font(t, t.font_px))
        self.refresh = QPushButton("Buscar")
        self.refresh.setCursor(Qt.PointingHandCursor)
        self.refresh.clicked.connect(self._scan)
        self.off = QPushButton("Desconectar")
        self.off.setCursor(Qt.PointingHandCursor)
        self.off.clicked.connect(lambda: self._busy("Desconectando…", "wifi.disconnect"))
        head = QHBoxLayout()
        head.addWidget(title)
        head.addStretch(1)
        head.addWidget(self.refresh)
        head.addWidget(self.off)
        self.note = QLabel("")
        self.note.setWordWrap(True)
        self.note.setFont(font(t, t.font_px))
        self.note.setStyleSheet(f"color: {t.dim};")
        self.location = QPushButton("Abrir los ajustes de ubicación")
        self.location.setCursor(Qt.PointingHandCursor)
        self.location.clicked.connect(lambda: os.startfile("ms-settings:privacy-location"))
        self.location.hide()
        self.list = QWidget()
        self.list_layout = QVBoxLayout(self.list)
        self.list_layout.setContentsMargins(0, 0, 0, 0)
        self.list_layout.setSpacing(2)
        self.list_layout.addStretch(1)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setWidget(self.list)
        scroll.setFrameShape(QScrollArea.NoFrame)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(2, 0, 2, 0)
        layout.addLayout(head)
        layout.addWidget(self.state)
        layout.addWidget(self.note)
        layout.addWidget(self.location)
        layout.addWidget(scroll, 1)
        self.setStyleSheet(
            f"QWidget {{ background: transparent; color: {t.ink}; }}"
            f"QLineEdit {{ background: {_css(t.field)}; border: 1px solid {_css(t.line)}; border-radius: 8px;"
            f" padding: 6px 10px; font: {t.font_px + 1}px '{t.font_family}'; selection-background-color: {_css(t.gold_soft)}; }}"
            f"QLineEdit:focus {{ border-color: {_css(t.gold_line)}; }}"
            f"QPushButton {{ background: {_css(t.hover)}; border: 1px solid {_css(t.line)}; border-radius: 8px;"
            f" padding: 6px 12px; font: {t.font_px}px '{t.font_family}'; }}"
            f"QPushButton:hover {{ border-color: {_css(t.gold_line)}; }}"
            f"QPushButton:checked {{ color: {t.gold}; }}"
            f"QScrollBar:vertical {{ width: 8px; background: transparent; }}"
            f"QScrollBar::handle:vertical {{ background: {_css(t.line)}; border-radius: 4px; min-height: 30px; }}"
            f"QScrollBar::add-line, QScrollBar::sub-line {{ height: 0; }}"
        )

    # ---------- estado ----------

    def on_state(self, state):
        self.wifi = state.get("wifi", {})
        self._show_state()

    def _show_state(self, message=None):
        w = self.wifi
        if message:
            text = message
        elif not w.get("available"):
            text = "Este equipo no tiene wifi o está apagado"
        elif w.get("connected"):
            text = f"Conectado a {w['ssid']} · señal {w['signal']} %"
        else:
            text = "Desconectado"
        self.state.setText(text)
        self.off.setVisible(bool(w.get("connected")))

    def activate(self):
        self._show_state()
        self._scan()

    def _scan(self):
        self._busy("Buscando redes…", "wifi.networks")

    def _busy(self, message, action, **payload):
        self.note.setText(message)
        self.refresh.setEnabled(False)
        self._invoke(action, **payload)

    # ---------- respuestas del núcleo ----------

    def on_result(self, result):
        self.refresh.setEnabled(True)
        if result["kind"] == "connect":
            self.note.setText(result["message"])
            return
        self.location.setVisible(bool(result.get("location")))
        self.note.setText(result.get("error", "") or ("" if result["networks"] else "No se ve ninguna red"))
        self._fill(result["networks"])

    def _fill(self, networks):
        for row in self.rows:
            row.deleteLater()
        self.rows = []
        for n in networks:
            row = NetworkRow(self.theme, n, self._connect, self._open_row)
            self.list_layout.insertWidget(self.list_layout.count() - 1, row)
            self.rows.append(row)

    def _open_row(self, row):
        n = row.network
        if n["connected"]:
            return
        if not n["supported"]:
            self.note.setText("Kyora solo sabe conectarse a redes personales (no a redes de empresa con usuario)")
            return
        if n["has_profile"] or not n["secured"]:
            self._connect(n["ssid"], "")
            return
        for other in self.rows:
            other.expand(other is row and not row.form.isVisible())

    def _connect(self, ssid, password):
        row = next((r for r in self.rows if r.network["ssid"] == ssid), None)
        if row and row.network["secured"] and not row.network["has_profile"] and not password:
            self.note.setText("Escribe la contraseña")
            return
        self._busy(f"Conectando a {ssid}…", "wifi.connect", ssid=ssid, password=password or None)

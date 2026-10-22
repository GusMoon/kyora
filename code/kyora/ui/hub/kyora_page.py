"""Sección Kyora del panel de arriba: lo que se usa mientras se desarrolla Kyora (el antiguo menú de la lechuza).

Cada opción es una tarjeta con su explicación; un clic la ejecuta.
"""
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QGridLayout, QLabel, QVBoxLayout, QWidget

from kyora.ui.hub.cards import Card
from kyora.ui.panels import OWL_OPTIONS

COLUMNS = 3


class OptionCard(Card):
    def __init__(self, theme, option, on_pick):
        title, text, *_ = option
        super().__init__(theme, title)
        self._option, self._on_pick = option, on_pick
        self.setCursor(Qt.PointingHandCursor)
        self.setAttribute(Qt.WA_Hover)
        label = QLabel(text)
        label.setObjectName("Dim")
        label.setWordWrap(True)
        layout = QVBoxLayout(self.inner)
        layout.setContentsMargins(18, 14, 18, 14)
        layout.addWidget(label)
        layout.addStretch(1)

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton and self.rect().contains(event.position().toPoint()):
            self._on_pick(self._option)

    def enterEvent(self, event):
        self.title.setStyleSheet(f"color: {self.theme.gold};")
        super().enterEvent(event)

    def leaveEvent(self, event):
        self.title.setStyleSheet("")
        super().leaveEvent(event)


class KyoraPage(QWidget):
    def __init__(self, theme, invoke, close):
        super().__init__()
        self._invoke, self._close = invoke, close
        grid = QGridLayout(self)
        grid.setContentsMargins(0, 0, 0, 0)
        grid.setSpacing(10)
        for i, option in enumerate(OWL_OPTIONS):
            card = OptionCard(theme, option, self._pick)
            card.setFixedHeight(140)
            grid.addWidget(card, i // COLUMNS, i % COLUMNS)
        grid.setRowStretch(len(OWL_OPTIONS) // COLUMNS + 1, 1)

    def _pick(self, option):
        _, _, action, payload = option
        self._close()
        self._invoke(action, **payload)

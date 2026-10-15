from typing import List, Tuple

from PySide6.QtCore import QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QPainter, QPen
from PySide6.QtWidgets import QHBoxLayout, QLabel, QPushButton, QVBoxLayout, QWidget

from core.matrix.motherboard.ecosystems.calendar.presentation.rootComponents import calendar_theme as theme

VISIBLE_MS = 20000
MAX_ENTRIES = 4


class ReminderBanner(QWidget):
    """
    Aviso flotante sci-fi que se muestra sobre cualquier ecosistema cuando llega
    la hora de un recordatorio. Acumula varios avisos y se cierra solo.
    """

    def __init__(self, parent=None):
        """
        Args:
            parent: Widget padre (la ventana principal).
        """
        super().__init__(parent)
        self.setFixedWidth(460)
        self._entries: List[Tuple[str, str]] = []
        self._hide_timer = QTimer(self)
        self._hide_timer.setSingleShot(True)
        self._hide_timer.setInterval(VISIBLE_MS)
        self._hide_timer.timeout.connect(self.hide)

        root = QVBoxLayout(self)
        root.setContentsMargins(22, 14, 14, 16)
        root.setSpacing(6)

        header = QHBoxLayout()
        caption = QLabel("RECORDATORIO")
        caption.setStyleSheet(
            f"color: {theme.ACCENT}; font-family: '{theme.FONT_FAMILY}'; font-size: 10px; "
            "font-weight: 700; letter-spacing: 2px; background: transparent;"
        )
        close = QPushButton("✕")
        close.setFixedSize(24, 24)
        close.setCursor(Qt.PointingHandCursor)
        close.setStyleSheet(
            f"QPushButton {{ background: transparent; color: {theme.MUTED}; border: none; font-size: 14px; }} "
            f"QPushButton:hover {{ color: {theme.TEXT}; }}"
        )
        close.clicked.connect(self.hide)
        header.addWidget(caption)
        header.addStretch()
        header.addWidget(close)
        root.addLayout(header)

        self.body = QLabel()
        self.body.setWordWrap(True)
        self.body.setTextFormat(Qt.RichText)
        self.body.setStyleSheet(
            f"color: {theme.TEXT}; font-family: '{theme.FONT_FAMILY}'; font-size: 14px; background: transparent;"
        )
        root.addWidget(self.body)
        self.hide()

    def push(self, title: str, body: str) -> None:
        """
        Agrega un aviso y muestra el banner.

        Args:
            title: Título del aviso.
            body: Detalle del aviso.
        """
        self._entries = (self._entries + [(title, body)])[-MAX_ENTRIES:]
        html = "<br>".join(
            f"<b>{self._escape(t)}</b><br><span style='color:{theme.MUTED}'>{self._escape(b)}</span>"
            for t, b in self._entries
        )
        self.body.setText(html)
        self.adjustSize()
        self.show()
        self.raise_()
        self._hide_timer.start()

    def hideEvent(self, event):
        self._entries = []
        self._hide_timer.stop()
        super().hideEvent(event)

    @staticmethod
    def _escape(text: str) -> str:
        """Escapa el texto del usuario antes de insertarlo en HTML."""
        return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setPen(QPen(QColor(theme.BORDER), 1))
        painter.setBrush(QColor(theme.PANEL))
        painter.drawPath(theme.rounded_path(QRectF(self.rect()).adjusted(1, 1, -1, -1), 6))

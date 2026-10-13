"""
Control interactivo de interruptor tipo píldora (Pill Toggle Switch).
Diseñado para la activación fluida de la fecha de entrega con estética cálida.
"""
from PySide6.QtWidgets import QWidget, QSizePolicy
from PySide6.QtCore import Qt, Signal, QRectF
from PySide6.QtGui import QPainter, QColor, QPen, QBrush, QFont, QPainterPath


class PillToggleSwitch(QWidget):
    """
    Control de interruptor tipo píldora moderno y estilizado,
    inspirado en el diseño minimalista de toggle cálido (terracota / durazno).
    """
    toggled = Signal(bool)

    def __init__(self, text: str = "Fecha límite de entrega", checked: bool = False, parent=None):
        super().__init__(parent)
        self._checked = checked
        self._text = text
        self.setFixedHeight(32)
        self.setCursor(Qt.PointingHandCursor)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

    def isChecked(self) -> bool:
        return self._checked

    def setChecked(self, checked: bool):
        if self._checked != checked:
            self._checked = checked
            self.toggled.emit(self._checked)
            self.update()

    def setText(self, text: str):
        self._text = text
        self.update()

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.setChecked(not self._checked)
            event.accept()
        else:
            super().mousePressEvent(event)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        w = float(self.width())
        h = float(self.height())

        # Configuración del track (píldora) a la derecha
        track_w = 44.0
        track_h = 24.0
        track_x = w - track_w - 4.0
        track_y = (h - track_h) / 2.0

        # 1. Dibujar el texto / etiqueta a la izquierda
        label_rect = QRectF(4.0, 0.0, track_x - 12.0, h)
        painter.setFont(QFont("Space Grotesk", 10, QFont.Bold if self._checked else QFont.Normal))
        text_color = QColor("#FFAA77") if self._checked else QColor("#888888")
        painter.setPen(text_color)
        painter.drawText(label_rect, Qt.AlignVCenter | Qt.AlignLeft, self._text)

        # 2. Dibujar el track tipo píldora
        track_path = QPainterPath()
        track_path.addRoundedRect(QRectF(track_x, track_y, track_w, track_h), track_h / 2.0, track_h / 2.0)

        if self._checked:
            track_brush = QBrush(QColor("#5C3424"))
            painter.fillPath(track_path, track_brush)
            painter.setPen(QPen(QColor("#7A4530"), 1.0))
            painter.drawPath(track_path)
        else:
            track_brush = QBrush(QColor("#222222"))
            painter.fillPath(track_path, track_brush)
            painter.setPen(QPen(QColor("#3A3A3A"), 1.0))
            painter.drawPath(track_path)

        # 3. Dibujar el thumb circular
        thumb_diameter = 18.0
        thumb_y = track_y + (track_h - thumb_diameter) / 2.0
        if self._checked:
            thumb_x = track_x + track_w - thumb_diameter - 3.0
            thumb_color = QColor("#FFAA77")
        else:
            thumb_x = track_x + 3.0
            thumb_color = QColor("#666666")

        thumb_rect = QRectF(thumb_x, thumb_y, thumb_diameter, thumb_diameter)
        painter.setBrush(QBrush(thumb_color))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(thumb_rect)

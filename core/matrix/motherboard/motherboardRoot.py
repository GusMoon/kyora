"""Ventana raíz de Kyora: la placa base sobre la que se montarán los ecosistemas.

Por ahora dibuja el fondo gris oscuro con iluminación suave, el reactor al centro
y fecha, hora, ubicación y clima en la esquina superior izquierda.
"""
from PySide6.QtCore import Qt, QPointF
from PySide6.QtGui import QColor, QKeyEvent, QPainter, QRadialGradient
from PySide6.QtWidgets import QMainWindow, QVBoxLayout, QWidget

from core.matrix.motherboard.globalArtifacts.reactor import Reactor
from core.matrix.motherboard.internalArtifacts.dateAndHour import DateAndHour
from core.matrix.motherboard.internalArtifacts.location import Location
from core.matrix.motherboard.internalArtifacts.weather import Weather

BASE_COLOR = QColor("#101010")
# Paradas (posición 0..1, color) del halo, del centro hacia el borde.
GLOW_STOPS = (
    (0.0, QColor("#3c3c3c")),
    (0.3, QColor("#2c2c2c")),
    (0.65, QColor("#181818")),
    (1.0, QColor("#0e0e0e")),
)
GLOW_RADIUS_FACTOR = 0.6
REACTOR_SIZE_FACTOR = 0.5  # del lado menor de la ventana
INFO_MARGIN = (16, 12)     # (x, y) del panel respecto a la esquina superior izquierda
INFO_ROW_SPACING = 10


class MotherboardRoot(QMainWindow):
    """Ventana principal sin marco que muestra el fondo de la placa base.

    Esc cierra la ventana, ya que no tiene barra de título.
    """

    def __init__(self):
        super().__init__()
        self.setWindowTitle("Kyora")
        self.setWindowFlag(Qt.FramelessWindowHint)
        self.reactor = Reactor(self)

        self.date_and_hour = DateAndHour()
        self.location = Location()
        self.weather = Weather()
        self.location.located.connect(self.weather.set_coordinates)

        self.info_panel = QWidget(self)
        # Hora grande arriba a la izquierda; fecha, ubicación y clima debajo en filas.
        column = QVBoxLayout(self.info_panel)
        column.setContentsMargins(0, 0, 0, 0)
        column.setSpacing(INFO_ROW_SPACING)
        column.addWidget(self.date_and_hour)
        column.addWidget(self.location)
        column.addWidget(self.weather)
        self.info_panel.adjustSize()
        self.info_panel.move(*INFO_MARGIN)

        self.showMaximized()

    def resizeEvent(self, event) -> None:
        """Mantiene el reactor centrado y proporcional a la ventana."""
        super().resizeEvent(event)
        side = int(min(self.width(), self.height()) * REACTOR_SIZE_FACTOR)
        self.reactor.setGeometry((self.width() - side) // 2, (self.height() - side) // 2, side, side)

    def keyPressEvent(self, event: QKeyEvent) -> None:
        """Cierra la ventana al pulsar Esc."""
        if event.key() == Qt.Key_Escape:
            self.close()
            return
        super().keyPressEvent(event)

    def paintEvent(self, event) -> None:
        """Pinta el gris oscuro base y un halo de luz suave hacia el centro."""
        painter = QPainter(self)
        painter.fillRect(self.rect(), BASE_COLOR)

        center = QPointF(self.width() * 0.5, self.height() * 0.5)
        radius = max(self.width(), self.height()) * GLOW_RADIUS_FACTOR
        glow = QRadialGradient(center, radius)
        for position, color in GLOW_STOPS:
            glow.setColorAt(position, color)
        painter.fillRect(self.rect(), glow)
        painter.end()

"""
Barra de progreso Sci-Fi con relleno en degradado.
"""
from PySide6.QtWidgets import QProgressBar, QSizePolicy
from PySide6.QtCore import Qt, QRectF
from PySide6.QtGui import QPainter, QColor, QLinearGradient, QPainterPath


class GradientProgressBar(QProgressBar):
    """
    QProgressBar que pinta el relleno con un degradado horizontal.

    El degradado se ancla al ancho completo de la pista y se recorta al valor actual:
    con poco progreso solo se ve el tramo inicial del degradado, y al llegar al 100%
    se muestra completo. Con un chunk de QSS el degradado se comprimiría en el relleno.
    """

    def __init__(
        self,
        parent=None,
        start_color: str = "#FFAA77",
        end_color: str = "#A04A2C",
        track_color: str = "#2A2A2A",
    ):
        super().__init__(parent)
        self._start_color = QColor(start_color)
        self._end_color = QColor(end_color)
        self._track_color = QColor(track_color)
        self.setTextVisible(False)

        # Mantiene su espacio cuando se oculta (p. ej. estado "fantasma" de un card arrastrado)
        policy = self.sizePolicy()
        policy.setRetainSizeWhenHidden(True)
        self.setSizePolicy(policy)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        rect = QRectF(self.rect())
        radius = rect.height() / 2.0

        track_path = QPainterPath()
        track_path.addRoundedRect(rect, radius, radius)
        painter.fillPath(track_path, self._track_color)

        span = self.maximum() - self.minimum()
        if span <= 0:
            return
        fraction = (self.value() - self.minimum()) / span
        fraction = max(0.0, min(1.0, fraction))
        if fraction <= 0.0:
            return

        gradient = QLinearGradient(rect.left(), 0, rect.right(), 0)
        gradient.setColorAt(0.0, self._start_color)
        gradient.setColorAt(1.0, self._end_color)

        painter.setClipPath(track_path)
        fill_rect = QRectF(rect.left(), rect.top(), rect.width() * fraction, rect.height())
        painter.fillRect(fill_rect, gradient)

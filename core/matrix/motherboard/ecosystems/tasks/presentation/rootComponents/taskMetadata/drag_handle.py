"""
Asa de arrastre (grip) compartida y tipos MIME de las operaciones de arrastre del detalle de tarea.
"""
from PySide6.QtWidgets import QWidget, QApplication
from PySide6.QtCore import Qt, Signal, QPointF
from PySide6.QtGui import QPainter, QColor

# Una subtarea arrastrada desde la lista (carga: id de la subtarea en UTF-8)
SUBTASK_MIME = "application/x-kiora-subtask"
# Un panel del espacio de trabajo (carga: "description" o "subtask")
PANE_MIME = "application/x-kiora-pane"


class DragHandle(QWidget):
    """
    Asa de seis puntos que emite `drag_requested` cuando el usuario la presiona y
    mueve el cursor más allá del umbral de arrastre del sistema.

    El widget que la hospeda es quien crea el QDrag con la carga que corresponda.
    """
    drag_requested = Signal()

    def __init__(self, parent=None, tooltip: str = "Arrastra para mover"):
        super().__init__(parent)
        self.setFixedSize(14, 22)
        self.setCursor(Qt.OpenHandCursor)
        self.setToolTip(tooltip)
        self._press_pos = None
        self._is_hovered = False

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor("#FFAA77") if self._is_hovered else QColor("#5E5E5E"))

        radius = 1.3
        for column in range(2):
            for row in range(3):
                center = QPointF(4.0 + column * 6.0, 5.0 + row * 6.0)
                painter.drawEllipse(center, radius, radius)

    def enterEvent(self, event):
        self._is_hovered = True
        self.update()
        super().enterEvent(event)

    def leaveEvent(self, event):
        self._is_hovered = False
        self.update()
        super().leaveEvent(event)

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self._press_pos = event.position().toPoint()
            self.setCursor(Qt.ClosedHandCursor)
            event.accept()
            return
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        if self._press_pos is not None and (event.buttons() & Qt.LeftButton):
            distance = (event.position().toPoint() - self._press_pos).manhattanLength()
            if distance >= QApplication.startDragDistance():
                self._press_pos = None
                self.drag_requested.emit()
                self.setCursor(Qt.OpenHandCursor)
                event.accept()
                return
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        self._press_pos = None
        self.setCursor(Qt.OpenHandCursor)
        super().mouseReleaseEvent(event)

"""Estilo compartido de los artefactos internos (texto informativo del motherboard)."""
from PySide6.QtCore import QPointF, Qt
from PySide6.QtGui import QColor, QFont, QPainter
from PySide6.QtWidgets import QHBoxLayout, QLabel, QWidget

TEXT_PRIMARY = "#ebeef2"    # mismo tono que BRIGHT del reactor
TEXT_SECONDARY = "#969ba2"  # mismo tono que MID del reactor
FONT_FAMILY = "Prototype"

ICON_BOX = 32      # lado del área que contiene el icono
ICON_SIZE = 28     # lado del icono dentro del área
ROW_SPACING = 12   # separación entre el icono y el texto


def make_label(point_size: int, color: str, bold: bool = False, parent=None) -> QLabel:
    """Crea un QLabel de texto sin fondo que no captura el ratón.

    Args:
        point_size: tamaño de la fuente en puntos.
        color: color del texto en formato CSS.
        bold: si el texto va en negrita.
        parent: widget padre opcional.

    Returns:
        El QLabel configurado.
    """
    label = QLabel(parent)
    font = QFont(FONT_FAMILY, point_size)
    font.setBold(bold)
    label.setFont(font)
    label.setStyleSheet(f"color: {color}; background: transparent;")
    label.setAttribute(Qt.WA_TransparentForMouseEvents)
    return label


class IconBox(QWidget):
    """Área fija con un icono vectorial centrado, sin contorno."""

    def __init__(self, draw_icon, parent=None):
        """Crea el área.

        Args:
            draw_icon: función ``draw(painter, center, scale, color, base_size)`` de
                ``core.resources.icons``.
            parent: widget padre opcional.
        """
        super().__init__(parent)
        self._draw_icon = draw_icon
        self.setFixedSize(ICON_BOX, ICON_BOX)
        self.setAttribute(Qt.WA_TransparentForMouseEvents)

    def paintEvent(self, event) -> None:
        """Dibuja el icono centrado."""
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        center = QPointF(self.width() / 2, self.height() / 2)
        self._draw_icon(painter, center, ICON_SIZE / 24.0, QColor(TEXT_PRIMARY), 24.0)
        painter.end()


class InfoRow(QWidget):
    """Fila de información: icono a la izquierda y el atributo a su lado."""

    def __init__(self, draw_icon, text: str = "", parent=None):
        """Crea la fila.

        Args:
            draw_icon: función de dibujo del icono (ver ``IconBox``).
            text: texto inicial del atributo.
            parent: widget padre opcional.
        """
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(ROW_SPACING)
        layout.addWidget(IconBox(draw_icon, self))
        self._label = make_label(11, TEXT_PRIMARY)
        self._label.setText(text)
        layout.addWidget(self._label, 1, Qt.AlignVCenter)

    def set_text(self, text: str) -> None:
        """Cambia el texto del atributo."""
        self._label.setText(text)

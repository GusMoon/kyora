from typing import Tuple

from PySide6.QtCore import QRectF, Qt
from PySide6.QtGui import QColor, QPainter, QPen, QPixmap
from PySide6.QtWidgets import QHBoxLayout, QVBoxLayout, QWidget

from core.matrix.motherboard.ecosystems.logbook.presentation.rootComponents import book_theme
from core.matrix.motherboard.ecosystems.logbook.presentation.rootComponents.page_flip import PageFlipOverlay

COVER_INSET = 6        # separación entre la cubierta y el borde del widget
COVER_THICKNESS = 12   # grosor visible de la cubierta alrededor del papel
PAGE_PAD_X = 52        # espacio entre el borde del papel y su contenido
PAGE_PAD_Y = 40
SPINE_GAP = 4          # separación visible entre las dos hojas (lomo)


class BookWidget(QWidget):
    """
    Libro abierto de dos páginas con lomo delgado, en estilo sci-fi.

    Expone `left_layout` y `right_layout` para colocar el contenido de cada
    página; la cubierta y el papel se dibujan alrededor de ellos. Permite
    capturar ambas páginas para animar el cambio de hoja.
    """

    def __init__(self, parent=None):
        """
        Args:
            parent: Widget padre.
        """
        super().__init__(parent)
        self.setMinimumSize(640, 420)

        self.left_page = QWidget()
        self.right_page = QWidget()
        self.left_layout = QVBoxLayout(self.left_page)
        self.right_layout = QVBoxLayout(self.right_page)
        for layout in (self.left_layout, self.right_layout):
            layout.setContentsMargins(0, 0, 0, 0)
            layout.setSpacing(14)

        inset_x = COVER_INSET + COVER_THICKNESS + PAGE_PAD_X
        inset_y = COVER_INSET + COVER_THICKNESS + PAGE_PAD_Y
        root = QHBoxLayout(self)
        root.setContentsMargins(inset_x, inset_y, inset_x, inset_y)
        root.setSpacing(SPINE_GAP + 2 * PAGE_PAD_X)
        root.addWidget(self.left_page, 1)
        root.addWidget(self.right_page, 1)

        self.flip_overlay = PageFlipOverlay(self)

    def left_paper_rect(self) -> QRectF:
        """Rectángulo del papel de la página izquierda, en coordenadas del libro."""
        return QRectF(self.left_page.geometry()).adjusted(-PAGE_PAD_X, -PAGE_PAD_Y, PAGE_PAD_X, PAGE_PAD_Y)

    def right_paper_rect(self) -> QRectF:
        """Rectángulo del papel de la página derecha, en coordenadas del libro."""
        return QRectF(self.right_page.geometry()).adjusted(-PAGE_PAD_X, -PAGE_PAD_Y, PAGE_PAD_X, PAGE_PAD_Y)

    def grab_pages(self) -> Tuple[QPixmap, QPixmap]:
        """
        Captura las dos páginas tal como se ven en este momento.

        Returns:
            tuple: `(izquierda, derecha)`.
        """
        self.flip_overlay.stop()
        self.layout().activate()
        for page_layout in (self.left_layout, self.right_layout):
            page_layout.activate()
        left = self.grab(self.left_paper_rect().toAlignedRect())
        right = self.grab(self.right_paper_rect().toAlignedRect())
        return left, right

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.flip_overlay.setGeometry(self.rect())

    def paintEvent(self, event):
        """Dibuja la cubierta, las dos hojas y la línea del lomo."""
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        cover = QRectF(self.rect()).adjusted(COVER_INSET, COVER_INSET, -COVER_INSET, -COVER_INSET)
        painter.setPen(QPen(QColor(book_theme.COVER_EDGE), 1))
        painter.setBrush(QColor(book_theme.COVER))
        painter.drawPath(book_theme.rounded_path(cover))

        left_paper, right_paper = self.left_paper_rect(), self.right_paper_rect()
        painter.setPen(QPen(QColor(book_theme.PAPER_EDGE), 1))
        painter.setBrush(QColor(book_theme.PAPER))
        painter.drawPath(book_theme.rounded_path(left_paper))
        painter.drawPath(book_theme.rounded_path(right_paper))

        x = (left_paper.right() + right_paper.left()) / 2
        painter.setPen(QPen(QColor(book_theme.SPINE), 1))
        painter.drawLine(int(x), int(left_paper.top()), int(x), int(left_paper.bottom()))

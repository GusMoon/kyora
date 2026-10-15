import math

from PySide6.QtCore import QEasingCurve, QPointF, QRectF, Qt, QVariantAnimation
from PySide6.QtGui import QColor, QLinearGradient, QPainter, QPen, QPixmap, QPolygonF
from PySide6.QtWidgets import QWidget

FLIP_DURATION_MS = 700
# Cuánto crece, en proporción, el borde libre de la hoja al levantarse: da perspectiva.
PERSPECTIVE = 0.03
STRIP_WIDTH_PX = 3


class PageFlipOverlay(QWidget):
    """
    Capa transparente que simula el giro clásico de una hoja sobre el lomo.

    La hoja se levanta, pasa por la vertical con perspectiva y sombra, y cae
    sobre la página contraria mostrando su reverso. Recibe capturas de las dos
    páginas antes y después del cambio.
    """

    def __init__(self, parent: QWidget):
        """
        Args:
            parent: Libro sobre el que se dibuja la animación.
        """
        super().__init__(parent)
        self.setAttribute(Qt.WA_TransparentForMouseEvents)
        self.hide()
        self._progress = 0.0
        self._forward = True
        self._left_rect = QRectF()
        self._right_rect = QRectF()
        self._old_left = QPixmap()
        self._old_right = QPixmap()
        self._new_left = QPixmap()
        self._new_right = QPixmap()

        self._anim = QVariantAnimation(self)
        self._anim.setStartValue(0.0)
        self._anim.setEndValue(1.0)
        self._anim.setDuration(FLIP_DURATION_MS)
        self._anim.setEasingCurve(QEasingCurve.InOutQuad)
        self._anim.valueChanged.connect(self._on_progress)
        self._anim.finished.connect(self.stop)

    def is_running(self) -> bool:
        """Indica si hay un giro de hoja en curso."""
        return self._anim.state() == QVariantAnimation.Running

    def start(self, forward, left_rect, right_rect, old_pages, new_pages) -> None:
        """
        Inicia la animación.

        Args:
            forward: True si se avanza (la hoja derecha pasa a la izquierda).
            left_rect: Rectángulo de la página izquierda en coordenadas del libro.
            right_rect: Rectángulo de la página derecha en coordenadas del libro.
            old_pages: Tupla `(izquierda, derecha)` de capturas antes del cambio.
            new_pages: Tupla `(izquierda, derecha)` de capturas después del cambio.
        """
        self._forward = forward
        self._left_rect = QRectF(left_rect)
        self._right_rect = QRectF(right_rect)
        self._old_left, self._old_right = old_pages
        self._new_left, self._new_right = new_pages
        self._progress = 0.0
        self.setGeometry(self.parentWidget().rect())
        self.show()
        self.raise_()
        self._anim.start()

    def stop(self) -> None:
        """Termina la animación de inmediato y libera las capturas."""
        self._anim.stop()
        self.hide()
        self._old_left = self._old_right = QPixmap()
        self._new_left = self._new_right = QPixmap()

    def _on_progress(self, value) -> None:
        """Guarda el avance y redibuja."""
        self._progress = float(value)
        self.update()

    def paintEvent(self, event):
        """Dibuja la página quieta, la hoja en giro, su sombra y su borde."""
        if self._old_left.isNull():
            return
        painter = QPainter(self)
        painter.setRenderHint(QPainter.SmoothPixmapTransform)
        lr, rr = self._left_rect, self._right_rect
        forward = self._forward

        static_pix, static_rect = (self._old_left, lr) if forward else (self._old_right, rr)
        painter.drawPixmap(static_rect, static_pix, QRectF(static_pix.rect()))

        theta = self._progress * math.pi
        cos_t, sin_t = math.cos(theta), math.sin(theta)
        front = theta < math.pi / 2
        sign = 1 if forward else -1
        width = lr.width()

        # La bisagra viaja del lomo de la página origen al de la página destino.
        hinge_from = rr.left() if forward else lr.right()
        hinge_to = lr.right() if forward else rr.left()
        hinge = hinge_from + (hinge_to - hinge_from) * (theta / math.pi)

        if front:
            pix = self._old_right if forward else self._old_left
        else:
            pix = self._new_left if forward else self._new_right
        if pix.isNull():
            return

        center_y = lr.center().y()
        page_h = lr.height()
        strips = max(40, int(width / STRIP_WIDTH_PX))
        pw, ph = pix.width(), pix.height()
        # `u` es 0 en la bisagra y 1 en el borde libre; el reverso se lee al revés.
        mirrored = (forward and not front) or (not forward and front)

        for i in range(strips):
            u0, u1 = i / strips, (i + 1) / strips
            um = (u0 + u1) / 2
            x0 = hinge + sign * u0 * width * cos_t
            x1 = hinge + sign * u1 * width * cos_t
            height = page_h * (1 + PERSPECTIVE * sin_t * um)
            dst = QRectF(min(x0, x1), center_y - height / 2, abs(x1 - x0) + 0.8, height)
            src_u = 1 - um if mirrored else um
            src = QRectF(max(0.0, (src_u - 0.5 / strips) * pw), 0, pw / strips, ph)
            painter.drawPixmap(dst, pix, src)

        free_x = hinge + sign * width * cos_t
        free_h = page_h * (1 + PERSPECTIVE * sin_t)
        top, bottom = center_y - page_h / 2, center_y + page_h / 2

        # Sombra propia de la hoja: más oscura hacia el borde libre.
        shade = QLinearGradient(hinge, 0, free_x, 0)
        shade.setColorAt(0.0, QColor(0, 0, 0, 0))
        shade.setColorAt(1.0, QColor(0, 0, 0, int(130 * sin_t)))
        painter.setPen(Qt.NoPen)
        painter.setBrush(shade)
        painter.drawPolygon(QPolygonF([
            QPointF(hinge, top), QPointF(free_x, center_y - free_h / 2),
            QPointF(free_x, center_y + free_h / 2), QPointF(hinge, bottom),
        ]))

        # Sombra proyectada sobre la página que va quedando al descubierto.
        beyond = (1 if cos_t >= 0 else -1) * sign
        cast_w = 90 * sin_t
        if cast_w > 1:
            cast = QLinearGradient(free_x, 0, free_x + beyond * cast_w, 0)
            cast.setColorAt(0.0, QColor(0, 0, 0, int(110 * sin_t)))
            cast.setColorAt(1.0, QColor(0, 0, 0, 0))
            painter.setBrush(cast)
            painter.drawRect(QRectF(min(free_x, free_x + beyond * cast_w), top, cast_w, page_h))

        painter.setPen(QPen(QColor(150, 150, 150, int(200 * max(sin_t, 0.15))), 1))
        painter.drawLine(QPointF(free_x, center_y - free_h / 2), QPointF(free_x, center_y + free_h / 2))

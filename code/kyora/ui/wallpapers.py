"""Carrusel de fondos de pantalla del buscador (`wallpapers`), como la imagen de referencia: la elegida grande en el
centro y las vecinas más pequeñas, giradas en perspectiva y oscurecidas a los lados.

←/→ cambian de imagen con un deslizamiento suave. Un poco después de la última flecha avisa con `picked(ruta)`
(no en cada pulsación: poner el fondo y recolorear Kyora cuesta). Las miniaturas se leen en un hilo con
QImageReader a tamaño reducido, así que un fondo de 8K no se carga entero.
"""
import os
import threading

from PySide6.QtCore import QEasingCurve, QRectF, QSize, Qt, QTimer, Signal
from PySide6.QtGui import (
    QColor,
    QImage,
    QImageReader,
    QPainter,
    QPainterPath,
    QPen,
    QTransform,
)
from PySide6.QtWidgets import QWidget

from kyora.ui.anim import Tween
from kyora.ui.bar import font
from kyora.ui.hub.cards import paint_glass

HEIGHT = 270  # alto del carrusel dentro del buscador
THUMB = QSize(640, 360)
SLIDE_MS = 220
SETTLE_MS = 250  # espera tras la última flecha antes de poner el fondo
TILT = 32  # grados que giran las vecinas
SPREAD = 0.62  # separación entre tarjetas, como fracción del ancho de la del centro
RADIUS = 14


def read_thumb(path, size=THUMB):
    """Miniatura que cubre `size` (recortada después al pintar). QImage nula si no se puede leer."""
    reader = QImageReader(path)
    reader.setAutoTransform(True)
    full = reader.size()
    if full.isValid():
        reader.setScaledSize(full.scaled(size, Qt.KeepAspectRatioByExpanding))
    return reader.read()


class WallpaperCarousel(QWidget):
    picked = Signal(str)  # la imagen elegida, cuando se queda quieta un momento
    _thumb_ready = Signal(int, int, QImage)  # (generación, índice, miniatura): llega del hilo de lectura

    def __init__(self, theme):
        super().__init__()
        self.theme = theme
        self.images = []
        self.index = 0
        self._pos = 0.0
        self._thumbs = {}
        self._generation = 0
        self._slide = Tween(self, self._set_pos)
        self._settle = QTimer(self)
        self._settle.setSingleShot(True)
        self._settle.setInterval(SETTLE_MS)
        self._settle.timeout.connect(lambda: self.picked.emit(self.current()) if self.images else None)
        self._thumb_ready.connect(self._got_thumb)

    # ---------- imágenes ----------

    def set_images(self, images, current=""):
        """Las imágenes de la carpeta; empieza en la del fondo actual si está entre ellas."""
        if images == self.images:
            return
        self.images = list(images)
        key = os.path.normcase(os.path.abspath(current)) if current else ""
        self.index = next((i for i, path in enumerate(self.images)
                           if os.path.normcase(os.path.abspath(path)) == key), 0)
        self._pos = float(self.index)
        self._thumbs = {}
        self._generation += 1
        generation, order = self._generation, sorted(range(len(self.images)), key=lambda i: abs(i - self.index))
        paths = list(self.images)
        threading.Thread(target=self._load, args=(generation, order, paths), daemon=True,
                         name="kyora-wallpapers").start()
        self.update()

    def _load(self, generation, order, paths):
        for i in order:  # primero la del centro y sus vecinas
            if generation != self._generation:
                return
            self._thumb_ready.emit(generation, i, read_thumb(paths[i]))

    def _got_thumb(self, generation, index, image):
        if generation == self._generation and not image.isNull():
            self._thumbs[index] = image
            self.update()

    def current(self):
        return self.images[self.index] if self.images else ""

    # ---------- moverse ----------

    def step(self, delta):
        if not self.images:
            return
        target = max(0, min(self.index + delta, len(self.images) - 1))
        if target == self.index:
            return
        self.index = target
        self._slide.start(self._pos, float(target), SLIDE_MS, QEasingCurve.OutCubic)
        self._settle.start()

    def stop(self):
        """Al salir del carrusel: no se pone ningún fondo pendiente."""
        self._settle.stop()

    def _set_pos(self, value):
        self._pos = float(value)
        self.update()

    def mouseReleaseEvent(self, event):
        x = event.position().x()
        if x < self.width() * 0.3:
            self.step(-1)
        elif x > self.width() * 0.7:
            self.step(1)

    def wheelEvent(self, event):
        self.step(-1 if event.angleDelta().y() > 0 else 1)

    # ---------- pintura ----------

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setRenderHint(QPainter.SmoothPixmapTransform)
        if not self.images:
            p.setPen(QColor(t.dim))
            p.setFont(font(t, 15))
            p.drawText(QRectF(self.rect()), Qt.AlignCenter | Qt.TextWordWrap,
                       "No hay imágenes en Imágenes\\wallpapers")
            return
        top, bottom = 30, 26  # sitio para el nombre arriba y el contador abajo
        card_h = self.height() - top - bottom
        card_w = min(card_h * 16 / 9, self.width() * 0.66)
        card_h = card_w * 9 / 16
        cy = top + (self.height() - top - bottom) / 2
        order = sorted(range(len(self.images)), key=lambda i: -abs(i - self._pos))  # las de lejos primero
        for i in order:
            d = i - self._pos
            if abs(d) > 2.6:
                continue
            ad = min(abs(d), 2.0)
            scale = 1 - 0.2 * ad
            x = self.width() / 2 + d * card_w * SPREAD * (1 - 0.12 * ad)
            transform = QTransform()
            transform.translate(x, cy)
            transform.rotate(max(min(-d * TILT, TILT), -TILT), Qt.YAxis)  # perspectiva: giran hacia el centro
            transform.scale(scale, scale)
            p.setTransform(transform)
            rect = QRectF(-card_w / 2, -card_h / 2, card_w, card_h)
            shape = QPainterPath()
            shape.addRoundedRect(rect, RADIUS, RADIUS)
            image = self._thumbs.get(i)
            if image is not None:
                p.save()
                p.setClipPath(shape)
                source = QRectF(image.rect())
                aspect = card_w / card_h
                if source.width() / source.height() > aspect:  # recortar para llenar sin deformar
                    w = source.height() * aspect
                    source = QRectF(source.x() + (source.width() - w) / 2, source.y(), w, source.height())
                else:
                    h = source.width() / aspect
                    source = QRectF(source.x(), source.y() + (source.height() - h) / 2, source.width(), h)
                p.drawImage(rect, image, source)
                p.restore()
            else:
                paint_glass(p, t, rect.toRect(), RADIUS)
            if ad > 0.01:  # las vecinas, oscurecidas
                p.fillPath(shape, QColor(0, 0, 0, int(min(ad, 1.5) * 110)))
            p.setPen(QPen(QColor(255, 255, 255, 40 if ad > 0.5 else 90), 1))
            p.setBrush(Qt.NoBrush)
            p.drawPath(shape)
        p.resetTransform()
        name = os.path.splitext(os.path.basename(self.current()))[0]
        p.setFont(font(t, 15, bold=True))
        p.setPen(QColor(t.ink))
        name = p.fontMetrics().elidedText(name, Qt.ElideMiddle, int(self.width() * 0.8))
        p.drawText(QRectF(0, 0, self.width(), top - 4), Qt.AlignCenter, name)
        p.setFont(font(t, 15))
        p.setPen(QColor(t.dim))
        p.drawText(QRectF(0, self.height() - bottom + 4, self.width(), bottom - 4), Qt.AlignCenter,
                   f"{self.index + 1} / {len(self.images)}   ·   ←/→ cambiar   ·   Enter dejar   ·   Esc volver")

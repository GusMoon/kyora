"""Win+W: solo los fondos de pantalla. Ninguna otra ventana ni panel: el fondo a pantalla completa y, abajo, la tira
de fondos como en la referencia (el elegido grande en el centro y los vecinos inclinados, cada vez más pequeños).

←/→ pasan de fondo: el nuevo aparece sobre el anterior con un barrido circular desde la tira, con un aro de luz del
color de Kyora, y los colores de Kyora cambian con él (se calculan en un hilo, un instante después de la última flecha).
Enter se queda con el fondo (lo pone en Windows) y Esc vuelve al que había, con sus colores.

Al ser una ventana opaca a pantalla completa, tapa todo lo demás sin tener que esconder ninguna ventana.
"""
import math
import threading
from collections import OrderedDict

from PySide6.QtCore import QEasingCurve, QEvent, QPointF, QRectF, Qt, QTimer, Signal
from PySide6.QtGui import (
    QColor,
    QImage,
    QPainter,
    QPainterPath,
    QPen,
    QPixmap,
    QTransform,
)
from PySide6.QtWidgets import QWidget

from kyora.system.win32 import force_foreground
from kyora.ui.anim import Tween
from kyora.ui.wallpaper_bg import load_image
from kyora.ui.wallpapers import WallpaperCarousel
from kyora.ui.win import hwnd_of, make_tool_window

STRIP_H = 250  # alto de la tira de fondos
STRIP_BOTTOM = 70  # lo que separa la tira del borde de abajo
SKEW = -0.28  # inclinación de las tarjetas (el borde de arriba se va a la derecha)
SHRINK = 0.2  # cuánto más pequeña es cada tarjeta que la anterior
SPREAD = 0.72  # separación entre centros, como fracción del ancho de la tarjeta central
REVEAL_MS = 420
FADE_MS = 160
KEEP = 5  # fondos a pantalla completa que se guardan listos (cada uno ocupa varios MB)
BLUR_CHECK_MS = 200


class FilmStrip(WallpaperCarousel):
    """La tira de fondos: la misma que el carrusel del buscador (miniaturas en un hilo, deslizamiento, ←/→), pero
    dibujada con tarjetas inclinadas, sin texto y sin recortes redondeados."""

    moved = Signal()  # cambió de fondo (con las flechas, la rueda o un clic)

    def step(self, delta):
        before = self.index
        super().step(delta)
        if self.index != before:
            self.moved.emit()

    def paintEvent(self, _):
        if not self.images:
            return
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setRenderHint(QPainter.SmoothPixmapTransform)
        card_h = self.height() - 20
        card_w = card_h * 16 / 9
        cy = self.height() / 2
        accent = QColor(self.theme.gold)
        for i in sorted(range(len(self.images)), key=lambda i: -abs(i - self._pos)):  # las de lejos primero
            d = i - self._pos
            if abs(d) > 4.5:
                continue
            ad = abs(d)
            scale = max(0.42, 1 - SHRINK * ad)
            x = self.width() / 2 + (1 if d > 0 else -1) * card_w * SPREAD * (min(ad, 1.0) + max(ad - 1.0, 0.0) * 0.55)
            transform = QTransform()
            transform.translate(x, cy)
            transform.shear(SKEW, 0)
            transform.scale(scale, scale)
            p.setTransform(transform)
            rect = QRectF(-card_w / 2, -card_h / 2, card_w, card_h)
            image = self._thumbs.get(i)
            if image is not None:
                source = QRectF(image.rect())
                aspect = card_w / card_h
                if source.width() / source.height() > aspect:  # recortar para llenar sin deformar
                    w = source.height() * aspect
                    source = QRectF(source.x() + (source.width() - w) / 2, source.y(), w, source.height())
                else:
                    h = source.width() / aspect
                    source = QRectF(source.x(), source.y() + (source.height() - h) / 2, source.width(), h)
                p.drawImage(rect, image, source)
            else:
                p.fillRect(rect, QColor(self.theme.plate_top))
            if ad > 0.01:  # las vecinas, oscurecidas
                p.fillRect(rect, QColor(0, 0, 0, int(min(ad, 2.0) * 85)))
            focused = max(0.0, 1.0 - ad)
            p.setPen(QPen(QColor(accent.red(), accent.green(), accent.blue(), int(200 * focused)) if focused > 0.05
                          else QColor(255, 255, 255, 50), 2 if focused > 0.05 else 1))
            p.setBrush(Qt.NoBrush)
            p.drawRect(rect)


class WallpaperMode(QWidget):
    visibility = Signal(bool)  # se abrió o se cerró: los paneles de los bordes no saltan mientras está
    _image_ready = Signal(str, QImage)  # (ruta, imagen a pantalla completa): llega del hilo de lectura

    def __init__(self, theme, screen_map, invoke, preview):
        """`invoke(acción, **datos)` pide cosas al núcleo; `preview(ruta)` recolorea Kyora con ese fondo (sin ponerlo)."""
        super().__init__()
        make_tool_window(self)
        self.setAttribute(Qt.WA_TranslucentBackground, False)
        self.setAttribute(Qt.WA_OpaquePaintEvent, True)
        self.setWindowTitle("KyoraWallpapers")
        self.setFocusPolicy(Qt.StrongFocus)
        self.theme, self.map, self._invoke, self._preview = theme, screen_map, invoke, preview
        self.opened = False
        self._original = ""
        self._want = ""  # el fondo que se quiere ver
        self._now = None  # pixmap del fondo que se ve (o el que llega)
        self._before = None  # el fondo de antes, mientras el nuevo se revela encima
        self._progress = 1.0
        self._opacity = 0.0
        self._cache = OrderedDict()  # ruta -> QPixmap a pantalla completa
        self._loading = set()
        self._reveal = Tween(self, self._set_progress, frame_ms=16)
        self._fade = Tween(self, self._set_opacity, self._faded)
        self.strip = FilmStrip(theme)
        self.strip.setParent(self)
        self.strip.picked.connect(self._preview)  # un instante después de la última flecha: los colores de Kyora
        self.strip.moved.connect(self._moved)
        self._image_ready.connect(self._got_image)

    # ---------- abrir y cerrar ----------

    def open(self, data):
        images = data["images"]
        if self.opened or not images:
            return
        g = self.map.geometry
        self._original = data["current"]
        self.strip.set_images(images, self._original)
        self._want = self.strip.current()
        self._now, self._before, self._progress = self._pixmap_now(self._original or self._want), None, 1.0
        self.opened = True
        self.visibility.emit(True)
        self.setGeometry(g)
        self.strip.setGeometry(0, g.height() - STRIP_H - STRIP_BOTTOM, g.width(), STRIP_H)
        self.setWindowOpacity(0.0)
        self._opacity = 0.0
        self.show()
        self.raise_()
        self.activateWindow()
        force_foreground(hwnd_of(self))
        self.setFocus()
        self._fade.start(0.0, 1.0, FADE_MS, QEasingCurve.OutCubic)
        self._want_path(self._want)
        self._prefetch()

    def _finish(self, keep):
        if not self.opened:
            return
        self.opened = False
        self.strip.stop()
        path = self.strip.current()
        if keep:
            self._invoke("wallpaper.set", path=path)  # lo pone en Windows (y recolorea Kyora una vez más)
        else:
            self._preview(self._original)  # los colores de antes
        self._fade.start(self._opacity, 0.0, FADE_MS, QEasingCurve.InCubic)
        self.visibility.emit(False)

    def _faded(self):
        if not self.opened:
            self.hide()
            self._cache.clear()
            self._now = self._before = None

    def _set_opacity(self, value):
        self._opacity = float(value)
        self.setWindowOpacity(self._opacity)

    # ---------- fondos a pantalla completa ----------

    def _pixmap_now(self, path):
        pm = self._cache.get(path)
        if pm is None:
            image = load_image(path, self.map.geometry.size(), self.map.dpr)  # el de ahora: se necesita ya
            pm = self._store(path, image) if image is not None else None
        return pm

    def _store(self, path, image):
        pm = QPixmap.fromImage(image)
        pm.setDevicePixelRatio(self.map.dpr)
        self._cache[path] = pm
        self._cache.move_to_end(path)
        while len(self._cache) > KEEP:
            self._cache.popitem(last=False)
        return pm

    def _want_path(self, path):
        """Pide el fondo `path` (en un hilo si no está ya) para enseñarlo cuando llegue."""
        if path in self._cache or path in self._loading or not path:
            return
        self._loading.add(path)
        size, dpr = self.map.geometry.size(), self.map.dpr
        threading.Thread(target=lambda: self._image_ready.emit(path, load_image(path, size, dpr) or QImage()),
                         daemon=True, name="kyora-wallpaper-full").start()

    def _got_image(self, path, image):
        self._loading.discard(path)
        if image.isNull() or not self.opened:
            return
        self._store(path, image)
        if path == self._want and self._now is not self._cache[path] and self._progress >= 1.0:
            self._show(path)

    def _prefetch(self):
        index = self.strip.index
        for i in (index + 1, index - 1, index + 2, index - 2):
            if 0 <= i < len(self.strip.images):
                self._want_path(self.strip.images[i])

    def _moved(self):
        path = self.strip.current()
        if path == self._want:
            return
        self._want = path
        if path in self._cache:
            self._show(path)
        else:
            self._want_path(path)
        self._prefetch()

    def _show(self, path):
        """Revela el fondo `path` sobre el que se ve ahora: un barrido circular desde la tira."""
        pm = self._cache.get(path)
        if pm is None:
            return
        self._before = self._now if self._now is not None else pm
        self._now = pm
        self._reveal.start(0.0, 1.0, REVEAL_MS, QEasingCurve.OutCubic)

    def _set_progress(self, value):
        self._progress = float(value)
        if self._progress >= 1.0:
            self._before = None
            if self._want in self._cache and self._now is not self._cache[self._want]:
                self._show(self._want)  # llegó otra flecha mientras tanto
        self.update()

    # ---------- teclado y foco ----------

    def keyPressEvent(self, event):
        key = event.key()
        if key in (Qt.Key_Left, Qt.Key_Up):
            self.strip.step(-1)
        elif key in (Qt.Key_Right, Qt.Key_Down):
            self.strip.step(1)
        elif key in (Qt.Key_Return, Qt.Key_Enter):
            self._finish(keep=True)
        elif key == Qt.Key_Escape:
            self._finish(keep=False)
        else:
            super().keyPressEvent(event)

    def wheelEvent(self, event):
        self.strip.step(-1 if event.angleDelta().y() > 0 else 1)

    def changeEvent(self, event):
        if event.type() == QEvent.ActivationChange and self.opened and not self.isActiveWindow():
            QTimer.singleShot(BLUR_CHECK_MS, self._check_blur)
        super().changeEvent(event)

    def _check_blur(self):
        if self.opened and not self.isActiveWindow():
            self._finish(keep=False)

    def closeEvent(self, event):
        event.ignore()
        self._finish(keep=False)

    # ---------- pintura ----------

    def paintEvent(self, _):
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        shown = self._before if self._before is not None else self._now
        if shown is None:
            p.fillRect(self.rect(), QColor(self.theme.frame_dark))
            return
        p.drawPixmap(0, 0, shown)
        if self._before is None or self._now is None or self._progress >= 1.0:
            return
        # el fondo nuevo se revela con un barrido circular desde la tira, con el borde suave (tres capas)
        origin = QPointF(self.width() / 2, self.height() - STRIP_BOTTOM - STRIP_H / 2)
        far = math.hypot(max(origin.x(), self.width() - origin.x()), max(origin.y(), self.height() - origin.y()))
        radius = self._progress * far * 1.15
        for scale, opacity in ((1.0, 0.34), (0.94, 0.66), (0.88, 1.0)):
            circle = QPainterPath()
            circle.addEllipse(origin, radius * scale, radius * scale)
            p.save()
            p.setClipPath(circle)
            p.setOpacity(opacity)
            p.drawPixmap(0, 0, self._now)
            p.restore()
        glow = QColor(self.theme.gold)  # el aro de luz: se apaga a medida que el barrido llega al borde
        glow.setAlphaF(max(0.0, 0.85 * (1.0 - self._progress)))
        p.setBrush(Qt.NoBrush)
        p.setPen(QPen(glow, 3))
        p.drawEllipse(origin, radius, radius)


"""El fondo de pantalla nítido, ajustado al tamaño de la pantalla (como lo pone Windows: llenando y recortando).

Lo usan las pantallas completas (el mapa de ejes, el deslizamiento de escritorios y el modo de fondos). Leer y
escalar una imagen grande tarda decenas de milisegundos, así que se prepara en un hilo (`prepare`) y la interfaz solo
la convierte en pixmap, una vez por fondo.
"""
import threading

from PySide6.QtCore import QSize, Qt
from PySide6.QtGui import QImage, QImageReader, QPixmap


def load_image(path, size, dpr):
    """QImage del fondo `path` llenando `size` (px lógicos) a resolución real de pantalla, o None. Se puede llamar
    desde un hilo."""
    if not path:
        return None
    reader = QImageReader(path)
    reader.setAutoTransform(True)
    full = reader.size()
    target = QSize(round(size.width() * dpr), round(size.height() * dpr))
    if not full.isValid() or target.isEmpty():
        return None
    reader.setScaledSize(full.scaled(target, Qt.KeepAspectRatioByExpanding))
    image = reader.read()
    if image.isNull():
        return None
    x, y = (image.width() - target.width()) // 2, (image.height() - target.height()) // 2
    image = image.copy(x, y, target.width(), target.height())
    return image.convertToFormat(QImage.Format_RGB32)


class WallpaperBg:
    """El fondo actual como pixmap listo para pintar. `pixmap()` solo lo convierte la primera vez (hilo de Qt)."""

    def __init__(self, screen_map):
        self.map = screen_map
        self._path = None
        self._image = None
        self._pixmap = None
        self._lock = threading.Lock()

    def prepare(self, path):
        """Lee `path` en un hilo para tenerlo listo cuando haga falta."""
        if path == self._path and self._image is not None:
            return
        threading.Thread(target=self._read, args=(path,), daemon=True, name="kyora-wallpaper-bg").start()

    def _read(self, path):
        image = load_image(path, self.map.geometry.size(), self.map.dpr)
        with self._lock:
            self._path, self._image, self._pixmap = path, image, None

    def pixmap(self, path):
        """El fondo de `path` (se lee aquí mismo si aún no se había preparado), o None si no se puede leer."""
        with self._lock:
            ready = path == self._path and self._image is not None
        if not ready:
            self._read(path)
        with self._lock:
            if self._pixmap is None and self._image is not None:
                self._pixmap = QPixmap.fromImage(self._image)
                self._pixmap.setDevicePixelRatio(self.map.dpr)
            return self._pixmap

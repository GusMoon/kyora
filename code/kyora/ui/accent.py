"""Color principal del fondo de pantalla: se usa como acento (contorno de la ventana activa, selección, etc.)."""
import ctypes
import logging

from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QImage

log = logging.getLogger("kyora.ui")

SPI_GETDESKWALLPAPER = 0x0073
SAMPLE = (96, 54)  # se analiza una miniatura: basta y es instantáneo
HUE_BINS = 36
MIN_SATURATION = 0.35  # los grises y los colores apagados no cuentan como "color principal"
MIN_VALUE = 0.30  # ni los muy oscuros (el azul marino profundo del fondo es el telón, no el acento)


def wallpaper_path():
    """Ruta de la imagen del fondo de pantalla actual, o ''."""
    buf = ctypes.create_unicode_buffer(520)
    ctypes.windll.user32.SystemParametersInfoW(SPI_GETDESKWALLPAPER, len(buf), buf, 0)
    return buf.value


def dominant_accent(image):
    """Color más presente entre los vivos de la imagen, ajustado para verse bien sobre gris oscuro. None si no hay."""
    small = image.scaled(*SAMPLE, Qt.IgnoreAspectRatio, Qt.SmoothTransformation).convertToFormat(QImage.Format_RGB32)
    weight = [0.0] * HUE_BINS
    sums = [[0.0, 0.0, 0.0] for _ in range(HUE_BINS)]
    for y in range(small.height()):
        for x in range(small.width()):
            c = small.pixelColor(x, y)
            s, v = c.hsvSaturationF(), c.valueF()
            if s < MIN_SATURATION or v < MIN_VALUE or c.hsvHueF() < 0:
                continue
            w = s * v
            b = min(int(c.hsvHueF() * HUE_BINS), HUE_BINS - 1)
            weight[b] += w
            sums[b][0] += c.hsvHueF() * w
            sums[b][1] += s * w
            sums[b][2] += v * w
    best = max(range(HUE_BINS), key=weight.__getitem__)
    if weight[best] <= 0:
        return None
    h, s, v = (sums[best][0] / weight[best], sums[best][1] / weight[best], sums[best][2] / weight[best])
    return QColor.fromHsvF(h, min(max(s, 0.45), 0.85), max(v, 0.85)).name()


def wallpaper_accent():
    """Acento sacado del fondo de pantalla; None si no se puede leer (el tema usa entonces su acento por defecto)."""
    try:
        image = QImage(wallpaper_path())
        return None if image.isNull() else dominant_accent(image)
    except Exception:
        log.debug("No se pudo leer el color del fondo de pantalla", exc_info=True)
        return None

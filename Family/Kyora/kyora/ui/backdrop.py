"""El gris de los paneles y el desenfoque barato de una captura (lo único de fondo que queda: no hay lienzo de pantalla
ni miniaturas del fondo guardadas, para gastar menos memoria).

- `PANEL_GRAY`: el gris oscuro liso y opaco de todos los paneles.
- `blur_image`: una captura de pantalla muy desenfocada, a tamaño pequeño (se estira al pintarla); la usa Ctrl+Shift+X
  para dejar todo borroso detrás de sus opciones. Se desenfoca encogiendo y estirando con suavizado, sin trabajo de píxeles.
"""
from PySide6.QtCore import QSize, Qt
from PySide6.QtGui import QImage

PANEL_GRAY = "#151515"  # el gris liso y opaco de los paneles: sin degradado, transparencia ni efectos
SMALL = 240  # ancho de la miniatura que se desenfoca
BLUR_PASSES = 4  # cada pasada encoge a la mitad y vuelve a estirar: más pasadas, más desenfoque


def _soften(image, passes=None):
    """Desenfoca una imagen pequeña encogiéndola y estirándola con suavizado (sin trabajo de píxeles)."""
    image = image.convertToFormat(QImage.Format_RGB32)
    small = image.size()
    for _ in range(BLUR_PASSES if passes is None else passes):
        half = image.scaled(max(image.width() // 2, 1), max(image.height() // 2, 1), Qt.IgnoreAspectRatio,
                            Qt.SmoothTransformation)
        image = half.scaled(small, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
    return image


def blur_image(image):
    """Una imagen cualquiera (la captura de la pantalla) muy desenfocada, a tamaño pequeño: se estira al pintarla."""
    small = QSize(SMALL, max(round(SMALL * image.height() / max(image.width(), 1)), 1))
    return _soften(image.scaled(small, Qt.IgnoreAspectRatio, Qt.SmoothTransformation))

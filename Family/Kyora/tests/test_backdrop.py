from PySide6.QtGui import QColor, QImage
from PySide6.QtWidgets import QApplication

from kyora.ui import backdrop

app = QApplication.instance() or QApplication([])


def test_blur_image_returns_a_small_smooth_copy():
    image = QImage(800, 600, QImage.Format_RGB32)
    image.fill(QColor("#ffffff"))
    blurred = backdrop.blur_image(image)
    assert blurred.width() == backdrop.SMALL and blurred.height() == 180
    assert QColor(backdrop.PANEL_GRAY).lightness() < 40     # el gris de los paneles es oscuro y liso

from PySide6.QtCore import QRect
from PySide6.QtGui import QColor, QImage, QPainter
from PySide6.QtWidgets import QApplication

from kyora.ui.hub.cards import paint_flat, paint_glass
from kyora.ui.theme import THEME

app = QApplication.instance() or QApplication([])


def _paint(fn):
    img = QImage(120, 80, QImage.Format_ARGB32)
    img.fill(QColor(0, 0, 0, 0))
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    fn(p, THEME, QRect(10, 10, 100, 50), 10)
    p.end()
    return img


def test_flat_surface_has_no_shadow_and_no_gradient():
    img = _paint(paint_flat)
    assert all(img.pixelColor(x, y).alpha() == 0 for x in range(20, 100) for y in range(61, 70))  # nada debajo
    top, bottom = img.pixelColor(60, 16), img.pixelColor(60, 54)
    assert top == bottom == QColor(THEME.plate_top)  # relleno liso


def test_skeuomorphic_plate_still_casts_its_short_shadow():
    img = _paint(paint_glass)
    assert any(img.pixelColor(60, y).alpha() > 0 for y in range(58, 62))

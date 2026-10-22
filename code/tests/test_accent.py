from PySide6.QtGui import QColor, QImage, QPainter

from kyora.ui.accent import dominant_accent
from kyora.ui.theme import THEME


def painted(background, patch=None, size=(200, 120)):
    image = QImage(*size, QImage.Format_RGB32)
    image.fill(QColor(background))
    if patch:
        p = QPainter(image)
        p.fillRect(20, 20, 70, 50, QColor(patch))
        p.end()
    return image


def test_accent_is_the_vivid_color_not_the_dark_backdrop():
    color = QColor(dominant_accent(painted("#0b1424", patch="#e3b25a")))
    assert 30 <= color.hsvHue() <= 55          # dorado
    assert color.valueF() >= 0.85              # se ajusta para verse sobre gris oscuro


def test_accent_follows_the_wallpaper_hue():
    color = QColor(dominant_accent(painted("#2f7bff")))
    assert 205 <= color.hsvHue() <= 235        # azul


def test_no_vivid_color_gives_none():
    assert dominant_accent(painted("#303030")) is None
    assert dominant_accent(painted("#0b1424")) is None


def test_with_accent_replaces_every_accent_color():
    t = THEME.with_accent("#4aa3ff")
    assert (t.gold, t.focus_color) == ("#4aa3ff", "#4aa3ff")
    assert t.gold_soft.endswith("4aa3ff") and t.drop_line.endswith("4aa3ff")
    assert t.frame == THEME.frame             # el marco sigue siendo gris oscuro


def test_frame_is_neutral_dark_gray():
    for color in (THEME.frame, THEME.frame_light, THEME.frame_dark):
        c = QColor(color)
        assert c.red() == c.green() == c.blue() and c.value() < 60

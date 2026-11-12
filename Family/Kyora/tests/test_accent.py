from PySide6.QtGui import QColor, QImage, QPainter

from kyora.ui.accent import derive_palette, dominant_colors, median_cut
from kyora.ui.theme import THEME


def painted(background, patch=None, size=(200, 120), patch_frac=0.3):
    image = QImage(*size, QImage.Format_RGB32)
    image.fill(QColor(background))
    if patch:
        p = QPainter(image)
        p.fillRect(0, 0, round(size[0] * patch_frac), size[1], QColor(patch))
        p.end()
    return image


def _luminance(color):
    def channel(c):
        c = c / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    q = QColor(color)
    return 0.2126 * channel(q.red()) + 0.7152 * channel(q.green()) + 0.0722 * channel(q.blue())


def _contrast(a, b):
    la, lb = sorted((_luminance(a), _luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def test_median_cut_orders_by_area():
    pixels = [(20, 60, 200)] * 70 + [(240, 200, 30)] * 30
    colors = median_cut(pixels)
    assert [round(w, 2) for _, w in colors] == [0.7, 0.3]
    assert QColor(colors[0][0]).blue() > 150 and QColor(colors[1][0]).red() > 200
    assert median_cut([]) == []


def test_gray_wallpaper_gives_a_gray_accent():
    palette = derive_palette(dominant_colors(painted("#6b6b6b", patch="#e3c020", patch_frac=0.05)))
    assert QColor(palette["accent"]).hsvSaturationF() < 0.05  # nada de amarillo: el fondo es gris
    assert QColor(palette["frame"]).hsvSaturationF() == 0


def test_blue_and_yellow_take_the_most_present_first():
    palette = derive_palette(dominant_colors(painted("#1e4fd0", patch="#f0c419", patch_frac=0.3)))
    accent, second = QColor(palette["accent"]), QColor(palette["second"])
    assert 0.55 < accent.hsvHueF() < 0.7  # azul: el que más ocupa
    assert 0.1 < second.hsvHueF() < 0.2  # amarillo: el segundo
    assert QColor(palette["frame"]).hsvSaturationF() == 0  # los fondos son gris neutro; el color queda para el énfasis


def test_dark_wallpapers_stay_dark_and_readable():
    for background, patch in (("#0b1f4a", "#3fa0ff"), ("#050505", "#9a1010"), ("#202020", None), ("#f5f5f5", None)):
        palette = derive_palette(dominant_colors(painted(background, patch)))
        for key in ("frame", "frame_light", "plate_top", "plate_bottom", "capsule"):
            assert QColor(palette[key]).valueF() <= 0.22, (background, key)
        assert _contrast(palette["ink"], palette["frame"]) >= 7
        assert QColor(palette["accent"]).valueF() >= 0.78  # siempre se lee sobre el marco
    near_black = derive_palette(dominant_colors(painted("#050505", "#9a1010")))
    assert QColor(near_black["accent"]).red() > 150  # el negro es el telón: el acento es el rojo


def test_theme_takes_the_palette():
    theme = THEME.with_palette({"frame": "#0a0c12", "ink": "#eef0ff", "accent": "#3fa0ff", "second": "#f0c419"})
    assert theme.frame == "#0a0c12" and theme.ink == "#eef0ff" and theme.second == "#f0c419"
    assert theme.gold == "#3fa0ff" and theme.focus_color == "#3fa0ff"
    assert THEME.with_palette({}) == THEME


def test_the_four_most_repeated_colors_of_the_wallpaper_are_kept_and_the_dark_theme_does_not_change():
    from PySide6.QtGui import QColor

    from kyora.ui import accent
    from kyora.ui.theme import THEME

    colors = [("#c8325a", 0.4), ("#2a2f6b", 0.25), ("#e3b25a", 0.2), ("#1d6b5a", 0.1), ("#808080", 0.05)]
    assert accent.top_colors(colors) == ["#c8325a", "#2a2f6b", "#e3b25a", "#1d6b5a"]
    palette = accent.derive_palette(colors)
    assert palette["wall_colors"] == ("#c8325a", "#2a2f6b", "#e3b25a", "#1d6b5a")
    for key in ("frame", "frame_light", "frame_dark", "plate_top", "capsule"):  # los fondos siguen siendo gris oscuro neutro
        color = QColor(palette[key])
        assert color.valueF() < 0.25 and color.hsvSaturationF() == 0
    themed = THEME.with_palette(palette)
    assert themed.wall_colors == palette["wall_colors"] and themed.third and themed.fourth


def test_a_mostly_white_wallpaper_with_vivid_colors_gets_a_vivid_accent():
    from PySide6.QtGui import QColor

    from kyora.ui import accent

    colors = [("#fffbe8", 0.35), ("#f5d9a8", 0.2), ("#e8a080", 0.15), ("#f0903a", 0.12)]
    palette = accent.derive_palette(colors)
    assert QColor(palette["accent"]).hsvSaturationF() > 0.3          # no el blanco: el color vivo
    gray = accent.derive_palette([("#e0e0e0", 0.5), ("#808080", 0.3), ("#202020", 0.2)])
    assert QColor(gray["accent"]).hsvSaturationF() < 0.12            # un fondo gris sigue dando un acento gris

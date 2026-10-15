from .font_icon import draw_font_icon


def draw(painter, center, scale, color, base_size=24):
    """Dibuja el ícono del calendario con el glifo de calendario de Segoe MDL2 Assets."""
    draw_font_icon(painter, center, scale, color, "", base_size)

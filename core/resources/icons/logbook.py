from .font_icon import draw_font_icon


def draw(painter, center, scale, color, base_size=24):
    """Dibuja el ícono de la bitácora con el glifo de edición de Segoe MDL2 Assets."""
    draw_font_icon(painter, center, scale, color, "", base_size)

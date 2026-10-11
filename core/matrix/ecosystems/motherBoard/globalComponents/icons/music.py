from .font_icon import draw_font_icon

def draw(painter, center, scale, color, base_size=24):
    draw_font_icon(painter, center, scale, color, "", base_size)

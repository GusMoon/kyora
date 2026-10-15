"""
Tokens visuales y estilos compartidos de Kyora.

Implementa en código los valores de `docs/reference/globalKyoraUI.md`. Cualquier
ecosistema que necesite colores, tipografía o estilos de botón debe importarlos
de aquí en lugar de repetir valores hexadecimales.
"""
from PySide6.QtCore import QRectF
from PySide6.QtGui import QPainterPath

FONT = "Prototype"

# --- Superficies (de más oscura a más clara) ---
BG_DEEP = "#0A0A0A"
BG_EDITOR = "#0D0D0D"
BG_APP = "#121212"
BG_PANEL_ALT = "#141414"
BG_CONTAINER = "#151515"
BG_INSET = "#171717"
BG_BADGE = "#1A1A1A"
BG_FOLDER = "#1C1C1C"
BG_ITEM = "#202020"
BG_CARD = "#222222"
BG_INPUT = "#242424"
BG_CARD_HOVER = "#262626"
VEIL_RGBA = (18, 18, 18, 240)

# --- Bordes ---
BORDER_FAINT = "#2A2A2A"
BORDER_SOFT = "#333333"
BORDER_INPUT = "#3E3E3E"
BORDER = "#444444"
BORDER_HOVER = "#4E4E4E"

# --- Texto ---
TEXT = "#FFFFFF"
TEXT_STRONG = "#E0E0E0"
TEXT_BODY = "#CCCCCC"
TEXT_MUTED = "#AAAAAA"
TEXT_SUB = "#888888"
TEXT_DIM = "#666666"
TEXT_DISABLED = "#555555"

# --- Acento y acción principal ---
ACCENT = "#FFAA77"
ACCENT_DEEP = "#A04A2C"
ACCENT_DEEP_BORDER = "#D46B3C"
ACCENT_DEEP_HOVER = "#B85834"
ACCENT_TINT = "#2A1D16"
PRIMARY = "#A31F34"
PRIMARY_BORDER = "#C42B42"
PRIMARY_HOVER = "#B9263D"

# --- Estados ---
STATUS_PENDING = "#FFA500"
STATUS_IN_PROGRESS = "#00BFFF"
STATUS_COMPLETED = "#00FA9A"
DANGER = "#FF5555"
DANGER_BORDER = "#441A1A"
DANGER_BG_HOVER = "#2D1111"

# --- Radios ---
RADIUS_CARD = 4
RADIUS_PANEL = 6

# variante -> (fondo, borde, texto, fondo hover, borde hover, texto hover)
_BUTTON_VARIANTS = {
    "standard": (BG_INPUT, BORDER, TEXT, "#333333", TEXT_SUB, TEXT),
    "primary": (PRIMARY, PRIMARY_BORDER, TEXT, PRIMARY_HOVER, PRIMARY_BORDER, TEXT),
    "ghost": ("transparent", BORDER_SOFT, TEXT_SUB, "transparent", "#555555", TEXT),
    "accent": (BG_CARD, "#383838", ACCENT, "#2D2D2D", ACCENT, ACCENT),
    "danger": ("transparent", DANGER_BORDER, DANGER, DANGER_BG_HOVER, DANGER, DANGER),
}


def button_style(kind: str = "standard", padding: str = "7px 16px", font_px: int = 11) -> str:
    """
    Devuelve el QSS de un botón con una de las variantes de globalKyoraUI.

    Args:
        kind: "standard", "primary", "ghost", "accent" o "danger".
        padding: Relleno CSS del botón.
        font_px: Tamaño de la fuente en píxeles.

    Returns:
        str: Hoja de estilos lista para `setStyleSheet`.

    Raises:
        KeyError: Si `kind` no es una variante conocida.
    """
    bg, border, color, hover_bg, hover_border, hover_color = _BUTTON_VARIANTS[kind]
    return (
        f"QPushButton {{ background-color: {bg}; color: {color}; border: 1px solid {border}; "
        f"font-family: '{FONT}'; font-size: {font_px}px; font-weight: bold; letter-spacing: 1px; "
        f"padding: {padding}; border-radius: {RADIUS_CARD}px; }} "
        f"QPushButton:hover {{ background-color: {hover_bg}; border: 1px solid {hover_border}; "
        f"color: {hover_color}; }}"
    )


def chip_style() -> str:
    """Devuelve el QSS de un chip conmutable (globalKyoraUI): reposo y `:checked`."""
    return (
        f"QPushButton {{ background-color: {BG_BADGE}; border: 1px solid {BORDER_SOFT}; "
        f"color: {TEXT_SUB}; font-family: '{FONT}'; font-size: 10px; font-weight: bold; "
        f"letter-spacing: 0.6px; padding: 5px 12px; border-radius: {RADIUS_CARD}px; }} "
        f"QPushButton:hover {{ color: {TEXT}; border-color: #555555; }} "
        f"QPushButton:checked {{ background-color: {ACCENT_TINT}; border-color: {ACCENT}; "
        f"color: {ACCENT}; }}"
    )


def rounded_path(rect: QRectF, radius: float) -> QPainterPath:
    """
    Construye un rectángulo de esquinas redondeadas.

    Args:
        rect: Rectángulo base.
        radius: Radio de las esquinas.

    Returns:
        QPainterPath: Trazado cerrado.
    """
    path = QPainterPath()
    path.addRoundedRect(rect, radius, radius)
    return path

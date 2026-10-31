"""Ayudantes de pintura que comparten el panel superior, el izquierdo y las listas: la letra, la cápsula en relieve del
elemento en uso y el color principal. (La barra lateral del marco ya no existe: el estado va en el panel superior.)
"""
from PySide6.QtCore import Qt
from PySide6.QtGui import QColor, QFont, QLinearGradient, QPen

LOW_BATTERY = 15  # % por debajo del cual la batería se avisa (si no está cargando)
WEEKDAYS = ("lun", "mar", "mié", "jue", "vie", "sáb", "dom")
MONTHS = ("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")


def font(theme, px=None, bold=False):
    """La letra de todo Kyora: un solo tamaño (`theme.font_px`); `px` se acepta por compatibilidad y se ignora. Lo único
    que distingue un título de un texto es la negrita."""
    f = QFont(theme.font_family)
    f.setPixelSize(theme.font_px)
    f.setBold(bold)
    return f


def paint_raised(p, theme, rect, radius):
    """La cápsula en relieve del icono en uso (como la referencia): sombra suave debajo, degradado claro arriba y
    oscuro abajo, un filete de luz en el borde de arriba y una línea oscura fina alrededor."""
    t = theme
    p.save()
    p.setPen(Qt.NoPen)
    for grow, alpha in ((3, 40), (1.5, 70)):  # sombra
        p.setBrush(QColor(0, 0, 0, alpha))
        p.drawRoundedRect(rect.adjusted(-grow / 2, grow / 2, grow / 2, grow + 1), radius + grow, radius + grow)
    grad = QLinearGradient(rect.topLeft(), rect.bottomLeft())
    grad.setColorAt(0, QColor(t.raised_top))
    grad.setColorAt(1, QColor(t.raised_bottom))
    p.setBrush(grad)
    p.setPen(QPen(QColor(0, 0, 0, 150), 1))
    p.drawRoundedRect(rect, radius, radius)
    light = QLinearGradient(rect.topLeft(), rect.bottomLeft())
    light.setColorAt(0, QColor(255, 255, 255, 60))
    light.setColorAt(0.45, QColor(255, 255, 255, 0))
    p.setBrush(Qt.NoBrush)
    p.setPen(QPen(light, 1))
    p.drawRoundedRect(rect.adjusted(1, 1, -1, -1), radius - 1, radius - 1)
    p.restore()


def accent(theme, lit):
    """El color de todo lo del panel: el acento de Kyora (el del borde de las ventanas), algo más claro si está
    activo o bajo el ratón."""
    color = QColor(theme.gold)
    return color.lighter(130) if lit else color

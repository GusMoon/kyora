"""Diseño de la tarjeta de un elemento (carpeta o archivo) del directorio.

De izquierda a derecha: número, recuadro con el icono, nombre con su detalle y un bloque
con el tipo. Reposa en gris claro con el contorno fino; bajo el cursor se levanta, con
grosor visible, en el color de acento. Solo dibuja: ``ContentPanel`` la coloca y atiende
el ratón.
"""
from typing import NamedTuple

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QFont, QFontMetricsF, QPainter, QPen, QPolygonF

import core.resources.icons.files.file as icon_file
import core.resources.icons.files.folder as icon_folder
from core.matrix.motherboard.modules import kyora_theme as kt

# Medidas en píxeles de referencia (ventana de ``REFERENCE_HEIGHT`` de alto)
REFERENCE_HEIGHT = 800
CARD_WIDTH = 430        # ancho máximo de la fila completa, con el número
CARD_HEIGHT = 48
CARD_GAP = 12
CARD_DEPTH = 5          # grosor visible de la tarjeta levantada
CARD_CUT = 9            # esquina cortada de la tarjeta
TILE_CUT = 10           # esquina cortada del recuadro del icono
INDEX_WIDTH = 30        # ancho reservado al número
TYPE_WIDTH = 96         # ancho del bloque del tipo, a la derecha
ICON_SCALE = 0.7
ICON_BASE_SIZE = 24.0


class Entry(NamedTuple):
    """Elemento de una carpeta: ``kind`` es la extensión o ``CARPETA``; ``detail`` el tamaño y la fecha."""

    name: str
    path: str
    is_dir: bool
    kind: str
    detail: str


def tinted(hex_color: str, alpha: float = 1.0) -> QColor:
    """Color del tema con la opacidad ``alpha`` (0..1)."""
    color = QColor(hex_color)
    color.setAlpha(int(255 * max(0.0, min(1.0, alpha))))
    return color


def ui_font(pixels: float, bold: bool = False, spacing: float = 0.0) -> QFont:
    """Fuente del tema con tamaño en píxeles y separación de letras opcional."""
    font = QFont(kt.FONT)
    font.setPixelSize(max(7, int(pixels)))
    font.setBold(bold)
    if spacing:
        font.setLetterSpacing(QFont.AbsoluteSpacing, spacing)
    return font


def pitch(scale: float) -> float:
    """Distancia vertical entre dos tarjetas contiguas, en píxeles."""
    return (CARD_HEIGHT + CARD_GAP) * scale


def _shape(rect: QRectF, cut_top_left: float = 0.0, cut_top_right: float = 0.0,
           cut_bottom_right: float = 0.0, offset: float = 0.0) -> QPolygonF:
    """Rectángulo con esquinas cortadas en diagonal, desplazado ``offset`` hacia abajo."""
    l, t, r, b = rect.left(), rect.top() + offset, rect.right(), rect.bottom() + offset
    return QPolygonF([
        QPointF(l + cut_top_left, t), QPointF(r - cut_top_right, t), QPointF(r, t + cut_top_right),
        QPointF(r, b - cut_bottom_right), QPointF(r - cut_bottom_right, b), QPointF(l, b),
        QPointF(l, t + cut_top_left),
    ])


def paint(p: QPainter, entry: Entry, index: int, row: QRectF, scale: float, hot: bool) -> None:
    """Dibuja una tarjeta.

    Args:
        p: QPainter activo.
        entry: elemento que muestra.
        index: posición en la lista, para el número.
        row: rectángulo de la fila; el número va a su izquierda y la tarjeta al resto.
        scale: escala respecto al alto de referencia.
        hot: si está bajo el cursor (levantada, en acento).
    """
    s = scale
    body = QRectF(row.left() + INDEX_WIDTH * s, row.top(), row.width() - INDEX_WIDTH * s, row.height())
    tile = QRectF(body.left(), body.top(), body.height(), body.height())
    kind_block = QRectF(body.right() - TYPE_WIDTH * s, body.top(), TYPE_WIDTH * s, body.height())

    p.setBrush(Qt.NoBrush)
    p.setPen(tinted(kt.ACCENT_DEEP_BORDER if hot else kt.TEXT_SUB))
    p.setFont(ui_font(13 * s, True))
    p.drawText(QRectF(row.left(), body.top(), INDEX_WIDTH * s - 6 * s, body.height()),
               Qt.AlignRight | Qt.AlignVCenter, str(index + 1))

    cut = CARD_CUT * s
    if hot:
        p.setPen(Qt.NoPen)
        p.setBrush(tinted(kt.ACCENT_DEEP))
        p.drawPolygon(_shape(body, cut, 0, cut, CARD_DEPTH * s))
        p.setBrush(tinted(kt.ACCENT_DEEP_BORDER))
        p.drawPolygon(_shape(body, cut, 0, cut))
        p.setBrush(tinted(kt.ACCENT_DEEP))
        p.drawPolygon(_shape(kind_block, cut, 0, cut))
    else:
        p.setPen(QPen(tinted(kt.BORDER), 1))
        p.setBrush(tinted(kt.BG_CARD_HOVER))
        p.drawPolygon(_shape(body, cut, 0, cut))
        p.setPen(QPen(tinted(kt.BORDER_INPUT), 1))
        p.setBrush(tinted(kt.BG_ITEM))
        p.drawPolygon(_shape(kind_block, cut, 0, cut))

    p.setPen(Qt.NoPen if hot else QPen(tinted(kt.BORDER), 1))
    p.setBrush(tinted(kt.BG_DEEP if hot else kt.BG_CARD))
    p.drawPolygon(_shape(tile, 0, TILE_CUT * s, 0))
    icon = icon_folder if entry.is_dir else icon_file
    icon.draw(p, tile.center(), ICON_SCALE * s,
              tinted(kt.ACCENT if hot else kt.TEXT_BODY if entry.is_dir else kt.TEXT_MUTED), ICON_BASE_SIZE)

    text_left = tile.right() + 11 * s
    text_width = kind_block.left() - text_left - 10 * s
    title_font = ui_font(13 * s, True)
    p.setFont(title_font)
    p.setPen(tinted(kt.BG_DEEP if hot else kt.TEXT))
    shown = QFontMetricsF(title_font).elidedText(entry.name, Qt.ElideMiddle, text_width)
    p.drawText(QRectF(text_left, body.top() + 6 * s, text_width, 20 * s), Qt.AlignLeft | Qt.AlignVCenter, shown)
    detail_font = ui_font(8 * s, False, 1)
    p.setFont(detail_font)
    p.setPen(tinted(kt.ACCENT_DEEP if hot else kt.TEXT_SUB))
    detail = QFontMetricsF(detail_font).elidedText("▸ " + entry.detail, Qt.ElideRight, text_width)
    p.drawText(QRectF(text_left, body.top() + 27 * s, text_width, 14 * s), Qt.AlignLeft | Qt.AlignVCenter, detail)

    pad = 14 * s
    p.setFont(ui_font(7 * s, True, 1.5))
    p.setPen(tinted(kt.ACCENT_TINT if hot else kt.TEXT_SUB))
    p.drawText(QRectF(kind_block.left() + pad, body.top() + 6 * s, kind_block.width() - pad, 12 * s),
               Qt.AlignLeft | Qt.AlignVCenter, "TIPO")
    kind_font = ui_font(13 * s, True, 1)
    p.setFont(kind_font)
    p.setPen(tinted(kt.BG_DEEP if hot else kt.TEXT_BODY))
    kind = QFontMetricsF(kind_font).elidedText(entry.kind, Qt.ElideRight, kind_block.width() - pad - 6 * s)
    p.drawText(QRectF(kind_block.left() + pad, body.top() + 20 * s, kind_block.width() - pad, 22 * s),
               Qt.AlignLeft | Qt.AlignVCenter, kind)

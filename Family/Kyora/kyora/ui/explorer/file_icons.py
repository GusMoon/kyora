"""Iconos propios del explorador (en lugar de los de Windows), lisos y sencillos:

- Carpeta: dos piezas planas (la de atrás con su pestaña, más oscura, y la de delante) en un color del fondo de pantalla.
- Archivo: hoja gris clara con la esquina doblada y unas rayas de texto.

Se dibujan una vez por tamaño y se guardan; además es más rápido que pedirle cada icono a Windows.
"""
import os

from PySide6.QtCore import QFileInfo, QRectF, Qt
from PySide6.QtGui import (
    QAbstractFileIconProvider,
    QColor,
    QGuiApplication,
    QIcon,
    QPainter,
    QPainterPath,
    QPixmap,
)

SIZES = (16, 20, 24, 32, 48, 64, 96, 128)
FOLDER_COLOR = "#7fa6d6"  # mientras no haya paleta del fondo de pantalla


def _unit(p, rect):
    """Pinta en una caja de 100×100 dentro de `rect`."""
    side = min(rect.width(), rect.height())
    p.translate(rect.x() + (rect.width() - side) / 2, rect.y() + (rect.height() - side) / 2)
    p.scale(side / 100, side / 100)


def folder_tone(color):
    """El color del fondo de pantalla, con la claridad justa para que la carpeta se vea sobre un panel oscuro."""
    h, s, l, _ = QColor(color).getHslF()
    return QColor.fromHslF(max(h, 0.0), min(s, 0.7), min(max(l, 0.58), 0.72))


def paint_folder(p, rect, color=FOLDER_COLOR):
    front = folder_tone(color)
    back = front.darker(135)
    p.save()
    p.setRenderHint(QPainter.Antialiasing)
    _unit(p, rect)
    p.setPen(Qt.NoPen)
    tab = QPainterPath()  # la pieza de atrás, con su pestaña
    tab.moveTo(8, 24)
    tab.quadTo(8, 14, 18, 14)
    tab.lineTo(36, 14)
    tab.quadTo(41, 14, 44, 19)
    tab.lineTo(47, 23)
    tab.lineTo(82, 23)
    tab.quadTo(92, 23, 92, 33)
    tab.lineTo(92, 80)
    tab.lineTo(8, 80)
    tab.closeSubpath()
    p.fillPath(tab, back)
    p.setBrush(front)  # la de delante
    p.drawRoundedRect(QRectF(8, 31, 84, 55), 9, 9)
    p.restore()


def paint_file(p, rect):
    p.save()
    p.setRenderHint(QPainter.Antialiasing)
    _unit(p, rect)
    fold = 22
    page = QPainterPath()
    page.moveTo(24, 8)
    page.lineTo(76 - fold, 8)
    page.lineTo(76, 8 + fold)
    page.lineTo(76, 84)
    page.quadTo(76, 92, 68, 92)
    page.lineTo(32, 92)
    page.quadTo(24, 92, 24, 84)
    page.lineTo(24, 16)
    page.quadTo(24, 8, 32, 8)
    page.closeSubpath()
    p.setPen(Qt.NoPen)
    p.fillPath(page, QColor("#ebebee"))
    corner = QPainterPath()  # la esquina doblada
    corner.moveTo(76 - fold, 8)
    corner.lineTo(76 - fold, 8 + fold - 5)
    corner.quadTo(76 - fold, 8 + fold, 76 - fold + 5, 8 + fold)
    corner.lineTo(76, 8 + fold)
    corner.closeSubpath()
    p.fillPath(corner, QColor("#cbcbd1"))
    p.setBrush(QColor("#b7b7be"))  # las rayas de texto
    for y, w, h in ((30, 24, 4), (42, 40, 4), (53, 40, 6), (65, 40, 4), (75, 28, 4)):
        p.drawRoundedRect(QRectF(33, y, w, h), h / 2, h / 2)
    p.restore()


def _pixmaps(paint):
    screen = QGuiApplication.primaryScreen()
    dpr = max(screen.devicePixelRatio() if screen else 1.0, 2.0)  # siempre nítido al ampliar
    icon = QIcon()
    for size in SIZES:
        pixmap = QPixmap(round(size * dpr), round(size * dpr))
        pixmap.setDevicePixelRatio(dpr)
        pixmap.fill(Qt.transparent)
        p = QPainter(pixmap)
        paint(p, QRectF(0, 0, size, size))
        p.end()
        icon.addPixmap(pixmap)
    return icon


class KyoraIcons(QAbstractFileIconProvider):
    """Carpeta (también unidades y carpetas especiales) u hoja, para QFileSystemModel y las listas del explorador."""

    def __init__(self):
        super().__init__()
        self._folder = self._file = None
        self._color = FOLDER_COLOR

    def set_color(self, color):
        """Carpetas en otro color (el del fondo de pantalla). Se repintan la próxima vez que se pidan."""
        if color != self._color:
            self._color, self._folder = color, None

    def folder(self):
        if self._folder is None:
            color = self._color
            self._folder = _pixmaps(lambda p, rect: paint_folder(p, rect, color))
        return self._folder

    def file(self):
        if self._file is None:
            self._file = _pixmaps(paint_file)
        return self._file

    def icon(self, what):
        if isinstance(what, QFileInfo):
            return self.folder() if what.isDir() or what.isRoot() else self.file()
        if what == QAbstractFileIconProvider.IconType.File:
            return self.file()
        return self.folder()

    def for_path(self, path):
        return self.folder() if os.path.isdir(path) else self.file()

    def type(self, info):
        if info.isRoot():
            return "Unidad"
        if info.isDir():
            return "Carpeta"
        suffix = info.suffix()
        return f"Archivo {suffix.upper()}" if suffix else "Archivo"


_shared = None


def shared():
    """El mismo proveedor para todo el explorador (los iconos se dibujan una sola vez)."""
    global _shared
    if _shared is None:
        _shared = KyoraIcons()
    return _shared

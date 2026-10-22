"""Iconos propios del explorador (en lugar de los de Windows), como las imágenes de referencia:

- Carpeta: fondo gris oscuro con su pestaña, unas hojas claras asomando y delante una solapa de cristal esmerilado
  (se ven las hojas desenfocadas a través).
- Archivo: hoja casi blanca con la esquina doblada, un pequeño logo de rombos y unas barras grises.

Se dibujan una vez por tamaño y se guardan; además es más rápido que pedirle cada icono a Windows.
"""
import os

from PySide6.QtCore import QFileInfo, QPointF, QRectF, Qt
from PySide6.QtGui import (
    QAbstractFileIconProvider,
    QBrush,
    QColor,
    QGuiApplication,
    QIcon,
    QImage,
    QLinearGradient,
    QPainter,
    QPainterPath,
    QPen,
    QPixmap,
)

SIZES = (16, 20, 24, 32, 48, 64, 96, 128)


def _unit(p, rect):
    """Pinta en una caja de 100×100 dentro de `rect`."""
    side = min(rect.width(), rect.height())
    p.translate(rect.x() + (rect.width() - side) / 2, rect.y() + (rect.height() - side) / 2)
    p.scale(side / 100, side / 100)


def _sheet(p, x, y, w, h, angle, color):
    p.save()
    p.translate(x + w / 2, y + h / 2)
    p.rotate(angle)
    p.setPen(Qt.NoPen)
    p.setBrush(QColor(color))
    p.drawRoundedRect(QRectF(-w / 2, -h / 2, w, h), 3, 3)
    p.setBrush(QColor("#b9b9b9"))
    for i, frac in enumerate((0.62, 0.8, 0.5, 0.7)):
        p.drawRoundedRect(QRectF(-w / 2 + 7, -h / 2 + 9 + i * 7, (w - 14) * frac, 2.6), 1.3, 1.3)
    p.restore()


def _papers(p):
    _sheet(p, 22, 16, 50, 58, -7, "#d9d9d9")
    _sheet(p, 30, 13, 50, 58, 5, "#ededed")
    _sheet(p, 25, 19, 52, 58, -1, "#f7f7f7")


def _flap():
    path = QPainterPath()
    path.moveTo(7, 44)
    path.quadTo(7, 39, 12, 39)
    path.lineTo(88, 39)
    path.quadTo(93, 39, 93, 44)
    path.lineTo(91, 84)
    path.quadTo(90.5, 90, 85, 90)
    path.lineTo(15, 90)
    path.quadTo(9.5, 90, 9, 84)
    path.closeSubpath()
    return path


def paint_folder(p, rect):
    p.save()
    p.setRenderHint(QPainter.Antialiasing)
    _unit(p, rect)
    # fondo con su pestaña
    back = QPainterPath()
    back.moveTo(9, 20)
    back.quadTo(9, 13, 16, 13)
    back.lineTo(36, 13)
    back.quadTo(40, 13, 42, 16)
    back.lineTo(45, 20)
    back.lineTo(84, 20)
    back.quadTo(91, 20, 91, 27)
    back.lineTo(91, 80)
    back.lineTo(9, 80)
    back.closeSubpath()
    grad = QLinearGradient(0, 13, 0, 80)
    grad.setColorAt(0, QColor("#5a5a5c"))
    grad.setColorAt(1, QColor("#2a2a2c"))
    p.setPen(Qt.NoPen)
    p.fillPath(back, grad)
    # hojas
    _papers(p)
    # solapa de cristal: las hojas desenfocadas a través
    flap = _flap()
    blurred = QImage(25, 25, QImage.Format_ARGB32_Premultiplied)  # reducir y ampliar = desenfoque barato
    blurred.fill(Qt.transparent)
    q = QPainter(blurred)
    q.setRenderHint(QPainter.Antialiasing)
    q.scale(0.25, 0.25)
    _papers(q)
    q.end()
    p.save()
    p.setClipPath(flap)
    p.setOpacity(0.55)
    p.setRenderHint(QPainter.SmoothPixmapTransform)
    p.drawImage(QRectF(0, 0, 100, 100), blurred)
    p.restore()
    glass = QLinearGradient(0, 39, 0, 90)
    glass.setColorAt(0, QColor(150, 150, 152, 150))
    glass.setColorAt(0.5, QColor(92, 92, 95, 200))
    glass.setColorAt(1, QColor(52, 52, 55, 235))
    p.fillPath(flap, glass)
    edge = QLinearGradient(0, 39, 0, 90)  # filete de luz arriba
    edge.setColorAt(0, QColor(255, 255, 255, 150))
    edge.setColorAt(0.25, QColor(255, 255, 255, 25))
    edge.setColorAt(1, QColor(255, 255, 255, 10))
    p.setPen(QPen(QBrush(edge), 1.2))
    p.setBrush(Qt.NoBrush)
    p.drawPath(flap)
    p.restore()


def _diamond(p, cx, cy, r):
    path = QPainterPath(QPointF(cx, cy - r))
    path.lineTo(cx + r, cy)
    path.lineTo(cx, cy + r)
    path.lineTo(cx - r, cy)
    path.closeSubpath()
    p.drawPath(path)


def paint_file(p, rect):
    p.save()
    p.setRenderHint(QPainter.Antialiasing)
    _unit(p, rect)
    fold = 20
    page = QPainterPath()
    page.moveTo(20, 10)
    page.lineTo(80 - fold, 10)
    page.lineTo(80, 10 + fold)
    page.lineTo(80, 86)
    page.quadTo(80, 92, 74, 92)
    page.lineTo(26, 92)
    page.quadTo(20, 92, 20, 86)
    page.lineTo(20, 16)
    page.quadTo(20, 10, 26, 10)
    page.closeSubpath()
    p.setPen(Qt.NoPen)
    p.setBrush(QColor(0, 0, 0, 60))  # sombra suave
    p.save()
    p.translate(0, 1.6)
    p.drawPath(page)
    p.restore()
    grad = QLinearGradient(0, 10, 0, 92)
    grad.setColorAt(0, QColor("#fbfbfb"))
    grad.setColorAt(1, QColor("#ececec"))
    p.fillPath(page, grad)
    corner = QPainterPath(QPointF(80 - fold, 10))  # la esquina doblada
    corner.lineTo(80 - fold, 10 + fold - 4)
    corner.quadTo(80 - fold, 10 + fold, 80 - fold + 4, 10 + fold)
    corner.lineTo(80, 10 + fold)
    corner.closeSubpath()
    p.fillPath(corner, QColor("#d2d2d2"))
    p.setBrush(QColor("#c9c9c9"))  # logo de cuatro rombos
    for dx, dy in ((0, -4.2), (4.2, 0), (0, 4.2), (-4.2, 0)):
        _diamond(p, 32 + dx, 26 + dy, 3.2)
    p.setBrush(QColor("#d9d9d9"))
    for y, w in ((50, 44), (60, 34), (70, 26)):
        p.drawRoundedRect(QRectF(29, y, w, 5), 2.5, 2.5)
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

    def folder(self):
        if self._folder is None:
            self._folder = _pixmaps(paint_folder)
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

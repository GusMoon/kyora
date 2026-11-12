"""Panel de Win+R: reemplazar la ventana enfocada por otra de este escritorio que no se ve (fuera de la pantalla o
minimizada).

Una pila vertical de tarjetas redondeadas, centrada y sin hueco entre ellas, con el nombre de cada app encima. La
ventana que se va a reemplazar sale pequeña arriba del todo; la elegida es la más grande y queda en el centro y las demás
se estrechan cuanto más lejos están. Con ↑/↓ (o la rueda) la pila se desliza; Enter pone la elegida en el sitio de la
enfocada (que pasa al panel izquierdo), Supr la cierra y Esc sale. Todo opaco: una placa sólida, sin transparencias ni
negros (si una captura sale vacía, la tarjeta lleva el icono de la app).
"""
import logging
import time

from PySide6.QtCore import QEasingCurve, QEvent, QRectF, Qt, QTimer
from PySide6.QtGui import (
    QColor,
    QGuiApplication,
    QImage,
    QLinearGradient,
    QPainter,
    QPainterPath,
    QPen,
    QPixmap,
)
from PySide6.QtWidgets import QWidget

from kyora.system.win32 import force_foreground
from kyora.ui.anim import Tween
from kyora.ui.bar import font
from kyora.ui.icons import app_icon
from kyora.ui.win import hwnd_of, make_tool_window

log = logging.getLogger("kyora.ui")

WIDEST = 0.62  # ancho de la tarjeta elegida, como fracción del panel
FALLOFF = 0.78  # cada paso de distancia estrecha la tarjeta en este factor
DEFAULT_ASPECT = 16 / 10  # tarjetas sin captura
MAX_HEIGHT = 0.55  # ninguna tarjeta pasa de esta fracción del alto del panel
PAD = 22
SLIDE_MS = 260
BLUR_CHECK_MS = 200
SLOW_OPEN_MS = 50  # abrir el panel más lento que esto se anota en kyora.log


def stack_layout(aspects, pos, width, height):
    """Rectángulos (x, y, ancho, alto) de las tarjetas para la posición `pos` (índice, con decimales al animar).

    `aspects` son las proporciones ancho/alto de cada captura. La tarjeta de `pos` queda centrada en vertical.
    """
    rects, y = [], 0.0
    for i, aspect in enumerate(aspects):
        w = width * WIDEST * FALLOFF ** abs(i - pos)
        h = min(w / aspect, height * MAX_HEIGHT)
        rects.append([0.0, y, w, h])
        y += h
    if not rects:
        return []
    low = min(int(pos), len(rects) - 1)
    high = min(low + 1, len(rects) - 1)
    center = lambda r: r[1] + r[3] / 2
    shift = height / 2 - (center(rects[low]) + (center(rects[high]) - center(rects[low])) * (pos - low))
    return [(x, top + shift, w, h) for x, top, w, h in rects]


class WaitingStack(QWidget):
    def __init__(self, theme, screen_map, items, thumb, invoke):
        """`items()` -> lista de {hwnd, name, title, exe}; `thumb(hwnd)` -> (ancho, alto, bytes) o None."""
        super().__init__()
        make_tool_window(self)
        self.setWindowTitle("KyoraSwitcher")
        self.setFocusPolicy(Qt.StrongFocus)
        self.setAttribute(Qt.WA_TranslucentBackground, False)  # opaco: sin transparencias
        self.setAttribute(Qt.WA_OpaquePaintEvent, True)
        self.theme = theme
        self.map = screen_map
        self._items_fn, self._thumb_fn, self._invoke = items, thumb, invoke
        self.opened = False
        self.items = []
        self.selected = 0
        self._pos = 0.0
        self._thumbs = {}
        self._current_shot = None  # la captura de la ventana que se reemplaza, tomada antes de abrir
        self._slide = Tween(self, self._set_pos)

    # ---------- abrir, cerrar y elegir ----------

    def toggle(self, rect):
        self.close_popout() if self.opened else self.open(rect)

    def open(self, rect):
        """`rect` = (izq, arriba, der, abajo) del hueco en px físicos."""
        started = time.perf_counter()
        g = self.map.geometry
        self.setGeometry(self.map.rect_to_logical(*rect).translated(g.x(), g.y()).toAlignedRect())
        self._thumbs.clear()
        grab = QGuiApplication.primaryScreen().grabWindow(0, self.x(), self.y(), self.width(), self.height())
        self._current_shot = None if grab.isNull() else grab  # antes de mostrar nada: es la ventana tal cual está
        self.items = self._items_fn()
        self.selected = 1 if len(self.items) > 1 and self.items[0].get("current") else 0
        self._pos = float(self.selected)
        self.opened = True
        self.setWindowOpacity(1.0)
        self.show()
        self.raise_()
        self.activateWindow()
        force_foreground(hwnd_of(self))
        self.setFocus()
        self.update()
        took = (time.perf_counter() - started) * 1000
        if took > SLOW_OPEN_MS:
            log.info("El panel de espera tardó %.0f ms en abrirse (%s ventanas)", took, len(self.items))

    def close_popout(self, refocus=True):
        if not self.opened:
            return
        self.opened = False
        self.hide()
        if refocus:
            self._invoke("wm.refocus")

    def _pick(self):
        if not self.items:
            return
        item = self.items[self.selected]
        if item.get("current"):  # la que ya está en su sitio: nada que reemplazar
            self.close_popout()
            return
        self._invoke("switcher.pick", hwnd=item["hwnd"])
        self.close_popout(refocus=False)

    def _select(self, index):
        if not self.items:
            return
        self.selected = max(0, min(index, len(self.items) - 1))
        self._slide.start(self._pos, self.selected, SLIDE_MS, QEasingCurve.OutCubic)

    def _set_pos(self, value):
        self._pos = float(value)
        self.update()

    # ---------- teclado y ratón ----------

    def keyPressEvent(self, event):
        key = event.key()
        if key in (Qt.Key_Up, Qt.Key_K):
            self._select(self.selected - 1)
        elif key in (Qt.Key_Down, Qt.Key_J):
            self._select(self.selected + 1)
        elif key in (Qt.Key_Return, Qt.Key_Enter):
            self._pick()
        elif key == Qt.Key_Escape:
            self.close_popout()
        elif key == Qt.Key_Delete and self.items and not self.items[self.selected].get("current"):
            self._invoke("wm.close_window", hwnd=self.items[self.selected]["hwnd"])
            self.items.pop(self.selected)
            self._select(min(self.selected, len(self.items) - 1))
            self.update()
        else:
            super().keyPressEvent(event)

    def wheelEvent(self, event):
        self._select(self.selected + (1 if event.angleDelta().y() < 0 else -1))

    def mouseReleaseEvent(self, event):
        if event.button() != Qt.LeftButton:
            return
        for i, (x, y, w, h) in enumerate(self._layout()):
            if QRectF(x, y, w, h).contains(event.position()):
                self.selected = i
                self._pick()
                return

    def changeEvent(self, event):
        if event.type() == QEvent.ActivationChange and self.opened and not self.isActiveWindow():
            QTimer.singleShot(BLUR_CHECK_MS, self._check_blur)
        super().changeEvent(event)

    def _check_blur(self):
        if self.opened and not self.isActiveWindow():
            self.close_popout(refocus=False)

    def closeEvent(self, event):
        event.ignore()
        self.close_popout()

    # ---------- pintura ----------

    def _pixmap(self, item):
        """La captura de una tarjeta, o None si no hay o salió vacía (negra): entonces se pinta su icono."""
        hwnd = item["hwnd"]
        if item.get("current"):
            shot = self._current_shot
            return None if shot is None or _blank(shot.toImage()) else shot
        if hwnd not in self._thumbs:
            shot = self._thumb_fn(hwnd)
            image = QImage(shot[2], shot[0], shot[1], shot[0] * 4, QImage.Format_RGB32) if shot else None
            self._thumbs[hwnd] = QPixmap.fromImage(image) if image is not None and not _blank(image) else None
        return self._thumbs[hwnd]

    def _layout(self):
        aspects = []
        for item in self.items:
            shot = self._pixmap(item)
            aspects.append(shot.width() / shot.height() if shot else DEFAULT_ASPECT)
        rects = stack_layout(aspects, self._pos, self.width(), self.height())
        return [((self.width() - w) / 2, y, w, h) for _, y, w, h in rects]  # centradas

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setRenderHint(QPainter.SmoothPixmapTransform)
        p.fillRect(self.rect(), QColor(t.plate_top))  # una placa sólida
        p.setFont(font(t))
        p.setPen(QColor(t.dim))
        p.drawText(QRectF(self.rect()).adjusted(0, 0, 0, -14), Qt.AlignHCenter | Qt.AlignBottom,
                   "↑↓ elegir  ·  Enter reemplazar  ·  Supr cerrar  ·  Esc salir")
        if len(self.items) < 2:
            p.setPen(QColor(t.ink))
            p.drawText(QRectF(self.rect()), Qt.AlignCenter, "No hay ventanas fuera de la pantalla")
            if not self.items:
                return
        for i, (item, (x, y, w, h)) in enumerate(zip(self.items, self._layout())):
            if y + h < 0 or y > self.height():
                continue
            self._paint_card(p, QRectF(x, y, w, h), item, abs(i - self._pos))

    def _paint_card(self, p, rect, item, distance):
        t = self.theme
        rect = rect.adjusted(0, 3, 0, -3)  # un respiro entre tarjetas
        radius = t.panel_radius + 4
        shape = QPainterPath()
        shape.addRoundedRect(rect, radius, radius)
        p.save()
        p.setClipPath(shape)
        p.fillRect(rect, QColor(t.capsule))  # base sólida: nada se transparenta detrás de la captura
        shot = self._pixmap(item)
        if shot:
            # recorte centrado, sin deformar la captura (se muestrea del original, nítida)
            scale = max(rect.width() / shot.width(), rect.height() / shot.height())
            cw, ch = rect.width() / scale, rect.height() / scale
            p.drawPixmap(rect, shot, QRectF((shot.width() - cw) / 2, (shot.height() - ch) / 2, cw, ch))
        else:
            side = int(min(t.icon_px * 2.4, rect.height() * 0.5))
            icon = app_icon(item.get("exe", ""), item["hwnd"], side, self.devicePixelRatioF())
            p.drawPixmap(int(rect.center().x() - side / 2), int(rect.center().y() - side / 2), icon)
        if rect.height() > 26:  # el nombre de la app, sobre un velo en la parte de abajo de la tarjeta
            label = ("ACTUAL · " if item.get("current") else "") + item["name"]
            veil = QLinearGradient(rect.left(), rect.bottom() - 40, rect.left(), rect.bottom())
            veil.setColorAt(0, QColor(0, 0, 0, 0))
            veil.setColorAt(1, QColor(0, 0, 0, 170))
            p.fillRect(QRectF(rect.left(), rect.bottom() - 40, rect.width(), 40), veil)
            p.setFont(font(t, bold=True))
            p.setPen(QColor("#ffffff"))
            p.drawText(rect.adjusted(14, 0, -14, -8), Qt.AlignLeft | Qt.AlignBottom,
                       p.fontMetrics().elidedText(label, Qt.ElideRight, int(rect.width() - 28)))
        p.restore()
        if distance < 0.5:  # la elegida: un borde fino del acento
            p.setPen(QPen(QColor(t.gold), 2))
            p.setBrush(Qt.NoBrush)
            p.drawRoundedRect(rect.adjusted(1, 1, -1, -1), radius, radius)


def _blank(image):
    """True si una captura es (casi) toda negra: PrintWindow no sabe leer algunas ventanas aceleradas."""
    step_x, step_y = max(image.width() // 8, 1), max(image.height() // 8, 1)
    for y in range(0, image.height(), step_y):
        for x in range(0, image.width(), step_x):
            c = image.pixelColor(x, y)
            if c.red() + c.green() + c.blue() > 24:
                return False
    return True

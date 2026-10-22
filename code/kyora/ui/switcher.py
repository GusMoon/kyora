"""Panel de Alt+E: las ventanas en espera de este escritorio, apiladas como en una revista.

Las capturas se apilan en vertical, sin hueco y alineadas a la izquierda. La elegida es la más ancha y queda en el
centro; las demás se estrechan cuanto más lejos están. Con ↑/↓ (o la rueda) la pila se desliza; Enter trae la
ventana al hueco enfocado, Supr la cierra y Esc sale. Sin ventanas en espera lo dice. Aparece con un fundido corto.
Es una pieza del marco: su mismo material y su borde, con las esquinas redondeadas de las ventanas.
"""
import logging
import time

from PySide6.QtCore import QEasingCurve, QEvent, QRectF, Qt, QTimer
from PySide6.QtGui import QColor, QFont, QImage, QPainter, QPainterPath, QPixmap
from PySide6.QtWidgets import QWidget

from kyora.system.win32 import force_foreground
from kyora.ui.anim import Tween
from kyora.ui.icons import app_icon
from kyora.ui.relief import frame_gradient, paint_raised_edge
from kyora.ui.win import hwnd_of, make_tool_window

log = logging.getLogger("kyora.ui")

WIDEST = 0.62  # ancho de la tarjeta elegida, como fracción del panel
FALLOFF = 0.78  # cada paso de distancia estrecha la tarjeta en este factor
DEFAULT_ASPECT = 16 / 10  # tarjetas sin captura
MAX_HEIGHT = 0.55  # ninguna tarjeta pasa de esta fracción del alto del panel
PAD = 22
FADE_MS = 90
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


def _mono(theme, px, bold=False):
    f = QFont(theme.mono_family)
    f.setStyleHint(QFont.Monospace)
    f.setPixelSize(px)
    f.setBold(bold)
    return f


class WaitingStack(QWidget):
    def __init__(self, theme, screen_map, items, thumb, invoke):
        """`items()` -> lista de {hwnd, name, title, exe}; `thumb(hwnd)` -> (ancho, alto, bytes) o None."""
        super().__init__()
        make_tool_window(self)
        self.setWindowTitle("KyoraSwitcher")
        self.setFocusPolicy(Qt.StrongFocus)
        self.theme = theme
        self.map = screen_map
        self._items_fn, self._thumb_fn, self._invoke = items, thumb, invoke
        self.opened = False
        self.items = []
        self.selected = 0
        self._pos = 0.0
        self._thumbs = {}
        self._fade = Tween(self, self.setWindowOpacity, self._finished)
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
        self.items = self._items_fn()
        self.selected, self._pos = 0, 0.0
        self.opened = True
        self.setWindowOpacity(0.0)
        self.show()
        self.raise_()
        self.activateWindow()
        force_foreground(hwnd_of(self))
        self.setFocus()
        self.update()
        self._fade.start(self.windowOpacity(), 1.0, FADE_MS, QEasingCurve.OutCubic)
        took = (time.perf_counter() - started) * 1000
        if took > SLOW_OPEN_MS:
            log.info("El panel de espera tardó %.0f ms en abrirse (%s ventanas)", took, len(self.items))

    def close_popout(self, refocus=True):
        if not self.opened:
            return
        self.opened = False
        self._fade.start(self.windowOpacity(), 0.0, FADE_MS, QEasingCurve.InCubic)
        if refocus:
            self._invoke("wm.refocus")

    def _finished(self):
        if not self.opened:
            self.hide()

    def _pick(self):
        if self.items:
            self._invoke("switcher.pick", hwnd=self.items[self.selected]["hwnd"])
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
        elif key == Qt.Key_Delete and self.items:
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

    def _pixmap(self, hwnd):
        if hwnd not in self._thumbs:
            shot = self._thumb_fn(hwnd)
            # RGB32: el cuarto byte de la captura no es alfa. fromImage copia los píxeles, así que no hace falta copy()
            self._thumbs[hwnd] = (
                QPixmap.fromImage(QImage(shot[2], shot[0], shot[1], shot[0] * 4, QImage.Format_RGB32)) if shot else None
            )
        return self._thumbs[hwnd]

    def _layout(self):
        aspects = []
        for item in self.items:
            shot = self._pixmap(item["hwnd"])
            aspects.append(shot.width() / shot.height() if shot else DEFAULT_ASPECT)
        return stack_layout(aspects, self._pos, self.width(), self.height())

    def paintEvent(self, _):
        t = self.theme
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setRenderHint(QPainter.SmoothPixmapTransform)
        # medio borde hacia dentro: así la línea oscura de fuera cabe en la ventana y no se corta
        inset = t.edge_width
        piece = QPainterPath()
        piece.addRoundedRect(QRectF(self.rect()).adjusted(inset, inset, -inset, -inset), t.panel_radius, t.panel_radius)
        p.fillPath(piece, frame_gradient(t, self.map.geometry.height(), self.y() - self.map.geometry.y()))
        paint_raised_edge(p, piece, QRectF(self.rect()), t)
        p.setClipPath(piece)  # las tarjetas y los textos no se salen de las esquinas redondeadas
        right = QRectF(self.width() * (WIDEST + 0.04), PAD, self.width() * (1 - WIDEST - 0.04) - PAD, self.height() - 2 * PAD)
        p.setPen(QColor(t.ink))
        p.setFont(_mono(t, t.small_px))
        p.drawText(right, Qt.AlignRight | Qt.AlignTop, f"EN ESPERA · {len(self.items)}")
        p.setPen(QColor(t.dim))
        p.drawText(right, Qt.AlignRight | Qt.AlignBottom, "↑↓ ELEGIR\nENTER TRAER · SUPR CERRAR\nESC SALIR")
        if not self.items:
            p.setPen(QColor(t.ink))
            p.setFont(_mono(t, t.font_px + 2))
            p.drawText(QRectF(self.rect()), Qt.AlignCenter, "No hay aplicaciones en espera")
            return
        layout = self._layout()
        for i, (item, (x, y, w, h)) in enumerate(zip(self.items, layout)):
            if y + h < 0 or y > self.height():
                continue
            self._paint_card(p, QRectF(x, y, w, h), item, abs(i - self._pos))
        x, y, w, h = layout[self.selected]
        item = self.items[self.selected]
        label = QRectF(right.left(), y, right.width(), h)
        p.setPen(QColor(t.ink))
        p.setFont(_mono(t, t.small_px + 1, bold=True))
        name = p.fontMetrics().elidedText(item["name"].upper(), Qt.ElideRight, int(label.width()))
        p.drawText(label.adjusted(0, 0, 0, -h / 2 - 2), Qt.AlignRight | Qt.AlignBottom, name)
        p.setPen(QColor(t.dim))
        p.setFont(_mono(t, t.small_px))
        title = p.fontMetrics().elidedText((item["title"] or "").upper(), Qt.ElideRight, int(label.width()))
        p.drawText(label.adjusted(0, h / 2 + 2, 0, 0), Qt.AlignRight | Qt.AlignTop, title)

    def _paint_card(self, p, rect, item, distance):
        t = self.theme
        p.save()
        p.setClipRect(rect, Qt.IntersectClip)
        shot = self._pixmap(item["hwnd"])
        if shot:
            # recorte centrado, sin deformar la captura. Se dibuja directamente del original: Qt la muestrea a la
            # resolución real de la pantalla (nítida con escala) y no hay que reescalarla en cada fotograma
            scale = max(rect.width() / shot.width(), rect.height() / shot.height())
            cw, ch = rect.width() / scale, rect.height() / scale
            p.drawPixmap(rect, shot, QRectF((shot.width() - cw) / 2, (shot.height() - ch) / 2, cw, ch))
        else:
            p.fillRect(rect, QColor(t.capsule))
            side = int(min(48, rect.height() * 0.5))
            icon = app_icon(item.get("exe", ""), item["hwnd"], side, self.devicePixelRatioF())
            p.drawPixmap(int(rect.center().x() - side / 2), int(rect.center().y() - side / 2), icon)
        if distance > 0.01:  # las que no están elegidas se apagan un poco
            p.fillRect(rect, QColor(0, 0, 0, round(90 * min(distance, 1.5))))
        p.restore()

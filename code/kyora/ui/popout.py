"""Paneles que sobresalen del marco: de la barra (apagar, wifi, Bluetooth, calendario) o del borde de arriba (el panel
de Archivos, Sistema y Kyora).

Los de la barra se abren al pasar el ratón (sin quitar el foco a nadie) y se cierran en cuanto el ratón se va; si se
escribe en ellos (la contraseña del wifi) se quedan hasta perder el foco. Abiertos con el teclado (Win+X) toman el foco.

Como el buscador, son ventanas transparentes de tamaño fijo: lo que se anima es la pieza que se pinta dentro, que
crece desde el borde con curvas cóncavas donde se une al marco. La forma se construye colgando del borde de arriba
(`popout_paths`, coordenadas u a lo largo del borde y v hacia fuera) y se gira al borde que toca.

La animación no mueve los widgets: al abrir y al cerrar se toma una imagen del contenido (`body.grab()`) y se pinta
recortada a la pieza, deslizándose con ella como un cajón y apareciendo con un fundido suave. Así es fluida aunque el
contenido sea grande (el panel de arriba).
"""
import math

from PySide6.QtCore import QEasingCurve, QEvent, QPoint, QRectF, Qt, QTimer
from PySide6.QtGui import QCursor, QPainter, QPainterPath, QPixmap, QRegion, QTransform
from PySide6.QtWidgets import QApplication, QLineEdit, QWidget

from kyora.system.win32 import force_foreground
from kyora.ui.anim import Tween
from kyora.ui.relief import frame_gradient, paint_raised_edge
from kyora.ui.shapes import (
    corner_popout_paths,
    popout_paths,
    rotate_to_right,
    transpose,
)
from kyora.ui.win import hwnd_of, make_tool_window

BLUR_CHECK_MS = 200
BAR_OVERLAP = 3  # px que la pieza pisa la barra: tapa su filete y la unión no se nota
LEAVE_CHECK_MS = 30  # cada cuánto se mira si el ratón se fue (se cierra al instante, sin esperar)
FADE_FROM, FADE_TO = 0.15, 0.7  # tramo de la apertura en el que el contenido pasa de invisible a visible


def grab_clear(widget):
    """Imagen de un widget y sus hijos sobre fondo transparente (grab() pondría el fondo gris de ventana)."""
    dpr = widget.devicePixelRatioF()
    shot = QPixmap(widget.size() * dpr)
    shot.setDevicePixelRatio(dpr)
    shot.fill(Qt.transparent)
    widget.render(shot, QPoint(), QRegion(), QWidget.DrawChildren)
    return shot


def _smooth(x):
    """Rampa suave de 0 a 1 (sin esquinas al empezar ni al acabar)."""
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


class EdgePopout(QWidget):
    """Pieza que sale de `edge` ("bar": del borde derecho de la barra; "right": del borde derecho del marco;
    "top": del borde de arriba, centrada en el hueco).

    `depth` es lo que sobresale y `length` lo que mide a lo largo del borde (px lógicos). Las subclases llenan
    `self.body` (ya colocado dentro de la pieza, con `pad` de margen) y pueden redefinir `escape()`. `along` permite una
    ventana más larga que la pieza (el panel de la barra, que se mueve a lo largo de ella).
    """

    def __init__(self, theme, screen_map, edge, depth, length, title, pad=14, along=None, extra=0):
        super().__init__()
        make_tool_window(self)
        self.setWindowTitle(title)
        self.theme, self.map, self.edge = theme, screen_map, edge
        self.depth, self.length, self.pad = depth, length, pad
        self.hover = False  # abierta al pasar el ratón: no toma el foco y se cierra cuando el ratón se va
        self.opened = False
        self._progress = 0.0
        t = theme
        self._joint = t.joint_radius
        self._root = BAR_OVERLAP if edge == "bar" else t.frame_width  # franja del marco que la pieza incluye
        self._shadow = math.ceil(t.edge_shadow_size) + 4
        self._along = along or round(length + 2 * (self._joint + 4))
        self._thick = round(self._root + depth + self._shadow + extra)
        if edge == "top":
            self.resize(self._along, self._thick)  # cuelga del borde de arriba: crece hacia abajo
        else:
            self.resize(self._thick, self._along)  # los bordes verticales: la pieza crece en horizontal
        self.body = QWidget(self)
        self.body.hide()
        self._shot = None  # imagen del contenido mientras se anima
        self._anim = Tween(self, self._set_progress, self._finished)
        self._leave = QTimer(self)  # en modo `hover`, mira si el ratón se fue de la pieza y de su botón
        self._leave.setInterval(LEAVE_CHECK_MS)
        self._leave.timeout.connect(self._check_leave)
        self._anchor_rect = None

    # ---------- geometría: se piensa colgando del borde de arriba (u a lo largo del borde, v hacia fuera) ----------

    def piece(self):
        """(inicio, fin, fondo, esquina) de la pieza ya abierta, en u/v. `esquina` = apoyada en el marco de abajo."""
        center = self._along / 2
        return center - self.length / 2, center + self.length / 2, self.depth, False

    def _to_widget(self):
        if self.edge == "top":
            return QTransform()  # ya cuelga del borde de arriba
        if self.edge == "bar":
            return QTransform(0, 1, 1, 0, 0, 0)  # (u, v) -> (v, u)
        return QTransform(0, 1, -1, 0, self.width(), 0)  # (u, v) -> (ancho - v, u)

    def _body_uv(self, start, end, depth):
        return QRectF(start + self.pad, self._root + self.pad, end - start - 2 * self.pad, depth - 2 * self.pad)

    def body_rect(self, piece=None):
        start, end, depth, _ = piece or self.piece()
        return self._to_widget().mapRect(self._body_uv(start, end, depth))

    def piece_rect(self):
        """Rectángulo global que ocupa ahora la pieza (con sus curvas): para saber si el ratón sigue encima."""
        start, end, depth, corner = self.piece()
        uv = QRectF(start - self._joint, 0, end - start + 2 * self._joint, self._root + depth + (self._joint if corner else 0))
        r = self._to_widget().mapRect(uv).toAlignedRect()
        return r.translated(self.pos())

    def place(self, anchor):
        """Coloca la ventana: `anchor` es la y (lógica, de pantalla) del centro para "bar"; para "right", None (centro)."""
        g = self.map.geometry
        t = self.theme
        lo, hi = g.y() + t.frame_width, g.y() + g.height() - t.frame_width - self._along
        if self.edge == "top":
            hole_center = g.x() + t.bar_width + (g.width() - t.bar_width - t.frame_width) / 2
            self.move(round(hole_center - self._along / 2), g.y())
        elif self.edge == "bar":
            y = g.y() + g.height() / 2 - self._along / 2 if anchor is None else anchor - self._along / 2
            self.move(round(g.x() + t.bar_width - BAR_OVERLAP), round(min(max(y, lo), hi)))
        else:
            y = g.y() + (g.height() - self._along) / 2
            self.move(round(g.x() + g.width() - self._thick), round(min(max(y, lo), hi)))

    # ---------- abrir y cerrar ----------

    def toggle(self, anchor=None):
        self.close_popout() if self.opened else self.open(anchor)

    def open(self, anchor=None, hover_zone=None):
        """Con `hover_zone` (QRect global de la zona de los botones) se abre al pasar el ratón: sin tomar el foco y
        cerrándose en cuanto el ratón sale de la pieza y de esa zona. Sin ella toma el foco (abierta con el teclado)."""
        if self.opened:
            if hover_zone is None and self.hover:  # estaba por el ratón y ahora la pide el teclado: toma el foco
                self.hover = False
                self._leave.stop()
                self._take_focus()
            elif hover_zone is not None:
                self._anchor_rect = hover_zone
            return
        self.opened = True
        self.hover = hover_zone is not None
        self._anchor_rect = hover_zone
        self.place(anchor)
        self.before_open()
        self.show()
        self.raise_()
        self._shot = self.snapshot()
        if self.hover:
            self._leave.start()
        else:
            self._take_focus()
        t = self.theme
        self._anim.start(self._progress, 1.0, int(t.open_ms * (1 - self._progress)), QEasingCurve.OutQuint)

    def snapshot(self):
        """Imagen del contenido colocado en su sitio final; después se oculta (lo que se anima es la imagen)."""
        self.body.setGeometry(self.body_rect().toAlignedRect())
        self.body.show()
        layout = self.body.layout()
        if layout is not None:
            layout.activate()
        shot = grab_clear(self.body)
        self.body.hide()
        return shot

    def close_popout(self):
        if not self.opened:
            return
        self.opened = False
        self._leave.stop()
        if self.body.isVisible():
            self._shot = grab_clear(self.body)
            self.body.hide()
        self._anim.start(self._progress, 0.0, int(self.theme.close_ms * max(self._progress, 0.2)), QEasingCurve.InOutCubic)
        self.after_close()

    def _take_focus(self):
        self.activateWindow()
        force_foreground(hwnd_of(self))
        self.focus_first()

    def before_open(self):
        """Para las subclases: refrescar el contenido justo antes de abrir."""

    def after_close(self):
        """Para las subclases: lo que haya que hacer al cerrar (devolver el foco…)."""

    def focus_first(self):
        self.setFocus()

    def escape(self):
        """Esc: por defecto cierra. El panel de arriba lo usa para cerrar antes la vista previa o la búsqueda."""
        self.close_popout()

    def _set_progress(self, value):
        self._progress = float(value)
        self.update()

    def _finished(self):
        if self.opened:
            self._shot = None
            self.body.setGeometry(self.body_rect().toAlignedRect())
            self.body.show()  # ya quieto: el contenido de verdad sustituye a la imagen
            if not self.hover:
                self.focus_first()
        else:
            self._shot = None
            self.hide()

    # ---------- teclado, foco y ratón ----------

    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Escape:
            self.escape()
        else:
            super().keyPressEvent(event)

    def _owns_focus(self):
        """True si el foco sigue en la pieza o en un menú o diálogo suyo."""
        if QApplication.activePopupWidget() is not None or QApplication.activeModalWidget() is not None:
            return True
        active = QApplication.activeWindow()
        while active is not None:
            if active is self:
                return True
            active = active.parentWidget()
        return False

    def changeEvent(self, event):
        if event.type() == QEvent.ActivationChange and self.opened and not self.isActiveWindow():
            QTimer.singleShot(BLUR_CHECK_MS, self._check_blur)
        super().changeEvent(event)

    def _check_blur(self):
        if not self.opened or self._owns_focus():
            return
        if not self.hover or not self._mouse_inside():  # la de ratón solo se cierra si además el ratón ya no está
            self.close_popout()

    def _typing(self):
        """True si se está escribiendo en la pieza (la contraseña del wifi): entonces no se cierra al irse el ratón."""
        focus = QApplication.focusWidget()
        return isinstance(focus, QLineEdit) and self.isActiveWindow() and self.isAncestorOf(focus)

    def _mouse_inside(self):
        pos = QCursor.pos()
        return self.piece_rect().contains(pos) or (self._anchor_rect is not None and self._anchor_rect.contains(pos))

    def _check_leave(self):
        if self._mouse_inside() or self._typing() or QApplication.activePopupWidget() is not None:
            return
        self.close_popout()

    def closeEvent(self, event):
        """Alt+F4 sobre la pieza solo la repliega."""
        event.ignore()
        self.close_popout()

    # ---------- pintura ----------

    def _paths(self, start, end, depth, corner):
        """(relleno, contorno, zona donde se pinta) en coordenadas de la ventana."""
        t = self.theme
        if corner:
            fill, outline = corner_popout_paths(self._along, self._root, start, end, depth, self._joint, t.corner_radius)
            span_uv = QRectF(start - self._joint, 0, self._along - start + self._joint, self._root + depth + self._joint)
        else:
            fill, outline = popout_paths(self._along, self._root, (start + end) / 2, end - start, depth, self._joint,
                                         t.corner_radius)
            reach = (end - start) / 2 + min(self._joint, depth / 2)
            center = (start + end) / 2
            span_uv = QRectF(center - reach, 0, 2 * reach, self._thick)
        # solo se pinta la pieza y sus curvas: a los lados se ve el marco (o la barra) de debajo, con su borde
        clip = QPainterPath()
        clip.addRect(span_uv)
        fill = fill.intersected(clip)
        if self.edge == "bar":
            fill, outline = transpose(fill), transpose(outline)
        elif self.edge == "right":
            fill, outline = rotate_to_right(fill, self.width()), rotate_to_right(outline, self.width())
        return fill, outline, self._to_widget().mapRect(span_uv)

    def paint_piece(self, p, start, end, depth, corner):
        fill, outline, span = self._paths(start, end, depth, corner)
        g = self.map.geometry
        p.fillPath(fill, frame_gradient(self.theme, g.height(), self.y() - g.y()))
        paint_raised_edge(p, fill, span, self.theme, contour=outline, shadow=True)
        return fill

    def paint_shot(self, p, shot, piece, slide, opacity, clip):
        """La imagen del contenido en la pieza: desplazada `slide` px hacia el borde y con `opacity`."""
        if shot is None or opacity <= 0.01:
            return
        start, end, depth, _ = piece
        uv = self._body_uv(start, end, depth)
        uv.translate(0, -slide)
        p.save()
        p.setClipPath(clip)
        p.setOpacity(opacity)
        p.drawPixmap(self._to_widget().mapRect(uv), shot, QRectF(shot.rect()))
        p.restore()

    def paintEvent(self, _):
        e = min(max(self._progress, 0.0), 1.0)
        start, end, depth, corner = self.piece()
        if depth * e <= 0:
            return
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setRenderHint(QPainter.SmoothPixmapTransform)
        fill = self.paint_piece(p, start, end, depth * e, corner)
        # el contenido llega con la pieza (como un cajón) y aparece con un fundido suave
        self.paint_shot(p, self._shot, (start, end, depth, corner), depth * (1 - e), _smooth(
            (e - FADE_FROM) / (FADE_TO - FADE_FROM)), fill)

"""El panel de la barra: una sola pieza que sale de la barra y se transforma de una página a otra.

Las páginas (apagar, wifi, Bluetooth y calendario) se abren al pasar el ratón por su icono. Si el panel ya está
abierto y el ratón pasa a otro icono, la pieza no se cierra: se desliza hasta el icono nuevo, toma el tamaño de su
página y el contenido cambia con un fundido cruzado. Cerca del fondo, la pieza se apoya en el marco de abajo con la
esquina abierta (ver `corner_popout_paths`).
"""
from PySide6.QtCore import QEasingCurve, Signal
from PySide6.QtGui import QPainter
from PySide6.QtWidgets import QStackedLayout, QWidget

from kyora.core.animation import lerp
from kyora.ui.anim import Tween
from kyora.ui.popout import BAR_OVERLAP, EdgePopout, grab_clear

CORNER_SNAP = 28  # px antes de la esquina del hueco a partir de los cuales la pieza se apoya en el marco de abajo


def dock_span(anchor, length, hole_top, hole_bottom, joint, snap=CORNER_SNAP):
    """(inicio, fin, esquina) de la pieza a lo largo de la barra, centrada en `anchor` si cabe.

    Si llegaría a la esquina de abajo, se apoya en el marco de abajo (`esquina` = True); arriba no pasa del hueco.
    """
    start = anchor - length / 2
    if start + length + joint + snap >= hole_bottom:
        return hole_bottom - length, hole_bottom, True
    start = max(start, hole_top + joint)
    return start, start + length, False


class DockPage(QWidget):
    """Una página del panel de la barra. `size` = (fondo, largo) en px lógicos."""

    size = (320, 300)
    close_requested = Signal()

    def activate(self):
        """Justo antes de mostrarse: refrescar lo que haga falta."""

    def focus_first(self):
        self.setFocus()


class BarDock(EdgePopout):
    def __init__(self, theme, screen_map, pages):
        g = screen_map.geometry
        depth = max(page.size[0] for page in pages.values())
        super().__init__(theme, screen_map, "bar", depth=depth, length=g.height(), title="KyoraDock",
                         along=g.height(), extra=theme.joint_radius)
        self.pages = pages
        self.stack = QStackedLayout(self.body)
        for page in pages.values():
            self.stack.addWidget(page)
            page.close_requested.connect(self.close_popout)
        self.name = None
        self._piece = (0.0, 0.0, 0.0, False)
        self._from = self._to = None
        self._old_shot = self._new_shot = None
        self._mix = 1.0
        self._morph = Tween(self, self._set_mix, self._morphed)

    # ---------- geometría ----------

    def piece(self):
        return self._piece

    def place(self, anchor):
        g = self.map.geometry
        self.move(round(g.x() + self.theme.bar_width - BAR_OVERLAP), g.y())  # la ventana cubre todo el alto

    def _target(self, name, anchor_y):
        t = self.theme
        depth, length = self.pages[name].size
        hole_top, hole_bottom = t.frame_width, self.map.geometry.height() - t.frame_width
        start, end, corner = dock_span(anchor_y - self.map.geometry.y(), length, hole_top, hole_bottom, t.joint_radius)
        return start, end, depth, corner

    # ---------- mostrar una página ----------

    def show_page(self, name, anchor_y, zone=None):
        """Abre (o transforma) el panel con la página `name` junto a la y `anchor_y`. Sin `zone`, con el teclado."""
        target = self._target(name, anchor_y)
        page = self.pages[name]
        if not self.opened:
            self.name = name
            self.stack.setCurrentWidget(page)
            self._piece = target
            self._mix = 1.0
            page.activate()
            self.open(anchor_y, zone)
            return
        if zone is not None:
            self._anchor_rect = zone
        else:
            self.open(anchor_y, None)  # ya abierta por el ratón y ahora la pide el teclado: toma el foco
        if name == self.name:
            return
        # ya abierta en otra página: la pieza se transforma hacia la nueva
        self._old_shot = grab_clear(self.body) if self.body.isVisible() else self._shot
        self._anim.stop()
        self._progress = 1.0
        self._shot = None
        self.name = name
        page.activate()
        self.stack.setCurrentWidget(page)
        self._from, self._to = self._piece, target
        self._piece = target
        self._new_shot = self.snapshot()
        self._piece = self._from
        self._morph.start(0.0, 1.0, self.theme.morph_ms, QEasingCurve.OutCubic)

    def _set_mix(self, value):
        self._mix = float(value)
        a, b = self._from, self._to
        corner = b[3] if self._mix > 0.5 else a[3]
        self._piece = (lerp(a[0], b[0], self._mix), lerp(a[1], b[1], self._mix), lerp(a[2], b[2], self._mix), corner)
        self.update()

    def _morphed(self):
        self._piece = self._to
        self._old_shot = self._new_shot = None
        self._mix = 1.0
        if self.opened:
            self.body.setGeometry(self.body_rect().toAlignedRect())
            self.body.show()
            if not self.hover:
                self.focus_first()
        self.update()

    def focus_first(self):
        if self.name:
            self.pages[self.name].focus_first()

    def escape(self):
        self.close_popout()

    def close_popout(self):
        if self._morph.running():  # cerrar a mitad de una transformación: se queda en la página nueva
            self._morph.stop()
            self._morphed()
        super().close_popout()

    # ---------- pintura ----------

    def paintEvent(self, event):
        if self._new_shot is None:
            return super().paintEvent(event)
        p = QPainter(self)
        p.setRenderHint(QPainter.Antialiasing)
        p.setRenderHint(QPainter.SmoothPixmapTransform)
        start, end, depth, corner = self._piece
        fill = self.paint_piece(p, start, end, depth, corner)
        # cada contenido va pegado al principio de la pieza, que se mueve; uno se apaga y el otro se enciende
        old = (start, start + (self._from[1] - self._from[0]), self._from[2], corner)
        new = (start, start + (self._to[1] - self._to[0]), self._to[2], corner)
        self.paint_shot(p, self._old_shot, old, 0, 1 - self._mix, fill)
        self.paint_shot(p, self._new_shot, new, 0, self._mix, fill)

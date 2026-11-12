"""Un panel suelto que cuelga de un borde de la pantalla y se transforma de una página a otra.

Las páginas se abren desde la fila de arriba (panel superior). Si el panel ya está abierto y se pide otra página, la
pieza no se cierra: cambia de tamaño hasta el de la página nueva y el contenido cambia con un fundido cruzado.
"""
from PySide6.QtCore import QEasingCurve, Signal
from PySide6.QtGui import QPainter
from PySide6.QtWidgets import QStackedLayout, QWidget

from kyora.core.animation import lerp
from kyora.ui.anim import Tween
from kyora.ui.popout import EdgePopout, grab_clear


class DockPage(QWidget):
    """Una página del panel. `size` = (alto, ancho) de la pieza en px lógicos (en un panel lateral, (fondo, largo))."""

    size = (320, 300)
    close_requested = Signal()

    def activate(self):
        """Justo antes de mostrarse: refrescar lo que haga falta."""

    def focus_first(self):
        self.setFocus()


class PageDock(EdgePopout):
    page_changed = Signal(str)  # la página abierta ("" al cerrar)

    def __init__(self, theme, screen_map, pages, edge="top", title="KyoraDock", pad=8, extra=0):
        # en el borde de arriba `size` es (alto, ancho); en el lateral, (fondo, largo): los dos casos son (v, u) al revés
        depth = max(page.size[0] for page in pages.values())
        length = max(page.size[1] for page in pages.values())
        super().__init__(theme, screen_map, edge, depth=depth, length=length, title=title, free=True, pad=pad, extra=extra)
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

    def _target(self, name):
        depth, length = self.pages[name].size
        center = self._along / 2
        return center - length / 2, center + length / 2, depth, False

    # ---------- mostrar una página ----------

    def show_page(self, name, zone=None):
        """Abre (o transforma) el panel con la página `name`. Con `zone` (zona global del ratón) se abre por el ratón;
        sin ella, con el teclado y tomando el foco."""
        target = self._target(name)
        page = self.pages[name]
        if not self.opened:
            self.name = name
            self.stack.setCurrentWidget(page)
            self._piece = target
            self._mix = 1.0
            page.activate()
            self.open(None, zone)
            self.page_changed.emit(name)
            return
        if zone is not None:
            self._anchor_rect = zone
        else:
            self.open(None, None)  # ya abierta por el ratón y ahora la pide el teclado: toma el foco
        if name == self.name:
            return
        # ya abierta en otra página: la pieza se transforma hacia la nueva
        self._old_shot = grab_clear(self.body) if self.body.isVisible() else self._shot
        self._anim.stop()
        self._progress = 1.0
        self._shot = None
        self.name = name
        self.page_changed.emit(name)
        page.activate()
        self.stack.setCurrentWidget(page)
        self._from, self._to = self._piece, target
        self._piece = target
        self._new_shot = self.snapshot()
        self._piece = self._from
        self._morph.start(0.0, 1.0, self.theme.morph_ms, QEasingCurve.OutCubic)

    def switch_now(self, name):
        """Cambia de página al instante: sin transformar la pieza ni sacar capturas de las dos páginas (es lo que
        cuesta). Lo usa el panel de arriba al pasar el cursor por un icono, que tiene que abrirse sin demora."""
        if not self.opened:
            return self.show_page(name)
        if name == self.name:
            return
        self._morph.stop()
        self._anim.stop()
        self._progress, self._shot, self._old_shot, self._new_shot, self._mix = 1.0, None, None, None, 1.0
        self.name = name
        self.page_changed.emit(name)
        self.pages[name].activate()
        self.stack.setCurrentWidget(self.pages[name])
        self._piece = self._target(name)
        self.body.setGeometry(self.body_rect().toAlignedRect())
        self.body.show()
        self.update()

    def _set_mix(self, value):
        self._mix = float(value)
        a, b = self._from, self._to
        self._piece = (lerp(a[0], b[0], self._mix), lerp(a[1], b[1], self._mix), lerp(a[2], b[2], self._mix), False)
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
        was_open = self.opened
        super().close_popout()
        if was_open:
            self.page_changed.emit("")

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

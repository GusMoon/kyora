"""Gestor de ventanas de Kyora: cada escritorio es un mosaico de hasta 3 ventanas.

El mosaico está siempre activo: las ventanas nuevas entran solas (las 3 primeras visibles y el resto en espera, en el
panel izquierdo); una ventana nueva ocupa el sitio de la que tiene el foco. Cada escritorio guarda su propio mosaico,
su lista de espera y su reparto; al cambiar de escritorio la pantalla se desliza.

No conoce Win32: habla con un objeto `system` (ver kyora/system/win32.py), lo que permite probarlo con un sistema
falso. Todo el estado vive bajo un único bloqueo.
"""
import threading
import time
from dataclasses import dataclass, field

from kyora.core.actions import ActionError
from kyora.core.drop import ZONES, plan, zone_at
from kyora.core.layout import (
    MAX_VISIBLE,
    Rect,
    adjust_ratios,
    compute_slots,
    fit_ratios,
    neighbor,
    slide_offset,
)

LAUNCH_WINDOW_SECONDS = 15  # tras abrir una app desde la búsqueda (se anota; la ventana nueva ya ocupa el sitio de la enfocada)
MAX_THUMBNAILS = 12  # capturas de ventanas guardadas para el panel de espera (cada una ocupa MB: pocas)
THUMB_FRESH_SECONDS = 5.0  # una captura más reciente que esto se reutiliza al ocultar la ventana
SHOW_GRACE_SECONDS = 1.0  # tras mostrar una ventana no se la da por desaparecida enseguida
DIRECTIONS = ("left", "right", "up", "down")
RESIZE_STEP = 0.05  # fracción del espacio que se mueve una división con el teclado
RESIZE_THRESHOLD = 8  # píxeles: menos que esto al arrastrar un borde no cuenta como cambio de tamaño
MIN_SIZE_TOLERANCE = 2  # píxeles: una ventana que queda más grande que su hueco por más que esto tiene tamaño mínimo
# giro de la ventana grande: arriba, derecha, abajo, izquierda (sin espejo la principal es la primera mitad)
ROTATION = (("rows", False), ("columns", True), ("rows", True), ("columns", False))
# Win+Alt+flecha sobre una ventana del mosaico: dónde queda la ventana grande
ARRANGE = {"up": ("rows", False), "right": ("columns", True), "down": ("rows", True), "left": ("columns", False)}


@dataclass
class Desktop:
    name: str
    tiled: list = field(default_factory=list)  # ventanas del mosaico (máx. 3), la principal primero
    waiting: list = field(default_factory=list)  # aparcadas o minimizadas: ocultas hasta que se pidan
    orientation: str = "columns"
    mirrored: bool = False
    ratio: float = 0.5  # espacio de la ventana principal
    ratio2: float = 0.5  # espacio de la primera ventana del par apilado
    last_focus: int = 0
    zoomed: int = 0  # ventana en grande sobre todo el hueco, o 0

    def windows(self):
        return self.tiled + self.waiting


class WindowManager:
    def __init__(self, system, config, notify=None, clock=time.monotonic):
        self.sys = system
        self.cfg = config
        self.notify = notify or (lambda: None)
        self.clock = clock
        self.lock = threading.RLock()
        self.desktops = [Desktop("1")]
        self.active = 0
        self.floating = set()
        self._hidden = set()  # ventanas que ocultó Kyora; las que se ocultan solas no cuentan
        self._shown_at = {}
        self._launch_until = 0.0
        self._thumb_at = {}  # hwnd -> cuándo se tomó su captura
        self._thumbs = {}  # hwnd -> (ancho, alto, bytes BGRX) de la última vez que se vio antes de ocultarse
        self._min_size = {}  # hwnd -> (ancho, alto) mínimos de las apps que no se dejan encoger (0 = sin mínimo)
        self._booting = False  # al arrancar, las ventanas que ya había se colocan sin animación

    # ---------- utilidades internas ----------

    def _current(self):
        return self.desktops[self.active]

    def _tracked(self):
        return {h for d in self.desktops for h in d.windows()}

    def _area(self):
        """Pantalla donde viven las ventanas (menos los márgenes `insets` si los hay: sin marco son cero)."""
        a = self.sys.work_area()
        left, top, right, bottom = self.cfg.get("insets", (0, 0, 0, 0))
        return Rect(a.left + left, a.top + top, a.right - right, a.bottom - bottom)

    def _outer(self, n):
        return self.cfg["outer_gap"] if n <= 1 else self.cfg.get("outer_gap_multi", self.cfg["outer_gap"])

    def _ratios(self, desktop):
        """Reparto del mosaico: el del usuario, movido lo justo para que ninguna app quede por debajo de su mínimo.

        No se guarda: cuando la app con mínimo se va, el mosaico vuelve al reparto del usuario.
        """
        n = len(desktop.tiled)
        return fit_ratios(
            n, self._area(), desktop.orientation, self.cfg["gap"], self._outer(n), desktop.ratio, desktop.ratio2,
            [self._min_size.get(h) for h in desktop.tiled],
        )

    def _slots(self, desktop):
        """Huecos del mosaico en pantalla, sin contar la ventana en grande (las direcciones y el reparto se calculan
        con estos)."""
        n = len(desktop.tiled)
        return compute_slots(
            n, self._area(), desktop.orientation, desktop.mirrored,
            self.cfg["gap"], self._outer(n), *self._ratios(desktop),
        )

    def _rects(self, desktop):
        """Dónde está cada ventana del mosaico: la ventana en grande ocupa todo el hueco."""
        slots = self._slots(desktop)
        if desktop.zoomed not in desktop.tiled:
            desktop.zoomed = 0
            return slots
        full = compute_slots(1, self._area(), gap=self.cfg["gap"], outer=self._outer(len(desktop.tiled)))[0]
        return [full if hwnd == desktop.zoomed else rect for hwnd, rect in zip(desktop.tiled, slots)]

    def _on_screen(self, desktop):
        """Las ventanas que se ven en la pantalla: las del mosaico."""
        return list(desktop.tiled)

    def _focused(self):
        cur = self._current()
        fg = self.sys.foreground()
        if fg in cur.tiled:
            cur.last_focus = fg
            return fg
        if cur.last_focus in cur.tiled:
            return cur.last_focus
        return cur.tiled[0] if cur.tiled else 0

    def _promote(self, desktop, count):
        """Sube ventanas de la espera al mosaico (sin las minimizadas) mientras haya hueco."""
        for _ in range(count):
            if len(desktop.tiled) >= MAX_VISIBLE:
                return
            candidate = next((h for h in desktop.waiting if not self.sys.is_minimized(h)), None)
            if candidate is None:
                return
            desktop.waiting.remove(candidate)
            desktop.tiled.append(candidate)

    def _place_in(self, desktop, hwnd):
        """Una ventana llega a otro escritorio (al cerrar uno o al enviarla): al mosaico si cabe; si no, a la espera."""
        (desktop.tiled if len(desktop.tiled) < MAX_VISIBLE else desktop.waiting).append(hwnd)

    def _forget(self, desktop, hwnd):
        """Saca una ventana de las listas de un escritorio (sin tocar la ventana)."""
        for group in (desktop.tiled, desktop.waiting):
            if hwnd in group:
                group.remove(hwnd)

    def _signature(self):
        return (
            self.active,
            tuple(
                (d.name, tuple(d.tiled), tuple(d.waiting), d.orientation, d.mirrored, d.ratio, d.ratio2, d.zoomed)
                for d in self.desktops
            ),
        )

    def _apply(self):
        """Deja el sistema como dice el estado: coloca lo que se ve y después oculta lo que sale.

        Se muestra antes de ocultar para que, al cambiar de escritorio, no se vea el fondo entre medias. Las
        ventanas se colocan al instante en su hueco: sin capturas estiradas ni animaciones que deformen su contenido.
        """
        cur = self._current()
        for _ in range(2):  # si una app resulta no dejarse encoger, se reparte otra vez con su mínimo
            learned = False
            for hwnd, rect in zip(cur.tiled, self._rects(cur)):
                if not self.sys.is_shown(hwnd):
                    self._shown_at[hwnd] = self.clock()
                    self.sys.show(hwnd)
                self._hidden.discard(hwnd)
                learned |= self._learn_minimum(hwnd, rect, self.sys.place(hwnd, rect))
            if not learned:
                break
        raise_ = getattr(self.sys, "raise_", None)
        if cur.zoomed and raise_:
            raise_(cur.zoomed)  # la ventana en grande queda por encima de las demás, sin robar el foco
        for i, desktop in enumerate(self.desktops):
            for hwnd in desktop.waiting if i == self.active else desktop.windows():
                if self.sys.is_shown(hwnd):
                    self._remember(hwnd)  # la captura se toma mientras todavía se ve (panel izquierdo y escritorios)
                    self.sys.hide(hwnd)
                self._hidden.add(hwnd)
        flush = getattr(self.sys, "flush", None)
        if flush:
            flush()  # el registro de ventanas ocultas se guarda una vez por pasada

    def _learn_minimum(self, hwnd, wanted, actual):
        """Si la ventana quedó más grande que su hueco, ese es su tamaño mínimo. True si se aprendió algo nuevo."""
        if actual is None:
            return False
        old = self._min_size.get(hwnd, (0, 0))
        new = (
            max(old[0], actual.width) if actual.width > wanted.width + MIN_SIZE_TOLERANCE else old[0],
            max(old[1], actual.height) if actual.height > wanted.height + MIN_SIZE_TOLERANCE else old[1],
        )
        if new == old:
            return False
        self._min_size[hwnd] = new
        return True

    def _remember(self, hwnd):
        """Guarda una captura de la ventana (para el panel izquierdo y los escritorios) si el sistema sabe hacerlas."""
        capture = getattr(self.sys, "capture", None)
        now = self.clock()
        if hwnd in self._thumbs and now - self._thumb_at.get(hwnd, -1e9) < THUMB_FRESH_SECONDS:
            return  # PrintWindow cuesta decenas de ms por ventana: con una captura reciente no se repite
        shot = capture(hwnd) if capture else None
        if shot:
            self._thumbs.pop(hwnd, None)
            self._thumbs[hwnd] = shot
            self._thumb_at[hwnd] = now
            while len(self._thumbs) > MAX_THUMBNAILS:
                self._thumbs.pop(next(iter(self._thumbs)))

    def thumbnail(self, hwnd):
        """Última captura de una ventana, o None."""
        with self.lock:
            return self._thumbs.get(hwnd)

    def _changed(self):
        self._apply()
        self.notify()

    # ---------- sincronización con Windows ----------

    def sync(self):
        """Reconcilia el estado con las ventanas reales (nuevas, cerradas, minimizadas)."""
        with self.lock:
            before = self._signature()
            now = self.clock()

            for desktop in self.desktops:
                dead = [h for h in desktop.tiled if not self.sys.is_alive(h)]
                desktop.tiled = [h for h in desktop.tiled if h not in dead]
                desktop.waiting = [h for h in desktop.waiting if self.sys.is_alive(h)]
                self._promote(desktop, len(dead))
            self.floating = {h for h in self.floating if self.sys.is_alive(h)}
            self._hidden &= self._tracked()
            self._thumbs = {h: s for h, s in self._thumbs.items() if h in self._tracked()}
            self._min_size = {h: m for h, m in self._min_size.items() if self.sys.is_alive(h)}

            cur = self._current()
            gone, keep = 0, []
            for hwnd in cur.tiled:
                if self.sys.is_minimized(hwnd):
                    cur.waiting.append(hwnd)
                    gone += 1
                elif hwnd in self._hidden:
                    keep.append(hwnd)  # la ocultó Kyora y _apply la va a mostrar
                elif not self.sys.is_manageable(hwnd) and now - self._shown_at.get(hwnd, -1e9) > SHOW_GRACE_SECONDS:
                    gone += 1
                else:
                    keep.append(hwnd)
            cur.tiled = keep
            self._promote(cur, gone)

            tracked = self._tracked()
            for hwnd in self.sys.list_windows():
                if hwnd in tracked or hwnd in self.floating:
                    continue
                self._join_mosaic(cur, hwnd)

            fg = self.sys.foreground()
            if fg in cur.tiled:
                cur.last_focus = fg
                if cur.zoomed and fg != cur.zoomed:
                    cur.zoomed = 0  # el foco pasó a otra ventana del mosaico: la grande vuelve a su sitio

            self._apply()
            if self._signature() != before:
                self.notify()

    def _join_mosaic(self, cur, hwnd):
        """Una ventana nueva entra al mosaico en el sitio de la enfocada: con hueco, la enfocada se
        corre; con 3, la enfocada pasa a la espera. Al arrancar (ventanas que ya había) solo se rellenan los huecos."""
        if self._booting:
            (cur.tiled if len(cur.tiled) < MAX_VISIBLE else cur.waiting).append(hwnd)
            return
        focused = self._focused()
        if focused in cur.tiled:
            index = cur.tiled.index(focused)
            if len(cur.tiled) < MAX_VISIBLE:
                cur.tiled.insert(index, hwnd)
            else:
                cur.tiled[index] = hwnd
                cur.waiting.append(focused)
        elif len(cur.tiled) < MAX_VISIBLE:
            cur.tiled.append(hwnd)
        else:
            cur.waiting.append(hwnd)
        self._launch_until = 0.0

    def adopt_existing(self):
        self._booting = True
        try:
            self.sync()
        finally:
            self._booting = False

    def expect_launch(self):
        with self.lock:
            self._launch_until = self.clock() + LAUNCH_WINDOW_SECONDS

    def _card(self, hwnd, rect, visible):
        app, _title = self.sys.describe(hwnd)
        return {"hwnd": hwnd, "rect": (rect.left, rect.top, rect.right, rect.bottom), "visible": visible,
                "name": app, "exe": self.sys.exe_path(hwnd), "shot": self._thumbs.get(hwnd)}

    # ---------- foco y disposición ----------

    def focus_dir(self, dir):
        self._check_direction(dir)
        with self.lock:
            cur = self._current()
            hwnd = self._focused()
            if not hwnd or hwnd not in cur.tiled:
                return
            target = neighbor(self._slots(cur), cur.tiled.index(hwnd), dir)
            if target is not None:
                if cur.zoomed:
                    cur.zoomed = 0  # cambiar de ventana deshace la ventana en grande
                    self._changed()
                cur.last_focus = cur.tiled[target]
                self.sys.focus(cur.last_focus)

    def focus_next(self):
        """Pasa el foco a la siguiente ventana del mosaico (después de la última, vuelve a la primera)."""
        with self.lock:
            cur = self._current()
            hwnd = self._focused()
            order = cur.tiled
            if not hwnd or len(order) < 2:
                return
            if cur.zoomed:
                cur.zoomed = 0  # cambiar de ventana deshace la ventana en grande
                self._changed()
            target = order[(order.index(hwnd) + 1) % len(order)] if hwnd in order else order[0]
            cur.last_focus = target
            self.sys.focus(target)

    def rotate(self):
        """Gira la ventana grande por los 4 lados: arriba, derecha, abajo, izquierda y otra vez arriba."""
        with self.lock:
            cur = self._current()
            here = (cur.orientation, cur.mirrored)
            cur.orientation, cur.mirrored = ROTATION[(ROTATION.index(here) + 1) % len(ROTATION)]
            self._changed()

    def arrange(self, dir):
        """Win+Alt+flecha. La ventana grande del mosaico pasa a ese lado; si ya estaba ahí, abajo la minimiza (al panel
        izquierdo)."""
        self._check_direction(dir)
        with self.lock:
            cur = self._current()
            hwnd = self._focused()
            if not hwnd or hwnd not in cur.tiled:
                return
            target = ARRANGE[dir]
            if (cur.orientation, cur.mirrored) == target and dir == "down":
                return self.park()
            cur.orientation, cur.mirrored = target
            self._changed()

    def zoom_toggle(self):
        """La ventana enfocada del mosaico pasa a ocupar todo el hueco por encima de las demás.

        Las demás no se mueven ni pasan a espera. Otra vez (o al enfocar otra ventana) vuelve a su sitio.
        """
        with self.lock:
            cur = self._current()
            hwnd = self._focused()
            if not hwnd or hwnd not in cur.tiled:
                return
            cur.zoomed = 0 if cur.zoomed == hwnd else hwnd
            self._changed()
            self.sys.focus(hwnd)

    def move_dir(self, dir):
        """Win+flechas: la ventana cambia de hueco con su vecina."""
        self._check_direction(dir)
        with self.lock:
            cur = self._current()
            hwnd = self._focused()
            if not hwnd or hwnd not in cur.tiled:
                return
            i = cur.tiled.index(hwnd)
            j = neighbor(self._slots(cur), i, dir)
            if j is None:
                return
            cur.tiled[i], cur.tiled[j] = cur.tiled[j], cur.tiled[i]
            self._changed()

    def orientation_toggle(self):
        with self.lock:
            cur = self._current()
            cur.orientation = "rows" if cur.orientation == "columns" else "columns"
            self._changed()

    def flip(self):
        with self.lock:
            cur = self._current()
            cur.mirrored = not cur.mirrored
            self._changed()

    def retile(self):
        self.sync()

    # ---------- ventanas ----------

    def park(self):
        """Aparca la ventana enfocada (la minimiza: espera en el panel izquierdo). Si hay otra esperando, ocupa su sitio."""
        with self.lock:
            cur = self._current()
            hwnd = self._focused()
            if not hwnd or hwnd not in cur.tiled:
                return
            i = cur.tiled.index(hwnd)
            replacement = next((h for h in cur.waiting if not self.sys.is_minimized(h)), None)
            if replacement:
                cur.tiled[i] = replacement
                cur.waiting.remove(replacement)
            else:
                cur.tiled.pop(i)
            cur.waiting.append(hwnd)
            self._changed()
            if replacement:
                self.sys.focus(replacement)

    def unpark(self, hwnd):
        """Trae una ventana aparcada: ocupa un hueco libre del mosaico o, si está lleno, el sitio de la enfocada."""
        with self.lock:
            cur = self._current()
            if hwnd not in cur.waiting:
                raise ActionError("not_waiting", "Esa ventana no está en espera en este escritorio")
            if len(cur.tiled) < MAX_VISIBLE:
                cur.waiting.remove(hwnd)
                cur.tiled.append(hwnd)
            else:
                focused = self._focused()
                self._swap_in(cur, hwnd, cur.tiled.index(focused) if focused in cur.tiled else len(cur.tiled) - 1)
            self._changed()
            self.sys.focus(hwnd)

    def bring_to(self, hwnd, x=None, y=None):
        """Trae una ventana en espera al mosaico. Si se suelta en (x, y) de la pantalla (desde el panel izquierdo),
        ocupa ese sitio."""
        with self.lock:
            cur = self._current()
            if hwnd in cur.tiled:
                self.sys.focus(hwnd)
                return
            if hwnd not in cur.waiting:
                raise ActionError("unknown_window", "Esa ventana no está en este escritorio")
            if x is not None and cur.tiled:
                self._drop_into_mosaic(cur, hwnd, x, y)
                return
            self.unpark(hwnd)

    def show_count(self, n):
        """Deja en el mosaico `n` ventanas (1, 2 o 3): aparca las de más, empezando por la última, o trae las que esperan."""
        if n not in range(1, MAX_VISIBLE + 1):
            raise ActionError("bad_count", f"Solo se pueden ver 1, 2 o 3 ventanas, no {n}")
        with self.lock:
            cur = self._current()
            focused = self._focused()
            while len(cur.tiled) > n:
                victim = next(h for h in reversed(cur.tiled) if h != focused)
                cur.tiled.remove(victim)
                cur.waiting.append(victim)
            self._promote(cur, n - len(cur.tiled))
            self._changed()
            if focused and focused in cur.tiled:
                self.sys.focus(focused)

    def close_window(self, hwnd):
        """Cierra una ventana concreta (por ejemplo desde el panel izquierdo)."""
        with self.lock:
            if hwnd not in self._tracked():
                raise ActionError("unknown_window", "Esa ventana ya no existe")
            self.sys.close(hwnd)

    def close_all(self):
        """Pide cerrarse a todas las ventanas de Kyora: de todos los escritorios y las flotantes.

        Es un cierre amable (la app puede preguntar si guardar). Las que no se cierran las recoloca el siguiente sync.
        """
        with self.lock:
            targets = [h for h in (*self._tracked(), *self.floating) if self.sys.is_alive(h)]
            for hwnd in targets:
                self.sys.close(hwnd)
            return len(targets)

    def solo(self):
        """Deja solo la ventana enfocada en el mosaico; las demás pasan a espera (no se cierran ni se minimizan)."""
        self.show_count(1)

    def unpark_next(self):
        """Trae la ventana que lleva más tiempo esperando."""
        with self.lock:
            cur = self._current()
            hwnd = next((h for h in cur.waiting if not self.sys.is_minimized(h)), None)
            if hwnd is None:
                raise ActionError("nothing_waiting", "No hay ventanas en espera")
            self.unpark(hwnd)

    def park_last(self):
        """Pasa a espera la última ventana del mosaico (nunca la enfocada)."""
        with self.lock:
            cur = self._current()
            focused = self._focused()
            victim = next((h for h in reversed(cur.tiled) if h != focused), None)
            if victim is None:
                return
            cur.tiled.remove(victim)
            cur.waiting.append(victim)
            self._changed()

    def drop(self, hwnd, x, y):
        """Suelta una ventana (en espera o del mosaico) en (x, y) de la pantalla: ocupa el sitio de esa zona y las demás
        se acomodan solas. Devuelve True si cambió algo; fuera de la pantalla la ventana vuelve a su hueco."""
        with self.lock:
            cur = self._current()
            if hwnd not in cur.tiled and hwnd not in cur.waiting:
                return False
            area = self._area()
            if not (area.left <= x < area.right and area.top <= y < area.bottom):
                self._apply()  # la ventana vuelve a su hueco
                return False
            self._drop_into_mosaic(cur, hwnd, x, y)
            return True

    def move_to_slot(self, slot, hwnd=0):
        """Lleva una ventana (por defecto la enfocada) al hueco `slot` del mosaico (0 = principal)."""
        with self.lock:
            cur = self._current()
            hwnd = hwnd or self._focused()
            if not hwnd:
                return
            if not isinstance(slot, int) or not 0 <= slot < len(cur.tiled):
                raise ActionError("no_slot", f"No hay un hueco {slot + 1 if isinstance(slot, int) else slot} en este escritorio")
            if hwnd in cur.waiting:
                self._swap_in(cur, hwnd, slot)
            elif hwnd in cur.tiled:
                i = cur.tiled.index(hwnd)
                cur.tiled[i], cur.tiled[slot] = cur.tiled[slot], cur.tiled[i]
            else:
                raise ActionError("unknown_window", "Esa ventana no está en este escritorio")
            self._changed()
            self.sys.focus(hwnd)

    def swap_into_focused(self, hwnd):
        """Win+R: una ventana en espera ocupa el sitio de la enfocada, que pasa a esperar en el panel izquierdo."""
        with self.lock:
            cur = self._current()
            if hwnd not in cur.waiting:
                raise ActionError("not_waiting", "Esa ventana no está en espera en este escritorio")
            focused = self._focused()
            if not focused:
                return self.unpark(hwnd)
            self._swap_in(cur, hwnd, cur.tiled.index(focused))
            cur.last_focus = hwnd
            self._changed()
            self.sys.focus(hwnd)

    def switcher_rect(self):
        """Dónde abrir el selector: el hueco de la ventana enfocada o, si no hay ninguna, toda la pantalla."""
        with self.lock:
            cur = self._current()
            focused = self._focused()
            if focused in cur.tiled:
                return self._rects(cur)[cur.tiled.index(focused)]
            return self._area()

    def _slot_index_at(self, desktop, x, y):
        rects = self._rects(desktop)
        if desktop.zoomed in desktop.tiled:  # la ventana en grande está encima: manda en todo el hueco que cubre
            i = desktop.tiled.index(desktop.zoomed)
            if rects[i].contains(x, y):
                return i
        return next((i for i, rect in enumerate(rects) if rect.contains(x, y)), None)

    def slot_rect_at(self, x, y):
        """Rectángulo del hueco que está bajo (x, y), o None (para resaltar el destino de un arrastre)."""
        with self.lock:
            cur = self._current()
            slot = self._slot_index_at(cur, x, y)
            return self._rects(cur)[slot] if slot is not None else None

    def _zone_rects(self, cur):
        """Los 4 sitios (izquierda-arriba, izquierda-abajo, derecha-arriba, derecha-abajo) como rectángulos de pantalla."""
        area = self._area()
        gap, outer = self.cfg["gap"], self._outer(MAX_VISIBLE)
        left, top = area.left + outer, area.top + outer
        right, bottom = area.right - outer, area.bottom - outer
        mid_x, mid_y = (left + right) // 2, (top + bottom) // 2
        h = gap // 2
        return {"left_top": Rect(left, top, mid_x - h, mid_y - h), "left_bottom": Rect(left, mid_y + h, mid_x - h, bottom),
                "right_top": Rect(mid_x + h, top, right, mid_y - h), "right_bottom": Rect(mid_x + h, mid_y + h, right, bottom)}

    def _plan_drop(self, cur, hwnd, x, y):
        """(tiled, mirrored, desplazada, sitio) que resultarían de soltar `hwnd` en (x, y)."""
        area = self._area()
        zone = zone_at((area.left, area.top, area.right, area.bottom), x, y)
        others = [h for h in cur.tiled if h != hwnd]
        tiled, mirrored, out = plan(others, cur.mirrored if cur.orientation == "columns" else False, hwnd, zone)
        return tiled, mirrored, out, zone

    def drop_zones(self, hwnd, x, y):
        """Lo que se enseña mientras se arrastra `hwnd`: los 4 sitios donde puede quedar, cuál está bajo (x, y) y el
        rectángulo donde quedaría de verdad. None si no hay mosaico."""
        with self.lock:
            cur = self._current()
            if not cur.tiled:
                return None
            tiled, mirrored, _, zone = self._plan_drop(cur, hwnd, x, y)
            slots = compute_slots(len(tiled), self._area(), "columns", mirrored, self.cfg["gap"], self._outer(len(tiled)))
            result = slots[tiled.index(hwnd)]
            quads = self._zone_rects(cur)
            return {"quads": [(quads[z].left, quads[z].top, quads[z].right, quads[z].bottom) for z in ZONES],
                    "hover": ZONES.index(zone), "result": (result.left, result.top, result.right, result.bottom)}

    def _drop_into_mosaic(self, cur, hwnd, x, y):
        """`hwnd` se suelta en (x, y): ocupa ese sitio y las demás se acomodan solas."""
        tiled, mirrored, out, _ = self._plan_drop(cur, hwnd, x, y)
        self._forget(cur, hwnd)
        if out is not None:
            self._forget(cur, out)
            cur.waiting.append(out)  # la ventana a la que quita el sitio espera en el panel izquierdo
        cur.tiled, cur.mirrored, cur.orientation = tiled, mirrored, "columns"
        cur.ratio = cur.ratio2 = 0.5
        cur.zoomed = 0
        self._changed()
        self.sys.focus(hwnd)

    def slot_rect(self, hwnd):
        """Rectángulo del hueco que le toca a una ventana del mosaico, o None."""
        with self.lock:
            cur = self._current()
            return self._rects(cur)[cur.tiled.index(hwnd)] if hwnd in cur.tiled else None

    def focused_window(self, keep_last=False):
        """Ventana del escritorio que tiene el foco ahora, o 0 (para rodearla con el contorno).

        Con `keep_last` también cuenta la última enfocada aunque el foco esté en otra parte (la tarjeta del buscador).
        """
        with self.lock:
            cur = self._current()
            fg = self.sys.foreground()
            if fg in cur.tiled:
                return fg
            return cur.last_focus if keep_last and cur.last_focus in cur.tiled else 0

    def visible_windows(self):
        """Ventanas que se ven ahora (para el contorno). Con una en grande, solo esa: las demás quedan debajo."""
        with self.lock:
            cur = self._current()
            if cur.zoomed in cur.tiled:
                return [cur.zoomed]
            return self._on_screen(cur)

    def is_draggable_here(self, hwnd):
        """True si es una ventana del mosaico: su arrastre enseña los huecos."""
        with self.lock:
            return hwnd in self._current().tiled

    def is_tiled(self, hwnd):
        with self.lock:
            return hwnd in self._current().tiled

    def focus_at(self, x, y):
        """Da el foco a la ventana que está bajo (x, y), si es una de Kyora y no la tiene ya."""
        with self.lock:
            cur = self._current()
            target = self.sys.window_at(x, y)
            if target not in cur.tiled:
                return False
            if self.sys.foreground() == target:
                return False
            cur.last_focus = target
            self.sys.focus(target)
            return True

    # ---------- tamaño de las divisiones ----------

    def _span(self, desktop, axis):
        """Largo (sin el hueco entre ventanas) sobre el que se reparte la división que cruza `axis`."""
        slots = self._slots(desktop)
        main_axis = "x" if desktop.orientation == "columns" else "y"
        group = slots if axis == main_axis else slots[1:]  # la división del par solo afecta a las ventanas 1 y 2
        if axis == "x":
            lo, hi = min(s.left for s in group), max(s.right for s in group)
        else:
            lo, hi = min(s.top for s in group), max(s.bottom for s in group)
        return max(hi - lo - self.cfg["gap"], 1)

    def _move_border(self, desktop, axis, fraction):
        desktop.ratio, desktop.ratio2 = self._ratios(desktop)  # se parte de lo que se ve (con los mínimos aplicados)
        desktop.ratio, desktop.ratio2 = adjust_ratios(
            len(desktop.tiled), desktop.orientation, desktop.mirrored,
            desktop.ratio, desktop.ratio2, axis, fraction,
        )

    def resize(self, dir):
        """Mueve en la dirección dada la división del mosaico que cruza ese eje."""
        self._check_direction(dir)
        with self.lock:
            cur = self._current()
            sign = 1 if dir in ("right", "down") else -1
            self._move_border(cur, "x" if dir in ("left", "right") else "y", sign * RESIZE_STEP)
            self._changed()

    def resize_from_drag(self, hwnd):
        """Tras arrastrar un borde de una ventana, conserva el nuevo reparto. False si no cambió nada útil."""
        with self.lock:
            cur = self._current()
            if hwnd not in cur.tiled or hwnd == cur.zoomed:  # la ventana en grande no reparte el mosaico
                self._apply()
                return False
            slots = self._slots(cur)
            index = cur.tiled.index(hwnd)
            old, new = slots[index], self.sys.frame_rect(hwnd)
            moves = {
                "left": new.left - old.left, "right": new.right - old.right,
                "up": new.top - old.top, "down": new.bottom - old.bottom,
            }
            edge = max(moves, key=lambda k: abs(moves[k]))
            # solo cuentan los bordes que tocan a otra ventana; los de la pantalla no se mueven
            if abs(moves[edge]) < RESIZE_THRESHOLD or neighbor(slots, index, edge) is None:
                self._apply()
                return False
            axis = "x" if edge in ("left", "right") else "y"
            before = (cur.ratio, cur.ratio2)
            self._move_border(cur, axis, moves[edge] / self._span(cur, axis))
            changed = (cur.ratio, cur.ratio2) != before
            self._changed()
            return changed

    def _swap_in(self, desktop, hwnd, slot):
        """`hwnd` (en espera) ocupa el hueco `slot` del mosaico; la que estaba pasa a esperar (en el mismo sitio de la
        lista, si venía de ella)."""
        out = desktop.tiled[slot]
        if hwnd in desktop.waiting:
            desktop.waiting[desktop.waiting.index(hwnd)] = out
        else:
            self._forget(desktop, hwnd)
            desktop.waiting.append(out)
        desktop.tiled[slot] = hwnd

    def refocus(self):
        """Devuelve el foco a la última ventana usada (al cerrar la búsqueda)."""
        with self.lock:
            hwnd = self._focused()
            if hwnd:
                self.sys.focus(hwnd)

    def close_focused(self):
        with self.lock:
            hwnd = self._focused()
            if hwnd:
                self.sys.close(hwnd)

    def float_toggle(self):
        """Saca de Kyora la ventana enfocada (queda libre de verdad: Kyora no la toca) o la devuelve al mosaico."""
        with self.lock:
            fg = self.sys.foreground()
            if fg in self.floating:
                self.floating.discard(fg)
                return self.sync()
            hwnd = self._focused()
            if not hwnd:
                return
            cur = self._current()
            self._forget(cur, hwnd)
            self.floating.add(hwnd)
            self._promote(cur, 1)
            self._changed()

    def activate(self, hwnd):
        """Lleva al frente cualquier ventana de Kyora, cambiando de escritorio si hace falta (la búsqueda). Una ventana
        en espera vuelve al mosaico."""
        with self.lock:
            index = next((i for i, d in enumerate(self.desktops) if hwnd in d.windows()), None)
            if index is None:
                raise ActionError("unknown_window", "Kyora no gestiona esa ventana")
            if index != self.active:
                self.desktop_switch(index)
            cur = self._current()
            if hwnd in cur.waiting:
                self.unpark(hwnd)
            else:
                self.sys.focus(hwnd)

    # ---------- escritorios ----------

    def _slide(self, target, direction):
        """Si el sistema sabe enseñarlo, desliza todo el contenido al escritorio `target` (ver ui/transition.py).
        True si se hizo; después hay que avisar con `transition_done`."""
        slide = getattr(self.sys, "slide", None)
        if not slide or self._booting or self.cfg.get("light_mode", True) or not self.cfg.get("animate_windows", True):
            return False
        cur, dest = self._current(), self.desktops[target]
        for hwnd in cur.tiled:
            self._remember(hwnd)  # lo que sale: la captura se guarda para cuando se vuelva
        old = self._cards(cur, cur.tiled)
        new = self._cards(dest, dest.tiled)
        return bool(slide({"old": old, "new": new, "offset": slide_offset(direction, self._area()),
                           "area": (*self._area().center,)}))

    def _cards(self, desktop, hwnds):
        rects = dict(zip(desktop.tiled, self._rects(desktop)))
        return [self._card(h, rects[h], True) for h in hwnds]

    def desktop_switch(self, index):
        with self.lock:
            if index == len(self.desktops):
                return self.desktop_create()
            self._check_index(index)
            if index == self.active:
                return
            started = self._slide(index, 1 if index > self.active else -1)
            self.active = index
            self._changed()
            if started:
                done = getattr(self.sys, "transition_done", None)
                if done:
                    done()
            cur = self._current()
            seen = self._on_screen(cur)
            target = cur.last_focus if cur.last_focus in seen else (seen[0] if seen else 0)
            if target:
                self.sys.focus(target)

    def desktop_step(self, delta):
        """Va al escritorio anterior (-1) o siguiente (+1); en los extremos no hace nada (no da la vuelta)."""
        with self.lock:
            target = self.active + delta
            if 0 <= target < len(self.desktops):
                self.desktop_switch(target)

    def _new_desktop(self):
        names = {d.name for d in self.desktops}
        number = next(n for n in range(1, len(names) + 2) if str(n) not in names)
        desktop = Desktop(str(number))
        self.desktops.append(desktop)
        return desktop

    def desktop_create(self):
        with self.lock:
            self._new_desktop()
            started = self._slide(len(self.desktops) - 1, 1)
            self.active = len(self.desktops) - 1
            self._changed()
            if started:
                done = getattr(self.sys, "transition_done", None)
                if done:
                    done()

    def desktop_rename(self, index, name):
        with self.lock:
            self._check_index(index)
            name = (name or "").strip()[:20]
            if not name:
                raise ActionError("empty_name", "El nombre no puede estar vacío")
            self.desktops[index].name = name
            self.notify()

    def desktop_close(self, index):
        with self.lock:
            self._check_index(index)
            if len(self.desktops) == 1:
                raise ActionError("last_desktop", "No se puede cerrar el único escritorio")
            closed = self.desktops.pop(index)
            dest_index = max(index - 1, 0)
            for hwnd in closed.windows():
                self._place_in(self.desktops[dest_index], hwnd)
            if self.active == index:
                self.active = dest_index
            elif self.active > index:
                self.active -= 1
            self._changed()

    def send_to_desktop(self, index):
        with self.lock:
            hwnd = self._focused()
            if not hwnd or index == self.active:
                return
            if index == len(self.desktops):
                self._new_desktop()
            self._check_index(index)
            cur = self._current()
            self._forget(cur, hwnd)
            self._place_in(self.desktops[index], hwnd)
            self._promote(cur, 1)
            self._changed()

    # ---------- salida ----------

    def release_all(self):
        """Vuelve a mostrar todas las ventanas ocultas por Kyora (cierre o emergencia)."""
        with self.lock:
            count = 0
            for desktop in self.desktops:
                for hwnd in desktop.windows():
                    if self.sys.is_alive(hwnd) and not self.sys.is_shown(hwnd):
                        self.sys.show(hwnd)
                        count += 1
            self._hidden.clear()
            return count

    def snapshot(self):
        with self.lock:
            cur = self._current()

            def info(hwnd):
                app, title = self.sys.describe(hwnd)
                return {"hwnd": hwnd, "app": app, "title": title, "exe": self.sys.exe_path(hwnd)}

            return {
                "desktops": [
                    {"index": i, "name": d.name, "count": len(d.windows()), "active": i == self.active}
                    for i, d in enumerate(self.desktops)
                ],
                "visible": [info(h) for h in self._on_screen(cur)],
                "tiled": [info(h) for h in cur.tiled],
                "waiting": [info(h) for h in cur.waiting],
                "orientation": cur.orientation,
                "mirrored": cur.mirrored,
                "active": self.active,
            }

    def window_list(self, blocking=True):
        """Las ventanas de todos los escritorios. Con `blocking=False`, si el gestor está ocupado (acomodando ventanas)
        devuelve None en vez de esperar: la interfaz no se queda parada."""
        if not self.lock.acquire(blocking):
            return None
        try:
            result = []
            for i, desktop in enumerate(self.desktops):
                for hwnd in desktop.windows():
                    app, title = self.sys.describe(hwnd)
                    result.append({
                        "hwnd": hwnd, "app": app, "title": title, "desktop": desktop.name, "index": i,
                        "exe": self.sys.exe_path(hwnd),
                    })
            return result
        finally:
            self.lock.release()

    # ---------- validaciones ----------

    @staticmethod
    def _check_direction(direction):
        if direction not in DIRECTIONS:
            raise ActionError("bad_direction", f"Dirección no válida: {direction}")

    def _check_index(self, index):
        if not isinstance(index, int) or not 0 <= index < len(self.desktops):
            raise ActionError("no_desktop", f"No existe el escritorio {index}")

"""Gestor de ventanas de Kyora: escritorios propios, máximo 3 ventanas visibles, el resto en espera.

No conoce Win32: habla con un objeto `system` (ver kyora/system/win32.py), lo que permite
probarlo con un sistema falso. Todo el estado vive bajo un único bloqueo.
"""
import threading
import time
from dataclasses import dataclass, field

from kyora.core.actions import ActionError
from kyora.core.layout import (
    MAX_VISIBLE,
    Rect,
    adjust_ratios,
    compute_slots,
    fit_ratios,
    neighbor,
)

LAUNCH_WINDOW_SECONDS = 15  # tras abrir una app desde la búsqueda, su ventana ocupa el lugar de la enfocada
MAX_THUMBNAILS = 16  # capturas de ventanas guardadas para el panel de espera (grandes: cada una ocupa unos MB)
SHOW_GRACE_SECONDS = 1.0  # tras mostrar una ventana no se la da por desaparecida enseguida
DIRECTIONS = ("left", "right", "up", "down")
RESIZE_STEP = 0.05  # fracción del espacio que se mueve una división con el teclado
RESIZE_THRESHOLD = 8  # píxeles: menos que esto al arrastrar un borde no cuenta como cambio de tamaño
MIN_SIZE_TOLERANCE = 2  # píxeles: una ventana que queda más grande que su hueco por más que esto tiene tamaño mínimo
# giro de la ventana grande con Alt+O: arriba, derecha, abajo, izquierda (sin espejo la principal es la primera mitad)
ROTATION = (("rows", False), ("columns", True), ("rows", True), ("columns", False))


@dataclass
class Desktop:
    name: str
    visible: list = field(default_factory=list)
    waiting: list = field(default_factory=list)
    orientation: str = "columns"
    mirrored: bool = False
    ratio: float = 0.5  # espacio de la ventana principal
    ratio2: float = 0.5  # espacio de la primera ventana del par apilado
    last_focus: int = 0
    zoomed: int = 0  # ventana en grande sobre todo el hueco (Alt+C), o 0

    def windows(self):
        return self.visible + self.waiting


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
        self._thumbs = {}  # hwnd -> (ancho, alto, bytes BGRX) de la última vez que se vio antes de pasar a espera
        self._min_size = {}  # hwnd -> (ancho, alto) mínimos de las apps que no se dejan encoger (0 = sin mínimo)

    # ---------- utilidades internas ----------

    def _current(self):
        return self.desktops[self.active]

    def _tracked(self):
        return {h for d in self.desktops for h in d.windows()}

    def _area(self):
        """Hueco que deja el marco de Kyora (barra a la izquierda y borde fino en los demás lados).

        La interfaz fija `insets` (izquierda, arriba, derecha, abajo) en píxeles físicos al arrancar.
        """
        a = self.sys.work_area()
        left, top, right, bottom = self.cfg.get("insets", (0, 0, 0, 0))
        return Rect(a.left + left, a.top + top, a.right - right, a.bottom - bottom)

    def _outer(self, n):
        return self.cfg["outer_gap"] if n <= 1 else self.cfg.get("outer_gap_multi", self.cfg["outer_gap"])

    def _ratios(self, desktop):
        """Reparto del mosaico: el del usuario, movido lo justo para que ninguna app quede por debajo de su mínimo.

        No se guarda: cuando la app con mínimo se va, el mosaico vuelve al reparto del usuario.
        """
        n = len(desktop.visible)
        return fit_ratios(
            n, self._area(), desktop.orientation, self.cfg["gap"], self._outer(n), desktop.ratio, desktop.ratio2,
            [self._min_size.get(h) for h in desktop.visible],
        )

    def _slots(self, desktop):
        """Huecos del mosaico, sin contar la ventana en grande (las direcciones y el reparto se calculan con estos)."""
        n = len(desktop.visible)
        return compute_slots(
            n, self._area(), desktop.orientation, desktop.mirrored,
            self.cfg["gap"], self._outer(n), *self._ratios(desktop),
        )

    def _rects(self, desktop):
        """Dónde está cada ventana visible: la ventana en grande ocupa todo el hueco, con el margen del marco."""
        slots = self._slots(desktop)
        if desktop.zoomed not in desktop.visible:
            desktop.zoomed = 0
            return slots
        full = compute_slots(1, self._area(), gap=self.cfg["gap"], outer=self._outer(len(desktop.visible)))[0]
        return [full if hwnd == desktop.zoomed else rect for hwnd, rect in zip(desktop.visible, slots)]

    def _focused(self):
        cur = self._current()
        fg = self.sys.foreground()
        if fg in cur.visible:
            cur.last_focus = fg
            return fg
        if cur.last_focus in cur.visible:
            return cur.last_focus
        return cur.visible[0] if cur.visible else 0

    def _promote(self, desktop, count):
        """Sube ventanas de la espera a visibles (sin las minimizadas) mientras haya hueco."""
        for _ in range(count):
            if len(desktop.visible) >= MAX_VISIBLE:
                return
            candidate = next((h for h in desktop.waiting if not self.sys.is_minimized(h)), None)
            if candidate is None:
                return
            desktop.waiting.remove(candidate)
            desktop.visible.append(candidate)

    def _place_in(self, desktop, hwnd):
        (desktop.visible if len(desktop.visible) < MAX_VISIBLE else desktop.waiting).append(hwnd)

    def _signature(self):
        return (
            self.active,
            tuple(
                (d.name, tuple(d.visible), tuple(d.waiting), d.orientation, d.mirrored, d.ratio, d.ratio2, d.zoomed)
                for d in self.desktops
            ),
        )

    def _apply(self):
        """Deja el sistema como dice el estado: coloca lo visible y después oculta lo que sale.

        Se muestra antes de ocultar para que, al cambiar de escritorio, no se vea el fondo entre medias.
        """
        cur = self._current()
        for _ in range(2):  # si una app resulta no dejarse encoger, se reparte otra vez con su mínimo
            learned = False
            for hwnd, rect in zip(cur.visible, self._rects(cur)):
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
            for hwnd in desktop.windows() if i != self.active else desktop.waiting:
                if self.sys.is_shown(hwnd):
                    # la captura se toma mientras todavía se ve, y solo si va a la espera: las que se ocultan al
                    # cambiar de escritorio vuelven a verse al volver a él y no aparecen en el panel
                    if hwnd in desktop.waiting:
                        self._remember(hwnd)
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
        """Guarda una captura de la ventana (para el panel de espera) si el sistema sabe hacerlas."""
        capture = getattr(self.sys, "capture", None)
        shot = capture(hwnd) if capture else None
        if shot:
            self._thumbs.pop(hwnd, None)
            self._thumbs[hwnd] = shot
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
                dead = [h for h in desktop.visible if not self.sys.is_alive(h)]
                desktop.visible = [h for h in desktop.visible if h not in dead]
                desktop.waiting = [h for h in desktop.waiting if self.sys.is_alive(h)]
                self._promote(desktop, len(dead))
            self.floating = {h for h in self.floating if self.sys.is_alive(h)}
            self._hidden &= self._tracked()
            self._thumbs = {h: s for h, s in self._thumbs.items() if h in self._tracked()}
            self._min_size = {h: m for h, m in self._min_size.items() if self.sys.is_alive(h)}

            cur = self._current()
            gone, keep = 0, []
            for hwnd in cur.visible:
                if self.sys.is_minimized(hwnd):
                    cur.waiting.append(hwnd)
                    gone += 1
                elif hwnd in self._hidden:
                    keep.append(hwnd)  # la ocultó Kyora y _apply la va a mostrar
                elif not self.sys.is_manageable(hwnd) and now - self._shown_at.get(hwnd, -1e9) > SHOW_GRACE_SECONDS:
                    gone += 1
                else:
                    keep.append(hwnd)
            cur.visible = keep
            self._promote(cur, gone)

            tracked = self._tracked()
            for hwnd in self.sys.list_windows():
                if hwnd in tracked or hwnd in self.floating:
                    continue
                if len(cur.visible) < MAX_VISIBLE:
                    cur.visible.append(hwnd)
                elif now < self._launch_until and cur.visible:
                    target = cur.last_focus if cur.last_focus in cur.visible else cur.visible[-1]
                    cur.visible[cur.visible.index(target)] = hwnd
                    cur.waiting.append(target)
                    self._launch_until = 0.0
                else:
                    cur.waiting.append(hwnd)

            fg = self.sys.foreground()
            if fg in cur.visible:
                cur.last_focus = fg
                if cur.zoomed and fg != cur.zoomed:
                    cur.zoomed = 0  # el foco pasó a otra ventana del mosaico: la grande vuelve a su sitio

            self._apply()
            if self._signature() != before:
                self.notify()

    def adopt_existing(self):
        self.sync()

    def expect_launch(self):
        with self.lock:
            self._launch_until = self.clock() + LAUNCH_WINDOW_SECONDS

    # ---------- foco y disposición ----------

    def focus_dir(self, dir):
        self._check_direction(dir)
        with self.lock:
            cur = self._current()
            hwnd = self._focused()
            if not hwnd:
                return
            target = neighbor(self._slots(cur), cur.visible.index(hwnd), dir)
            if target is not None:
                if cur.zoomed:
                    cur.zoomed = 0  # cambiar de ventana deshace la ventana en grande
                    self._changed()
                cur.last_focus = cur.visible[target]
                self.sys.focus(cur.last_focus)

    def focus_next(self):
        """Pasa el foco a la siguiente ventana visible del mosaico (después de la última, vuelve a la primera)."""
        with self.lock:
            cur = self._current()
            hwnd = self._focused()
            if not hwnd or len(cur.visible) < 2:
                return
            if cur.zoomed:
                cur.zoomed = 0  # cambiar de ventana deshace la ventana en grande
                self._changed()
            cur.last_focus = cur.visible[(cur.visible.index(hwnd) + 1) % len(cur.visible)]
            self.sys.focus(cur.last_focus)

    def rotate(self):
        """Gira la ventana grande por los 4 lados: arriba, derecha, abajo, izquierda y otra vez arriba."""
        with self.lock:
            cur = self._current()
            here = (cur.orientation, cur.mirrored)
            cur.orientation, cur.mirrored = ROTATION[(ROTATION.index(here) + 1) % len(ROTATION)]
            self._changed()

    def zoom_toggle(self):
        """La ventana enfocada pasa a ocupar todo el hueco (con el margen del marco) por encima de las demás.

        Las demás no se mueven ni pasan a espera. Otra vez (o al enfocar otra ventana) vuelve a su sitio.
        """
        with self.lock:
            cur = self._current()
            hwnd = self._focused()
            if not hwnd:
                return
            cur.zoomed = 0 if cur.zoomed == hwnd else hwnd
            self._changed()
            self.sys.focus(hwnd)

    def move_dir(self, dir):
        self._check_direction(dir)
        with self.lock:
            cur = self._current()
            hwnd = self._focused()
            if not hwnd:
                return
            i = cur.visible.index(hwnd)
            j = neighbor(self._slots(cur), i, dir)
            if j is None:
                return
            cur.visible[i], cur.visible[j] = cur.visible[j], cur.visible[i]
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
        """Manda la ventana enfocada a la espera; si hay otra esperando, ocupa su sitio."""
        with self.lock:
            cur = self._current()
            hwnd = self._focused()
            if not hwnd:
                return
            i = cur.visible.index(hwnd)
            replacement = next((h for h in cur.waiting if not self.sys.is_minimized(h)), None)
            if replacement:
                cur.visible[i] = replacement
                cur.waiting.remove(replacement)
            else:
                cur.visible.pop(i)
            cur.waiting.append(hwnd)
            self._changed()
            if replacement:
                self.sys.focus(replacement)

    def unpark(self, hwnd):
        """Trae una ventana en espera: ocupa un hueco libre o reemplaza a la enfocada."""
        with self.lock:
            cur = self._current()
            if hwnd not in cur.waiting:
                raise ActionError("not_waiting", "Esa ventana no está en espera en este escritorio")
            if len(cur.visible) < MAX_VISIBLE:
                cur.waiting.remove(hwnd)
                cur.visible.append(hwnd)
            else:
                self._swap_in(cur, hwnd, cur.visible.index(self._focused()))
            self._changed()
            self.sys.focus(hwnd)

    def show_count(self, n):
        """Deja visibles `n` ventanas (1, 2 o 3): aparca las de más, empezando por la última, o trae las que esperan."""
        if n not in range(1, MAX_VISIBLE + 1):
            raise ActionError("bad_count", f"Solo se pueden ver 1, 2 o 3 ventanas, no {n}")
        with self.lock:
            cur = self._current()
            focused = self._focused()
            while len(cur.visible) > n:
                victim = next(h for h in reversed(cur.visible) if h != focused)
                cur.visible.remove(victim)
                cur.waiting.append(victim)
            self._promote(cur, n - len(cur.visible))
            self._changed()
            if focused and focused in cur.visible:
                self.sys.focus(focused)

    def close_window(self, hwnd):
        """Cierra una ventana concreta (por ejemplo desde el panel de espera)."""
        with self.lock:
            if hwnd not in self._tracked():
                raise ActionError("unknown_window", "Esa ventana ya no existe")
            self.sys.close(hwnd)

    def close_all(self):
        """Pide cerrarse a todas las ventanas de Kyora: visibles, en espera, de otros escritorios y flotantes.

        Es un cierre amable (la app puede preguntar si guardar). Las que no se cierran las recoloca el siguiente sync.
        """
        with self.lock:
            targets = [h for h in (*self._tracked(), *self.floating) if self.sys.is_alive(h)]
            for hwnd in targets:
                self.sys.close(hwnd)
            return len(targets)

    def solo(self):
        """Deja solo la ventana enfocada; las demás pasan a espera (no se cierran ni se minimizan)."""
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
            victim = next((h for h in reversed(cur.visible) if h != focused), None)
            if victim is None:
                return
            cur.visible.remove(victim)
            cur.waiting.append(victim)
            self._changed()

    def drop(self, hwnd, x, y):
        """Suelta una ventana (en espera o visible) sobre el hueco que está en (x, y) de la pantalla.

        Devuelve True si cambió algo. Soltar fuera de un hueco, o sobre el suyo, deja todo como estaba.
        """
        with self.lock:
            cur = self._current()
            slot = self._slot_index_at(cur, x, y)
            if hwnd in cur.waiting:
                if slot is None:
                    return False
                self._swap_in(cur, hwnd, slot)
                self._changed()
                self.sys.focus(hwnd)
                return True
            if hwnd in cur.visible:
                i = cur.visible.index(hwnd)
                if slot is None or slot == i:
                    self._apply()  # la ventana vuelve a su hueco
                    return False
                cur.visible[i], cur.visible[slot] = cur.visible[slot], cur.visible[i]
                self._changed()
                self.sys.focus(hwnd)
                return True
            return False

    def move_to_slot(self, slot, hwnd=0):
        """Lleva una ventana (por defecto la enfocada) al hueco `slot` (0 = principal)."""
        with self.lock:
            cur = self._current()
            hwnd = hwnd or self._focused()
            if not hwnd:
                return
            if not isinstance(slot, int) or not 0 <= slot < len(cur.visible):
                raise ActionError("no_slot", f"No hay un hueco {slot + 1 if isinstance(slot, int) else slot} en este escritorio")
            if hwnd in cur.waiting:
                self._swap_in(cur, hwnd, slot)
            elif hwnd in cur.visible:
                i = cur.visible.index(hwnd)
                cur.visible[i], cur.visible[slot] = cur.visible[slot], cur.visible[i]
            else:
                raise ActionError("unknown_window", "Esa ventana no está en este escritorio")
            self._changed()
            self.sys.focus(hwnd)

    def swap_into_focused(self, hwnd):
        """Una ventana en espera ocupa el hueco de la enfocada, que pasa a espera (el selector de Alt+E)."""
        with self.lock:
            cur = self._current()
            if hwnd not in cur.waiting:
                raise ActionError("not_waiting", "Esa ventana no está en espera en este escritorio")
            focused = self._focused()
            if not focused:
                return self.unpark(hwnd)
            self._swap_in(cur, hwnd, cur.visible.index(focused))
            cur.last_focus = hwnd
            self._changed()
            self.sys.focus(hwnd)

    def switcher_rect(self):
        """Dónde abrir el selector: el hueco de la ventana enfocada o, si no hay ninguna, todo el hueco del marco."""
        with self.lock:
            cur = self._current()
            focused = self._focused()
            return self._rects(cur)[cur.visible.index(focused)] if focused else self._area()

    def _slot_index_at(self, desktop, x, y):
        rects = self._rects(desktop)
        if desktop.zoomed:  # la ventana en grande está encima: manda en todo el hueco que cubre
            i = desktop.visible.index(desktop.zoomed)
            if rects[i].contains(x, y):
                return i
        return next((i for i, rect in enumerate(rects) if rect.contains(x, y)), None)

    def slot_rect_at(self, x, y):
        """Rectángulo del hueco que está bajo (x, y), o None (para resaltar el destino de un arrastre)."""
        with self.lock:
            cur = self._current()
            slot = self._slot_index_at(cur, x, y)
            return self._rects(cur)[slot] if slot is not None else None

    def slot_rect(self, hwnd):
        """Rectángulo del hueco que le toca a una ventana visible, o None."""
        with self.lock:
            cur = self._current()
            return self._rects(cur)[cur.visible.index(hwnd)] if hwnd in cur.visible else None

    def focused_window(self, keep_last=False):
        """Ventana del mosaico que tiene el foco ahora, o 0 (para rodearla con el contorno).

        Con `keep_last` también cuenta la última enfocada aunque el foco esté en otra parte (la tarjeta del buscador).
        """
        with self.lock:
            cur = self._current()
            fg = self.sys.foreground()
            if fg in cur.visible:
                return fg
            return cur.last_focus if keep_last and cur.last_focus in cur.visible else 0

    def visible_windows(self):
        """Ventanas que se ven ahora en el mosaico (para dibujar su borde). Con una en grande, solo esa: las demás
        quedan debajo y su borde se pintaría encima de ella."""
        with self.lock:
            cur = self._current()
            if cur.zoomed in cur.visible:
                return [cur.zoomed]
            return list(cur.visible)

    def is_tiled(self, hwnd):
        with self.lock:
            return hwnd in self._current().visible

    def focus_at(self, x, y):
        """Da el foco a la ventana del mosaico que está bajo (x, y), si realmente es la que se ve ahí."""
        with self.lock:
            cur = self._current()
            slot = self._slot_index_at(cur, x, y)
            if slot is None:
                return False
            target = cur.visible[slot]
            if self.sys.foreground() == target or self.sys.window_at(x, y) != target:
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
            len(desktop.visible), desktop.orientation, desktop.mirrored,
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
            if hwnd not in cur.visible or hwnd == cur.zoomed:  # la ventana en grande no reparte el mosaico
                self._apply()
                return False
            slots = self._slots(cur)
            index = cur.visible.index(hwnd)
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
        out = desktop.visible[slot]
        desktop.visible[slot] = hwnd
        desktop.waiting[desktop.waiting.index(hwnd)] = out

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
        """Saca de Kyora la ventana enfocada (queda libre) o la devuelve al mosaico."""
        with self.lock:
            fg = self.sys.foreground()
            if fg in self.floating:
                self.floating.discard(fg)
                return self.sync()
            hwnd = self._focused()
            if not hwnd:
                return
            cur = self._current()
            cur.visible.remove(hwnd)
            self.floating.add(hwnd)
            self._promote(cur, 1)
            self._changed()

    def activate(self, hwnd):
        """Lleva al frente cualquier ventana de Kyora, cambiando de escritorio si hace falta."""
        with self.lock:
            index = next((i for i, d in enumerate(self.desktops) if hwnd in d.windows()), None)
            if index is None:
                raise ActionError("unknown_window", "Kyora no gestiona esa ventana")
            if index != self.active:
                self.desktop_switch(index)
            if hwnd in self._current().waiting:
                self.unpark(hwnd)
            else:
                self.sys.focus(hwnd)

    # ---------- escritorios ----------

    def desktop_switch(self, index):
        with self.lock:
            if index == len(self.desktops):
                return self.desktop_create()
            self._check_index(index)
            if index == self.active:
                return
            self.active = index
            self._changed()
            cur = self._current()
            target = cur.last_focus if cur.last_focus in cur.visible else (cur.visible[0] if cur.visible else 0)
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
            self.active = len(self.desktops) - 1
            self._changed()

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
            cur.visible.remove(hwnd)
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
                "visible": [info(h) for h in cur.visible],
                "waiting": [info(h) for h in cur.waiting],
                "orientation": cur.orientation,
                "mirrored": cur.mirrored,
            }

    def window_list(self):
        with self.lock:
            result = []
            for i, desktop in enumerate(self.desktops):
                for hwnd in desktop.windows():
                    app, title = self.sys.describe(hwnd)
                    result.append({
                        "hwnd": hwnd, "app": app, "title": title, "desktop": desktop.name, "index": i,
                        "exe": self.sys.exe_path(hwnd),
                    })
            return result

    # ---------- validaciones ----------

    @staticmethod
    def _check_direction(direction):
        if direction not in DIRECTIONS:
            raise ActionError("bad_direction", f"Dirección no válida: {direction}")

    def _check_index(self, index):
        if not isinstance(index, int) or not 0 <= index < len(self.desktops):
            raise ActionError("no_desktop", f"No existe el escritorio {index}")

"""Cálculo de layouts. Funciones puras, sin Windows ni UI.

Nunca hay más de 3 ventanas visibles (MAX_VISIBLE). Disposiciones posibles:
  1 ventana          -> pantalla completa
  2 ventanas         -> "columns" (lado a lado) o "rows" (una encima de otra)
  3 ventanas         -> una mitad completa + la otra mitad dividida en dos
`mirrored` cambia de lado la ventana grande (o el orden, con 2 ventanas).
"""
from dataclasses import dataclass

MAX_VISIBLE = 3
ORIENTATIONS = ("columns", "rows")


@dataclass(frozen=True)
class Rect:
    left: int
    top: int
    right: int
    bottom: int

    @property
    def width(self):
        return self.right - self.left

    @property
    def height(self):
        return self.bottom - self.top

    @property
    def center(self):
        return (self.left + self.right) / 2, (self.top + self.bottom) / 2

    def contains(self, x, y):
        return self.left <= x < self.right and self.top <= y < self.bottom


MIN_RATIO, MAX_RATIO = 0.2, 0.8


def _clamp(ratio):
    return min(max(ratio, MIN_RATIO), MAX_RATIO)


def _split(rect, axis, gap, ratio=0.5):
    """Divide en dos; la primera mitad (izquierda o superior) recibe `ratio` del espacio."""
    if axis == "columns":
        w = round((rect.width - gap) * ratio)
        return (
            Rect(rect.left, rect.top, rect.left + w, rect.bottom),
            Rect(rect.left + w + gap, rect.top, rect.right, rect.bottom),
        )
    h = round((rect.height - gap) * ratio)
    return (
        Rect(rect.left, rect.top, rect.right, rect.top + h),
        Rect(rect.left, rect.top + h + gap, rect.right, rect.bottom),
    )


def compute_slots(n, area, orientation="columns", mirrored=False, gap=8, outer=8, ratio=0.5, ratio2=0.5):
    """Devuelve los rectángulos de las n ventanas visibles, la ventana "principal" primero.

    `ratio` es la fracción que ocupa la ventana principal; `ratio2`, la que ocupa la primera
    de las dos ventanas apiladas (índice 1) dentro de su mitad.
    """
    if n < 0 or n > MAX_VISIBLE:
        raise ValueError(f"Kyora admite como máximo {MAX_VISIBLE} ventanas visibles, no {n}")
    if orientation not in ORIENTATIONS:
        raise ValueError(f"Orientación desconocida: {orientation}")
    if n == 0:
        return []
    inner = Rect(area.left + outer, area.top + outer, area.right - outer, area.bottom - outer)
    if n == 1:
        return [inner]
    ratio, ratio2 = _clamp(ratio), _clamp(ratio2)
    first, second = _split(inner, orientation, gap, 1 - ratio if mirrored else ratio)
    main_half, rest_half = (second, first) if mirrored else (first, second)
    if n == 2:
        return [main_half, rest_half]
    cross = "rows" if orientation == "columns" else "columns"
    return [main_half, *_split(rest_half, cross, gap, ratio2)]


def _fit_share(share, need_first, need_second, usable):
    """Parte (`share`) de la primera pieza para que cada una tenga al menos lo que pide (0 = no pide nada)."""
    if usable <= 0 or not (need_first or need_second):
        return share
    lo = (need_first + 1) / usable if need_first else 0.0  # +1 px: el reparto se redondea
    hi = 1 - (need_second + 1) / usable if need_second else 1.0
    if lo > hi:  # no caben las dos: se reparte en proporción a lo que pide cada una
        return _clamp(need_first / (need_first + need_second))
    return _clamp(min(max(share, lo), hi))


def fit_ratios(n, area, orientation="columns", gap=8, outer=8, ratio=0.5, ratio2=0.5, minimums=()):
    """(ratio, ratio2) movidos lo justo para que ninguna ventana quede por debajo de su tamaño mínimo.

    `minimums` son los (ancho, alto) mínimos de cada ventana visible en el orden de los huecos (None o 0 = sin
    mínimo). Algunas apps (Calculadora, Fotos…) no se dejan encoger y se saldrían de su hueco. `ratio` es siempre lo
    que ocupa la ventana principal y `ratio2` lo de la primera del par apilado, con espejo o sin él.
    """
    ratio, ratio2 = _clamp(ratio), _clamp(ratio2)
    if n < 2:
        return ratio, ratio2
    mins = [tuple(m) if m else (0, 0) for m in minimums][:n]
    mins += [(0, 0)] * (n - len(mins))
    along = 0 if orientation == "columns" else 1  # el lado de la ventana que reparte la división principal
    inner_w, inner_h = area.width - 2 * outer, area.height - 2 * outer
    main_len, cross_len = (inner_w, inner_h) if orientation == "columns" else (inner_h, inner_w)
    ratio = _fit_share(ratio, mins[0][along], max(m[along] for m in mins[1:]), main_len - gap)
    if n == 3:
        ratio2 = _fit_share(ratio2, mins[1][1 - along], mins[2][1 - along], cross_len - gap)
    return ratio, ratio2


def adjust_ratios(n, orientation, mirrored, ratio, ratio2, axis, fraction):
    """Mueve la división que cruza `axis` ("x" o "y") `fraction` del espacio hacia la derecha/abajo.

    Devuelve (ratio, ratio2); si no hay ninguna división en ese eje, los devuelve sin cambios.
    """
    main_axis = "x" if orientation == "columns" else "y"
    if n >= 2 and axis == main_axis:
        main_is_first = not mirrored
        first = ratio if main_is_first else 1 - ratio
        first = _clamp(first + fraction)
        return (first if main_is_first else 1 - first), ratio2
    if n == 3 and axis != main_axis:
        return ratio, _clamp(ratio2 + fraction)
    return ratio, ratio2


def neighbor(slots, index, direction):
    """Índice del slot vecino en la dirección dada (left/right/up/down), o None."""
    here = slots[index]
    cx, cy = here.center
    best, best_score = None, None
    for j, other in enumerate(slots):
        if j == index:
            continue
        beyond = {
            "left": other.right <= here.left,
            "right": other.left >= here.right,
            "up": other.bottom <= here.top,
            "down": other.top >= here.bottom,
        }[direction]
        if not beyond:
            continue
        ox, oy = other.center
        horizontal = direction in ("left", "right")
        score = abs(ox - cx) + 2 * abs(oy - cy) if horizontal else abs(oy - cy) + 2 * abs(ox - cx)
        if best_score is None or score < best_score:
            best, best_score = j, score
    return best


def slide_offset(direction, area):
    """(dx, dy) en píxeles de pantalla que se desplaza todo al pasar al escritorio de abajo (+1) o de arriba (-1):
    lo que sale se va hacia el lado contrario al que llega lo nuevo."""
    return 0, -direction * area.height

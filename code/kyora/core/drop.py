"""Dónde queda una ventana que se suelta con el mosaico hecho. Lógica pura (sin Windows ni Qt).

El mosaico son dos columnas, izquierda y derecha, y a lo sumo 3 ventanas: una columna entera y la otra partida en dos
(arriba y abajo). Hay 4 sitios donde soltar: izquierda-arriba, izquierda-abajo, derecha-arriba y derecha-abajo. Lo que
hay en cada sitio depende de lo que ya hay:
- con 0 ventanas, la suelta ocupa la pantalla; con 1, se pone a ese lado y la otra se queda con el otro;
- con 2 (una por columna), la columna donde se suelta se parte en dos, arriba o abajo según donde se suelte;
- con 3 (una columna ya partida), solo hay una ventana en la otra: soltar sobre la columna partida cambia la ventana
  de ese sitio, y sobre la columna entera cambia la ventana de esa columna. La que sale queda libre.

El mosaico se guarda como lo entiende el gestor: lista `tiled` con la ventana principal primero y las dos de la
columna partida después (arriba, abajo), más `mirrored`: sin espejo la principal va a la izquierda.
"""
ZONES = ("left_top", "left_bottom", "right_top", "right_bottom")


def zone_at(area, x, y):
    """El sitio (uno de ZONES) que corresponde a un punto de la pantalla `area` (izq, arriba, der, abajo)."""
    left, top, right, bottom = area
    side = "left" if x < (left + right) / 2 else "right"
    half = "top" if y < (top + bottom) / 2 else "bottom"
    return f"{side}_{half}"


def columns(tiled, mirrored):
    """(izquierda, derecha): las ventanas de cada columna, de arriba abajo."""
    n = len(tiled)
    if n <= 1:
        return list(tiled), []
    if n == 2:
        return ([tiled[1]], [tiled[0]]) if mirrored else ([tiled[0]], [tiled[1]])
    return (list(tiled[1:]), [tiled[0]]) if mirrored else ([tiled[0]], list(tiled[1:]))


def from_columns(left, right):
    """(tiled, mirrored) del mosaico que forman las dos columnas."""
    if len(left) == 2:
        return [right[0], *left], True
    if len(right) == 2:
        return [left[0], *right], False
    return [*left, *right], False


def plan(others, mirrored, dragged, zone):
    """Mosaico que queda al soltar `dragged` en `zone`, con `others` (el mosaico sin ella) como estaba.

    Devuelve (tiled, mirrored, desplazada): `desplazada` es la ventana que sale del mosaico (o None).
    """
    side, half = zone.split("_")
    left, right = columns(others, mirrored)
    if not others:
        return [dragged], False, None
    if len(others) == 1:
        return ([dragged, *others], False, None) if side == "left" else ([*others, dragged], False, None)
    column = left if side == "left" else right
    if len(others) == 2:  # una por columna: la de ese lado se parte en dos
        pair = [dragged, column[0]] if half == "top" else [column[0], dragged]
        left, right = (pair, right) if side == "left" else (left, pair)
        tiled, mirrored = from_columns(left, right)
        return tiled, mirrored, None
    index = 0 if half == "top" or len(column) == 1 else 1  # tres: cambia la ventana de ese sitio
    out = column[index]
    column[index] = dragged
    tiled, mirrored = from_columns(left, right)
    return tiled, mirrored, out

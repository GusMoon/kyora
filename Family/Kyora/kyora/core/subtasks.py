"""Cuentas de la lista de subtareas, sin Qt (se pueden probar): a qué sitio cae una fila arrastrada y el nuevo orden."""


def drop_index(y, row_tops, row_h):
    """Posición (0 = la primera) en la que cae una fila arrastrada cuyo centro está en `y`.

    `row_tops`: la y de arriba de cada fila (de arriba abajo); `row_h`: el alto de todas o la lista de sus altos."""
    index = 0
    for i, top in enumerate(row_tops):
        height = row_h[i] if isinstance(row_h, (list, tuple)) else row_h
        if y > top + height / 2:
            index += 1
    return min(index, max(len(row_tops) - 1, 0))


def reordered(ids, source, target):
    """`ids` con el elemento de la posición `source` puesto en `target`."""
    items = list(ids)
    if not 0 <= source < len(items):
        return items
    item = items.pop(source)
    items.insert(max(0, min(target, len(items))), item)
    return items

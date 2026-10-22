"""Formas del marco y de las piezas que sobresalen de él (funciones puras: se pueden probar sin ventanas).

Ángulos de Qt: 0° a las 3 en punto y positivos en sentido antihorario tal como se ve en pantalla.
"""
from PySide6.QtCore import QPointF, QRectF
from PySide6.QtGui import QPainterPath, QPolygonF, QTransform


def hole_rect(width, height, insets):
    left, top, right, bottom = insets
    return QRectF(left, top, width - left - right, height - top - bottom)


def frame_path(width, height, insets, radius, outer_radius=0):
    """El marco: toda la pantalla menos el hueco redondeado donde viven las ventanas.

    `outer_radius` redondea las esquinas exteriores del marco (las esquinas de la pantalla).
    Con 0 (por defecto) las esquinas exteriores son rectas.
    """
    outer = QPainterPath()
    if outer_radius > 0:
        outer.addRoundedRect(QRectF(0, 0, width, height), outer_radius, outer_radius)
    else:
        outer.addRect(QRectF(0, 0, width, height))
    return outer.subtracted(hole_path(width, height, insets, radius))


def hole_path(width, height, insets, radius):
    hole = QPainterPath()
    hole.addRoundedRect(hole_rect(width, height, insets), radius, radius)
    return hole


def mirror_vertical(path, height):
    """Voltea una forma de arriba abajo dentro de una ventana de `height` de alto (colgar del borde inferior)."""
    return QTransform(1, 0, 0, -1, 0, height).map(path)


def rotate_to_right(path, width):
    """Gira una forma pensada para colgar del borde de arriba para que cuelgue del borde derecho de una ventana de `width`."""
    return QTransform(0, 1, -1, 0, width, 0).map(path)


def corner_popout_paths(width, top, start, end, depth, joint_radius, corner_radius):
    """Pieza que cuelga del borde situado a la altura `top` y que en su final (`end`) se apoya en el borde perpendicular
    (el marco de abajo, para los paneles de la barra): la esquina queda abierta hacia ese borde.

    Mismas coordenadas que `popout_paths` (x a lo largo del borde, y hacia fuera). Empieza con la curva cóncava de
    siempre en `start`; en `end` el lado de fuera de la pieza gira con otra curva cóncava y sigue por el borde
    perpendicular. El relleno incluye la franja del borde perpendicular (de `end` hasta `width`).
    """
    d = max(float(depth), 0.0)
    joint = min(joint_radius, d / 2)
    corner = min(corner_radius, d / 2)
    bottom = top + d
    outline = QPainterPath(QPointF(0, top))
    outline.lineTo(start - joint, top)
    outline.arcTo(QRectF(start - 2 * joint, top, 2 * joint, 2 * joint), 90, -90)  # curva cóncava con la barra
    outline.lineTo(start, bottom - corner)
    outline.arcTo(QRectF(start, bottom - 2 * corner, 2 * corner, 2 * corner), 180, 90)  # esquina redondeada
    outline.lineTo(end - joint, bottom)
    outline.arcTo(QRectF(end - 2 * joint, bottom, 2 * joint, 2 * joint), 90, -90)  # curva cóncava con el marco
    outline.lineTo(end, bottom + joint + 2 * corner_radius)
    fill = QPainterPath(outline)
    fill.lineTo(width, bottom + joint + 2 * corner_radius)
    fill.lineTo(width, 0)
    fill.lineTo(0, 0)
    fill.closeSubpath()
    return fill, outline


def transpose(path):
    """Cambia x por y: una forma pensada para colgar del borde de arriba pasa a salir hacia la derecha de un borde
    vertical a la izquierda (los paneles que salen de la barra)."""
    return QTransform(0, 1, 1, 0, 0, 0).map(path)


def bulge_pill_path(cx, top, bottom, half_width, bulge_y, bulge_radius, fillet):
    """Píldora vertical estrecha con un abultamiento redondo en `bulge_y` (los escritorios de la barra).

    El abultamiento se une a la píldora con curvas cóncavas de radio `fillet`. Cada círculo de empalme es tangente
    a la vez a la píldora y al abultamiento; el rincón entre sus dos puntos de tangencia se rellena.
    """
    pill = QPainterPath()
    pill.addRoundedRect(QRectF(cx - half_width, top, 2 * half_width, bottom - top), half_width, half_width)
    bulge = QPainterPath()
    bulge.addEllipse(QPointF(cx, bulge_y), bulge_radius, bulge_radius)
    shape = pill.united(bulge)
    reach = half_width + fillet  # distancia horizontal del eje al centro de cada círculo de empalme
    if bulge_radius <= half_width or bulge_radius + fillet <= reach:
        return shape
    rise = ((bulge_radius + fillet) ** 2 - reach**2) ** 0.5  # distancia vertical del centro del abultamiento
    k = bulge_radius / (bulge_radius + fillet)  # el punto de tangencia con el abultamiento, entre los dos centros
    for sign in (-1, 1):  # cuello de arriba y de abajo
        y = bulge_y + sign * rise
        for side in (-1, 1):
            corner = QPainterPath()
            corner.addPolygon(QPolygonF([
                QPointF(cx, bulge_y),
                QPointF(cx + side * reach * k, bulge_y + sign * rise * k),  # tangencia con el abultamiento
                QPointF(cx + side * reach, y),  # centro del empalme
                QPointF(cx + side * half_width, y),  # tangencia con la píldora
                QPointF(cx, y),
            ]))
            corner.closeSubpath()
            fillet_circle = QPainterPath()
            fillet_circle.addEllipse(QPointF(cx + side * reach, y), fillet, fillet)
            shape = shape.united(corner.subtracted(fillet_circle))
    return shape.simplified()


def popout_paths(width, top, center_x, body_width, height, joint_radius, corner_radius):
    """Pieza que cuelga del borde del marco situado a la altura `top`.

    Devuelve (relleno, contorno):
    - el contorno es el borde visible: recorre el borde del marco, baja por una curva cóncava
      (radio invertido), sigue por los lados y el fondo redondeado de la pieza y sube por la otra curva;
    - el relleno es lo que queda por encima del contorno (franja del marco + pieza), del color del marco.
    Con `height` 0 la pieza no existe y el contorno es solo el borde recto del marco.
    """
    h = max(float(height), 0.0)
    half = body_width / 2
    left, right = center_x - half, center_x + half
    joint = min(joint_radius, h / 2)
    corner = min(corner_radius, h / 2, half)

    outline = QPainterPath(QPointF(0, top))
    if h > 0:
        outline.lineTo(left - joint, top)
        outline.arcTo(QRectF(left - 2 * joint, top, 2 * joint, 2 * joint), 90, -90)  # curva cóncava izquierda
        outline.lineTo(left, top + h - corner)
        outline.arcTo(QRectF(left, top + h - 2 * corner, 2 * corner, 2 * corner), 180, 90)  # esquina inferior izq.
        outline.lineTo(right - corner, top + h)
        outline.arcTo(QRectF(right - 2 * corner, top + h - 2 * corner, 2 * corner, 2 * corner), 270, 90)
        outline.lineTo(right, top + joint)
        outline.arcTo(QRectF(right, top, 2 * joint, 2 * joint), 180, -90)  # curva cóncava derecha
    outline.lineTo(width, top)

    fill = QPainterPath(outline)
    fill.lineTo(width, 0)
    fill.lineTo(0, 0)
    fill.closeSubpath()
    return fill, outline

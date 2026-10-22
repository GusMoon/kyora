"""Iconos de línea fina de la barra, dibujados a mano (no dependen de ninguna fuente de símbolos).

Cada función pinta su icono dentro de `box` (un QRectF cuadrado) con el lápiz que ya tenga el pintor.
"""
import math

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QPainterPath, QPen

STROKE = 1.4


def pen(color, width=STROKE):
    p = QPen(color, width)
    p.setCapStyle(Qt.RoundCap)
    p.setJoinStyle(Qt.RoundJoin)
    return p


def _inset(box, fraction):
    d = box.width() * fraction
    return box.adjusted(d, d, -d, -d)


def _at(box, fx, fy):
    """Punto de la caja en fracciones de su ancho y alto."""
    return QPointF(box.left() + box.width() * fx, box.top() + box.height() * fy)


def power(p, box):
    r = _inset(box, 0.16)
    p.drawArc(r, 120 * 16, 300 * 16)  # abierto arriba (de 120° a 60° por abajo)
    p.drawLine(QPointF(r.center().x(), box.top() + box.height() * 0.1), QPointF(r.center().x(), r.center().y()))


def restart(p, box):
    """Flecha que da la vuelta."""
    r = _inset(box, 0.16)
    p.drawArc(r, 90 * 16, 300 * 16)
    tip = QPointF(r.center().x(), r.top())
    s = box.width() * 0.14
    p.drawLine(tip, tip + QPointF(-s, -s))
    p.drawLine(tip, tip + QPointF(-s, s))


def moon(p, box):
    """Luna creciente (suspender)."""
    r = _inset(box, 0.18)
    outer = QPainterPath()
    outer.addEllipse(r)
    bite = QPainterPath()
    bite.addEllipse(r.translated(r.width() * 0.38, -r.height() * 0.22))
    p.drawPath(outer.subtracted(bite))


def owl(p, box):
    """Lechuza de frente: cabeza con orejas, dos ojos grandes y el pico (el icono de Kyora)."""
    body = QPainterPath(_at(box, 0.2, 0.18))
    body.lineTo(_at(box, 0.35, 0.3))  # oreja izquierda
    body.quadTo(_at(box, 0.5, 0.25), _at(box, 0.65, 0.3))
    body.lineTo(_at(box, 0.8, 0.18))  # oreja derecha
    body.cubicTo(_at(box, 0.92, 0.5), _at(box, 0.86, 0.92), _at(box, 0.5, 0.94))
    body.cubicTo(_at(box, 0.14, 0.92), _at(box, 0.08, 0.5), _at(box, 0.2, 0.18))
    p.drawPath(body)
    eye = box.width() * 0.13
    for fx in (0.36, 0.64):
        p.drawEllipse(_at(box, fx, 0.48), eye, eye)
    beak = QPainterPath(_at(box, 0.45, 0.62))
    beak.lineTo(_at(box, 0.55, 0.62))
    beak.lineTo(_at(box, 0.5, 0.72))
    beak.closeSubpath()
    p.drawPath(beak)


def sun(p, box, rays=True):
    c = box.center()
    r = box.width() * (0.2 if rays else 0.3)
    p.drawEllipse(c, r, r)
    if rays:
        for i in range(8):
            a = math.pi / 4 * i
            d1, d2 = box.width() * 0.32, box.width() * 0.44
            p.drawLine(c + QPointF(math.cos(a) * d1, math.sin(a) * d1), c + QPointF(math.cos(a) * d2, math.sin(a) * d2))


def night(p, box):
    moon(p, box)


def _cloud_path(box):
    path = QPainterPath(_at(box, 0.22, 0.72))
    path.cubicTo(_at(box, 0.02, 0.72), _at(box, 0.06, 0.42), _at(box, 0.3, 0.46))
    path.cubicTo(_at(box, 0.32, 0.18), _at(box, 0.7, 0.16), _at(box, 0.72, 0.42))
    path.cubicTo(_at(box, 0.98, 0.4), _at(box, 0.98, 0.72), _at(box, 0.78, 0.72))
    path.closeSubpath()
    return path


def cloud(p, box):
    p.drawPath(_cloud_path(box))


def partly(p, box, day=True):
    """Sol (o luna) asomando por detrás de una nube."""
    small = QRectF(box.left(), box.top(), box.width() * 0.6, box.height() * 0.6)
    (sun if day else night)(p, small)
    p.drawPath(_cloud_path(box.translated(0, box.height() * 0.12)))


def _under_cloud(p, box, draw):
    upper = box.translated(0, -box.height() * 0.14)
    p.drawPath(_cloud_path(upper))
    for fx in (0.35, 0.55, 0.75):
        draw(_at(box, fx, 0.78))


def rain(p, box):
    s = box.width() * 0.08
    _under_cloud(p, box, lambda pt: p.drawLine(pt, pt + QPointF(-s, 2 * s)))


def snow(p, box):
    s = box.width() * 0.05
    _under_cloud(p, box, lambda pt: p.drawEllipse(pt + QPointF(0, s), s, s))


def storm(p, box):
    p.drawPath(_cloud_path(box.translated(0, -box.height() * 0.14)))
    bolt = QPainterPath(_at(box, 0.55, 0.6))
    bolt.lineTo(_at(box, 0.42, 0.8))
    bolt.lineTo(_at(box, 0.56, 0.8))
    bolt.lineTo(_at(box, 0.46, 0.98))
    p.drawPath(bolt)


def fog(p, box):
    for i, fy in enumerate((0.35, 0.52, 0.69)):
        inset = 0.12 if i % 2 else 0.2
        p.drawLine(_at(box, inset, fy), _at(box, 1 - inset, fy))


WEATHER = {"sun": sun, "night": night, "partly_day": partly, "partly_night": lambda p, b: partly(p, b, day=False),
           "cloud": cloud, "rain": rain, "snow": snow, "storm": storm, "fog": fog}


def speaker(p, box, level=1.0, muted=False):
    """Altavoz con ondas según el volumen (0-1), o tachado si está en silencio."""
    body = QPainterPath(_at(box, 0.14, 0.38))
    body.lineTo(_at(box, 0.3, 0.38))
    body.lineTo(_at(box, 0.5, 0.2))
    body.lineTo(_at(box, 0.5, 0.8))
    body.lineTo(_at(box, 0.3, 0.62))
    body.lineTo(_at(box, 0.14, 0.62))
    body.closeSubpath()
    p.drawPath(body)
    if muted:
        p.drawLine(_at(box, 0.64, 0.38), _at(box, 0.86, 0.62))
        p.drawLine(_at(box, 0.86, 0.38), _at(box, 0.64, 0.62))
        return
    c = _at(box, 0.5, 0.5)
    for i, reach in enumerate((0.16, 0.3)):
        if level > 0.01 + 0.5 * i:
            r = box.width() * reach
            p.drawArc(QRectF(c.x() - r, c.y() - r, 2 * r, 2 * r), -45 * 16, 90 * 16)


def brightness(p, box):
    sun(p, _inset(box, 0.04))


def lock(p, box):
    p.drawRoundedRect(QRectF(_at(box, 0.24, 0.46), _at(box, 0.76, 0.86)), 2, 2)
    p.drawArc(QRectF(_at(box, 0.34, 0.16), _at(box, 0.66, 0.6)), 0, 180 * 16)


def arrow(p, box, direction="left"):
    """Flecha de navegación: "left", "right" o "up"."""
    c = box.center()
    s = box.width() * 0.32
    tip, tail = {"left": (QPointF(-s, 0), QPointF(s, 0)), "right": (QPointF(s, 0), QPointF(-s, 0)),
                 "up": (QPointF(0, -s), QPointF(0, s))}[direction]
    p.drawLine(c + tail, c + tip)
    w = s * 0.75
    if direction == "up":
        p.drawLine(c + tip, c + tip + QPointF(-w, w))
        p.drawLine(c + tip, c + tip + QPointF(w, w))
    else:
        back = w if direction == "left" else -w
        p.drawLine(c + tip, c + tip + QPointF(back, -w))
        p.drawLine(c + tip, c + tip + QPointF(back, w))


def magnifier(p, box):
    r = box.width() * 0.24
    c = _at(box, 0.43, 0.43)
    p.drawEllipse(c, r, r)
    p.drawLine(c + QPointF(r * 0.72, r * 0.72), _at(box, 0.82, 0.82))


def grid(p, box):
    for fx in (0.22, 0.56):
        for fy in (0.22, 0.56):
            p.drawRoundedRect(QRectF(_at(box, fx, fy), _at(box, fx + 0.22, fy + 0.22)), 1.5, 1.5)


def rows(p, box):
    for fy in (0.3, 0.5, 0.7):
        p.drawLine(_at(box, 0.2, fy), _at(box, 0.8, fy))


def dots(p, box):
    """⋮ el menú."""
    r = box.width() * 0.04
    for fy in (0.28, 0.5, 0.72):
        p.drawEllipse(_at(box, 0.5, fy), r, r)


def cross(p, box):
    p.drawLine(_at(box, 0.28, 0.28), _at(box, 0.72, 0.72))
    p.drawLine(_at(box, 0.72, 0.28), _at(box, 0.28, 0.72))


def play(p, box):
    path = QPainterPath(_at(box, 0.32, 0.22))
    path.lineTo(_at(box, 0.78, 0.5))
    path.lineTo(_at(box, 0.32, 0.78))
    path.closeSubpath()
    p.drawPath(path)


def pause(p, box):
    p.drawLine(_at(box, 0.38, 0.25), _at(box, 0.38, 0.75))
    p.drawLine(_at(box, 0.62, 0.25), _at(box, 0.62, 0.75))


def music(p, box):
    p.drawEllipse(_at(box, 0.32, 0.74), box.width() * 0.11, box.width() * 0.09)
    p.drawEllipse(_at(box, 0.72, 0.66), box.width() * 0.11, box.width() * 0.09)
    p.drawLine(_at(box, 0.42, 0.72), _at(box, 0.42, 0.22))
    p.drawLine(_at(box, 0.82, 0.64), _at(box, 0.82, 0.16))
    p.drawLine(_at(box, 0.42, 0.22), _at(box, 0.82, 0.16))


def bluetooth(p, box):
    """La runa del Bluetooth."""
    path = QPainterPath(_at(box, 0.3, 0.32))
    path.lineTo(_at(box, 0.7, 0.68))
    path.lineTo(_at(box, 0.5, 0.86))
    path.lineTo(_at(box, 0.5, 0.14))
    path.lineTo(_at(box, 0.7, 0.32))
    path.lineTo(_at(box, 0.3, 0.68))
    p.drawPath(path)


def calendar(p, box):
    p.drawRoundedRect(QRectF(_at(box, 0.16, 0.22), _at(box, 0.84, 0.86)), 2.5, 2.5)
    p.drawLine(_at(box, 0.16, 0.4), _at(box, 0.84, 0.4))
    for fx in (0.34, 0.66):
        p.drawLine(_at(box, fx, 0.12), _at(box, fx, 0.3))
    r = box.width() * 0.03
    for fx in (0.34, 0.5, 0.66):
        for fy in (0.56, 0.72):
            p.drawEllipse(_at(box, fx, fy), r, r)


def home(p, box):
    """Casita de las migas de pan."""
    path = QPainterPath(_at(box, 0.18, 0.48))
    path.lineTo(_at(box, 0.5, 0.18))
    path.lineTo(_at(box, 0.82, 0.48))
    p.drawPath(path)
    p.drawRoundedRect(QRectF(_at(box, 0.28, 0.44), _at(box, 0.72, 0.84)), 2, 2)


def folder(p, box):
    path = QPainterPath(_at(box, 0.14, 0.28))
    path.lineTo(_at(box, 0.4, 0.28))
    path.lineTo(_at(box, 0.48, 0.36))
    path.lineTo(_at(box, 0.86, 0.36))
    path.lineTo(_at(box, 0.86, 0.8))
    path.lineTo(_at(box, 0.14, 0.8))
    path.closeSubpath()
    p.drawPath(path)


def chip(p, box):
    """Procesador: Sistema."""
    p.drawRoundedRect(QRectF(_at(box, 0.28, 0.28), _at(box, 0.72, 0.72)), 2, 2)
    for f in (0.4, 0.6):
        for a, b in (((f, 0.14), (f, 0.28)), ((f, 0.72), (f, 0.86)), ((0.14, f), (0.28, f)), ((0.72, f), (0.86, f))):
            p.drawLine(_at(box, *a), _at(box, *b))


def task(p, box):
    """Tareas: una casilla redondeada con su marca."""
    p.drawRoundedRect(QRectF(_at(box, 0.18, 0.18), _at(box, 0.82, 0.82)), 4, 4)
    path = QPainterPath(_at(box, 0.34, 0.5))
    path.lineTo(_at(box, 0.46, 0.62))
    path.lineTo(_at(box, 0.68, 0.38))
    p.drawPath(path)


def brain(p, box):
    """Segundo Cerebro: una neurona (núcleo y dendritas que salen de él)."""
    center = _at(box, 0.5, 0.5)
    r = box.width() * 0.13
    p.drawEllipse(center, r, r)
    for angle in (-90, -18, 54, 126, 198):
        a = math.radians(angle)
        start = QPointF(center.x() + math.cos(a) * r, center.y() + math.sin(a) * r)
        end = QPointF(center.x() + math.cos(a) * box.width() * 0.36, center.y() + math.sin(a) * box.width() * 0.36)
        p.drawLine(start, end)
        tip = box.width() * 0.045
        p.drawEllipse(end, tip, tip)


def clock(p, box):
    """Reloj pequeño (la hora de entrega de una tarea)."""
    center = _at(box, 0.5, 0.5)
    r = box.width() * 0.36
    p.drawEllipse(center, r, r)
    p.drawLine(center, _at(box, 0.5, 0.3))
    p.drawLine(center, _at(box, 0.64, 0.58))


def plus(p, box):
    p.drawLine(_at(box, 0.5, 0.2), _at(box, 0.5, 0.8))
    p.drawLine(_at(box, 0.2, 0.5), _at(box, 0.8, 0.5))


def trash(p, box):
    p.drawLine(_at(box, 0.2, 0.28), _at(box, 0.8, 0.28))
    p.drawLine(_at(box, 0.4, 0.28), _at(box, 0.42, 0.16))
    p.drawLine(_at(box, 0.42, 0.16), _at(box, 0.58, 0.16))
    p.drawLine(_at(box, 0.58, 0.16), _at(box, 0.6, 0.28))
    path = QPainterPath(_at(box, 0.28, 0.28))
    path.lineTo(_at(box, 0.33, 0.84))
    path.lineTo(_at(box, 0.67, 0.84))
    path.lineTo(_at(box, 0.72, 0.28))
    p.drawPath(path)


def chevron(p, box, direction="up"):
    """Flecha pequeña (subir o bajar una subtarea)."""
    if direction == "up":
        points = (_at(box, 0.28, 0.6), _at(box, 0.5, 0.38), _at(box, 0.72, 0.6))
    else:
        points = (_at(box, 0.28, 0.4), _at(box, 0.5, 0.62), _at(box, 0.72, 0.4))
    path = QPainterPath(points[0])
    for point in points[1:]:
        path.lineTo(point)
    p.drawPath(path)

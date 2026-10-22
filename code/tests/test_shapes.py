"""Formas del marco y del buscador que sale de él."""
from PySide6.QtCore import QPointF

from kyora.ui.shapes import frame_path, hole_rect, popout_paths
from kyora.ui.theme import THEME

W, H = 1536, 960
INSETS = (46, 8, 8, 8)


def inside(path, x, y):
    return path.contains(QPointF(x, y))


def test_frame_covers_the_edges_and_leaves_the_hole_free():
    frame = frame_path(W, H, INSETS, 16)
    assert inside(frame, 20, 480)        # la barra izquierda
    assert inside(frame, 700, 4)         # borde superior
    assert inside(frame, W - 4, 480)     # borde derecho
    assert not inside(frame, 700, 480)   # centro del hueco
    assert inside(frame, 48, 10)         # la esquina interior es redondeada: el marco la rellena
    assert not inside(frame, 46 + 16, 8 + 16)


def test_hole_matches_the_insets():
    rect = hole_rect(W, H, INSETS)
    assert (rect.left(), rect.top(), rect.right(), rect.bottom()) == (46, 8, W - 8, H - 8)


def test_popout_hangs_from_the_frame_with_concave_joints():
    fill, outline = popout_paths(800, 8, 400, 560, 340, 22, 18)
    assert inside(fill, 400, 200)          # el cuerpo del buscador
    assert inside(fill, 10, 4)             # la franja del marco
    assert not inside(fill, 10, 30)        # fuera de la pieza, bajo el marco: transparente
    # curva cóncava izquierda: rellena el rincón entre el marco y el lado de la pieza...
    left = 400 - 280
    assert inside(fill, left - 2, 8 + 2)
    # ...pero no más allá del cuarto de círculo
    assert not inside(fill, left - 20, 8 + 20)
    assert outline.length() > 2 * 340      # el contorno baja por los lados


def test_closed_popout_is_just_the_frame_edge():
    fill, outline = popout_paths(800, 8, 400, 560, 0, 22, 18)
    assert not inside(fill, 400, 12)
    assert outline.length() == 800


def test_small_popout_shrinks_its_curves():
    fill, _ = popout_paths(800, 8, 400, 560, 10, 22, 18)
    assert inside(fill, 400, 12)
    assert not inside(fill, 400, 20)


def test_theme_is_consistent():
    assert THEME.joint_radius * 2 < THEME.search_rows * 34
    assert THEME.corner_radius * 2 < THEME.search_width
    assert all(v > 0 for v in THEME.insets())
    assert THEME.font_px >= 13


def test_hole_edge_is_the_same_on_every_side():
    from kyora.ui.relief import build_frame_image

    w, h = 900, 700
    image = build_frame_image(THEME, w, h)
    left, top, right, bottom = THEME.insets()
    alpha = lambda x, y: image.pixelColor(x, y).alphaF()
    # (x, y, paso hacia dentro del hueco) de cada lado, empezando en el primer píxel del hueco
    sides = ((w // 2, top, (0, 1)), (w // 2, h - bottom - 1, (0, -1)), (left, h // 2, (1, 0)), (w - right - 1, h // 2, (-1, 0)))
    clear = round(THEME.edge_width + THEME.edge_shadow_size + 2)
    edges = []
    for x, y, (dx, dy) in sides:
        edges.append(alpha(x, y))
        assert alpha(x, y) > alpha(x + 3 * dx, y + 3 * dy) > 0, (x, y)  # línea oscura y sombra que se desvanece
        assert alpha(x + clear * dx, y + clear * dy) == 0, (x, y)        # el resto del hueco queda limpio
    assert max(edges) - min(edges) < 0.02, edges  # ningún lado se ve distinto
    assert alpha(w // 2, h // 2) == 0
    # filete de luz por dentro del marco: el filo es más claro que el marco de al lado
    assert image.pixelColor(w // 2, top - 1).lightness() > image.pixelColor(w // 2, top - 5).lightness()
    assert image.pixelColor(w // 2, h - bottom).lightness() > image.pixelColor(w // 2, h - bottom + 4).lightness()
    assert alpha(w // 2, 2) == 1  # el marco es opaco
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):  # esquinas de la pantalla rectas
        assert image.pixelColor(x, y).alphaF() == 1, (x, y)
    for x, y in ((left + 1, top + 1), (w - right - 2, top + 1), (left + 1, h - bottom - 2), (w - right - 2, h - bottom - 2)):
        assert image.pixelColor(x, y).alphaF() == 1, (x, y)  # las 4 esquinas del hueco, redondeadas


def test_side_bar_keeps_its_width():
    """Si la barra se ensancha tapa la curva de las esquinas izquierdas del hueco."""
    from PySide6.QtCore import QRect
    from PySide6.QtWidgets import QApplication

    from kyora.ui.bar import SideBar

    app = QApplication.instance() or QApplication([])
    screen_map = type("Map", (), {"geometry": QRect(0, 0, 1536, 960), "dpr": 1.25})()
    bar = SideBar(THEME, screen_map, lambda *a, **k: None)
    bar.dots.set_desktops([{"index": 0, "name": "1", "count": 0, "active": True}])
    bar.adjustSize()
    assert bar.width() == THEME.bar_width
    assert bar.minimumSizeHint().width() <= THEME.bar_width
    bar.deleteLater()
    app.processEvents()


def test_frame_material_is_lighter_at_the_top():
    from kyora.ui.relief import build_frame_image

    image = build_frame_image(THEME, 900, 700)
    assert image.pixelColor(20, 30).lightness() > image.pixelColor(20, 670).lightness()


def test_popout_can_hang_from_the_bottom_edge():
    from kyora.ui.shapes import mirror_vertical

    height = 400
    fill, _ = popout_paths(800, 8, 400, 560, 100, 22, 18)  # colgado del borde de arriba
    flipped = mirror_vertical(fill, height)
    assert inside(flipped, 400, height - 50)      # el cuerpo queda abajo
    assert inside(flipped, 10, height - 4)        # la franja del marco, en el borde inferior
    assert not inside(flipped, 400, 50)           # lo de arriba queda libre
    left = 400 - 280
    assert inside(flipped, left - 2, height - 8 - 2)      # curva cóncava pegada al marco de abajo
    assert not inside(flipped, left - 20, height - 8 - 20)


def test_every_theme_field_used_by_the_ui_exists():
    """Un campo del tema que se lee y no existe solo fallaba al pintar el contorno: se comprueba todo el código."""
    import re
    from pathlib import Path

    from kyora.ui.theme import Theme

    fields = set(Theme.__dataclass_fields__) | {"insets", "margins", "with_accent"}
    used = set()
    for path in (Path(__file__).parent.parent / "kyora" / "ui").glob("*.py"):
        used |= set(re.findall(r"\b(?:theme|t)\.([a-z_]+)\b", path.read_text(encoding="utf-8")))
    assert not (used - fields - {"x", "y", "width", "height"}), sorted(used - fields)


def test_popout_can_hang_from_the_right_edge():
    from kyora.ui.shapes import rotate_to_right

    width, length = 300, 600
    fill, _ = popout_paths(length, 8, length / 2, 400, 120, 22, 18)  # colgado del borde de arriba, 120 de fondo
    rotated = rotate_to_right(fill, width)
    assert inside(rotated, width - 60, length / 2)       # el cuerpo queda pegado a la derecha
    assert inside(rotated, width - 4, 10)                # la franja del marco, en el borde derecho
    assert not inside(rotated, 40, length / 2)           # a la izquierda queda libre
    top = (length - 400) / 2
    assert inside(rotated, width - 8 - 2, top - 2)       # curva cóncava pegada al marco
    assert not inside(rotated, width - 8 - 20, top - 20)


def test_transpose_makes_a_piece_grow_right_from_the_bar():
    from kyora.ui.shapes import transpose

    length = 600
    fill, _ = popout_paths(length, 3, length / 2, 400, 120, 22, 18)
    piece = transpose(fill)
    assert inside(piece, 60, length / 2)                 # el cuerpo sale hacia la derecha de la barra
    assert not inside(piece, 200, length / 2)            # no pasa de su fondo (3 + 120)
    assert not inside(piece, 60, 20)                     # fuera de su largo queda libre


def test_top_popout_hangs_from_the_top_edge():
    length, depth = 800, 300
    fill, _ = popout_paths(length + 52, 8, (length + 52) / 2, length, depth, 22, 18)  # como el borde "top"
    assert inside(fill, (length + 52) / 2, 8 + depth - 20)      # el cuerpo baja desde el marco
    assert not inside(fill, (length + 52) / 2, 8 + depth + 10)  # y no pasa de su fondo
    assert inside(fill, 4, 4)                                    # la franja del marco arriba


def test_corner_popout_rests_on_the_perpendicular_border():
    from kyora.ui.shapes import corner_popout_paths

    width, top, start, end, depth, joint = 900, 3, 400, 856, 300, 22
    fill, _ = corner_popout_paths(width, top, start, end, depth, joint, 18)
    assert inside(fill, 600, top + depth - 20)            # el cuerpo de la pieza
    assert inside(fill, end - 4, top + depth + 4)         # la curva cóncava con el marco de abajo rellena la esquina
    assert not inside(fill, end - joint - 2, top + depth + 4)  # antes de la curva, fuera de la pieza
    assert inside(fill, end + 10, top + depth + 30)       # la franja del marco de abajo
    assert not inside(fill, start - joint - 10, top + 40)  # antes del inicio queda libre


def test_bulge_pill_joins_the_bulge_with_concave_curves():
    from kyora.ui.shapes import bulge_pill_path

    cx, half, bulge_y, radius, fillet = 20, 9, 80, 16, 6
    path = bulge_pill_path(cx, 0, 200, half, bulge_y, radius, fillet)
    assert inside(path, cx, 5) and inside(path, cx, 195)       # la píldora de arriba abajo
    assert inside(path, cx + radius - 1, bulge_y)              # el abultamiento
    assert not inside(path, cx + half + 2, 30)                 # lejos del abultamiento, solo la píldora estrecha
    reach = half + fillet
    rise = ((radius + fillet) ** 2 - reach**2) ** 0.5
    # el cuello rellena el rincón (fuera de la píldora y del abultamiento) hasta la curva cóncava...
    assert inside(path, cx + half + 0.5, bulge_y - 13.3)
    assert not inside(path, cx + reach, bulge_y - rise)           # ...pero no el círculo de empalme


def test_waiting_stack_centers_the_chosen_card_and_narrows_the_rest():
    from itertools import pairwise

    from kyora.ui.switcher import stack_layout

    rects = stack_layout([1.6] * 5, 2, 1000, 800)
    widths = [w for _, _, w, _ in rects]
    assert widths[2] == max(widths) and widths[1] == widths[3] > widths[0] == widths[4]
    _, y, _, h = rects[2]
    assert abs(y + h / 2 - 400) < 1e-6                        # la elegida, centrada en vertical
    assert all(r[0] == 0 for r in rects)                       # alineadas a la izquierda
    for (_, y1, _, h1), (_, y2, _, _) in pairwise(rects):
        assert abs(y1 + h1 - y2) < 1e-6                       # sin hueco entre tarjetas
    assert stack_layout([], 0, 1000, 800) == []

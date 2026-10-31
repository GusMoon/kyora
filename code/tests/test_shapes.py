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
    assert THEME.insets() == (0, 0, 0, 0)  # sin marco: las ventanas usan toda la pantalla
    assert THEME.font_px >= 11  # un solo tamaño de letra, pequeño por decisión de Gustavo


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


def test_hanging_panel_hangs_from_the_top_edge_with_rounded_bottom_corners():
    from kyora.ui.shapes import hanging_paths

    fill, outline = hanging_paths(100, 500, 200, 18)
    assert inside(fill, 300, 100)              # el cuerpo
    assert inside(fill, 300, 2)                # pegado al borde de arriba
    assert not inside(fill, 300, 210)          # no pasa de su fondo
    assert not inside(fill, 90, 100)           # ni de sus lados
    assert not inside(fill, 101, 199)          # la esquina de abajo es redonda
    assert outline.length() > 2 * 200          # el contorno baja por los lados y rodea el fondo
    closed, _ = hanging_paths(100, 500, 0, 18)
    assert not inside(closed, 300, 4)          # sin fondo no hay pieza


def test_hanging_panel_flares_into_small_tabs_where_it_meets_the_screen_edge():
    from kyora.ui.shapes import hanging_paths

    fill, _ = hanging_paths(100, 500, 200, 10, joint=12)
    assert inside(fill, 95, 1)                 # la pestaña ensancha la pieza justo en el borde...
    assert inside(fill, 505, 1)
    assert not inside(fill, 92, 20)            # ...y a un palmo del borde ya no está
    assert not inside(fill, 86, 1)             # la pestaña no pasa de su radio
    assert inside(fill, 300, 100)


def test_a_corner_panel_can_keep_its_far_end_square():
    from kyora.ui.shapes import hanging_paths

    round_fill, _ = hanging_paths(100, 500, 200, 18)
    square_fill, _ = hanging_paths(100, 500, 200, 18, square_end=True)
    assert not inside(round_fill, 499, 199)    # la esquina del final es redonda...
    assert inside(square_fill, 499, 199)       # ...o recta si el panel está pegado a otro borde
    assert not inside(square_fill, 101, 199)   # la del principio sigue siendo redonda


def test_a_corner_panel_flares_into_the_screen_edge_at_its_far_end():
    from kyora.ui.shapes import hanging_paths

    fill, _ = hanging_paths(100, 500, 200, 18, joint=12, square_end=True)
    assert inside(fill, 499, 203)              # la curva cóncava sube pegada al borde de la pantalla...
    assert not inside(fill, 490, 206)          # ...dejando el hueco redondo bajo la curva...
    assert not inside(fill, 499, 216)          # ...sin pasar de su altura
    assert inside(fill, 300, 100) and not inside(fill, 300, 215)

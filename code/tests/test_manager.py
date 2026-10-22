import pytest
from fakes import FakeSystem

from kyora.core.actions import ActionError
from kyora.core.layout import Rect
from kyora.wm.manager import WindowManager

CONFIG = {"insets": (0, 56, 0, 0), "gap": 8, "outer_gap": 8}


class Clock:
    def __init__(self):
        self.now = 1000.0

    def __call__(self):
        return self.now


@pytest.fixture
def env():
    system = FakeSystem()
    clock = Clock()
    events = []
    manager = WindowManager(system, CONFIG, notify=lambda: events.append(1), clock=clock)
    return system, manager, clock, events


def open_windows(system, manager, *hwnds):
    for h in hwnds:
        system.open(h)
        manager.sync()


def test_first_three_visible_rest_waiting_and_hidden(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4, 5)
    snap = m.snapshot()
    assert [w["hwnd"] for w in snap["visible"]] == [1, 2, 3]
    assert [w["hwnd"] for w in snap["waiting"]] == [4, 5]
    assert not system.is_shown(4) and not system.is_shown(5)
    assert all(system.is_shown(h) for h in (1, 2, 3))


def test_windows_never_overlap_the_bar(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3)
    assert all(r.top >= 56 for r in system.rects.values())


def test_closing_visible_promotes_waiting(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4)
    system.kill(2)
    m.sync()
    snap = m.snapshot()
    assert [w["hwnd"] for w in snap["visible"]] == [1, 3, 4]
    assert snap["waiting"] == []
    assert system.is_shown(4)


def test_minimized_visible_goes_to_waiting_and_is_hidden(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.minimized.add(2)
    m.sync()
    snap = m.snapshot()
    assert [w["hwnd"] for w in snap["visible"]] == [1]
    assert [w["hwnd"] for w in snap["waiting"]] == [2]
    assert not system.is_shown(2)


def test_unpark_with_room_adds_window(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.minimized.add(2)
    m.sync()
    m.unpark(2)
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [1, 2]
    assert system.is_shown(2) and system.fg == 2


def test_unpark_when_full_replaces_focused(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4)
    system.fg = 2
    m.unpark(4)
    snap = m.snapshot()
    assert [w["hwnd"] for w in snap["visible"]] == [1, 4, 3]
    assert [w["hwnd"] for w in snap["waiting"]] == [2]
    assert not system.is_shown(2)


def test_unpark_visible_window_is_an_error(env):
    system, m, _, _ = env
    open_windows(system, m, 1)
    with pytest.raises(ActionError):
        m.unpark(1)


def test_drop_on_slot_replaces_that_window(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4)
    slot_of_3 = system.rects[3]
    assert m.drop(4, *slot_of_3.center) is True
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [1, 2, 4]
    assert [w["hwnd"] for w in m.snapshot()["waiting"]] == [3]


def test_drop_outside_slots_does_nothing(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4)
    assert m.drop(4, 10, 10) is False  # sobre la barra
    assert [w["hwnd"] for w in m.snapshot()["waiting"]] == [4]


def test_park_swaps_with_first_waiting_in_same_slot(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4)
    system.fg = 2
    m.park()
    snap = m.snapshot()
    assert [w["hwnd"] for w in snap["visible"]] == [1, 4, 3]
    assert [w["hwnd"] for w in snap["waiting"]] == [2]


def test_park_without_waiting_shrinks_layout_and_is_not_repromoted(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.fg = 2
    m.park()
    m.sync()
    snap = m.snapshot()
    assert [w["hwnd"] for w in snap["visible"]] == [1]
    assert [w["hwnd"] for w in snap["waiting"]] == [2]


def test_move_swaps_slots(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.fg = 1
    m.move_dir("right")
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [2, 1]


def test_focus_moves_to_neighbor(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.fg = 1
    m.focus_dir("right")
    assert system.fg == 2


def test_orientation_and_flip_change_layout(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    side_by_side = system.rects[2]
    m.orientation_toggle()
    stacked = system.rects[2]
    assert stacked != side_by_side and stacked.top > system.rects[1].top
    m.flip()
    assert system.rects[2].top < system.rects[1].top


def test_desktops_hide_and_restore_windows(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    m.desktop_create()
    assert not system.is_shown(1) and not system.is_shown(2)
    open_windows(system, m, 3)
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [3]
    m.desktop_switch(0)
    assert system.is_shown(1) and system.is_shown(2) and not system.is_shown(3)


def test_switch_to_next_index_creates_desktop(env):
    _, m, _, _ = env
    m.desktop_switch(1)
    assert len(m.snapshot()["desktops"]) == 2
    with pytest.raises(ActionError):
        m.desktop_switch(5)


def test_send_to_desktop_moves_focused_window(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.fg = 2
    m.send_to_desktop(1)
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [1]
    assert not system.is_shown(2)
    m.desktop_switch(1)
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [2]


def test_close_desktop_moves_windows_to_previous(env):
    system, m, _, _ = env
    open_windows(system, m, 1)
    m.desktop_create()
    open_windows(system, m, 2)
    m.desktop_close(1)
    snap = m.snapshot()
    assert len(snap["desktops"]) == 1
    assert [w["hwnd"] for w in snap["visible"]] == [1, 2]


def test_cannot_close_last_desktop(env):
    _, m, _, _ = env
    with pytest.raises(ActionError):
        m.desktop_close(0)


def test_rename_desktop(env):
    _, m, _, _ = env
    m.desktop_rename(0, "  Trabajo  ")
    assert m.snapshot()["desktops"][0]["name"] == "Trabajo"
    with pytest.raises(ActionError):
        m.desktop_rename(0, "   ")


def test_floating_window_is_released_and_readopted(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.fg = 2
    m.float_toggle()
    m.sync()
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [1]
    system.fg = 2
    m.float_toggle()
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [1, 2]


def test_launch_from_search_replaces_focused_when_full(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3)
    system.fg = 2
    m.sync()
    m.expect_launch()
    open_windows(system, m, 9)
    snap = m.snapshot()
    assert [w["hwnd"] for w in snap["visible"]] == [1, 9, 3]
    assert [w["hwnd"] for w in snap["waiting"]] == [2]


def test_launch_replacement_expires(env):
    system, m, clock, _ = env
    open_windows(system, m, 1, 2, 3)
    m.expect_launch()
    clock.now += 60
    open_windows(system, m, 9)
    assert [w["hwnd"] for w in m.snapshot()["waiting"]] == [9]


def test_activate_switches_desktop_and_unparks(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4)
    m.desktop_create()
    m.activate(4)
    assert m.snapshot()["desktops"][0]["active"]
    assert 4 in [w["hwnd"] for w in m.snapshot()["visible"]]


def test_release_all_shows_every_hidden_window(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4)
    m.desktop_create()
    assert m.release_all() == 4
    assert all(system.is_shown(h) for h in (1, 2, 3, 4))


def test_bad_direction_rejected(env):
    _, m, _, _ = env
    with pytest.raises(ActionError):
        m.focus_dir("diagonal")


def test_sync_is_quiet_when_nothing_changes(env):
    system, m, _, events = env
    open_windows(system, m, 1, 2)
    events.clear()
    m.sync()
    assert events == []


# ---------- mover cualquier ventana a cualquier hueco ----------


def test_drop_visible_window_swaps_with_target_slot(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3)
    assert m.drop(1, *system.rects[3].center) is True
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [3, 2, 1]
    assert system.fg == 1


def test_drop_visible_outside_slots_snaps_back(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    original = system.rects[1]
    system.rects[1] = type(original)(700, 300, 900, 500)  # el usuario la arrastró
    assert m.drop(1, 10, 10) is False
    assert system.rects[1] == original
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [1, 2]


def test_drop_visible_on_own_slot_changes_nothing(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    assert m.drop(1, *system.rects[1].center) is False
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [1, 2]


def test_move_to_slot_moves_focused_window(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3)
    system.fg = 3
    m.move_to_slot(0)
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [3, 2, 1]


def test_move_to_slot_brings_waiting_window_into_slot(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4)
    m.move_to_slot(1, hwnd=4)
    snap = m.snapshot()
    assert [w["hwnd"] for w in snap["visible"]] == [1, 4, 3]
    assert [w["hwnd"] for w in snap["waiting"]] == [2]


def test_move_to_slot_rejects_missing_slot(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    with pytest.raises(ActionError):
        m.move_to_slot(2)


# ---------- tamaño de las divisiones ----------


def test_resize_with_keyboard_moves_the_border(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    before = system.rects[1].width
    m.resize("right")
    assert system.rects[1].width > before
    m.resize("left")
    m.resize("left")
    assert system.rects[1].width < before


def test_resize_in_axis_without_split_does_nothing(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    before = dict(system.rects)
    m.resize("down")
    assert system.rects == before


def test_resize_from_drag_keeps_new_split(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    old = system.rects[1]
    system.rects[1] = type(old)(old.left, old.top, old.right + 200, old.bottom)  # arrastró su borde derecho
    assert m.resize_from_drag(1) is True
    assert system.rects[1].width > old.width + 150
    assert system.rects[2].width < old.width - 150


def test_resize_from_drag_ignores_outer_edges(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    old = system.rects[1]
    system.rects[1] = type(old)(old.left + 100, old.top, old.right, old.bottom)  # borde izquierdo: el de la pantalla
    assert m.resize_from_drag(1) is False
    assert system.rects[1] == old


def test_resize_from_drag_ignores_tiny_changes(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    old = system.rects[1]
    system.rects[1] = type(old)(old.left, old.top, old.right + 3, old.bottom)
    assert m.resize_from_drag(1) is False
    assert system.rects[1] == old


def test_resize_keeps_ratio_per_desktop(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    m.resize("right")
    m.desktop_create()
    open_windows(system, m, 3, 4)
    assert system.rects[3].width == system.rects[4].width  # el escritorio nuevo parte del 50/50


# ---------- foco con el ratón y utilidades ----------


def test_focus_at_focuses_window_under_cursor(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.fg = 1
    system.under = 2
    assert m.focus_at(*system.rects[2].center) is True
    assert system.fg == 2


def test_focus_at_ignores_cursor_over_other_windows(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.fg = 1
    system.under = 999  # algo flotante o la barra está encima
    assert m.focus_at(*system.rects[2].center) is False
    assert system.fg == 1


def test_focus_at_does_nothing_when_already_focused_or_over_gap(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.fg = 2
    system.under = 2
    assert m.focus_at(*system.rects[2].center) is False
    assert m.focus_at(5, 5) is False


def test_slot_rect_helpers(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3)
    assert m.slot_rect_at(*system.rects[2].center) == system.rects[2]
    assert m.slot_rect_at(5, 5) is None
    assert m.slot_rect(3) == system.rects[3]
    assert m.is_tiled(1) and not m.is_tiled(99)


def test_switching_desktops_shows_before_hiding(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    m.desktop_create()
    open_windows(system, m, 3)
    system.calls.clear()
    m.desktop_switch(0)
    kinds = [kind for kind, _ in system.calls]
    assert kinds.index("show") < kinds.index("hide")


def test_area_is_the_hole_inside_the_frame():
    system = FakeSystem()
    framed = WindowManager(system, {**CONFIG, "insets": (55, 10, 10, 10)}, notify=lambda: None)
    system.open(1)
    framed.sync()
    gap = CONFIG["outer_gap"]
    assert system.rects[1] == Rect(55 + gap, 10 + gap, 1920 - 10 - gap, 1200 - 10 - gap)


def test_area_without_insets_is_the_whole_work_area():
    system = FakeSystem()
    bare = WindowManager(system, {"gap": 8, "outer_gap": 8}, notify=lambda: None)
    system.open(1)
    bare.sync()
    assert system.rects[1] == Rect(8, 8, 1912, 1192)


def _manager(gap=0, single=14, multi=20):
    system = FakeSystem()
    cfg = {"insets": (46, 8, 8, 8), "gap": gap, "outer_gap": single, "outer_gap_multi": multi}
    return system, WindowManager(system, cfg, notify=lambda: None)


def test_one_window_keeps_the_single_margin_from_the_frame():
    system, m = _manager()
    system.open(1)
    m.sync()
    assert system.rects[1] == Rect(46 + 14, 8 + 14, 1920 - 8 - 14, 1200 - 8 - 14)


def test_several_windows_use_a_slightly_larger_margin():
    system, m = _manager()
    open_windows(system, m, 1, 2)
    rects = list(system.rects.values())
    assert min(r.left for r in rects) == 46 + 20 and max(r.right for r in rects) == 1920 - 8 - 20
    assert min(r.top for r in rects) == 8 + 20 and max(r.bottom for r in rects) == 1200 - 8 - 20


def test_windows_are_flush_with_no_gap_between_them():
    system, m = _manager()
    open_windows(system, m, 1, 2, 3)
    big, top, bottom = sorted(system.rects.values(), key=lambda r: (r.left, r.top))
    assert big.right == top.left == bottom.left   # sin hueco entre columnas
    assert top.bottom == bottom.top               # ni entre las dos apiladas


@pytest.mark.parametrize("orientation", ["columns", "rows"])
@pytest.mark.parametrize("mirrored", [False, True])
@pytest.mark.parametrize("count", [1, 2, 3])
def test_windows_never_leave_the_frame(orientation, mirrored, count):
    system, m = _manager()
    open_windows(system, m, *range(1, count + 1))
    if orientation == "rows":
        m.orientation_toggle()
    if mirrored:
        m.flip()
    hole = Rect(46, 8, 1920 - 8, 1200 - 8)
    for r in system.rects.values():
        assert hole.left < r.left and r.right < hole.right and hole.top < r.top and r.bottom < hole.bottom


# ---------- ver 1, 2 o 3 ventanas, solo una, traer y aparcar ----------

def _three(env_system=None):
    system, m = _manager()
    open_windows(system, m, 1, 2, 3, 4)  # 4 -> en espera
    return system, m


def test_solo_keeps_only_the_focused_window_and_parks_the_rest():
    system, m = _three()
    system.fg = 2
    m.solo()
    cur = m._current()
    assert cur.visible == [2] and sorted(cur.waiting) == [1, 3, 4]
    assert not {1, 3, 4} & system.shown          # no se cierran: se ocultan para poder traerlas
    assert system.closed == []


def test_show_count_grows_back_from_the_waiting_list():
    _, m = _three()
    m.show_count(1)
    m.show_count(3)
    assert len(m._current().visible) == 3
    m.show_count(2)
    assert len(m._current().visible) == 2 and len(m._current().waiting) == 2


def test_show_count_never_parks_the_focused_window():
    system, m = _three()
    system.fg = 3
    m.show_count(2)
    assert 3 in m._current().visible
    system.fg = 1
    m.show_count(1)
    assert m._current().visible == [1]


@pytest.mark.parametrize("bad", [0, 4, -1, "2"])
def test_show_count_rejects_impossible_numbers(bad):
    _, m = _three()
    with pytest.raises(ActionError):
        m.show_count(bad)


def test_unpark_next_and_park_last_round_trip():
    system, m = _manager()
    open_windows(system, m, 1, 2)
    system.fg = 1
    m.park_last()
    assert m._current().visible == [1] and m._current().waiting == [2]
    m.unpark_next()
    assert sorted(m._current().visible) == [1, 2] and m._current().waiting == []
    with pytest.raises(ActionError):
        m.unpark_next()


def test_park_last_never_parks_the_only_window():
    system, m = _manager()
    open_windows(system, m, 1)
    m.park_last()
    assert m._current().visible == [1]


def test_thumbnail_is_taken_just_before_a_window_is_hidden():
    system, m = _three()
    system.fg = 1
    m.solo()
    assert m.thumbnail(2) == (2, 1, bytes([2]) * 8)   # se capturó mientras aún se veía
    assert m.thumbnail(99) is None


def test_snapshot_includes_the_executable_path():
    _, m = _three()
    assert m.snapshot()["waiting"][0]["exe"] == "C:/fake/App4.exe"


def test_swap_into_focused_takes_the_slot_of_the_focused_window(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4)
    system.fg = 2
    slot_of_2 = m.slot_rect(2)
    m.swap_into_focused(4)
    snap = m.snapshot()
    assert [w["hwnd"] for w in snap["visible"]] == [1, 4, 3]   # la elegida, en el hueco de la enfocada
    assert [w["hwnd"] for w in snap["waiting"]] == [2]          # y la que estaba pasa a espera
    assert m.slot_rect(4) == slot_of_2


def test_swap_into_focused_replaces_even_with_free_room(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3)
    system.fg = 1
    m.park_last()  # 1 y 2 visibles, 3 en espera: hay sitio libre, pero se cambia en el hueco enfocado
    m.swap_into_focused(3)
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [3, 2]


def test_switcher_opens_over_the_focused_slot(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.fg = 2
    assert m.switcher_rect() == m.slot_rect(2)


def test_swap_into_focused_rejects_windows_not_waiting(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    with pytest.raises(ActionError):
        m.swap_into_focused(2)


def test_desktop_step_moves_one_and_stops_at_the_ends(env):
    _, m, _, _ = env
    m.desktop_create()
    m.desktop_create()
    assert m.active == 2
    m.desktop_step(1)
    assert m.active == 2  # el último: no da la vuelta
    m.desktop_step(-1)
    assert m.active == 1
    m.desktop_step(-1)
    m.desktop_step(-1)
    assert m.active == 0


def test_zoom_fills_the_hole_keeps_the_others_and_toggles_back(env):
    system, m, _, _ = env
    cfg = dict(CONFIG, outer_gap_multi=8)
    m.cfg = cfg
    open_windows(system, m, 1, 2, 3)
    system.fg = 1
    before = {h: system.rects[h] for h in (1, 2, 3)}
    m.zoom_toggle()
    area = system.work_area()
    left, top, right, bottom = cfg["insets"]
    assert system.rects[1] == Rect(area.left + left + 8, area.top + top + 8, area.right - right - 8, area.bottom - bottom - 8)
    assert system.rects[2] == before[2] and system.rects[3] == before[3]  # las demás no se mueven
    assert [w["hwnd"] for w in m.snapshot()["visible"]] == [1, 2, 3]       # ni pasan a espera
    assert m.slot_rect_at(*system.rects[2].center) == system.rects[1]     # la grande manda en todo el hueco
    m.zoom_toggle()
    assert system.rects[1] == before[1]


def test_zoom_is_undone_when_the_window_is_parked_or_focus_moves(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    system.fg = 1
    m.zoom_toggle()
    zoomed = system.rects[1]
    system.fg = 2  # el foco pasa a la otra ventana del mosaico
    m.sync()
    assert system.rects[1] != zoomed
    system.fg = 1
    m.zoom_toggle()
    m.park()
    assert m._current().zoomed == 0


def test_focus_next_cycles_through_the_visible_windows(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3)
    system.fg = 1
    seen = []
    for _ in range(4):
        m.focus_next()
        seen.append(system.fg)
    assert seen == [2, 3, 1, 2]


def test_rotate_moves_the_big_window_top_right_bottom_left(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    big = m.snapshot()["visible"][0]["hwnd"]

    def side():
        r, other = system.rects[big], system.rects[3 - big]
        if r.bottom <= other.top:
            return "arriba"
        if r.left >= other.right:
            return "derecha"
        if r.top >= other.bottom:
            return "abajo"
        return "izquierda"

    sides = []
    for _ in range(5):
        m.rotate()
        sides.append(side())
    assert sides == ["arriba", "derecha", "abajo", "izquierda", "arriba"]


def test_switching_desktop_does_not_capture_windows_that_stay_on_their_desktop(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2)
    m.desktop_create()
    assert not system.is_shown(1) and m.thumbnail(1) is None  # vuelve a verse al volver: no hace falta captura


def test_window_with_a_minimum_size_gets_room_and_the_split_comes_back(env):
    system, m, _, _ = env
    system.min_sizes[2] = (0, 800)  # como la Calculadora en el hueco apilado
    open_windows(system, m, 1, 2, 3, 4)
    top, bottom = system.rects[2], system.rects[3]
    assert top.height >= 800 and bottom.top >= top.bottom  # ya no se sale ni pisa a la de abajo
    assert m._current().ratio2 == 0.5  # el reparto del usuario no se toca
    system.fg = 2
    m.park()  # la 4 ocupa su hueco
    assert abs(system.rects[4].height - system.rects[3].height) <= 1  # sin la app con mínimo, mitad y mitad


def test_close_all_asks_every_window_on_every_desktop_to_close(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4)
    m.desktop_create()
    open_windows(system, m, 5)
    assert m.close_all() == 5
    assert sorted(system.closed) == [1, 2, 3, 4, 5]


def test_visible_windows_for_the_borders(env):
    system, m, _, _ = env
    open_windows(system, m, 1, 2, 3, 4)
    assert m.visible_windows() == [1, 2, 3]
    system.fg = 2
    m.zoom_toggle()
    assert m.visible_windows() == [2]  # la ventana en grande tapa a las demás: solo su borde

import pytest

from kyora.core.layout import (
    MAX_VISIBLE,
    Rect,
    adjust_ratios,
    compute_slots,
    fit_ratios,
    neighbor,
)

AREA = Rect(0, 56, 1920, 1200)


def covers_without_overlap(slots):
    for i, a in enumerate(slots):
        for b in slots[i + 1:]:
            assert a.right <= b.left or b.right <= a.left or a.bottom <= b.top or b.bottom <= a.top
    return True


def test_one_window_fills_area_minus_outer_gap():
    assert compute_slots(1, AREA, outer=8) == [Rect(8, 64, 1912, 1192)]


def test_zero_windows():
    assert compute_slots(0, AREA) == []


def test_four_windows_never_allowed():
    with pytest.raises(ValueError):
        compute_slots(MAX_VISIBLE + 1, AREA)


@pytest.mark.parametrize("n", [1, 2, 3])
@pytest.mark.parametrize("orientation", ["columns", "rows"])
@pytest.mark.parametrize("mirrored", [False, True])
def test_slots_never_overlap_and_stay_inside(n, orientation, mirrored):
    slots = compute_slots(n, AREA, orientation, mirrored, gap=8, outer=8)
    assert len(slots) == n
    assert covers_without_overlap(slots)
    for s in slots:
        assert s.left >= AREA.left and s.right <= AREA.right
        assert s.top >= AREA.top and s.bottom <= AREA.bottom
        assert s.width > 0 and s.height > 0


def test_two_columns_side_by_side():
    a, b = compute_slots(2, AREA, "columns", gap=8, outer=8)
    assert a.left < b.left and a.top == b.top and a.bottom == b.bottom
    assert b.left - a.right == 8


def test_two_rows_stacked():
    a, b = compute_slots(2, AREA, "rows", gap=8, outer=8)
    assert a.top < b.top and a.left == b.left and a.right == b.right


def test_three_columns_main_left_two_stacked_right():
    main, top, bottom = compute_slots(3, AREA, "columns")
    assert main.height > top.height
    assert main.right < top.left
    assert top.bottom < bottom.top


def test_three_mirrored_main_on_right():
    main, top, _ = compute_slots(3, AREA, "columns", mirrored=True)
    assert main.left > top.right


def test_three_rows_main_on_top():
    main, left, right = compute_slots(3, AREA, "rows")
    assert main.bottom < left.top and left.right < right.left
    assert main.width > left.width


def test_neighbor_directions_in_three_columns():
    slots = compute_slots(3, AREA, "columns")  # principal | arriba-der / abajo-der
    assert neighbor(slots, 0, "right") in (1, 2)
    assert neighbor(slots, 1, "left") == 0
    assert neighbor(slots, 2, "left") == 0
    assert neighbor(slots, 1, "down") == 2
    assert neighbor(slots, 2, "up") == 1
    assert neighbor(slots, 0, "left") is None
    assert neighbor(slots, 0, "up") is None


def test_ratio_gives_main_window_more_space():
    even = compute_slots(2, AREA, "columns")
    wide = compute_slots(2, AREA, "columns", ratio=0.7)
    assert wide[0].width > even[0].width and wide[1].width < even[1].width


def test_ratio_applies_to_main_window_even_when_mirrored():
    main, rest = compute_slots(2, AREA, "columns", mirrored=True, ratio=0.7)
    assert main.width > rest.width and main.left > rest.left


def test_ratio2_splits_the_stacked_pair():
    _, top, bottom = compute_slots(3, AREA, "columns", ratio2=0.7)
    assert top.height > bottom.height
    assert covers_without_overlap([top, bottom])


def test_ratio_is_clamped():
    tiny = compute_slots(2, AREA, "columns", ratio=0.01)
    assert tiny[0].width > 0.19 * AREA.width


def test_adjust_ratios_main_split_follows_border():
    # columnas, principal a la izquierda: mover el borde a la derecha agranda la principal
    assert adjust_ratios(2, "columns", False, 0.5, 0.5, "x", 0.05) == (pytest.approx(0.55), 0.5)
    # reflejado, la principal está a la derecha: mover el borde a la derecha la reduce
    assert adjust_ratios(2, "columns", True, 0.5, 0.5, "x", 0.05) == (pytest.approx(0.45), 0.5)


def test_adjust_ratios_pair_split_uses_cross_axis():
    assert adjust_ratios(3, "columns", False, 0.5, 0.5, "y", 0.1) == (0.5, pytest.approx(0.6))
    assert adjust_ratios(2, "columns", False, 0.5, 0.5, "y", 0.1) == (0.5, 0.5)  # sin par: nada que mover
    assert adjust_ratios(1, "columns", False, 0.5, 0.5, "x", 0.1) == (0.5, 0.5)


def test_adjust_ratios_rows_swap_axes():
    assert adjust_ratios(3, "rows", False, 0.5, 0.5, "y", 0.05)[0] == pytest.approx(0.55)
    assert adjust_ratios(3, "rows", False, 0.5, 0.5, "x", 0.05)[1] == pytest.approx(0.55)


def test_adjust_ratios_clamps():
    assert adjust_ratios(2, "columns", False, 0.78, 0.5, "x", 0.5)[0] == 0.8


SMALL = Rect(0, 0, 1000, 800)


def test_fit_ratios_without_minimums_keeps_the_user_split():
    assert fit_ratios(3, SMALL, "columns", 8, 8, 0.5, 0.4, [None, None, None]) == (0.5, 0.4)
    assert fit_ratios(1, SMALL, "columns", 8, 8, 0.5, 0.5, [(2000, 2000)]) == (0.5, 0.5)


@pytest.mark.parametrize("mirrored", [False, True])
def test_fit_ratios_gives_the_stacked_window_its_minimum_height(mirrored):
    ratio, ratio2 = fit_ratios(3, SMALL, "columns", 8, 8, 0.5, 0.5, [None, (0, 500), None])
    slots = compute_slots(3, SMALL, "columns", mirrored, 8, 8, ratio, ratio2)
    assert slots[1].height >= 500 and ratio == 0.5


def test_fit_ratios_moves_the_main_split_for_a_wide_minimum():
    for orientation, minimum, side in (("columns", (600, 0), "width"), ("rows", (0, 500), "height")):
        ratio, _ = fit_ratios(2, SMALL, orientation, 8, 8, 0.5, 0.5, [None, minimum])
        slots = compute_slots(2, SMALL, orientation, False, 8, 8, ratio)
        assert getattr(slots[1], side) >= max(minimum)


def test_fit_ratios_shares_the_space_when_both_cannot_fit():
    ratio, _ = fit_ratios(2, SMALL, "columns", 8, 8, 0.5, 0.5, [(600, 0), (900, 0)])
    assert ratio == pytest.approx(0.4)


def test_fit_ratios_stays_within_the_limits():
    ratio, _ = fit_ratios(2, SMALL, "columns", 8, 8, 0.5, 0.5, [(970, 0), None])
    assert ratio == 0.8


def test_slide_offset_moves_everything_one_screen_height():
    from kyora.core.layout import Rect, slide_offset

    area = Rect(0, 0, 1920, 1080)
    assert slide_offset(1, area) == (0, -1080)
    assert slide_offset(-1, area) == (0, 1080)

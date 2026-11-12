from kyora.core.drop import columns, from_columns, plan, zone_at

AREA = (0, 0, 1000, 800)


def test_zone_is_the_quadrant_under_the_point():
    assert zone_at(AREA, 100, 100) == "left_top"
    assert zone_at(AREA, 900, 700) == "right_bottom"
    assert zone_at(AREA, 100, 700) == "left_bottom"
    assert zone_at(AREA, 900, 100) == "right_top"


def test_columns_round_trip():
    for tiled, mirrored in (([1], False), ([1, 2], False), ([1, 2, 3], False), ([1, 2, 3], True)):
        left, right = columns(tiled, mirrored)
        assert from_columns(left, right) == (tiled, mirrored) or len(tiled) == 2 and mirrored
    assert columns([1, 2, 3], True) == ([2, 3], [1])
    assert columns([1, 2, 3], False) == ([1], [2, 3])


def test_first_window_takes_everything_and_the_second_takes_a_side():
    assert plan([], False, 9, "left_top") == ([9], False, None)
    assert plan([5], False, 9, "left_bottom") == ([9, 5], False, None)
    assert plan([5], False, 9, "right_top") == ([5, 9], False, None)


def test_with_two_the_column_where_it_lands_is_split_top_or_bottom():
    tiled, mirrored, out = plan([1, 2], False, 9, "right_top")      # 1 a la izquierda, 2 a la derecha
    assert columns(tiled, mirrored) == ([1], [9, 2]) and out is None
    tiled, mirrored, out = plan([1, 2], False, 9, "right_bottom")
    assert columns(tiled, mirrored) == ([1], [2, 9])
    tiled, mirrored, out = plan([1, 2], False, 9, "left_bottom")
    assert columns(tiled, mirrored) == ([1, 9], [2]) and mirrored is True and tiled[0] == 2


def test_with_three_it_replaces_the_window_of_that_place_and_the_other_gets_out():
    tiled = [1, 2, 3]                                                # 1 entera a la izquierda; 2 arriba y 3 abajo a la derecha
    t, m, out = plan(tiled, False, 9, "right_bottom")
    assert columns(t, m) == ([1], [2, 9]) and out == 3
    t, m, out = plan(tiled, False, 9, "left_top")                    # la columna entera: cambia su única ventana
    assert columns(t, m) == ([9], [2, 3]) and out == 1
    t, m, out = plan([1, 2, 3], True, 9, "left_top")                 # espejo: la partida está a la izquierda
    assert columns(t, m) == ([9, 3], [1]) and out == 2


def test_never_more_than_three():
    for others in ([], [1], [1, 2], [1, 2, 3]):
        for zone in ("left_top", "left_bottom", "right_top", "right_bottom"):
            tiled, _, out = plan(others, False, 9, zone)
            assert len(tiled) <= 3 and 9 in tiled
            assert out is None or out not in tiled

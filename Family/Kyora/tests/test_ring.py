import pytest

from kyora.core.ring import RingMotion

# ---------- aparición del contorno ----------
A = (0, 0, 100, 100)
B = (200, 0, 300, 100)
LOOK = {"rest": 0.5, "fade_seconds": 1.0}


def test_motion_without_target_draws_nothing():
    motion = RingMotion()
    assert motion.frame(0, **LOOK) is None
    motion.retarget(1, A, 0)
    motion.retarget(None, None, 1)
    assert motion.frame(1, **LOOK) is None


def test_motion_appears_in_place_and_fades_in_to_rest():
    motion = RingMotion()
    motion.retarget(1, A, 0)
    rect, opacity = motion.frame(0.0, **LOOK)
    assert rect == A and opacity == pytest.approx(0)
    assert 0 < motion.frame(0.5, **LOOK)[1] < 0.5
    assert motion.frame(1.0, **LOOK)[1] == pytest.approx(0.5)  # nunca pasa del reposo: sin destello
    assert motion.settled(1.0, 1.0)


def test_motion_jumps_to_a_new_window_without_gliding():
    motion = RingMotion()
    motion.retarget(1, A, 0)
    motion.retarget(2, B, 5)
    rect, opacity = motion.frame(5.0, **LOOK)
    assert rect == B                              # ya está en la ventana nueva, sin posiciones intermedias
    assert opacity == pytest.approx(0)            # y aparece con un fundido
    assert not motion.settled(5.5, 1.0)


def test_motion_same_window_resized_follows_without_fading():
    motion = RingMotion()
    motion.retarget(1, A, 0)
    motion.retarget(1, B, 5)
    assert motion.frame(5.0, **LOOK) == (B, pytest.approx(0.5))


def test_light_is_drawn_once_growing_until_the_whole_edge_and_stops():
    motion = RingMotion()
    motion.retarget(1, A, 0)
    turn0, length0 = motion.trace(0.0, 0.9)
    _, length_mid = motion.trace(0.3, 0.9)
    turn_end, length_end = motion.trace(0.9, 0.9)
    assert turn0 == pytest.approx(0) and 0 < length0 < length_mid < 1  # nace corta y se alarga girando
    assert length_end == pytest.approx(1) and turn_end > 0
    assert not motion.settled(0.5, 0.09, 0.9) and motion.settled(0.9, 0.09, 0.9)  # y se para
    assert motion.trace(30.0, 0.9) == (turn_end, length_end)


def test_same_window_moving_does_not_redraw_the_light():
    motion = RingMotion()
    motion.retarget(1, A, 0)
    motion.retarget(1, B, 5)
    assert motion.trace(5.0, 0.9)[1] == pytest.approx(1)  # sigue entero
    motion.retarget(2, A, 6)
    assert motion.trace(6.0, 0.9)[1] < 0.5  # otra ventana: se vuelve a dibujar

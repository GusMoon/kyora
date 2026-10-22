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

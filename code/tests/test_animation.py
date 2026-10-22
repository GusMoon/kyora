import pytest

from kyora.core.animation import Animation, ease_in_cubic, ease_out_back, lerp


class FakeTime:
    """Reloj y pausa simulados: dormir adelanta el reloj."""

    def __init__(self):
        self.now = 0.0

    def clock(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


def make():
    time = FakeTime()
    return Animation(clock=time.clock, sleep=time.sleep), time


def test_easing_endpoints():
    assert ease_out_back(0) == pytest.approx(0)
    assert ease_out_back(1) == pytest.approx(1)
    assert ease_in_cubic(0) == 0 and ease_in_cubic(1) == 1


def test_ease_out_back_overshoots_a_little_then_settles():
    peak = max(ease_out_back(i / 100) for i in range(101))
    assert 1.02 < peak < 1.12


def test_ease_in_cubic_starts_slow():
    assert ease_in_cubic(0.5) < 0.2


def test_lerp():
    assert lerp(10, 20, 0.5) == 15


def test_run_goes_from_start_to_end_and_finishes_exactly_on_end():
    anim, _ = make()
    values = []
    assert anim.run(values.append, 0, 1, 0.1, lambda t: t) is True
    assert values[0] == pytest.approx(0, abs=0.1)
    assert values[-1] == 1
    assert values == sorted(values)  # con una curva lineal, nunca retrocede


def test_run_respects_duration_even_with_slow_frames():
    anim, time = make()
    calls = []

    def slow_step(value):
        calls.append(value)
        time.now += 0.05  # cada fotograma tarda mucho

    anim.run(slow_step, 0, 1, 0.1, lambda t: t)
    assert len(calls) <= 4  # salta fotogramas en lugar de alargar la animación
    assert time.now < 0.2


def test_run_can_be_cancelled():
    anim, _ = make()
    seen = []
    assert anim.run(seen.append, 0, 1, 1.0, lambda t: t, cancelled=lambda: len(seen) >= 3) is False
    assert len(seen) == 3 and seen[-1] < 1


def test_run_with_zero_duration_jumps_to_end():
    anim, _ = make()
    seen = []
    assert anim.run(seen.append, 0, 5, 0, lambda t: t) is True
    assert seen == [5]


def test_run_backwards():
    anim, _ = make()
    seen = []
    anim.run(seen.append, 1, 0, 0.1, ease_in_cubic)
    assert seen[-1] == 0 and seen[0] == pytest.approx(1, abs=0.05)

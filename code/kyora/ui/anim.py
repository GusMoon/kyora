"""Animaciones de la interfaz con reloj preciso."""
from PySide6.QtCore import QEasingCurve, QElapsedTimer, Qt, QTimer

from kyora.core.animation import lerp

FRAME_MS = 7  # ~140 fotogramas por segundo: también en pantallas de 120/144 Hz


class Tween:
    """Animación por tiempo real con un reloj preciso: si un fotograma se retrasa, el siguiente salta a donde toca."""

    def __init__(self, parent, on_value, on_finished=lambda: None):
        self._on_value, self._on_finished = on_value, on_finished
        self._timer = QTimer(parent)
        self._timer.setTimerType(Qt.PreciseTimer)
        self._timer.setInterval(FRAME_MS)
        self._timer.timeout.connect(self._step)
        self._clock = QElapsedTimer()
        self._start = self._end = 0.0
        self._ms = 1
        self._curve = QEasingCurve()

    def start(self, start, end, ms, curve):
        self._start, self._end, self._ms, self._curve = start, end, max(ms, 1), QEasingCurve(curve)
        self._clock.start()
        self._timer.start()
        self._step()

    def stop(self):
        self._timer.stop()

    def running(self):
        return self._timer.isActive()

    def _step(self):
        t = min(self._clock.elapsed() / self._ms, 1.0)
        self._on_value(lerp(self._start, self._end, self._curve.valueForProgress(t)))
        if t >= 1.0:
            self._timer.stop()
            self._on_finished()

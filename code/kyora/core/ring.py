"""Aparición del contorno que rodea a la ventana activa (sin Windows ni Qt: se puede probar)."""
from kyora.core.animation import ease_out_cubic


class RingMotion:
    """Contorno sutil: no se desliza de una ventana a otra; aparece en su sitio con un fundido corto.

    No sabe nada de Windows: recibe objetivos (rectángulos) y el instante, y devuelve dónde dibujarse
    y con qué opacidad (de 0 a `rest`). Si la misma ventana cambia de tamaño, el contorno la sigue sin parpadear.
    """

    def __init__(self):
        self.goal = None
        self.key = None
        self._show_t0 = 0.0

    def retarget(self, key, rect, now):
        """`key` identifica a la ventana (una ventana nueva provoca un fundido); rect=None lo oculta."""
        if rect is None:
            self.goal = self.key = None
            return
        if self.goal is None or key != self.key:
            self._show_t0 = now
        self.goal, self.key = rect, key

    @staticmethod
    def _progress(now, t0, seconds):
        return 1.0 if seconds <= 0 else min(max((now - t0) / seconds, 0.0), 1.0)

    def frame(self, now, rest, fade_seconds):
        """(rectángulo, opacidad) de este instante, o None si no hay nada que dibujar."""
        if self.goal is None:
            return None
        return self.goal, rest * ease_out_cubic(self._progress(now, self._show_t0, fade_seconds))

    def settled(self, now, fade_seconds):
        """True si ya no cambia de opacidad (no hace falta redibujar deprisa)."""
        return self.goal is None or self._progress(now, self._show_t0, fade_seconds) >= 1.0

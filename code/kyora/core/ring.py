"""Aparición del contorno que rodea a la ventana activa (sin Windows ni Qt: se puede probar)."""
from kyora.core.animation import ease_out_cubic

START_LENGTH = 0.06  # trozo de borde con el que nace la luz (una serpiente corta), como fracción de la vuelta
TURNS = 5  # vueltas que da mientras crece: en cada una es más larga, hasta rodear la ventana entera


class RingMotion:
    """Contorno sutil: no se desliza de una ventana a otra; aparece en su sitio con un fundido corto.

    No sabe nada de Windows: recibe objetivos (rectángulos) y el instante, y devuelve dónde dibujarse
    y con qué opacidad (de 0 a `rest`). Si la misma ventana cambia de tamaño, el contorno la sigue sin parpadear.

    Al llegar a una ventana nueva, la luz se dibuja una sola vez (`trace`): nace como un trazo corto que gira y se
    alarga hasta llenar todo el borde, y ahí se para.
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

    def trace(self, now, draw_seconds):
        """(giro de la cabeza 0-1, largo 0-1) del trazo de luz. Con largo 1 el borde está entero y quieto."""
        e = self._progress(now, self._show_t0, draw_seconds)  # lineal: velocidad y crecimiento parejos
        return TURNS * e, START_LENGTH + (1 - START_LENGTH) * e

    def settled(self, now, fade_seconds, draw_seconds=0.0):
        """True si ya no cambia nada (no hace falta redibujar)."""
        return self.goal is None or self._progress(now, self._show_t0, max(fade_seconds, draw_seconds)) >= 1.0

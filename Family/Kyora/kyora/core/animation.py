"""Animaciones por tiempo real (no por número de fotogramas), sin Windows ni UI.

Si un fotograma tarda más de la cuenta, el siguiente salta a donde toca: la duración total
se respeta siempre y el movimiento no se "arrastra".
"""
import time


def ease_out_back(t, overshoot=0.9):
    """Sale rápido, se pasa un poco y asienta: el efecto de gota."""
    c3 = overshoot + 1
    return 1 + c3 * (t - 1) ** 3 + overshoot * (t - 1) ** 2


def ease_out_cubic(t):
    """Sale rápido y asienta suave, sin rebote."""
    return 1 + (t - 1) ** 3


def ease_in_cubic(t):
    """Arranca despacio y termina rápido: se repliega sin dudar."""
    return t**3


def lerp(a, b, t):
    return a + (b - a) * t


class Animation:
    def __init__(self, clock=time.monotonic, sleep=time.sleep):
        self._clock = clock
        self._sleep = sleep

    def run(self, step, start, end, duration, ease, cancelled=lambda: False, interval=0.004):
        """Llama a `step(valor)` de `start` a `end` en `duration` segundos.

        Devuelve True si llegó al final y False si `cancelled()` la interrumpió.
        """
        began = self._clock()
        while True:
            if cancelled():
                return False
            elapsed = (self._clock() - began) / duration if duration > 0 else 1.0
            if elapsed >= 1.0:
                step(end)
                return True
            step(lerp(start, end, ease(elapsed)))
            self._sleep(interval)

"""Combinaciones de dos teclas con Alt (Alt+F+flechas, Alt+M+flechas), sin Windows: se puede probar.

RegisterHotKey solo admite modificadores más una tecla, así que estas combinaciones las resuelve el gancho de teclado.
Con Alt pulsado (sin Shift ni Ctrl), una tecla de "capa" (F, M) se traga y queda activa; las teclas que forman
combinación con ella disparan su acción y también se tragan. Si la capa se suelta sin haberla usado, dispara su
"toque" (Alt+F suelto sigue siendo ventana flotante). Al soltar Alt después, se pide tapar la pulsación para que
la app no abra su menú (como pasa al pulsar y soltar Alt solo).
"""
ALT_KEYS = (0x12, 0xA4, 0xA5)
SHIFT_KEYS = (0x10, 0xA0, 0xA1)
CTRL_KEYS = (0x11, 0xA2, 0xA3)

PASS = (False, None, False)


class ChordGuard:
    def __init__(self, chords, taps=None):
        """`chords`: {(capa, tecla): acción}; `taps`: {capa: acción} al soltar la capa sin usarla."""
        self.chords = dict(chords)
        self.taps = dict(taps or {})
        self.layers = {layer for layer, _ in self.chords} | set(self.taps)
        self._held = {"alt": set(), "shift": set(), "ctrl": set()}
        self._layer = None
        self._used = False
        self._pressed = set()  # teclas de combinación pulsadas (para ignorar la autorrepetición y tragar su subida)
        self._mask = False

    def _modifier(self, vk):
        for name, keys in (("alt", ALT_KEYS), ("shift", SHIFT_KEYS), ("ctrl", CTRL_KEYS)):
            if vk in keys:
                return name
        return None

    def feed(self, vk, down):
        """Procesa una tecla física. Devuelve (tragar, acción a disparar o None, tapar antes de dejarla pasar)."""
        modifier = self._modifier(vk)
        if modifier:
            (self._held[modifier].add if down else self._held[modifier].discard)(vk)
            if modifier == "alt" and not down and not self._held["alt"] and self._mask:
                self._mask = False
                return False, None, True
            return PASS
        if vk in self.layers:
            if down:
                if self._layer == vk:
                    return True, None, False  # autorrepetición de la capa
                if self._layer is None and self._held["alt"] and not self._held["shift"] and not self._held["ctrl"]:
                    self._layer, self._used, self._mask = vk, False, True
                    return True, None, False
                return PASS
            if self._layer == vk:
                self._layer = None
                return True, (None if self._used else self.taps.get(vk)), False
            return PASS
        if not down and vk in self._pressed:
            self._pressed.discard(vk)
            return True, None, False
        if down and self._layer is not None and self._held["alt"] and (self._layer, vk) in self.chords:
            if vk in self._pressed:
                return True, None, False  # autorrepetición: la acción ya se disparó
            self._pressed.add(vk)
            self._used = True
            return True, self.chords[(self._layer, vk)], False
        return PASS

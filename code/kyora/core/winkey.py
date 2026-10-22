"""Lógica de la tecla Windows: ignorar la pulsación suelta y dejar pasar las combinaciones (sin Windows: se puede probar).

Pulsar y soltar Windows sin tocar nada más abre el menú de inicio. Para impedirlo se "tapa" la pulsación inyectando
una tecla sin asignar justo antes de soltarla. Con una combinación (Win+L, Win+D, Win+Shift+S…) no hace falta.
"""
VK_LWIN, VK_RWIN = 0x5B, 0x5C
WIN_KEYS = (VK_LWIN, VK_RWIN)


class WinKeyGuard:
    def __init__(self):
        self._down = set()
        self._combo = False

    def feed(self, vk, is_down):
        """Procesa una tecla física. Devuelve True si hay que inyectar la tecla tapadera antes de dejarla pasar."""
        if vk in WIN_KEYS:
            if is_down:
                if not self._down:
                    self._combo = False
                self._down.add(vk)
                return False
            lone = vk in self._down and len(self._down) == 1 and not self._combo
            self._down.discard(vk)
            return lone
        if is_down and self._down:
            self._combo = True
        return False


OTHER_MODIFIERS = (0x10, 0xA0, 0xA1, 0x11, 0xA2, 0xA3, 0x12, 0xA4, 0xA5)  # Shift, Ctrl y Alt


class WinComboGuard:
    """Win+tecla que resuelve Kyora (Win+↑/↓, Win+Esc) en vez de Windows.

    Solo con Windows pulsado (sin Shift, Ctrl ni Alt): la tecla se traga al bajar y al subir y su acción se dispara una
    vez (la autorrepetición no la repite). Win+Shift+↑ y las demás combinaciones siguen llegando a Windows.
    """

    def __init__(self, combos):
        """`combos`: {tecla: acción}."""
        self.combos = dict(combos)
        self._win = set()
        self._others = set()
        self._pressed = set()

    def feed(self, vk, down):
        """Procesa una tecla física. Devuelve (tragar, acción a disparar o None)."""
        if vk in WIN_KEYS or vk in OTHER_MODIFIERS:
            held = self._win if vk in WIN_KEYS else self._others
            (held.add if down else held.discard)(vk)
            return False, None
        if not down:
            if vk in self._pressed:
                self._pressed.discard(vk)
                return True, None
            return False, None
        if vk in self._pressed:
            return True, None  # autorrepetición: la acción ya se disparó
        if self._win and not self._others and vk in self.combos:
            self._pressed.add(vk)
            return True, self.combos[vk]
        return False, None

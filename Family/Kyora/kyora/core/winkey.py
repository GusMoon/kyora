"""El bloqueo de la tecla Windows (sin Windows: se puede probar).

Kyora no usa la tecla Windows: la traga entera, así que no abre el menú de inicio ni forma ninguna combinación de
Windows (Win+E, Win+D, Win+Tab...). También traga Ctrl+Esc, que abre el menú de inicio igual. Todo lo demás pasa sin
tocarse. (Win+L lo resuelve el propio Windows antes que ningún programa y no se puede bloquear.)
"""
VK_LWIN, VK_RWIN = 0x5B, 0x5C
WIN_KEYS = (VK_LWIN, VK_RWIN)
VK_ESCAPE = 0x1B
CTRL_KEYS = (0x11, 0xA2, 0xA3)
SHIFT_KEYS = (0x10, 0xA0, 0xA1)


class WinBlock:
    def __init__(self):
        self._ctrl, self._shift = set(), set()
        self._eaten_esc = False  # se tragó la bajada de Esc: también se traga su subida

    def feed(self, vk, is_down):
        """Procesa una tecla física. Devuelve True si hay que tragarla (que nadie más la reciba)."""
        if vk in WIN_KEYS:
            return True
        for keys, held in ((CTRL_KEYS, self._ctrl), (SHIFT_KEYS, self._shift)):
            if vk in keys:
                (held.add if is_down else held.discard)(vk)
        if vk == VK_ESCAPE:
            if is_down:
                self._eaten_esc = bool(self._ctrl) and not self._shift  # Ctrl+Esc (Ctrl+Mayús+Esc es el administrador de tareas)
                return self._eaten_esc
            eaten, self._eaten_esc = self._eaten_esc, False
            return eaten
        return False

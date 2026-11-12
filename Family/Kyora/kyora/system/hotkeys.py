"""Atajos de teclado globales (RegisterHotKey) en un hilo propio."""
import ctypes
import logging
import threading
from ctypes import wintypes

log = logging.getLogger("kyora.hotkeys")

user32 = ctypes.windll.user32
kernel32 = ctypes.windll.kernel32

WM_HOTKEY = 0x0312
WM_QUIT = 0x0012
MOD_ALT, MOD_CONTROL, MOD_SHIFT, MOD_WIN, MOD_NOREPEAT = 0x1, 0x2, 0x4, 0x8, 0x4000

MODIFIERS = {"alt": MOD_ALT, "ctrl": MOD_CONTROL, "shift": MOD_SHIFT, "win": MOD_WIN}
NAMED_KEYS = {
    "space": 0x20, "enter": 0x0D, "tab": 0x09, "esc": 0x1B, "pageup": 0x21, "pagedown": 0x22,
    "backspace": 0x08, "delete": 0x2E,
    "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28,
    "-": 0xBD, "minus": 0xBD,  # la tecla - de al lado del punto
    "subtract": 0x6D,  # el - del teclado numérico
    **{f"f{n}": 0x6F + n for n in range(1, 13)},
}


def _parts(combo):
    """'alt+f+left' -> (["alt"], ["f", "left"]): modificadores y teclas."""
    parts = combo.lower().replace(" ", "").split("+")
    return [p for p in parts if p in MODIFIERS], [p for p in parts if p not in MODIFIERS]


def _key_code(part, combo):
    if part in NAMED_KEYS:
        return NAMED_KEYS[part]
    if len(part) == 1 and part.isascii() and part.isalnum():
        return ord(part.upper())
    raise ValueError(f"Tecla desconocida '{part}' en '{combo}'")


def parse_combo(combo):
    """'alt+shift+h' -> (modificadores, código de tecla virtual)."""
    mods, keys = _parts(combo)
    if not mods or len(keys) != 1:
        raise ValueError(f"El atajo '{combo}' necesita al menos un modificador y una tecla")
    value = 0
    for mod in mods:
        value |= MODIFIERS[mod]
    return value, _key_code(keys[0], combo)


def parse_chord(combo):
    """'alt+f+left' -> (tecla de capa, tecla): combinación de dos teclas con Alt (la resuelve el gancho de teclado)."""
    mods, keys = _parts(combo)
    if mods != ["alt"] or len(keys) != 2:
        raise ValueError(f"La combinación '{combo}' debe ser Alt + una tecla + otra tecla")
    return _key_code(keys[0], combo), _key_code(keys[1], combo)


def split_bindings(bindings):
    """Reparte {atajo: valor} en (normales, combinaciones, toques, fallidos).

    - normales: {atajo: valor} para RegisterHotKey (Ctrl+Shift+tecla...);
    - combinaciones: {(capa, tecla): valor} de los atajos con dos teclas ('alt+f+left');
    - toques: {capa: valor} de 'alt+f' cuando F es la capa de alguna combinación (se dispara al soltar F);
    - fallidos: atajos mal escritos y los que usan la tecla Windows (Kyora la bloquea: usa Ctrl+Shift).
    """
    normal, chords, taps, failed = {}, {}, {}, []
    for combo, value in bindings.items():
        mods, keys = _parts(combo)
        if "win" in mods:
            log.error("El atajo '%s' usa la tecla Windows, que Kyora bloquea: usa Ctrl+Shift", combo)
            failed.append(combo)
        elif len(keys) == 2:
            try:
                chords[parse_chord(combo)] = value
            except ValueError as err:
                log.error("%s", err)
                failed.append(combo)
    layers = {layer for layer, _ in chords}
    for combo, value in bindings.items():
        mods, keys = _parts(combo)
        if "win" in mods or len(keys) == 2:
            continue
        if mods == ["alt"] and len(keys) == 1 and layers:
            try:
                vk = _key_code(keys[0], combo)
            except ValueError:
                vk = None  # RegisterHotKey lo rechazará y quedará entre los fallidos
            if vk in layers:
                taps[vk] = value
                continue
        normal[combo] = value
    return normal, chords, taps, failed


def is_free(combo):
    """True si Windows deja registrar `combo` ahora (ningún otro programa la tiene). Se registra y se suelta al momento."""
    try:
        mods, key = parse_combo(combo)
    except ValueError:
        return False
    probe = 0x7FF0  # un identificador que Kyora no usa
    if user32.RegisterHotKey(None, probe, mods | MOD_NOREPEAT, key):
        user32.UnregisterHotKey(None, probe)
        return True
    return False


class Hotkeys(threading.Thread):
    def __init__(self, bindings):
        """bindings: {combo: callable}"""
        super().__init__(daemon=True, name="kyora-hotkeys")
        self._bindings = bindings
        self._by_id = {}
        self._thread_id = 0
        self.failed = []
        self.ready = threading.Event()

    def run(self):
        self._thread_id = kernel32.GetCurrentThreadId()
        for i, (combo, fn) in enumerate(self._bindings.items(), start=1):
            try:
                mods, key = parse_combo(combo)
            except ValueError as err:
                log.error("%s", err)
                self.failed.append(combo)
                continue
            if user32.RegisterHotKey(None, i, mods | MOD_NOREPEAT, key):
                self._by_id[i] = fn
            else:
                log.warning("No se pudo registrar el atajo %s (¿lo usa otro programa?)", combo)
                self.failed.append(combo)
        self.ready.set()
        msg = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            if msg.message == WM_HOTKEY and msg.wParam in self._by_id:
                try:
                    self._by_id[msg.wParam]()
                except Exception:
                    log.exception("Fallo en el atajo")
        for i in self._by_id:
            user32.UnregisterHotKey(None, i)

    def stop(self):
        if self._thread_id:
            user32.PostThreadMessageW(self._thread_id, WM_QUIT, 0, 0)

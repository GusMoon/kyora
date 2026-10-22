"""La lista de atajos que muestra el buscador al escribir "commands" (sin Qt ni Windows: se puede probar).

Sale de los atajos reales de config.json, así que refleja lo que Gustavo haya cambiado. Los atajos de una misma
acción con los mismos modificadores se juntan en una fila: Alt+←/→/↑/↓, Alt+1/2/3, Win+↑/↓.
"""
COMMANDS_WORD = "commands"

MODIFIER_NAMES = {"ctrl": "Ctrl", "alt": "Alt", "shift": "Shift", "win": "Win"}
MODIFIER_ORDER = ("ctrl", "alt", "shift", "win")
KEY_NAMES = {
    "left": "←", "right": "→", "up": "↑", "down": "↓",
    "space": "Espacio", "esc": "Esc", "enter": "Enter", "tab": "Tab",
    "minus": "-", "subtract": "Num -",
}

# los mismos textos que COMANDOS.md
ACTION_TEXT = {
    "wm.focus_next": "Pasar el foco a la siguiente ventana visible",
    "wm.focus": "Pasar el foco a la ventana de ese lado",
    "wm.move": "Mover la ventana con foco al hueco de ese lado",
    "wm.close": "Cerrar la ventana con foco",
    "wm.close_all": "Cerrar todas las ventanas de todos los escritorios (pulsar dos veces)",
    "desktop.create": "Nuevo escritorio (y se va a él)",
    "desktop.step": "Ir al escritorio de arriba o de abajo",
    "desktop.switch": "Ir a un escritorio",
    "desktop.close_current": "Cerrar este escritorio (sus ventanas pasan al anterior)",
    "power.menu": "Apagar, reiniciar o suspender el equipo",
    "hub.toggle": "Panel de arriba: Lobby (I), Archivos (E), Tareas (T), Segundo Cerebro (B) o Kyora (K)",
    "switcher.toggle": "Cambiar de app: panel de ventanas en espera",
    "wm.rotate": "Girar la ventana grande: arriba, derecha, abajo, izquierda",
    "wm.show_count": "Ver 1, 2 o 3 ventanas",
    "search.toggle": "Buscador de apps y ventanas",
    "app.focus_follows_mouse": "Activar o desactivar el foco con el ratón",
    "app.release": "Salida de emergencia: devuelve todo a Windows y cierra Kyora",
    "wm.float_toggle": "Sacar la ventana del mosaico o devolverla",
    "wm.zoom_toggle": "Ventana en grande sobre todo el hueco",
    "wm.park": "Mandar la ventana con foco a la espera",
    "wm.solo": "Dejar solo la ventana con foco",
}


# atajos de dentro del panel de arriba (no son globales: solo funcionan con el panel abierto)
PANEL_ROWS = (
    {"keys": "Ctrl+1/2/3/4/5", "text": "Panel de arriba: Lobby, Archivos, Tareas, Segundo Cerebro o Kyora"},
    {"keys": "Ctrl+Tab / Ctrl+Shift+Tab", "text": "Panel de arriba: sección siguiente o anterior"},
    {"keys": "Ctrl+Shift+H/E/O/D/I", "text": "Archivos: carpeta personal, Escritorio, Documentos, Descargas o Imágenes"},
    {"keys": "Ctrl+L / Ctrl+F", "text": "Archivos: escribir la ruta / buscar"},
    {"keys": "Espacio", "text": "Archivos: vista previa"},
    {"keys": "Ctrl+N / Ctrl+Shift+N", "text": "Tareas: nueva tarea / nueva subtarea"},
    {"keys": "Ctrl+Enter / Ctrl+T", "text": "Tareas: finalizar o reabrir / cronómetro"},
    {"keys": "Supr / Ctrl+↑/↓", "text": "Tareas: borrar / mover la subtarea"},
    {"keys": "Ctrl+N / Ctrl+Shift+I", "text": "Segundo Cerebro: nueva nota / impulso"},
    {"keys": "Ctrl+S / Ctrl+M", "text": "Segundo Cerebro: guardar / ver el Markdown"},
    {"keys": "Ctrl+B / Ctrl+I / Ctrl+Alt+1/2/3", "text": "Segundo Cerebro: negrita / cursiva / títulos"},
    {"keys": "Ctrl+Shift+F", "text": "Segundo Cerebro: buscar"},
)


def _split(combo):
    parts = combo.lower().replace(" ", "").split("+")
    mods = tuple(m for m in MODIFIER_ORDER if m in parts)
    return mods, [p for p in parts if p not in MODIFIER_NAMES]


def _key(part):
    return KEY_NAMES.get(part, part.upper())


def command_rows(hotkeys):
    """[{keys, text}] de los atajos globales, en el orden de la configuración, y después los del panel de arriba."""
    groups = {}  # (acción, modificadores, teclas antes de la última) -> [últimas teclas], en el orden en que aparecen
    for combo, spec in hotkeys.items():
        action = spec[0] if isinstance(spec, (list, tuple)) and spec else str(spec)
        mods, keys = _split(combo)
        if keys:
            groups.setdefault((action, mods, tuple(keys[:-1])), []).append(keys[-1])
    rows = []
    for (action, mods, head), lasts in groups.items():
        # las combinaciones de dos teclas (Alt+F+←) solo juntan la última tecla
        keys = "".join(MODIFIER_NAMES[m] + "+" for m in mods) + "".join(_key(k) + "+" for k in head)
        rows.append({"keys": keys + "/".join(_key(k) for k in lasts), "text": ACTION_TEXT.get(action, action)})
    return rows + list(PANEL_ROWS)

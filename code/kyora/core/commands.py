"""La lista de atajos del panel de configuración (el botón de ajustes), agrupada por secciones (sin Qt ni Windows: se puede probar).

Sale de los atajos reales de config.json, así que refleja lo que Gustavo haya cambiado. Los atajos de una misma
acción con los mismos modificadores se juntan en una fila: Ctrl+Shift+←/→/↑/↓, Ctrl+Shift+1/2/3.
"""
COMMANDS_WORD = "commands"  # en el buscador se escribe con ">" delante: >commands
# los comandos de ">" en el buscador: (palabra, qué hace)
KYORA_COMMANDS = (
    ("tree", "Todos tus archivos en árbol (/carpeta y @archivo buscan directamente)"),
    ("task", "Tus tareas, directo en el tablero Kanban"),
    ("notes", "Tus notas, aquí mismo, con formato (Ctrl+N nueva, Ctrl+RePág/AvPág pasar)"),
    ("wallpaper", "Cambiar el fondo de pantalla (y los colores de Kyora)"),
    ("config", "Opciones de Kyora: desconectar, reiniciar, actualizar…"),
    ("commands", "Todos los atajos de Kyora"),
)
# (título, explicación, acción, datos) de ">config": lo que se usa al desarrollar Kyora. Desconectar va al
# final, para que un Enter despistado al escribir ">config" no cierre Kyora
KYORA_OPTIONS = (
    ("Reiniciar Kyora", "Cierra y vuelve a abrir Kyora (por ejemplo tras cambiar config.json).", "app.restart", {}),
    ("Actualizar", "actualizar_kyora.bat: dependencias, pruebas y la vuelve a abrir. Si algo falla, no la abre.",
     "app.run_script", {"name": "actualizar"}),
    ("Abrir con consola", "iniciar_kyora.bat: reinicia Kyora con una consola para ver los errores.",
     "app.run_script", {"name": "consola"}),
    ("Rescate", "rescate_kyora.bat: cierra Kyora y devuelve las ventanas ocultas y la barra de tareas.",
     "app.run_script", {"name": "rescate"}),
    ("Arrancar con Windows", "instalar_inicio.bat: Kyora se abre sola al iniciar sesión.",
     "app.run_script", {"name": "instalar_inicio"}),
    ("No arrancar con Windows", "quitar_inicio.bat: quita ese arranque automático.",
     "app.run_script", {"name": "quitar_inicio"}),
    ("Desconectar Kyora", "Devuelve las ventanas y la barra de Windows y cierra Kyora.", "app.quit", {}),
)

MODIFIER_NAMES = {"ctrl": "Ctrl", "alt": "Alt", "shift": "Shift", "win": "Win"}
MODIFIER_ORDER = ("win", "ctrl", "shift", "alt")  # Ctrl+Shift+Alt+tecla (Win ya no se usa: se lee por si hay una config antigua)
KEY_NAMES = {
    "left": "←", "right": "→", "up": "↑", "down": "↓",
    "space": "Espacio", "esc": "Esc", "enter": "Enter", "tab": "Tab", "pageup": "RePág", "pagedown": "AvPág",
    "backspace": "Retroceso", "delete": "Supr",
    "minus": "-", "subtract": "Num -",
}

# los mismos textos que COMANDOS.md
ACTION_TEXT = {
    "wm.focus_next": "Pasar el foco a la siguiente ventana del mosaico",
    "wm.focus": "Pasar el foco a la ventana de ese lado",
    "wm.move": "Mover la ventana con foco un paso (en el mosaico, al hueco de ese lado)",
    "wm.arrange": "Orientación de la ventana con foco: pegarla arriba, abajo o a un lado; abajo otra vez la minimiza",
    "wallpaper.mode": "Ver solo los fondos de pantalla y cambiarlos con las flechas (los colores de Kyora los siguen)",
    "wm.close": "Cerrar la ventana con foco",
    "wm.close_all": "Cerrar todas las ventanas de todos los escritorios (un atajo aparte, difícil de pulsar sin querer)",
    "desktop.create": "Nuevo escritorio (y se va a él)",
    "desktop.step": "Ir al escritorio anterior o siguiente (la pantalla se desliza)",
    "desktop.switch": "Ir a un escritorio",
    "desktop.close_current": "Cerrar este escritorio (sus ventanas pasan al anterior)",
    "power.menu": "Apagar, reiniciar o suspender el equipo",
    "switcher.toggle": "Reemplazar la ventana con foco por otra que está en espera (↑/↓ y Enter)",
    "wm.rotate": "Girar la ventana grande: arriba, derecha, abajo, izquierda",
    "wm.show_count": "Ver 1, 2 o 3 ventanas",
    "search.toggle": "Buscador de apps, archivos y carpetas",
    "search.open_mode": "Tus tareas (T, directo en el tablero Kanban), tus notas (N) y el chat con tus dispositivos (C), aquí mismo",
    "music.panel": "Música: tus listas de YouTube y su descarga en MP3 (carpeta Música)",
    "app.release": "Salida de emergencia: devuelve todo a Windows y cierra Kyora",
    "wm.float_toggle": "Sacar la ventana del mosaico o devolverla",
    "wm.zoom_toggle": "Ventana en grande sobre todo el hueco",
    "wm.park": "Mandar la ventana con foco a la espera",
    "wm.solo": "Dejar solo la ventana con foco",
}


SECTIONS = ("Navegación", "Ventanas", "Escritorios", "Sistema", "Tareas")
ACTION_SECTION = {
    "search.toggle": "Navegación", "search.open_mode": "Tareas", "wm.focus_next": "Navegación", "wm.focus": "Navegación",
    "wm.move": "Ventanas", "wm.arrange": "Ventanas", "wm.close": "Ventanas",
    "wm.close_all": "Ventanas", "switcher.toggle": "Ventanas", "wm.rotate": "Ventanas", "wm.show_count": "Ventanas",
    "wm.float_toggle": "Ventanas", "wm.zoom_toggle": "Ventanas", "wm.park": "Ventanas", "wm.solo": "Ventanas",
    "desktop.create": "Escritorios", "desktop.step": "Escritorios", "desktop.switch": "Escritorios",
    "desktop.close_current": "Escritorios", "wallpaper.mode": "Sistema", "power.menu": "Sistema",
    "music.panel": "Sistema", "app.release": "Sistema",
}

# atajos de dentro del buscador (no son globales: solo funcionan con ellos abiertos)
PANEL_ROWS = (
    {"keys": "<texto · /texto · @texto", "text": "Buscador: solo aplicaciones · solo carpetas · solo archivos",
     "section": "Navegación"},
    {"keys": "↑↓←→ · Enter (en el tablero)", "text": "Tareas: elegir una tarjeta · abrirla (con algo escrito arriba, Enter crea una tarea nueva)",
     "section": "Tareas"},
    {"keys": "Ctrl+←/→ · Ctrl+Enter · Ctrl+Supr ×2 (en el tablero)",
     "text": "Tareas: pasar de estado · terminar o reabrir · borrar (dos veces)", "section": "Tareas"},
    {"keys": "Arrastrar · clic · rueda (en el tablero)", "text": "Tareas: cambiar el estado · abrirla · desplazar la columna",
     "section": "Tareas"},
    {"keys": "Esc · Ctrl+N (en una tarea)", "text": "Tarea abierta: volver al tablero · tarea nueva", "section": "Tareas"},
    {"keys": "Ctrl+Shift+S · Ctrl+↑/↓ · Alt+↑/↓", "text": "Tarea abierta: nueva subtarea · deslizar la lista · mover la subtarea",
     "section": "Tareas"},
    {"keys": "Ctrl+Enter · Ctrl+Supr ×2 (en una tarea)", "text": "Tarea abierta: terminar o reabrir · borrarla (dos veces)",
     "section": "Tareas"},
    {"keys": "Ctrl+N · Ctrl+Supr ×2 (en las notas)", "text": "Notas: nueva · borrar (dos veces)", "section": "Tareas"},
    {"keys": "Ctrl+B · Ctrl+I · Ctrl+K (en las notas)", "text": "Notas: negrita · cursiva · enlace", "section": "Tareas"},
    {"keys": "Ctrl+RePág / Ctrl+AvPág (en las notas)", "text": "Notas: anterior / siguiente", "section": "Tareas"},
)


def _split(combo):
    parts = combo.lower().replace(" ", "").split("+")
    mods = tuple(m for m in MODIFIER_ORDER if m in parts)
    return mods, [p for p in parts if p not in MODIFIER_NAMES]


def _key(part):
    return KEY_NAMES.get(part, part.upper())


def command_rows(hotkeys):
    """[{keys, text, section, combos, editable}] de los atajos globales, en el orden de la configuración, y después los
    del buscador y del panel de tarea. `combos` son los atajos de `config.json` que forman la fila (se editan juntos)."""
    groups = {}  # (acción, modificadores, teclas antes de la última) -> [(última tecla, combinación)], en orden
    for combo, spec in hotkeys.items():
        action = spec[0] if isinstance(spec, (list, tuple)) and spec else str(spec)
        mods, keys = _split(combo)
        if keys:
            groups.setdefault((action, mods, tuple(keys[:-1])), []).append((keys[-1], combo))
        elif mods:  # una tecla modificadora sola
            groups[(action, mods, None)] = [(None, combo)]
    rows = []
    for (action, mods, head), lasts in groups.items():
        text, section = ACTION_TEXT.get(action, action), ACTION_SECTION.get(action, "Sistema")
        combos = [combo for _, combo in lasts]
        if head is None:
            rows.append({"keys": "+".join(MODIFIER_NAMES[m] for m in mods) + " (sola)", "text": text, "section": section,
                         "combos": combos, "editable": False})
            continue
        # las combinaciones de dos teclas (Alt+F+←) solo juntan la última tecla
        keys = "".join(MODIFIER_NAMES[m] + "+" for m in mods) + "".join(_key(k) + "+" for k in head)
        rows.append({"keys": keys + "/".join(_key(k) for k, _ in lasts), "text": text, "section": section,
                     "combos": combos, "editable": not head})
    return rows + [{**row, "combos": [], "editable": False} for row in PANEL_ROWS]


def _view(row):
    """Lo que enseña la página de configuración de una fila de atajos."""
    return {"keys": row["keys"], "text": row["text"], "combos": row["combos"], "editable": row["editable"]}


def sections(hotkeys):
    """{sección: [{keys, text}]} de todos los atajos, en el orden de SECTIONS."""
    grouped = {name: [] for name in SECTIONS}
    for row in command_rows(hotkeys):
        grouped.setdefault(row["section"], []).append(_view(row))
    return grouped


# ---------- la página de configuración (el botón de la barra de arriba) ----------

# qué es cada sección de atajos (se enseña al abrir su tarjeta)
SECTION_INFO = {
    "Navegación": "Moverte entre ventanas y abrir el buscador: lo que usas todo el día.",
    "Ventanas": "Acomodar el mosaico: orientación, mover, cerrar y reemplazar ventanas.",
    "Escritorios": "Crear, cerrar y cambiar de escritorio (la pantalla se desliza al de al lado).",
    "Sistema": "Fondos de pantalla, música, energía, el foco con el ratón y la salida de emergencia.",
    "Tareas": "Tus tareas y notas, y los atajos que valen dentro del buscador.",
}
# los atajos agrupados por su tecla principal (con qué empiezan), en este orden
KEY_GROUPS = (
    ("Ctrl+Shift", "Control y Mayús a la vez: los atajos principales de Kyora (la tecla Windows está bloqueada)."),
    ("Ctrl+Shift+Alt", "Control, Mayús y Alt: orientación de la ventana, cerrar todo, cerrar escritorio y la salida de emergencia."),
    ("Ctrl", "Atajos con Control: los de dentro de las tareas y las notas."),
    ("Alt", "Combinaciones de dos teclas con Alt (Alt+F+flecha...): para quien las configure en config.json."),
    ("Otras", "Teclas sueltas y prefijos que se escriben en el buscador."),
)
# los ejecutables, por secciones: (nombre, qué es, posiciones en KYORA_OPTIONS)
EXECUTABLE_SECTIONS = (
    ("Kyora", "Reiniciar o actualizar Kyora y abrirla con una consola para ver los errores.", (0, 1, 2)),
    ("Rescate y cierre", "Cuando algo falla: devolver las ventanas y la barra de Windows, o cerrar Kyora.", (3, 6)),
    ("Inicio con Windows", "Que Kyora se abra sola al iniciar sesión, o dejar de hacerlo.", (4, 5)),
)


def key_group(keys):
    """El grupo de teclas de una fila ("Ctrl+Shift+←/→" -> "Ctrl+Shift", "Ctrl+N · ..." -> "Ctrl", "<texto" -> "Otras")."""
    first = keys.split(" ")[0]
    mods = []
    for part in first.split("+"):
        if part not in MODIFIER_NAMES.values():
            break
        mods.append(part)
    return "+".join(mods) if mods else "Otras"


def commands_by_section(hotkeys):
    """[{title, info, rows}] de los atajos, una tarjeta por sección."""
    data = sections(hotkeys)
    return [{"title": name, "info": SECTION_INFO.get(name, ""), "rows": data[name]} for name in SECTIONS if data.get(name)]


def commands_by_key(hotkeys):
    """[{title, info, rows}] de los atajos, una tarjeta por tecla principal (Ctrl+Shift, Ctrl+Shift+Alt, Ctrl...)."""
    buckets = {}
    for row in command_rows(hotkeys):
        buckets.setdefault(key_group(row["keys"]), []).append(_view(row))
    known = [name for name, _ in KEY_GROUPS]
    order = known + sorted(name for name in buckets if name not in known)
    info = dict(KEY_GROUPS)
    return [{"title": name, "info": info.get(name, f"Combinaciones que empiezan con {name}."), "rows": buckets[name]}
            for name in order if buckets.get(name)]


def executables():
    """[{title, info, rows}] de los ejecutables, una tarjeta por sección; cada fila lleva su acción y sus datos."""
    cards = []
    for name, info, indexes in EXECUTABLE_SECTIONS:
        rows = [{"keys": KYORA_OPTIONS[i][0], "text": KYORA_OPTIONS[i][1], "action": KYORA_OPTIONS[i][2],
                 "payload": KYORA_OPTIONS[i][3]} for i in indexes]
        cards.append({"title": name, "info": info, "rows": rows})
    return cards


def config_data(hotkeys):
    """Todo lo que enseña la página de configuración: {"commands": {"section": [...], "key": [...]}, "executables": [...]}."""
    return {"commands": {"section": commands_by_section(hotkeys), "key": commands_by_key(hotkeys)},
            "executables": executables(), "hotkeys": dict(hotkeys)}


# ---------- ayudas de la página de configuración ----------

def key_tokens(keys):
    """Parte el texto de unas teclas en piezas para pintarlas como teclas: [("cap", "Ctrl"), ("cap", "Shift"), ("cap", "T")].
    Los " · " entre combinaciones salen como ("sep", "·") y lo que va entre paréntesis como ("note", "(en las tareas)")."""
    tokens = []
    for n, segment in enumerate(keys.split(" · ")):
        if n:
            tokens.append(("sep", "·"))
        note = ""
        if " (" in segment:
            segment, note = segment.split(" (", 1)
            note = "(" + note
        tokens.extend(("cap", part) for part in segment.split("+") if part)
        if note:
            tokens.append(("note", note))
    return tokens


def filter_cards(cards, text):
    """Las tarjetas con solo las filas que contienen `text` (en las teclas o en la explicación); si coincide el título de
    una tarjeta, se queda entera. Sin texto, todas tal cual."""
    needle = (text or "").strip().lower()
    if not needle:
        return cards
    result = []
    for card in cards:
        if needle in card["title"].lower():
            result.append(card)
            continue
        rows = [r for r in card["rows"] if needle in r["keys"].lower() or needle in r["text"].lower()]
        if rows:
            result.append({**card, "rows": rows})
    return result


def label_of(hotkeys, combo):
    """Lo que hace el atajo `combo` de `hotkeys`, en pocas palabras (para avisar de que ya está usado)."""
    spec = hotkeys.get(combo)
    action = spec[0] if isinstance(spec, (list, tuple)) and spec else str(spec)
    return ACTION_TEXT.get(action, action).split(" (")[0]

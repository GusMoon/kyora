"""Editar los atajos desde la configuración, sin Qt ni Windows (se puede probar).

Valida una combinación nueva (que tenga sentido, que no use la tecla Windows ni choque con las de todas las apps, que no
la use ya otro atajo de Kyora) y arma la configuración nueva. Un atajo suelto cambia entera; un grupo (las cuatro
flechas, 1/2/3, T/N…) cambia solo sus modificadores y conserva sus teclas.
"""
MOD_ORDER = ("ctrl", "shift", "alt")
NAMED_KEYS = ("space", "enter", "tab", "esc", "left", "up", "right", "down", "pageup", "pagedown", "backspace", "delete",
              "minus", *(f"f{n}" for n in range(1, 13)))
# combinaciones que el sistema o casi todas las apps usan: tragárselas rompería todo
RESERVED = {
    "alt+f4": "cerrar la ventana", "alt+tab": "cambiar de ventana", "alt+esc": "cambiar de ventana",
    "ctrl+esc": "abrir el menú de inicio", "ctrl+shift+esc": "el administrador de tareas",
    "ctrl+alt+delete": "las opciones de seguridad de Windows",
    **{f"ctrl+{k}": name for k, name in (("c", "copiar"), ("v", "pegar"), ("x", "cortar"), ("z", "deshacer"),
                                         ("y", "rehacer"), ("a", "seleccionar todo"), ("s", "guardar"))},
}


def normalize(combo):
    """'Shift+Ctrl+T' -> 'ctrl+shift+t' (modificadores en un orden fijo y en minúsculas)."""
    parts = [p for p in combo.lower().replace(" ", "").split("+") if p]
    mods = [m for m in MOD_ORDER if m in parts]
    rest = [p for p in parts if p not in MOD_ORDER]
    return "+".join(mods + rest)


def split(combo):
    """'ctrl+shift+t' -> (['ctrl', 'shift'], ['t'])."""
    parts = normalize(combo).split("+") if combo else []
    return [p for p in parts if p in MOD_ORDER + ("win",)], [p for p in parts if p not in MOD_ORDER + ("win",)]


def valid_key(key):
    return key in NAMED_KEYS or (len(key) == 1 and key.isascii() and key.isalnum())


def validate(combo, hotkeys, own=(), label=lambda combo: combo, is_free=None):
    """(ok, mensaje) de una combinación nueva. `own`: las combinaciones del atajo que se edita (no cuentan como uso
    ajeno); `label(combo)`: cómo se llama lo que hace un atajo; `is_free(combo)`: pregunta al sistema si otro programa
    ya la tiene (None: no se pregunta)."""
    combo = normalize(combo)
    mods, keys = split(combo)
    if "win" in mods:
        return False, "La tecla Windows está bloqueada: usa Ctrl, Mayús o Alt."
    if len(keys) != 1 or not valid_key(keys[0]):
        return False, "Pulsa una sola tecla (letra, número, flecha, F1-F12…) junto a los modificadores."
    if not ({"ctrl", "alt"} & set(mods)):
        return False, "Necesita Ctrl o Alt, si no se tragaría la tecla en todas las apps."
    if combo in RESERVED:
        return False, f"Ya lo usan casi todas las apps ({RESERVED[combo]}): elige otra."
    own = {normalize(c) for c in own}
    for other in hotkeys:
        if normalize(other) == combo and normalize(other) not in own:
            return False, f"Ya lo usa «{label(other)}»."
    if is_free is not None and combo not in {normalize(c) for c in hotkeys} and not is_free(combo):
        return False, "Otro programa ya usa esa combinación."
    return True, ""


def apply_edit(hotkeys, row_combos, pressed, label=lambda combo: combo, is_free=None):
    """(hotkeys nuevos, "") o (None, mensaje). `pressed`: la combinación que pulsó el usuario. Con un solo atajo en la
    fila se sustituye entero; con varios (un grupo), se aplican los modificadores de `pressed` a cada uno."""
    row_combos = [normalize(c) for c in row_combos]
    mods, _keys = split(pressed)
    if len(row_combos) == 1:
        new = {row_combos[0]: normalize(pressed)}
    else:
        new = {old: normalize("+".join([*mods, *split(old)[1]])) for old in row_combos}
        if len(set(new.values())) != len(new):
            return None, "Esa combinación repetiría teclas del grupo."
    for combo in new.values():
        ok, message = validate(combo, hotkeys, own=row_combos, label=label, is_free=is_free)
        if not ok:
            return None, message
    # los demás atajos que no se editan no pueden coincidir con los nuevos
    result = {}
    for combo, spec in hotkeys.items():
        key = normalize(combo)
        result[new.get(key, combo)] = spec
    return result, ""

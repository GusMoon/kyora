"""Configuración de Kyora en %APPDATA%\\Kyora\\config.json (se crea con los valores por defecto)."""
import copy
import json
import os
from pathlib import Path

CONFIG_VERSION = 18  # súbelo cuando cambien los valores por defecto: el config.json anterior se guarda aparte


def data_dir():
    base = os.environ.get("APPDATA") or str(Path.home())
    path = Path(base) / "Kyora"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _default_hotkeys():
    """Atajos por defecto. Se pueden cambiar o añadir más en config.json (las acciones están en app.py)."""
    keys = {
        "alt+f": ["wm.focus_next", {}],  # el foco pasa a la siguiente ventana visible
        "alt+esc": ["wm.close", {}],
        "alt+d": ["desktop.create", {}],
        "alt+e": ["switcher.toggle", {}],  # panel de ventanas en espera: cambiar de app
        "alt+o": ["wm.rotate", {}],  # la ventana grande gira: arriba, derecha, abajo, izquierda
        "alt+space": ["search.toggle", {}],
        "alt+m": ["app.focus_follows_mouse", {}],
        "ctrl+alt+shift+q": ["app.release", {}],  # salida de emergencia
    }
    for direction in ("left", "right", "up", "down"):
        keys[f"alt+{direction}"] = ["wm.move", {"dir": direction}]  # la ventana cambia de hueco con su vecina
    for n in (1, 2, 3):
        keys[f"alt+{n}"] = ["wm.show_count", {"n": n}]  # ver 1, 2 o 3 ventanas
    keys["win+up"] = ["desktop.step", {"delta": -1}]  # escritorio de arriba (la barra los numera de arriba abajo)
    keys["win+down"] = ["desktop.step", {"delta": 1}]  # escritorio de abajo
    keys["win+esc"] = ["wm.close_all", {}]  # cerrar todas las ventanas (pulsado dos veces)
    keys["win+-"] = ["desktop.close_current", {}]  # cerrar este escritorio (sus ventanas pasan al anterior)
    keys["win+subtract"] = ["desktop.close_current", {}]  # lo mismo con el - del teclado numérico
    keys["win+x"] = ["power.menu", {}]  # apagar, reiniciar o suspender (como el menú de Win+X de Windows)
    keys["win+i"] = ["hub.toggle", {"section": "lobby"}]  # panel de arriba en el Lobby (Inicio)
    keys["win+e"] = ["hub.toggle", {"section": "files"}]  # en Archivos, en lugar del Explorador
    keys["win+t"] = ["hub.toggle", {"section": "tasks"}]  # en Tareas
    keys["win+b"] = ["hub.toggle", {"section": "brain"}]  # en el Segundo Cerebro (Brain)
    keys["win+k"] = ["hub.toggle", {"section": "kyora"}]  # en Kyora
    return keys


DEFAULTS = {
    "config_version": CONFIG_VERSION,
    "focus_follows_mouse": True,
    "hide_taskbar": True,
    "ignore_processes": [
        "TextInputHost.exe",
        "SearchHost.exe",
        "StartMenuExperienceHost.exe",
        "ShellExperienceHost.exe",
        "LockApp.exe",
    ],
    "hotkeys": _default_hotkeys(),
    "weather": {"city": ""},  # tu ciudad (por ejemplo "Madrid"): el clima de la barra sale de Open-Meteo
}


def load():
    """Lee la configuración; las claves que falten se completan con los valores por defecto.

    Si el archivo es de una versión anterior (o está dañado) se guarda como config.old.json y se
    crea uno nuevo, para que los valores por defecto nuevos (barra, atajos) se apliquen.
    """
    path = data_dir() / "config.json"
    config = copy.deepcopy(DEFAULTS)
    if path.exists():
        try:
            user = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            user = None
        if isinstance(user, dict) and user.get("config_version", 0) >= CONFIG_VERSION:
            hotkeys = user.pop("hotkeys", None)
            config.update(user)
            if isinstance(hotkeys, dict):
                config["hotkeys"] = hotkeys
            return config
        path.replace(path.with_name("config.old.json"))
    path.write_text(json.dumps(DEFAULTS, indent=2, ensure_ascii=False), encoding="utf-8")
    return config

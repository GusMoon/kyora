"""Configuración de Kyora en %APPDATA%\\Kyora\\config.json (se crea con los valores por defecto)."""
import copy
import json
import os
from pathlib import Path

CONFIG_VERSION = 30  # súbelo cuando cambien los valores por defecto: el config.json anterior se guarda aparte


def data_dir():
    base = os.environ.get("APPDATA") or str(Path.home())
    path = Path(base) / "Kyora"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _default_hotkeys():
    """Atajos globales por defecto: todos con Ctrl+Shift (la tecla Windows está bloqueada y los Alt+… quedan para las
    apps). Se pueden cambiar o añadir más en config.json (las acciones están en app.py)."""
    keys = {
        "ctrl+shift+space": ["search.toggle", {}],  # el buscador del borde de arriba
        "ctrl+shift+t": ["search.open_mode", {"mode": "task"}],  # tus tareas, directo en el Kanban
        "ctrl+shift+n": ["search.open_mode", {"mode": "notes"}],  # tus notas
        "ctrl+shift+c": ["search.open_mode", {"mode": "chat"}],  # el chat con tus otros dispositivos (Supabase)
        "ctrl+shift+f": ["wm.focus_next", {}],  # el foco pasa a la siguiente ventana del mosaico
        "ctrl+shift+r": ["switcher.toggle", {}],  # reemplazar la ventana enfocada por otra que está en espera
        "ctrl+shift+w": ["wallpaper.mode", {}],  # los fondos de pantalla, con las flechas, y los colores de Kyora cambian
        "ctrl+shift+e": ["desktop.create", {}],  # escritorio nuevo
        "ctrl+shift+x": ["power.menu", {}],  # apagar, reiniciar o suspender, con todo desenfocado
        "ctrl+shift+q": ["wm.close", {}],  # cerrar la ventana con foco
        "ctrl+shift+alt+x": ["wm.close_all", {}],  # cerrar todo en todos los escritorios
        "ctrl+shift+m": ["music.panel", {}],  # tus listas de YouTube y su descarga en MP3
    }
    for direction in ("left", "right", "up", "down"):
        keys[f"ctrl+shift+{direction}"] = ["wm.move", {"dir": direction}]  # la ventana cambia de hueco con su vecina
        keys[f"ctrl+shift+alt+{direction}"] = ["wm.arrange", {"dir": direction}]  # orientación: arriba, abajo, minimizar…
    for n in (1, 2, 3):
        keys[f"ctrl+shift+{n}"] = ["wm.show_count", {"n": n}]  # ver 1, 2 o 3 ventanas en el mosaico
    keys["ctrl+shift+pageup"] = ["desktop.step", {"delta": -1}]  # escritorio anterior: la pantalla se desliza
    keys["ctrl+shift+pagedown"] = ["desktop.step", {"delta": 1}]  # escritorio siguiente
    keys["ctrl+shift+alt+e"] = ["desktop.close_current", {}]  # cerrar este escritorio (sus ventanas pasan al anterior)
    keys["ctrl+alt+shift+q"] = ["app.release", {}]  # salida de emergencia
    return keys


# Atajos que llegaron después de la primera versión: el config.json de quien ya usa Kyora guarda sus atajos enteros y no los
# tomaría de los de fábrica, así que se le ofrecen UNA vez (si la combinación está libre) y se anota en `hotkeys_offered`.
NEW_HOTKEYS = {"chat": {"ctrl+shift+c": ["search.open_mode", {"mode": "chat"}]}}

DEFAULTS = {
    "config_version": CONFIG_VERSION,
    "focus_follows_mouse": True,
    "hide_taskbar": True,
    "disable_snap": True,  # apaga mientras Kyora está abierta el acoplado y acomodo de ventanas de Windows
    "light_mode": True,  # equipos justos de RAM: sin deslizamiento al cambiar de escritorio ni borde luminoso en las ventanas
    "animate_windows": True,  # la pantalla se desliza al cambiar de escritorio (False: cambia de golpe)
    "ignore_processes": [
        "TextInputHost.exe",
        "SearchHost.exe",
        "StartMenuExperienceHost.exe",
        "ShellExperienceHost.exe",
        "LockApp.exe",
    ],
    "hotkeys": _default_hotkeys(),
    "hotkeys_offered": sorted(NEW_HOTKEYS),  # qué atajos nuevos de NEW_HOTKEYS ya se ofrecieron a este config.json
    "music": {"browser": "chrome", "cookies_file": "", "sync": True},  # sync: lo que bajas sube a Supabase para tu móvil. Cookies de YouTube: del navegador, o de un cookies.txt (si existe %APPDATA%\Kyora\cookies.txt se usa solo)
    "web_shortcuts": [],  # páginas del buscador: [{"name": "youtube", "url": "https://youtube.com"}]
    "defaults": {"browser": ""},  # navegador con el que abren las páginas (ruta del .exe; vacío: el predeterminado de Windows)
    "chat": {"max_mb": 50, "history": 50},  # el chat con Supabase (credenciales en supabase/.env): límite por archivo y mensajes que se cargan
    "weather": {"city": ""},  # tu ciudad (por ejemplo "Madrid"): el clima de la barra sale de Open-Meteo
}


def default_hotkeys():
    """Una copia de los atajos por defecto (para restaurarlos)."""
    return copy.deepcopy(_default_hotkeys())


def save_option(key, value):
    """Guarda un ajuste en config.json sin tocar lo demás."""
    path = data_dir() / "config.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            data = copy.deepcopy(DEFAULTS)
    except (OSError, ValueError):
        data = copy.deepcopy(DEFAULTS)
    data[key] = value
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def save_hotkeys(hotkeys):
    """Guarda los atajos en config.json sin tocar lo demás."""
    path = data_dir() / "config.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            data = copy.deepcopy(DEFAULTS)
    except (OSError, ValueError):
        data = copy.deepcopy(DEFAULTS)
    data["hotkeys"] = hotkeys
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


def _offer_new_hotkeys(config, user):
    """Añade (una sola vez) los atajos de NEW_HOTKEYS que este config.json aún no conocía, sin pisar ninguno suyo."""
    offered = set(user.get("hotkeys_offered") or [])
    pending = [name for name in NEW_HOTKEYS if name not in offered]
    if not pending:
        return
    hotkeys = config["hotkeys"]
    for name in pending:
        for combo, spec in NEW_HOTKEYS[name].items():
            taken = combo in hotkeys or any(v == spec or list(v) == spec for v in hotkeys.values())
            if not taken:
                hotkeys[combo] = copy.deepcopy(spec)
        offered.add(name)
    config["hotkeys_offered"] = sorted(offered)
    save_hotkeys(hotkeys)
    save_option("hotkeys_offered", config["hotkeys_offered"])


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
                _offer_new_hotkeys(config, user)
            return config
        path.replace(path.with_name("config.old.json"))
    path.write_text(json.dumps(DEFAULTS, indent=2, ensure_ascii=False), encoding="utf-8")
    return config

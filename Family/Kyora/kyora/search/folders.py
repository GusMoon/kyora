"""Carpetas para el buscador (sin Qt: se puede probar): las raíces y los hijos del árbol de "/", las unidades y
la carpeta de fondos de `>wallpaper`.
"""
import os
import string

from kyora.brain.links import normalize

IMAGE_TYPES = (".jpg", ".jpeg", ".png", ".bmp", ".webp")
LIMIT = 200  # hijos que enseña una carpeta del árbol
THIS_PC = "equipos:"  # la "ruta" de Equipos, el nodo del que cuelgan las unidades
# raíces del árbol, como el acceso rápido del Explorador: (nombre que se ve, clave de la carpeta de Windows)
TREE_ROOTS = (
    ("Escritorio", "desktop"),
    ("Descargas", "downloads"),
    ("Documentos", "documents"),
    ("Imágenes", "pictures"),
    ("Música", "music"),
    ("Vídeos", "videos"),
)


def drives():
    """Las unidades que existen (C:\\, D:\\…)."""
    if hasattr(os, "listdrives"):
        return list(os.listdrives())
    return [f"{letter}:\\" for letter in string.ascii_uppercase if os.path.exists(f"{letter}:\\")]


def tree_roots(known_folder):
    """[{name, path, is_dir, size, drive}] de lo que se ve al escribir "/": las carpetas del acceso rápido y Equipos."""
    roots = []
    for name, key in TREE_ROOTS:
        path = known_folder(key)
        if path and os.path.isdir(path):
            roots.append({"name": name, "path": path, "is_dir": True, "size": 0, "drive": False})
    roots.append({"name": "Equipos", "path": THIS_PC, "is_dir": True, "size": 0, "drive": False, "computer": True})
    return roots


def pc_entries(drive_list=drives):
    """Lo que cuelga de Equipos: las unidades."""
    return [{"name": d.rstrip("\\"), "path": d, "is_dir": True, "size": 0, "drive": True} for d in drive_list()]


def _hidden(entry):
    if entry.name.startswith("."):
        return True
    try:
        return bool(entry.stat(follow_symlinks=False).st_file_attributes & 0x2)  # FILE_ATTRIBUTE_HIDDEN
    except (OSError, AttributeError):
        return False


def listing(folder, needle="", show_hidden=False, limit=LIMIT):
    """[{name, path, is_dir, size}] de la carpeta: primero las carpetas y después los archivos, por nombre.
    `needle` filtra por nombre (sin tildes ni mayúsculas)."""
    key = normalize(needle)
    found = []
    try:
        with os.scandir(folder) as entries:
            for entry in entries:
                if (key and key not in normalize(entry.name)) or (not show_hidden and _hidden(entry)):
                    continue
                try:
                    is_dir = entry.is_dir()
                    size = 0 if is_dir else entry.stat().st_size
                except OSError:
                    continue
                found.append({"name": entry.name, "path": entry.path, "is_dir": is_dir, "size": size})
    except OSError:
        return []
    found.sort(key=lambda e: (not e["is_dir"], e["name"].lower()))
    return found[:limit]


def human_size(n):
    """"512 B", "1,4 KB", "23,5 MB", "1,2 GB"."""
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n} {unit}" if unit == "B" else f"{n:.1f} {unit}".replace(".", ",")
        n /= 1024
    return ""


def short_path(path, keep=3):
    """"…\\Documents\\Kyora\\code": la carpeta que contiene algo, abreviada para una fila del buscador."""
    home = os.path.expanduser("~")
    if os.path.normcase(path).startswith(os.path.normcase(home)):
        path = "~" + path[len(home):]
    parts = [p for p in path.replace("/", "\\").split("\\") if p]
    if len(parts) <= keep + 1:
        return "\\".join(parts) if not path.startswith("\\") else path
    return parts[0] + "\\…\\" + "\\".join(parts[-keep:])


def wallpapers(known_folder):
    """(carpeta, [rutas de imágenes]) de Imágenes\\wallpapers, por nombre."""
    pictures = known_folder("pictures") or os.path.join(os.path.expanduser("~"), "Pictures")
    folder = os.path.join(pictures, "wallpapers")
    try:
        names = sorted((n for n in os.listdir(folder) if n.lower().endswith(IMAGE_TYPES)), key=str.lower)
    except OSError:
        return folder, []
    return folder, [os.path.join(folder, n) for n in names]

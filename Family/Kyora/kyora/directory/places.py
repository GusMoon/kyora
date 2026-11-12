"""Lugares del explorador (las carpetas de siempre y las ancladas) y sus preferencias, en directory.json."""
import json
import logging
import os

log = logging.getLogger("kyora.directory")

DEFAULT_PLACES = (
    ("Carpeta personal", "home"),
    ("Escritorio", "desktop"),
    ("Documentos", "documents"),
    ("Descargas", "downloads"),
    ("Imágenes", "pictures"),
    ("Música", "music"),
    ("Vídeos", "videos"),
)


def default_places(known_folder):
    """[(nombre, ruta)] de las carpetas de siempre que existen. `known_folder(clave)` da la ruta de Windows."""
    places = []
    for name, key in DEFAULT_PLACES:
        path = os.path.expanduser("~") if key == "home" else known_folder(key)
        if path and os.path.isdir(path):
            places.append((name, path))
    return places


class DirectoryState:
    """Carpetas ancladas, "mostrar ocultos" y la vista (cuadrícula o lista). Se guardan al cambiar."""

    def __init__(self, path):
        self._path = path
        self.pinned, self.show_hidden, self.view = [], False, "grid"
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            self.pinned = [p for p in data.get("pinned", []) if isinstance(p, str)]
            self.show_hidden = bool(data.get("show_hidden", False))
            self.view = data.get("view") if data.get("view") in ("grid", "list") else "grid"
        except (OSError, ValueError, AttributeError):
            pass

    def save(self):
        data = {"pinned": self.pinned, "show_hidden": self.show_hidden, "view": self.view}
        try:
            self._path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        except OSError as err:
            log.warning("No se pudo guardar directory.json: %s", err)

    def pin(self, path):
        if not os.path.isdir(path):
            raise ValueError("Solo se pueden anclar carpetas")
        if all(os.path.normcase(p) != os.path.normcase(path) for p in self.pinned):
            self.pinned.append(path)
            self.save()

    def unpin(self, path):
        self.pinned = [p for p in self.pinned if os.path.normcase(p) != os.path.normcase(path)]
        self.save()

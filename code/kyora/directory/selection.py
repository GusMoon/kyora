"""Selección múltiple avanzada: elementos de varias carpetas a la vez.

Un clic normal deja seleccionado solo lo de la carpeta actual; con Ctrl lo de esta carpeta se suma a lo que ya
estaba elegido en otras, y se conserva al navegar.
"""
import os


def _key(path):
    return os.path.normcase(os.path.abspath(path))


class MultiSelection:
    def __init__(self):
        self._paths = {}  # clave normalizada -> ruta tal cual, en orden de elección

    def replace(self, paths):
        """Solo estas rutas (clic normal)."""
        self._paths = {_key(p): p for p in paths}

    def set_folder(self, folder, paths):
        """Lo elegido en `folder` pasa a ser `paths`; lo de otras carpetas se queda (Ctrl+clic)."""
        folder = _key(folder)
        self._paths = {k: p for k, p in self._paths.items() if os.path.dirname(k) != folder}
        self._paths.update({_key(p): p for p in paths})

    def discard(self, paths):
        for p in paths:
            self._paths.pop(_key(p), None)

    def clear(self):
        self._paths = {}

    def paths(self):
        return list(self._paths.values())

    def folders(self):
        return {os.path.dirname(k) for k in self._paths}

    def __len__(self):
        return len(self._paths)

    def summary(self):
        """"3 seleccionados en 2 carpetas", o "" si no hay nada de varias carpetas."""
        n, folders = len(self._paths), len(self.folders())
        if n == 0 or folders < 2:
            return ""
        return f"{n} seleccionados en {folders} carpetas"

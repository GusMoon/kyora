"""Deshacer del explorador: cada operación guarda cómo volver atrás.

Crear y copiar se deshacen mandando lo nuevo a la Papelera; renombrar y mover, devolviéndolo a su sitio.
Lo que se manda a la Papelera no se deshace desde aquí: se recupera desde la Papelera de Windows.
"""
import os
import shutil

LIMIT = 50


class UndoStack:
    def __init__(self, recycle):
        self._recycle = recycle
        self._items = []

    def push(self, kind, data, label):
        """`kind`: "create" (rutas), "copy" (rutas nuevas), "rename" ((vieja, nueva)), "move" ([(origen, destino)])."""
        self._items.append((kind, data, label))
        del self._items[:-LIMIT]

    def __len__(self):
        return len(self._items)

    def undo(self):
        """Deshace lo último. Devuelve el texto de lo deshecho, o None si no hay nada."""
        if not self._items:
            return None
        kind, data, label = self._items.pop()
        if kind in ("create", "copy"):
            self._recycle([p for p in data if os.path.lexists(p)])
        elif kind == "rename":
            old, new = data
            if os.path.lexists(old):
                raise FileExistsError(f"No se puede deshacer: ya existe {os.path.basename(old)}")
            os.rename(new, old)
        elif kind == "move":
            for src, dst in reversed(data):
                if os.path.lexists(src):
                    raise FileExistsError(f"No se puede deshacer: ya existe {src}")
                shutil.move(dst, src)
        return label

"""El módulo Directorio (4.2 de kyoraBase.md): lo que el explorador puede pedir, como acciones con nombre.

Las operaciones rápidas (crear, renombrar, anclar…) responden enseguida. Copiar, mover, mandar a la Papelera y
buscar corren en un hilo y avisan con `emit(evento)`:
- {"kind": "progress", "done", "total", "current"}
- {"kind": "conflict", "name", "src", "dst"}: el hilo espera la respuesta (`resolve`)
- {"kind": "done", "message", "paths"} o {"kind": "error", "message"}
- {"kind": "search", "query", "paths"} y {"kind": "search_done", "query", "count"}
"""
import os
import threading
import time

from kyora.core.actions import ActionError
from kyora.directory import ops
from kyora.directory.places import DirectoryState, default_places
from kyora.directory.search import search
from kyora.directory.undo import UndoStack

PROGRESS_EVERY = 0.1  # segundos entre avisos de progreso


def _plural(n, one, many):
    return f"{n} {one if n == 1 else many}"


class DirectoryService:
    def __init__(self, data_dir, emit, known_folder, recycle, open_with):
        self.state = DirectoryState(data_dir / "directory.json")
        self.undo_stack = UndoStack(recycle)
        self._emit, self._known, self._recycle, self._open_with = emit, known_folder, recycle, open_with
        self._busy = threading.Lock()
        self._cancel = threading.Event()
        self._answer = threading.Event()
        self._choice = None
        self._search_cancel = threading.Event()

    def register(self, registry):
        r = registry
        r.register("directory.places", self.places)
        r.register("directory.prefs", self.prefs)
        r.register("directory.set_prefs", self.set_prefs)
        r.register("directory.pin", self.pin)
        r.register("directory.unpin", self.unpin)
        r.register("directory.open", self.open)
        r.register("directory.open_with", self.open_with)
        r.register("directory.create_folder", self.create_folder)
        r.register("directory.create_file", self.create_file)
        r.register("directory.rename", self.rename)
        r.register("directory.transfer", self.transfer)
        r.register("directory.duplicate", self.duplicate)
        r.register("directory.recycle", self.recycle, destructive=True)
        r.register("directory.undo", self.undo)
        r.register("directory.resolve", self.resolve)
        r.register("directory.cancel", self.cancel)
        r.register("directory.search", self.search)
        r.register("directory.stop_search", self.stop_search)

    # ---------- lugares y preferencias ----------

    def places(self):
        return {"places": default_places(self._known), "pinned": list(self.state.pinned)}

    def prefs(self):
        return {"show_hidden": self.state.show_hidden, "view": self.state.view}

    def set_prefs(self, show_hidden=None, view=None):
        if show_hidden is not None:
            self.state.show_hidden = bool(show_hidden)
        if view in ("grid", "list"):
            self.state.view = view
        self.state.save()
        return self.prefs()

    def pin(self, path):
        try:
            self.state.pin(path)
        except ValueError as err:
            raise ActionError("not_folder", str(err)) from err
        return self.places()

    def unpin(self, path):
        self.state.unpin(path)
        return self.places()

    # ---------- abrir, crear y renombrar ----------

    @staticmethod
    def open(path):
        if not os.path.exists(path):
            raise ActionError("missing", "Ese archivo ya no existe")
        os.startfile(path)

    def open_with(self, path):
        self._open_with(path)

    def _create(self, fn, parent, what):
        try:
            path = fn(parent)
        except OSError as err:
            raise ActionError("create_failed", f"No se pudo crear {what}: {err.strerror or err}") from err
        self.undo_stack.push("create", [path], f"Crear «{os.path.basename(path)}»")
        return path

    def create_folder(self, parent):
        return self._create(ops.create_folder, parent, "la carpeta")

    def create_file(self, parent):
        return self._create(ops.create_file, parent, "el archivo")

    def rename(self, path, name):
        try:
            new = ops.rename(path, name)
        except (ValueError, FileExistsError) as err:
            raise ActionError("bad_name", str(err)) from err
        except OSError as err:
            raise ActionError("rename_failed", f"No se pudo renombrar: {err.strerror or err}") from err
        if new != path:
            self.undo_stack.push("rename", (path, new), f"Renombrar «{os.path.basename(new)}»")
        return new

    # ---------- operaciones largas (en un hilo) ----------

    def _start(self, work):
        if not self._busy.acquire(blocking=False):
            raise ActionError("busy", "Espera a que termine la operación en curso")
        self._cancel.clear()

        def run():
            try:
                self._emit(work())
            except ops.Cancelled:
                self._emit({"kind": "done", "message": "Cancelado", "paths": []})
            except (OSError, ValueError) as err:
                self._emit({"kind": "error", "message": str(err)})
            finally:
                self._busy.release()

        threading.Thread(target=run, daemon=True, name="kyora-files").start()

    def _reporter(self):
        last = [0.0]

        def report(done, total, current):
            now = time.monotonic()
            if now - last[0] >= PROGRESS_EVERY or done >= total:
                last[0] = now
                self._emit({"kind": "progress", "done": done, "total": total, "current": current})

        return report

    def _ask(self, src, dst):
        """Pregunta a la interfaz qué hacer con un nombre repetido y espera la respuesta."""
        self._answer.clear()
        self._emit({"kind": "conflict", "name": os.path.basename(dst), "src": src, "dst": dst})
        while not self._answer.wait(0.2):
            if self._cancel.is_set():
                raise ops.Cancelled()
        return self._choice

    def resolve(self, choice, every=False):
        """Respuesta al conflicto: "replace", "both" o "skip" (y si se aplica a todos los que vengan)."""
        if choice not in ("replace", "both", "skip"):
            raise ActionError("bad_choice", f"Respuesta desconocida: {choice}")
        self._choice = (choice, bool(every))
        self._answer.set()

    def cancel(self):
        self._cancel.set()
        self._answer.set()  # por si estaba esperando una respuesta

    def transfer(self, sources, dest, move=False):
        """Copia o mueve `sources` a la carpeta `dest`."""
        sources = [s for s in sources if os.path.exists(s)]
        if not sources:
            raise ActionError("nothing", "No hay nada que pegar")

        def work():
            done = ops.transfer(sources, dest, move, self._ask, self._recycle, self._reporter(), self._cancel)
            if done:
                verb = "Mover" if move else "Copiar"
                self.undo_stack.push("move" if move else "copy", done if move else [d for _, d in done],
                                     f"{verb} {_plural(len(done), 'elemento', 'elementos')}")
            what = "Movidos" if move else "Copiados"
            return {"kind": "done", "message": f"{what}: {_plural(len(done), 'elemento', 'elementos')}",
                    "paths": [d for _, d in done]}

        self._start(work)

    def duplicate(self, paths):
        """Copia cada elemento en su misma carpeta, con otro nombre ("nombre (2)")."""
        folders = {os.path.dirname(p) for p in paths}
        if len(folders) != 1:
            raise ActionError("many_folders", "Duplica elementos de una sola carpeta a la vez")
        self.transfer(paths, folders.pop(), move=False)

    def recycle(self, paths):
        paths = [p for p in paths if os.path.lexists(p)]
        if not paths:
            raise ActionError("nothing", "No hay nada seleccionado")

        def work():
            self._recycle(paths)
            return {"kind": "done", "paths": [],
                    "message": f"{_plural(len(paths), 'elemento', 'elementos')} a la Papelera "
                               "(se recuperan desde la Papelera de Windows)"}

        self._start(work)

    def undo(self):
        try:
            label = self.undo_stack.undo()
        except OSError as err:
            raise ActionError("undo_failed", str(err)) from err
        if label is None:
            raise ActionError("nothing", "No hay nada que deshacer")
        return f"Deshecho: {label}"

    # ---------- búsqueda ----------

    def search(self, root, query):
        self.stop_search()
        cancel = threading.Event()
        self._search_cancel = cancel

        def run():
            count = 0
            for batch in search(root, query, self.state.show_hidden, cancel):
                if cancel.is_set():
                    return
                count += len(batch)
                self._emit({"kind": "search", "query": query, "paths": batch})
            if not cancel.is_set():
                self._emit({"kind": "search_done", "query": query, "count": count})

        threading.Thread(target=run, daemon=True, name="kyora-search-files").start()

    def stop_search(self):
        self._search_cancel.set()

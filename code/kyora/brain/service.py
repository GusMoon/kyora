"""El Segundo Cerebro como acciones con nombre (brain.*).

La carpeta se elige la primera vez (`brain.setup`) y se guarda en brain.json, en la carpeta de datos de Kyora.
Para las sinapsis, los enlaces de vuelta y la búsqueda se guarda en memoria el texto de las notas, y se vuelve a
leer solo lo que cambió en disco (por su fecha de modificación).
"""
import json
import logging
import os
import re
import threading
from datetime import datetime

from kyora.brain import links, vault
from kyora.core.actions import ActionError

log = logging.getLogger("kyora.brain")
SEARCH_LIMIT = 60
IMPULSE_WORDS = 6


class BrainService:
    def __init__(self, data_dir, recycle, documents=None, now=datetime.now):
        """`recycle(paths)`: manda a la Papelera. `documents`: la carpeta Documentos (para la ruta por defecto)."""
        self._state_path = data_dir / "brain.json"
        self._recycle, self._now = recycle, now
        self._documents = documents or os.path.join(os.path.expanduser("~"), "Documents")
        self._cache = {}  # ruta -> (mtime, metadatos, cuerpo)
        self._lock = threading.RLock()
        self.root = None
        try:
            root = json.loads(self._state_path.read_text(encoding="utf-8")).get("root")
            if root and os.path.isdir(root):
                self.root = root
        except (OSError, ValueError, AttributeError):
            pass

    def register(self, registry):
        r = registry
        r.register("brain.status", self.status)
        r.register("brain.setup", self.setup)
        r.register("brain.tree", self.tree)
        r.register("brain.read", self.read)
        r.register("brain.save", self.save)
        r.register("brain.titles", self.titles)
        r.register("brain.resolve", self.resolve)
        r.register("brain.nucleus", self.nucleus)
        r.register("brain.search", self.search)
        r.register("brain.create_area", self.create_area)
        r.register("brain.create_dendrite", self.create_dendrite)
        r.register("brain.create_neuron", self.create_neuron)
        r.register("brain.create_note", self.create_note)
        r.register("brain.impulse", self.impulse)
        r.register("brain.derive", self.derive)
        r.register("brain.rename", self.rename)
        r.register("brain.delete", self.delete, destructive=True)

    # ---------- carpeta ----------

    def status(self):
        return {"configured": self.root is not None, "root": self.root,
                "default": os.path.join(self._documents, "Segundo Cerebro")}

    def setup(self, path):
        path = os.path.abspath(os.path.expandvars(os.path.expanduser((path or "").strip())))
        if not path or os.path.isfile(path):
            raise ActionError("bad_path", "Elige una carpeta")
        try:
            vault.setup(path)
            self._state_path.write_text(json.dumps({"root": path}, ensure_ascii=False), encoding="utf-8")
        except OSError as err:
            raise ActionError("io", f"No se pudo crear: {err}") from err
        self.root = path
        self._cache.clear()
        return self.status()

    def _root(self):
        if self.root is None or not os.path.isdir(self.root):
            raise ActionError("no_brain", "Primero elige dónde crear tu Segundo Cerebro")
        return self.root

    def _inside(self, path):
        """La ruta, si está dentro del cerebro (nunca se toca nada de fuera)."""
        root = os.path.normcase(os.path.abspath(self._root()))
        full = os.path.abspath(path or "")
        if os.path.normcase(full) != root and not os.path.normcase(full).startswith(root + os.sep):
            raise ActionError("outside", "Esa ruta no es del Segundo Cerebro")
        return full

    # ---------- índice en memoria ----------

    def _entry(self, path):
        """(metadatos, cuerpo) de la nota, leyéndola de nuevo solo si cambió."""
        with self._lock:
            try:
                mtime = os.path.getmtime(path)
            except OSError:
                self._cache.pop(path, None)
                return None
            cached = self._cache.get(path)
            if cached is None or cached[0] != mtime:
                try:
                    note = vault.read_note(path)
                except (OSError, UnicodeDecodeError) as err:
                    log.warning("No se pudo leer %s: %s", path, err)
                    return None
                cached = self._cache[path] = (mtime, note["meta"], note["body"])
            return cached[1], cached[2]

    def _all(self):
        """{ruta: (metadatos, cuerpo)} de todas las notas."""
        found = {}
        for folder, _, names in os.walk(self._root()):
            for name in names:
                if name.lower().endswith(".md"):
                    path = os.path.join(folder, name)
                    entry = self._entry(path)
                    if entry is not None:
                        found[path] = entry
        with self._lock:
            for gone in set(self._cache) - set(found):
                self._cache.pop(gone, None)
        return found

    def titles(self):
        return sorted({vault.title_of(p) for p in self._all()}, key=str.lower)

    def resolve(self, title):
        """Ruta de la nota con ese título (sin distinguir mayúsculas ni tildes), o None."""
        key = links.normalize(title.strip())
        for path in self._all():
            if links.normalize(vault.title_of(path)) == key:
                return path
        return None

    # ---------- leer y guardar ----------

    def tree(self):
        return vault.tree(self._root(), lambda p: (self._entry(p) or ({}, ""))[0])

    def _details(self, path, meta, body):
        notes = self._all()
        by_title = {links.normalize(vault.title_of(p)): p for p in notes}
        title = vault.title_of(path)
        key = links.normalize(title)
        backlinks = [{"title": vault.title_of(p), "path": p} for p, (_, other) in sorted(notes.items())
                     if p != path and key in {links.normalize(t) for t in links.extract_links(other)}]
        synapses = [{"title": t, "path": by_title.get(links.normalize(t))} for t in links.extract_links(body)]
        return {"soma": links.soma(body), "synapses": synapses, "backlinks": backlinks,
                "kind": vault.kind_of(self._root(), path, meta), "title": title}

    def read(self, path):
        path = self._inside(path)
        try:
            note = vault.read_note(path)
        except (OSError, UnicodeDecodeError) as err:
            raise ActionError("io", f"No se pudo abrir: {err}") from err
        return {"path": path, "meta": note["meta"], "body": note["body"], "mtime": note["mtime"],
                **self._details(path, note["meta"], note["body"])}

    def save(self, path, body, meta=None, mtime=None, force=False):
        """Guarda el cuerpo (y los metadatos). Si el archivo cambió en disco desde `mtime`, error "changed",
        salvo con `force`."""
        path = self._inside(path)
        if meta is None:
            meta = (self._entry(path) or ({}, ""))[0]
        try:
            new_mtime = vault.save_note(path, meta, body, self._now(), None if force else mtime)
        except vault.Changed as err:
            raise ActionError("changed", "La nota cambió fuera de Kyora desde que la abriste") from err
        except OSError as err:
            raise ActionError("io", f"No se pudo guardar: {err}") from err
        meta = (self._entry(path) or (meta, body))[0]
        return {"mtime": new_mtime, "meta": meta, **self._details(path, meta, body)}

    def nucleus(self, path):
        """Núcleo de una dendrita: sus neuronas y axones con sus títulos."""
        folder = self._inside(path)
        rows = []
        for name in sorted(os.listdir(folder), key=str.lower):
            note = os.path.join(folder, name)
            if name.lower().endswith(".md") and os.path.isfile(note):
                meta, body = self._entry(note) or ({}, "")
                rows.append({"title": vault.title_of(note), "path": note, "kind": vault.kind_of(self.root, note, meta),
                             "origin": vault.origin_of(meta), "headings": links.soma(body)["headings"]})
        return rows

    def search(self, query):
        """Notas cuyo título o contenido tienen `query` (sin tildes ni mayúsculas): primero las de título."""
        key = links.normalize((query or "").strip())
        if not key:
            return []
        by_title, by_text = [], []
        for path, (_, body) in sorted(self._all().items()):
            title = vault.title_of(path)
            row = {"title": title, "path": path, "kind": vault.kind_of(self.root, path)}
            if key in links.normalize(title):
                by_title.append(dict(row, snippet=links.snippet(body, query)))
            elif key in links.normalize(body):
                by_text.append(dict(row, snippet=links.snippet(body, query)))
        return (by_title + by_text)[:SEARCH_LIMIT]

    # ---------- crear ----------

    def _name(self, title):
        try:
            return vault.safe_name(title)
        except ValueError as err:
            raise ActionError("empty_name", str(err)) from err

    def _new(self, folder, title, kind, area="", dendrite="", origin=""):
        title = self._name(title)
        if self.resolve(title):
            raise ActionError("exists", f"Ya hay una nota «{title}»: los títulos no se repiten, para que las "
                                        f"sinapsis sepan a cuál apuntan")
        meta, body = vault.template(kind, title, self._now(), area, dendrite, origin)
        path = os.path.join(folder, title + ".md")
        try:
            vault.create_note(path, meta, body)
        except OSError as err:
            raise ActionError("io", f"No se pudo crear: {err}") from err
        return path

    def _mkdir(self, path):
        if os.path.exists(path):
            raise ActionError("exists", f"Ya existe «{os.path.basename(path)}»")
        try:
            os.makedirs(path)
        except OSError as err:
            raise ActionError("io", f"No se pudo crear: {err}") from err
        return path

    def create_area(self, name):
        return self._mkdir(os.path.join(self._root(), vault.CORTEX, self._name(name)))

    def create_dendrite(self, area, name):
        return self._mkdir(os.path.join(self._inside(area), self._name(name)))

    def _place(self, folder):
        """(área, dendrita) de una carpeta de dendrita."""
        rel = os.path.relpath(folder, os.path.join(self._root(), vault.CORTEX)).split(os.sep)
        if len(rel) != 2 or rel[0] == "..":
            raise ActionError("not_dendrite", "Las neuronas van dentro de una dendrita (Corteza › Área › Dendrita)")
        return rel

    def create_neuron(self, dendrite, title):
        folder = self._inside(dendrite)
        area, branch = self._place(folder)
        return self._new(folder, title, "neurona", area, branch)

    def create_note(self, title):
        return self._new(os.path.join(self._root(), vault.NOTES), title, "nota")

    def impulse(self, text):
        """Idea rápida: una nota en Notas/Impulsos con la fecha y sus primeras palabras como título."""
        text = (text or "").strip()
        if not text:
            raise ActionError("empty", "Escribe la idea")
        words = " ".join(re.findall(r"[\w'’-]+", text)[:IMPULSE_WORDS])
        title = self._name(f"{self._now().strftime('%Y-%m-%d %H%M')} {words}")
        base, n = title, 2
        while self.resolve(title):
            title, n = f"{base} ({n})", n + 1
        path = self._new(os.path.join(self._root(), vault.IMPULSES), title, "impulso")
        vault.write_atomic(path, vault.join_front(vault.read_note(path)["meta"], text + "\n"))
        return path

    def derive(self, path, title):
        """Axón: una nota derivada de una neurona, en su misma dendrita, con `origen: [[Neurona]]`."""
        source = self._inside(path)
        folder = os.path.dirname(source)
        area, branch = self._place(folder)
        return self._new(folder, title, "axón", area, branch, origin=vault.title_of(source))

    # ---------- renombrar y borrar ----------

    def _not_fixed(self, path):
        """Ni la raíz ni Notas, Impulsos o Corteza se renombran ni se borran."""
        fixed = {os.path.normcase(os.path.normpath(os.path.join(self.root, p))) for p in (".", *vault.LAYOUT)}
        if os.path.normcase(os.path.normpath(path)) in fixed:
            raise ActionError("fixed", "Esa carpeta es parte del esquema del cerebro")

    def rename(self, path, name):
        """Renombra una nota (y actualiza las sinapsis que apuntan a ella) o una carpeta de la Corteza."""
        old = self._inside(path)
        self._not_fixed(old)
        name = self._name(name)
        if os.path.isdir(old):
            new = os.path.join(os.path.dirname(old), name)
            if os.path.exists(new):
                raise ActionError("exists", f"Ya existe «{name}»")
            os.rename(old, new)
            self._retag_folder(new)
            return new
        old_title = vault.title_of(old)
        if links.normalize(old_title) != links.normalize(name) and self.resolve(name):
            raise ActionError("exists", f"Ya hay una nota «{name}»")
        new = os.path.join(os.path.dirname(old), name + ".md")
        os.rename(old, new)
        for note, (meta, body) in self._all().items():
            changed = links.rename_links(body, old_title, name)
            origin = str(meta.get("origen", ""))
            new_origin = links.rename_links(origin, old_title, name)
            if changed != body or new_origin != origin:
                if new_origin != origin:
                    meta = dict(meta, origen=new_origin)
                vault.save_note(note, meta, changed, self._now())
        return new

    def _retag_folder(self, folder):
        """Tras renombrar un área o una dendrita, sus neuronas apuntan a su nuevo nombre en los metadatos."""
        cortex = os.path.join(self.root, vault.CORTEX)
        for path, (meta, body) in self._all().items():
            if not os.path.normcase(path).startswith(os.path.normcase(folder) + os.sep):
                continue
            rel = os.path.relpath(path, cortex).split(os.sep)
            if len(rel) == 3 and meta:
                fixed = dict(meta, corteza=rel[0], dendrita=rel[1])
                if fixed != meta:
                    vault.write_atomic(path, vault.join_front(fixed, body))

    def delete(self, path):
        target = self._inside(path)
        self._not_fixed(target)
        try:
            self._recycle([target])
        except OSError as err:
            raise ActionError("io", str(err)) from err
        with self._lock:
            for cached in [p for p in self._cache if os.path.normcase(p).startswith(os.path.normcase(target))]:
                self._cache.pop(cached, None)

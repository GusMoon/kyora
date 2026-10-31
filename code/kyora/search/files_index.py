"""Índice de carpetas y archivos para el buscador ("/carpeta" y "@archivo").

Se recorre en un hilo la carpeta personal y las demás unidades (D:, E:…), saltando lo que nadie busca (AppData,
.git, node_modules, entornos de Python, la papelera…) y lo oculto. En C: solo se mira la carpeta personal: el resto
es Windows y programas. Se rehace cada cierto tiempo; mientras tanto se busca en lo que ya hay.
"""
import logging
import os
import threading
import time

from kyora.brain.links import normalize

log = logging.getLogger("kyora.search")

SKIP = {"appdata", ".git", "node_modules", ".venv", "venv", "__pycache__", "site-packages", "$recycle.bin",
        "system volume information", ".cache", ".npm", ".gradle", ".m2", ".nuget", ".vscode-server"}
MAX_ENTRIES = 400_000
RESULTS = 40
REFRESH_S = 15 * 60


def _hidden(entry):
    if entry.name.startswith("."):
        return True
    try:
        return bool(entry.stat(follow_symlinks=False).st_file_attributes & 0x6)  # oculto o de sistema
    except (OSError, AttributeError):
        return False


def walk(roots, limit=MAX_ENTRIES, found=None):
    """[(nombre normalizado, ruta, es_carpeta)] de todo lo que cuelga de `roots`, sin lo saltado ni lo oculto.
    Con `found`, se va añadiendo a esa lista (para buscar mientras se recorre)."""
    found = [] if found is None else found
    stack = list(reversed(roots))
    while stack and len(found) < limit:
        folder = stack.pop()
        try:
            with os.scandir(folder) as entries:
                children = []
                for entry in entries:
                    if entry.name.lower() in SKIP or _hidden(entry):
                        continue
                    try:
                        is_dir = entry.is_dir(follow_symlinks=False)
                    except OSError:
                        continue
                    found.append((normalize(entry.name), entry.path, is_dir))
                    if is_dir:
                        children.append(entry.path)
                stack.extend(reversed(children))
        except OSError:
            continue
    return found[:limit]


def default_roots(drive_list):
    """La carpeta personal y las unidades que no son C:."""
    home = os.path.expanduser("~")
    system = os.path.splitdrive(home)[0].upper()
    return [home] + [d for d in drive_list() if os.path.splitdrive(d)[0].upper() != system]


def rank(entries, query, only=None, limit=RESULTS):
    """Las entradas cuyo nombre contiene `query`: primero las que empiezan por él, después las de ruta más corta.
    `only`: "dir" o "file" para quedarse con unas."""
    key = normalize(query.strip())
    if not key:
        return []
    hits = []
    for name, path, is_dir in entries:
        if (only == "dir" and not is_dir) or (only == "file" and is_dir):
            continue
        at = name.find(key)
        if at >= 0:
            hits.append((0 if at == 0 else 1, path.count(os.sep), len(path), path, is_dir))
    hits.sort()
    return [{"path": path, "name": os.path.basename(path), "is_dir": is_dir} for *_, path, is_dir in hits[:limit]]


class FileIndex:
    def __init__(self, roots_fn):
        """`roots_fn()`: las carpetas que se recorren (se piden cada vez, por si se conecta una unidad)."""
        self._roots_fn = roots_fn
        self._entries = []
        self._lock = threading.Lock()
        self.ready = threading.Event()
        self._building = False

    def start(self, stop_event=None):
        def loop():
            while stop_event is None or not stop_event.is_set():
                self.rebuild()
                if stop_event is None:
                    return
                stop_event.wait(REFRESH_S)

        threading.Thread(target=loop, daemon=True, name="kyora-files").start()

    def rebuild(self):
        if self._building:
            return
        self._building = True
        started = time.perf_counter()
        try:
            if self.ready.is_set():  # ya hay índice: se rehace aparte y se cambia de golpe
                entries = walk(self._roots_fn())
                with self._lock:
                    self._entries = entries
            else:  # la primera vez se busca en lo que ya se ha recorrido
                entries = self._entries
                walk(self._roots_fn(), found=entries)
            self.ready.set()
            log.info("Índice de archivos: %d entradas en %.1f s", len(entries), time.perf_counter() - started)
        finally:
            self._building = False

    def __len__(self):
        return len(self._entries)

    def search(self, query, only=None, limit=RESULTS):
        with self._lock:
            entries = self._entries
        return rank(list(entries), query, only, limit)

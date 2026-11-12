"""El Segundo Cerebro en disco: carpetas, metadatos (front matter), plantillas y guardado seguro.

    Segundo Cerebro/
      Notas/                notas sueltas
        Impulsos/           ideas rápidas
      Corteza/
        <Área>/             Corteza: área de conocimiento
          <Dendrita>/       Dendrita: rama
            <Neurona>.md    Neurona: nota principal
            <Axón>.md       Axón: nota derivada (origen: [[Neurona]])

El título de una nota es el nombre de su archivo sin ".md". Los metadatos son un front matter mínimo (sin PyYAML):
líneas `clave: valor` y listas `[a, b]`.
"""
import os
import re

NOTES, IMPULSES, CORTEX = "Notas", os.path.join("Notas", "Impulsos"), "Corteza"
LAYOUT = (NOTES, IMPULSES, CORTEX)
META_ORDER = ("tipo", "corteza", "dendrita", "etiquetas", "origen", "creada", "actualizada")
STAMP = "%Y-%m-%d %H:%M"
_BAD = re.compile(r'[<>:"/\\|?*\x00-\x1f\[\]#^]')
MAX_NAME = 120


class Changed(Exception):
    """El archivo cambió en disco desde que se abrió (otro programa lo tocó)."""


def setup(root):
    """Crea el esquema de carpetas (si ya existe, no toca nada)."""
    for part in LAYOUT:
        os.makedirs(os.path.join(root, part), exist_ok=True)
    return root


def safe_name(title):
    """Un título válido como nombre de archivo o carpeta en Windows. Lanza ValueError si queda vacío."""
    name = _BAD.sub(" ", title or "")
    name = re.sub(r"\s+", " ", name).strip(" .")[:MAX_NAME].strip(" .")
    if not name:
        raise ValueError("Escribe un nombre")
    if name.upper().split(".")[0] in {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)),
                                      *(f"LPT{i}" for i in range(1, 10))}:
        name = f"{name} (nota)"
    return name


def title_of(path):
    return os.path.splitext(os.path.basename(path))[0]


# ---------- metadatos ----------

def _value(text):
    text = text.strip()
    if text.startswith("[") and text.endswith("]") and not text.startswith("[["):
        return [x.strip() for x in text[1:-1].split(",") if x.strip()]
    return text


def _render(value):
    if isinstance(value, (list, tuple)):
        return "[" + ", ".join(value) + "]"
    return "" if value is None else str(value)


def split_front(text):
    """(metadatos, cuerpo). Si no hay front matter, metadatos vacíos y el texto entero."""
    if not text.startswith("---"):
        return {}, text
    lines = text.splitlines(keepends=True)
    if lines[0].strip() != "---":
        return {}, text
    for end in range(1, len(lines)):
        if lines[end].strip() == "---":
            meta = {}
            for line in lines[1:end]:
                if ":" in line:
                    key, _, value = line.partition(":")
                    meta[key.strip()] = _value(value)
            return meta, "".join(lines[end + 1:]).lstrip("\n")
    return {}, text


def join_front(meta, body):
    """Texto del archivo: los metadatos (en el orden de la plantilla, y después los demás) y el cuerpo."""
    if not meta:
        return body
    keys = [k for k in META_ORDER if k in meta] + [k for k in meta if k not in META_ORDER]
    head = "".join(f"{k}: {_render(meta[k])}".rstrip() + "\n" for k in keys)
    return f"---\n{head}---\n{body.lstrip(chr(10))}"


def template(kind, title, now, area="", dendrite="", origin=""):
    """Metadatos y cuerpo de una nota nueva. `kind`: neurona, axón, nota o impulso."""
    stamp = now.strftime(STAMP)
    meta = {"tipo": kind}
    if kind in ("neurona", "axón"):
        meta.update(corteza=area, dendrita=dendrite)
    meta["etiquetas"] = []
    if kind in ("neurona", "axón"):
        meta["origen"] = f"[[{origin}]]" if origin else ""
    meta.update(creada=stamp, actualizada=stamp)
    return meta, f"# {title}\n"


# ---------- leer y guardar ----------

def read_note(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    meta, body = split_front(text)
    return {"meta": meta, "body": body, "mtime": os.path.getmtime(path)}


def write_atomic(path, text):
    """Guardado seguro: se escribe en un archivo aparte, se fuerza a disco y se cambia de golpe por el original.
    Si algo falla a mitad, el original queda intacto."""
    tmp = f"{path}.kyora-tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def save_note(path, meta, body, now, expected_mtime=None):
    """Guarda la nota y pone la fecha de actualización. Si `expected_mtime` no coincide con el del disco, lanza
    Changed (para no pisar lo que otro programa escribió). Devuelve el mtime nuevo."""
    if (expected_mtime is not None and os.path.exists(path)
            and abs(os.path.getmtime(path) - expected_mtime) > 1e-3):
        raise Changed(path)
    meta = dict(meta)
    if meta:
        meta["actualizada"] = now.strftime(STAMP)
    write_atomic(path, join_front(meta, body))
    return os.path.getmtime(path)


def create_note(path, meta, body):
    """Crea la nota; no sobrescribe nunca (FileExistsError si ya hay una con ese nombre)."""
    with open(path, "x", encoding="utf-8", newline="\n") as f:
        f.write(join_front(meta, body))
    return path


def kind_of(root, path, meta=None):
    """neurona / axón / nota / impulso, por dónde está (y por sus metadatos, para distinguir los axones)."""
    rel = os.path.relpath(path, root)
    parts = rel.split(os.sep)
    if parts[0] == CORTEX:
        return "axón" if (meta or {}).get("tipo") == "axón" else "neurona"
    if len(parts) > 2 and parts[1] == "Impulsos":
        return "impulso"
    return "nota"


def tree(root, read_meta):
    """Lo que hay en el cerebro, para el árbol de la interfaz. `read_meta(path)` da los metadatos de una nota."""

    def notes_in(folder):
        try:
            names = sorted(os.listdir(folder), key=str.lower)
        except OSError:
            return []
        found = []
        for name in names:
            path = os.path.join(folder, name)
            if name.lower().endswith(".md") and os.path.isfile(path):
                meta = read_meta(path)
                found.append({"title": title_of(path), "path": path, "kind": kind_of(root, path, meta),
                              "origin": origin_of(meta)})
        return found

    def dirs_in(folder):
        try:
            return sorted((d for d in os.listdir(folder) if os.path.isdir(os.path.join(folder, d))), key=str.lower)
        except OSError:
            return []

    cortex = []
    for area in dirs_in(os.path.join(root, CORTEX)):
        area_path = os.path.join(root, CORTEX, area)
        cortex.append({"name": area, "path": area_path, "dendrites": [
            {"name": d, "path": os.path.join(area_path, d), "notes": notes_in(os.path.join(area_path, d))}
            for d in dirs_in(area_path)]})
    return {"notes": notes_in(os.path.join(root, NOTES)), "impulses": notes_in(os.path.join(root, IMPULSES)),
            "cortex": cortex}


def origin_of(meta):
    """El título de `origen: [[Neurona]]` (o vacío)."""
    match = re.search(r"\[\[([^\]|]+)", str((meta or {}).get("origen", "")))
    return match.group(1).strip() if match else ""



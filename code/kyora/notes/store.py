"""Las notas en disco: un .md por nota, con unos metadatos mínimos (creada, actualizada, color) y el título en la
primera línea ("# Título"). Se guarda de forma segura (archivo aparte y cambio de golpe) y al borrar va a la Papelera.

El texto es Markdown (negrita, listas, citas, enlaces: lo escribe el editor de `>notes`). Las notas guardadas antes,
de texto plano, no llevan `formato: md`; `legacy_to_markdown` las pasa a Markdown sin perder sus saltos de línea.
"""
import os
import re
import secrets
from datetime import datetime

from kyora.brain import vault
from kyora.core.actions import ActionError

STAMP = "%Y-%m-%d %H:%M"
FORMAT = "md"  # las notas que ya se guardaron con texto Markdown
COLORS = 4  # tintes de las tarjetas, por turno


def _parse(path):
    note = vault.read_note(path)
    body = note["body"]
    first, _, rest = body.partition("\n")
    title = first[2:].strip() if first.startswith("# ") else ""
    text = rest.strip("\n") if title or first.startswith("# ") else body.strip("\n")
    meta = note["meta"]
    try:
        color = int(meta.get("color", 0)) % COLORS
    except ValueError:
        color = 0
    return {"id": os.path.basename(path), "title": title, "text": text, "created": meta.get("creada", ""),
            "updated": meta.get("actualizada", ""), "color": color, "mtime": note["mtime"],
            "markdown": meta.get("formato") == FORMAT}


def legacy_to_markdown(text):
    """Texto plano de antes -> Markdown que se ve igual: un salto de línea suelto pasa a salto duro (dos espacios al
    final), para que las líneas no se junten en un solo párrafo. Las líneas en blanco (párrafos) se quedan."""
    return re.sub(r"(?<!\n)\n(?!\n)", "  \n", text)


class NotesStore:
    def __init__(self, folder, recycle, now=datetime.now):
        """`folder`: la carpeta de las notas (se crea al guardar la primera). `recycle(paths)`: a la Papelera."""
        self.folder, self._recycle, self._now = folder, recycle, now

    def _path(self, note_id):
        name = os.path.basename(note_id or "")
        if not re.fullmatch(r"[\w\-]+\.md", name):
            raise ActionError("bad_note", "Esa nota no existe")
        return os.path.join(self.folder, name)

    def list(self):
        """Todas las notas, de la más nueva a la más antigua."""
        try:
            names = [n for n in os.listdir(self.folder) if n.lower().endswith(".md")]
        except OSError:
            return []
        notes = []
        for name in names:
            try:
                notes.append(_parse(os.path.join(self.folder, name)))
            except (OSError, UnicodeDecodeError):
                continue
        notes.sort(key=lambda n: (n["created"], n["id"]), reverse=True)
        return notes

    def create(self, title="", text=""):
        """Una nota nueva (en blanco si no se dice nada). Devuelve la nota."""
        os.makedirs(self.folder, exist_ok=True)
        now = self._now()
        count = len([n for n in os.listdir(self.folder) if n.lower().endswith(".md")])
        name = f"{now.strftime('%Y%m%d-%H%M%S')}-{secrets.token_hex(2)}.md"
        stamp = now.strftime(STAMP)
        meta = {"creada": stamp, "actualizada": stamp, "color": str(count % COLORS), "formato": FORMAT}
        vault.write_atomic(os.path.join(self.folder, name), vault.join_front(meta, f"# {title.strip()}\n\n{text}"))
        return _parse(os.path.join(self.folder, name))

    def save(self, id, title, text):
        """Guarda el título y el texto (y la fecha de actualización)."""
        path = self._path(id)
        if not os.path.exists(path):
            raise ActionError("missing", "Esa nota ya no existe")
        meta = vault.read_note(path)["meta"]
        meta["actualizada"] = self._now().strftime(STAMP)
        meta["formato"] = FORMAT
        vault.write_atomic(path, vault.join_front(meta, f"# {title.strip()}\n\n{text}"))
        return _parse(path)

    def delete(self, id):
        path = self._path(id)
        if not os.path.exists(path):
            raise ActionError("missing", "Esa nota ya no existe")
        self._recycle([path])

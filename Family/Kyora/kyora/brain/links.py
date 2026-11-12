"""Sinapsis, Soma y búsqueda: lo que se calcula sobre el texto de las notas (sin Qt ni disco: se puede probar).

- Sinapsis: `[[Título]]` o `[[Título|texto]]` en el cuerpo (como Obsidian).
- Soma: índice de una neurona: sus títulos y subtítulos y qué componentes tiene (listas, tablas, código…).
- El editor visual no entiende `[[…]]`: al cargar se convierten en enlaces `[texto](sinapsis:Título)` y al
  guardar se devuelven a su forma.
"""
import re
import unicodedata
from urllib.parse import quote, unquote

LINK = re.compile(r"\[\[([^\[\]|]+?)(?:\|([^\[\]]*))?\]\]")
ANCHOR = re.compile(r"\[([^\[\]]*)\]\(<?sinapsis:([^)>\s]*)>?\)")
HEADING = re.compile(r"^(#{1,6})\s+(.+?)\s*#*\s*$")
SCHEME = "sinapsis:"


def normalize(text):
    """Sin tildes ni mayúsculas, para buscar y comparar títulos."""
    text = unicodedata.normalize("NFKD", text or "")
    return "".join(c for c in text if not unicodedata.combining(c)).casefold()


def extract_links(body):
    """Títulos enlazados en el cuerpo, sin repetir, en el orden en que aparecen."""
    seen, found = set(), []
    for match in LINK.finditer(body or ""):
        title = match.group(1).strip()
        key = normalize(title)
        if title and key not in seen:
            seen.add(key)
            found.append(title)
    return found


def wiki_to_anchor(body):
    def repl(match):
        title = match.group(1).strip()
        text = (match.group(2) or "").strip() or title
        return f"[{text}]({SCHEME}{quote(title)})"

    return LINK.sub(repl, body or "")


def anchor_to_wiki(body):
    def repl(match):
        text, title = match.group(1).strip(), unquote(match.group(2)).strip()
        return f"[[{title}]]" if text == title or not text else f"[[{title}|{text}]]"

    return ANCHOR.sub(repl, body or "")


def rename_links(body, old, new):
    """Cambia los enlaces a `old` por enlaces a `new` (sin distinguir mayúsculas ni tildes)."""
    key = normalize(old)

    def repl(match):
        if normalize(match.group(1).strip()) != key:
            return match.group(0)
        return f"[[{new}|{match.group(2)}]]" if match.group(2) is not None else f"[[{new}]]"

    return LINK.sub(repl, body or "")


def soma(body):
    """{"headings": [{level, text, line}], "parts": {nombre: cuántos}} de una nota. No mira dentro del código."""
    headings, parts = [], {"Listas": 0, "Tablas": 0, "Bloques de código": 0, "Citas": 0, "Imágenes": 0,
                           "Sinapsis": len(extract_links(body))}
    in_code = in_list = in_table = in_quote = False
    for number, line in enumerate((body or "").splitlines()):
        stripped = line.strip()
        if stripped.startswith(("```", "~~~")):
            if not in_code:
                parts["Bloques de código"] += 1
            in_code = not in_code
            continue
        if in_code:
            continue
        match = HEADING.match(stripped)
        if match:
            headings.append({"level": len(match.group(1)), "text": match.group(2), "line": number})
        is_list = bool(re.match(r"^([-*+]|\d+[.)])\s+", stripped))
        is_table = stripped.startswith("|") and stripped.count("|") >= 2
        is_quote = stripped.startswith(">")
        parts["Listas"] += is_list and not in_list
        parts["Tablas"] += is_table and not in_table
        parts["Citas"] += is_quote and not in_quote
        parts["Imágenes"] += len(re.findall(r"!\[[^\]]*\]\([^)]+\)", stripped))
        in_list, in_table, in_quote = (is_list or (in_list and stripped != "")), is_table, is_quote
    return {"headings": headings, "parts": {k: v for k, v in parts.items() if v}}


def snippet(text, query, width=80):
    """Un trozo del texto alrededor de la primera aparición de `query` (sin tildes ni mayúsculas)."""
    flat = " ".join((text or "").split())
    at = normalize(flat).find(normalize(query))
    if at < 0:
        return flat[:width]
    start = max(at - width // 3, 0)
    return ("…" if start else "") + flat[start:start + width] + ("…" if start + width < len(flat) else "")


_BLOCK = re.compile(r"^\s*([-*+]\s|\d+[.)]\s|#|\||```|~~~)")


def unwrap(markdown):
    """Une las líneas que el editor corta a 80 caracteres al guardar (dentro de un párrafo, una lista o una cita),
    para que el archivo quede como se escribió. No toca el código, las tablas ni los saltos de línea forzados."""
    out, in_code = [], False
    for line in (markdown or "").split("\n"):
        stripped = line.strip()
        if stripped.startswith(("```", "~~~")):
            in_code = not in_code
            out.append(line)
            continue
        prev = out[-1] if out else ""
        joinable = (not in_code and stripped and prev.strip() and not prev.endswith(("  ", "\\"))
                    and not prev.lstrip().startswith(("#", "|", "```", "~~~")))
        if joinable and stripped.startswith(">") and prev.lstrip().startswith(">"):
            out[-1] = prev.rstrip() + " " + stripped.lstrip(">").strip()
        elif joinable and not stripped.startswith(">") and not _BLOCK.match(line):
            out[-1] = prev.rstrip() + " " + stripped
        else:
            out.append(line)
    return "\n".join(out)

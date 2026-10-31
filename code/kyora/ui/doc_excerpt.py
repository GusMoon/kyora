"""El extracto que enseña la tarjeta de un documento en el chat: las primeras líneas de un PDF, un Word, un TXT o un MD.

`excerpt(ruta)` devuelve el principio del texto (ya limpio y corto) o None si el tipo no tiene extracto o no se pudo leer.
Todo es lectura local y sin red; el chat lo pide en un hilo (ver `DocLoader` en `kyora/ui/chat.py`).
"""
import html
import os
import re
import zipfile

from kyora.ui.explorer.preview import kind_of, read_text

LIMIT = 600  # caracteres que se guardan: la tarjeta enseña unas cinco líneas
MAX_AUTO_BYTES = 10_000_000  # un documento recibido más grande que esto no se baja solo para sacar su extracto
WORD_EXT = {".docx"}


def supported(name):
    """¿Este nombre de archivo es de un tipo del que se saca extracto? (PDF, Word, TXT, MD y demás texto)."""
    ext = os.path.splitext(str(name).lower())[1]
    return ext in WORD_EXT or kind_of(str(name)) in ("pdf", "text", "markdown")


def _front_matter(text):
    """Un Markdown puede abrir con un bloque de metadatos (--- … ---): no es el contenido, se salta."""
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            return text[end + 4:]
    return text


def _clean(text):
    lines = []
    for raw in text.replace("\r", "").split("\n"):
        line = re.sub(r"^[\s#>*\-]+(?=\S)", "", raw).strip()  # marcas de títulos, citas y viñetas de Markdown
        line = re.sub(r"[*_`]{1,3}", "", line)
        if line:
            lines.append(line)
    return "\n".join(lines)[:LIMIT].strip()


def _pdf(path):
    import pypdfium2 as pdfium  # se carga solo al leer un PDF

    doc = pdfium.PdfDocument(path)
    try:
        for index in range(min(len(doc), 3)):  # la primera página con texto
            text = doc[index].get_textpage().get_text_range()
            if text.strip():
                return text
        return ""
    finally:
        doc.close()


def _docx(path):
    with zipfile.ZipFile(path) as z:
        xml = z.read("word/document.xml").decode("utf-8", errors="replace")
    xml = re.sub(r"</w:p>|<w:br\s*/>|<w:tab\s*/>", "\n", xml)
    return html.unescape(re.sub(r"<[^>]+>", "", xml))


def excerpt(path):
    """El principio del texto del documento, o None."""
    ext = os.path.splitext(str(path).lower())[1]
    try:
        if ext in WORD_EXT:
            text = _docx(path)
        elif kind_of(path) == "pdf":
            text = _pdf(path)
        elif kind_of(path) in ("text", "markdown"):
            text = read_text(path)
        else:
            return None
    except Exception:  # noqa: BLE001 - un documento dañado o protegido no debe romper el chat: sin extracto
        return None
    cleaned = _clean(_front_matter((text or "").lstrip("\ufeff")))
    return cleaned or None

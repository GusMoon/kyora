"""Páginas web del buscador: cada una tiene un nombre (lo que se escribe) y una dirección."""
import re

from kyora.search.apps import score

SCHEME = re.compile(r"^[a-z][a-z0-9+.-]*://", re.IGNORECASE)


def normalize_url(url):
    """La dirección con su esquema (https:// si falta); None si está vacía o no parece una dirección."""
    url = (url or "").strip()
    if not url or " " in url:
        return None
    if not SCHEME.match(url):
        url = "https://" + url
    host = url.split("://", 1)[1]
    return url if host and not host.startswith("/") else None


def clean(items):
    """Valida la lista [{"name", "url"}]: nombres no vacíos y sin repetir (sin mayúsculas), direcciones con esquema.
    Lanza ValueError con el motivo, en español."""
    result, seen = [], set()
    for item in items or []:
        name = str(item.get("name", "")).strip()
        url = normalize_url(item.get("url", ""))
        if not name:
            raise ValueError("Falta el nombre de la página.")
        if name.lower() in seen:
            raise ValueError(f"«{name}» está repetido.")
        if url is None:
            raise ValueError(f"La dirección de «{name}» no es válida.")
        seen.add(name.lower())
        result.append({"name": name, "url": url})
    return result


def search(items, text, limit=3):
    """Las páginas cuyo nombre coincide con `text`, las mejores primero."""
    scored = []
    for item in items or []:
        s = score(text, item["name"])
        if s is not None:
            scored.append((s, len(item["name"]), item))
    scored.sort(key=lambda t: (t[0], t[1], t[2]["name"].lower()))
    return [item for _, _, item in scored[:limit]]

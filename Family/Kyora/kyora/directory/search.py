"""Búsqueda por nombre dentro de una carpeta y todas sus subcarpetas (sin Qt).

Recorre con os.scandir, sin seguir accesos directos de carpetas (junctions) para no entrar en bucles. Se para en
cuanto se cancela o llega al límite.
"""
import os
import stat

LIMIT = 2000
BATCH = 50  # resultados que se entregan de una vez


def _hidden(entry):
    try:
        return bool(entry.stat(follow_symlinks=False).st_file_attributes & stat.FILE_ATTRIBUTE_HIDDEN)
    except (OSError, AttributeError):
        return False


def search(root, query, show_hidden=False, cancel=None, limit=LIMIT):
    """Genera lotes de rutas cuyo nombre contiene `query` (sin distinguir mayúsculas)."""
    needle = query.casefold().strip()
    if not needle:
        return
    pending, batch, found = [root], [], 0
    while pending:
        if cancel is not None and cancel.is_set():
            return
        folder = pending.pop()
        try:
            entries = list(os.scandir(folder))
        except OSError:
            continue  # sin permiso o desaparecida
        for entry in entries:
            if not show_hidden and _hidden(entry):
                continue
            if needle in entry.name.casefold():
                batch.append(entry.path)
                found += 1
                if found >= limit:
                    yield batch
                    return
                if len(batch) >= BATCH:
                    yield batch
                    batch = []
            try:
                if entry.is_dir(follow_symlinks=False) and not entry.is_junction():
                    pending.append(entry.path)
            except OSError:
                pass
    if batch:
        yield batch

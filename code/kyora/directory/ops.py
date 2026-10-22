"""Operaciones con archivos del explorador (sin Qt): nombres, crear, renombrar, copiar y mover con progreso.

Copiar y mover se hacen por bloques para poder informar del progreso y cancelar. Ante un nombre que ya existe se
pregunta con `resolve(origen, destino)`, que devuelve "replace" (lo que había va a la Papelera), "both" (se guarda
con otro nombre) o "skip".
"""
import os
import re
import shutil

CHUNK = 1024 * 1024
INVALID = set('<>:"/\\|?*') | {chr(c) for c in range(32)}
RESERVED = {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}


class Cancelled(Exception):
    """El usuario canceló la operación."""


def valid_name(name):
    """None si `name` sirve como nombre en Windows; si no, el motivo."""
    if not name or not name.strip():
        return "El nombre no puede estar vacío"
    bad = sorted(set(name) & INVALID)
    if bad:
        return "Un nombre no puede llevar " + " ".join(c if c.isprintable() else "control" for c in bad)
    if name.endswith((" ", ".")):
        return "Un nombre no puede terminar en espacio ni en punto"
    if name.split(".")[0].upper() in RESERVED:
        return f"«{name}» es un nombre reservado de Windows"
    if len(name) > 255:
        return "El nombre es demasiado largo"
    return None


def unique_name(folder, name):
    """`name` si no existe en `folder`; si no, "nombre (2).ext", "nombre (3).ext"…"""
    if not os.path.lexists(os.path.join(folder, name)):
        return name
    is_dir = os.path.isdir(os.path.join(folder, name))
    stem, ext = (name, "") if is_dir else os.path.splitext(name)
    stem = re.sub(r" \(\d+\)$", "", stem)
    n = 2
    while os.path.lexists(os.path.join(folder, f"{stem} ({n}){ext}")):
        n += 1
    return f"{stem} ({n}){ext}"


def create_folder(parent, name="Carpeta nueva"):
    path = os.path.join(parent, unique_name(parent, name))
    os.mkdir(path)
    return path


def create_file(parent, name="Archivo nuevo.txt"):
    path = os.path.join(parent, unique_name(parent, name))
    with open(path, "x", encoding="utf-8"):
        pass
    return path


def rename(path, new_name):
    """Renombra y devuelve la ruta nueva. ValueError si el nombre no vale; FileExistsError si ya hay otro igual."""
    problem = valid_name(new_name)
    if problem:
        raise ValueError(problem)
    target = os.path.join(os.path.dirname(path), new_name)
    same_file = os.path.normcase(target) == os.path.normcase(path)  # solo cambian mayúsculas
    if os.path.lexists(target) and not same_file:
        raise FileExistsError(f"Ya existe «{new_name}» en esta carpeta")
    os.rename(path, target)
    return target


def size_of(paths):
    """Bytes de todos los archivos (las carpetas, con todo lo que tienen dentro)."""
    total = 0
    for path in paths:
        if os.path.isdir(path) and not os.path.islink(path):
            for root, _, files in os.walk(path):
                for f in files:
                    try:
                        total += os.path.getsize(os.path.join(root, f))
                    except OSError:
                        pass
        else:
            try:
                total += os.path.getsize(path)
            except OSError:
                pass
    return total


def _inside(child, parent):
    child, parent = os.path.normcase(os.path.abspath(child)), os.path.normcase(os.path.abspath(parent))
    return child == parent or child.startswith(parent.rstrip("\\/") + os.sep)


def _same_drive(a, b):
    return os.path.splitdrive(os.path.abspath(a))[0].lower() == os.path.splitdrive(os.path.abspath(b))[0].lower()


class _Progress:
    def __init__(self, total, report, cancel):
        self.done, self.total, self.report, self.cancel = 0, total, report, cancel

    def add(self, n, current):
        self.done += n
        if self.report:
            self.report(self.done, self.total, current)
        if self.cancel is not None and self.cancel.is_set():
            raise Cancelled()


def _copy_file(src, dst, progress):
    try:
        with open(src, "rb") as fin, open(dst, "wb") as fout:
            while True:
                block = fin.read(CHUNK)
                if not block:
                    break
                fout.write(block)
                progress.add(len(block), src)
        shutil.copystat(src, dst)
    except BaseException:
        try:
            os.remove(dst)  # no dejar un archivo a medias
        except OSError:
            pass
        raise


def _copy_tree(src, dst, progress):
    os.mkdir(dst)
    for entry in os.scandir(src):
        target = os.path.join(dst, entry.name)
        if entry.is_dir(follow_symlinks=False):
            _copy_tree(entry.path, target, progress)
        else:
            _copy_file(entry.path, target, progress)
    shutil.copystat(src, dst)


def transfer(sources, dest_dir, move, resolve, recycle, report=None, cancel=None):
    """Copia (o mueve) `sources` a `dest_dir`. Devuelve [(origen, destino)] de lo que se hizo, para deshacer.

    Copiar a la misma carpeta duplica con otro nombre. Lanza Cancelled si se cancela (lo ya hecho se queda) y
    ValueError si se intenta meter una carpeta dentro de sí misma.
    """
    progress = _Progress(size_of(sources), report, cancel)
    done = []
    apply_all = None
    for src in sources:
        name = os.path.basename(os.path.normpath(src))
        same_folder = os.path.normcase(os.path.dirname(os.path.abspath(src))) == os.path.normcase(os.path.abspath(dest_dir))
        if move and same_folder:
            continue  # moverlo a donde ya está: nada que hacer
        if os.path.isdir(src) and _inside(dest_dir, src):
            raise ValueError(f"No se puede meter «{name}» dentro de sí misma")
        if same_folder:
            name = unique_name(dest_dir, name)  # duplicar
        dst = os.path.join(dest_dir, name)
        if os.path.lexists(dst):
            choice = apply_all or resolve(src, dst)
            if isinstance(choice, tuple):  # (elección, aplicar a todos)
                choice, every = choice
                apply_all = choice if every else None
            if choice == "skip":
                continue
            if choice == "both":
                dst = os.path.join(dest_dir, unique_name(dest_dir, name))
            else:
                recycle([dst])  # reemplazar: lo que había se puede recuperar de la Papelera
        if move and _same_drive(src, dest_dir):
            os.replace(src, dst)
            progress.add(size_of([dst]), src)
        else:
            if os.path.isdir(src) and not os.path.islink(src):
                try:
                    _copy_tree(src, dst, progress)
                except BaseException:
                    shutil.rmtree(dst, ignore_errors=True)  # no dejar una carpeta a medias
                    raise
            else:
                _copy_file(src, dst, progress)
            if move:
                shutil.rmtree(src) if os.path.isdir(src) and not os.path.islink(src) else os.remove(src)
        done.append((src, dst))
    return done

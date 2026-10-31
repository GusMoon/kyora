import os
import threading
import types
from datetime import datetime

import pytest

from kyora import app as kyora_app
from kyora.config import DEFAULTS
from kyora.search import files_index, folders
from kyora.tasks.service import TaskService


@pytest.fixture
def home(tmp_path):
    docs = tmp_path / "Documents"
    (docs / "Proyecto" / "Informe").mkdir(parents=True)
    (docs / "Proyecto" / "informe final.txt").write_text("x", encoding="utf-8")
    (docs / "notas.md").write_text("hola", encoding="utf-8")
    (docs / ".oculto").write_text("", encoding="utf-8")
    (docs / "node_modules" / "informe").mkdir(parents=True)  # se salta
    walls = tmp_path / "Pictures" / "wallpapers"
    walls.mkdir(parents=True)
    for name in ("b.jpg", "a.PNG", "leeme.txt"):
        (walls / name).write_bytes(b"x")
    known = {"documents": str(docs), "pictures": str(tmp_path / "Pictures")}
    return tmp_path, known.get


def test_listing_and_tree_roots(home):
    _, known = home
    entries = folders.listing(known("documents"))
    assert [e["name"] for e in entries] == ["node_modules", "Proyecto", "notas.md"]  # sin ocultos, carpetas primero
    roots = folders.tree_roots(known, drive_list=lambda: ["C:\\", "D:\\"])
    names = [r["name"] for r in roots]
    assert names[:2] == ["Carpeta personal", "Documentos"] and names[-2:] == ["C:", "D:"]
    assert roots[-1]["drive"] and roots[0]["path"] == os.path.expanduser("~")


def test_wallpapers_folder(home):
    tmp, known = home
    folder, images = folders.wallpapers(known)
    assert folder == str(tmp / "Pictures" / "wallpapers")
    assert [p.rsplit("\\", 1)[-1] for p in images] == ["a.PNG", "b.jpg"]


def test_human_size_and_short_path():
    assert folders.human_size(512) == "512 B"
    assert folders.human_size(1536) == "1,5 KB"
    assert folders.human_size(3 * 1024 ** 3) == "3,0 GB"
    assert folders.short_path(r"D:\a\b\c\d\e") == r"D:\…\c\d\e"
    assert folders.short_path(r"D:\a\b") == r"D:\a\b"


def test_file_index_skips_ranks_and_filters(home):
    tmp, _ = home
    entries = files_index.walk([str(tmp)])
    paths = {os.path.relpath(p, tmp) for _, p, _ in entries}
    assert os.path.join("Documents", "Proyecto", "informe final.txt") in paths
    assert not any("node_modules" in p or ".oculto" in p for p in paths)
    hits = files_index.rank(entries, "INFORME")
    assert [h["name"] for h in hits] == ["Informe", "informe final.txt"]  # empiezan igual: la ruta corta primero
    assert [h["name"] for h in files_index.rank(entries, "inform", only="file")] == ["informe final.txt"]
    assert [h["name"] for h in files_index.rank(entries, "yecto", only="dir")] == ["Proyecto"]  # contiene
    assert files_index.rank(entries, "  ") == []
    assert len(files_index.rank(entries, "", limit=1)) == 0
    index = files_index.FileIndex(lambda: [str(tmp)])
    index.rebuild()
    assert index.ready.is_set() and len(index) == len(entries)
    assert index.search("notas")[0]["name"] == "notas.md"


def _kyora(tmp_path):
    k = kyora_app.Kyora.__new__(kyora_app.Kyora)
    k.cfg = {"hotkeys": DEFAULTS["hotkeys"]}
    k.manager = types.SimpleNamespace(window_list=lambda blocking=True: [])
    ready = threading.Event()
    ready.set()
    k.index = types.SimpleNamespace(search=lambda text, limit: [], ready=ready)
    k.files = files_index.FileIndex(lambda: [str(tmp_path)])
    k.files.rebuild()
    k.tasks = TaskService(":memory:", now=lambda: datetime(2026, 10, 22, 12, 0))
    return k


def test_search_query_no_longer_has_greater_than_commands(home, monkeypatch):
    tmp, known = home
    monkeypatch.setattr(kyora_app.shell, "known_folder", known)
    k = _kyora(tmp)
    plain = k.search_query(">task")  # el ">" ya no es especial: es texto normal
    assert "mode" not in plain
    assert k.search_query("Documentos")["results"] == []
    executables = [row["keys"] for card in k.config_data()["executables"] for row in card["rows"]]
    assert "Reiniciar Kyora" in executables and "Desconectar Kyora" in executables
    assert k.config_data()["executables"][-1]["rows"][-1]["keys"] != "Desconectar Kyora"  # no queda al final: un Enter despistado


def test_search_query_folders_files_and_tasks(home, monkeypatch):
    tmp, known = home
    monkeypatch.setattr(kyora_app.shell, "known_folder", known)
    k = _kyora(tmp)
    folders_found = k.search_query("/proy")["results"]
    assert [(r["name"], r["is_dir"]) for r in folders_found] == [("Proyecto", True)]
    assert folders_found[0]["detail"].endswith("Documents")
    files_found = k.search_query("@inform")["results"]
    assert [r["name"] for r in files_found] == ["informe final.txt"] and files_found[0]["detail"].startswith("1 B")
    assert k.search_query("", "task")["mode"] == "tasks"                 # las tareas abren directo el Kanban
    assert k.search_query("", "notes")["mode"] == "notes"
    new_id = k.search_launch("task_new", "Comprar pan")  # sin cerrar el buscador: devuelve el id
    assert k.tasks.store.get(new_id)["name"] == "Comprar pan"
    assert k.tasks.store.get(new_id)["status"] == "pending"
    children = k.files_children(known("documents"))
    assert [c["name"] for c in children][:2] == ["node_modules", "Proyecto"]


def test_desktop_step_sends_the_numbers(monkeypatch):
    k = kyora_app.Kyora.__new__(kyora_app.Kyora)
    sent = []
    steps = []
    k._emit = lambda name, *args: sent.append((name, args))
    k.manager = types.SimpleNamespace(
        desktop_step=steps.append, active=1, desktops=[0, 1, 2],
        window_list=lambda: [{"app": "Chrome", "exe": "c.exe", "hwnd": 1, "index": 0},
                             {"app": "Code", "exe": "v.exe", "hwnd": 2, "index": 1}],
        snapshot=lambda: {"desktops": [{"index": 0, "active": False}, {"index": 1, "active": True},
                                       {"index": 2, "active": False}]})
    k.desktop_step(1)
    assert steps == [1]
    name, (columns,) = sent[0]
    assert name == "desktops_overview"
    # los números salen antes del cambio, con el escritorio al que se va ya iluminado
    assert [(c["index"], c["active"]) for c in columns] == [(0, False), (1, False), (2, True)]

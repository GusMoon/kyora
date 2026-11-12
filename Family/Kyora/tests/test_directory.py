import os
import threading
import time

import pytest

from kyora.core.actions import ActionRegistry
from kyora.directory import ops
from kyora.directory.places import DirectoryState
from kyora.directory.search import search
from kyora.directory.selection import MultiSelection
from kyora.directory.service import DirectoryService
from kyora.directory.undo import UndoStack


def fake_recycle(bin_):
    def recycle(paths):
        for p in paths:
            target = bin_ / f"{len(list(bin_.iterdir()))}-{os.path.basename(p)}"
            os.replace(p, target)
    return recycle


@pytest.fixture
def tree(tmp_path):
    (tmp_path / "a").mkdir()
    (tmp_path / "a" / "uno.txt").write_text("1" * 3000, encoding="utf-8")
    (tmp_path / "a" / "sub").mkdir()
    (tmp_path / "a" / "sub" / "dos.md").write_text("# dos", encoding="utf-8")
    (tmp_path / "b").mkdir()
    (tmp_path / "bin").mkdir()
    return tmp_path


def test_valid_names():
    assert ops.valid_name("informe.txt") is None
    assert "no puede llevar" in ops.valid_name("a/b")
    assert "reservado" in ops.valid_name("CON.txt")
    assert ops.valid_name("fin.") and ops.valid_name("  ")


def test_unique_name_numbers_files_and_folders(tree):
    a = tree / "a"
    assert ops.unique_name(a, "nuevo.txt") == "nuevo.txt"
    assert ops.unique_name(a, "uno.txt") == "uno (2).txt"
    (a / "uno (2).txt").write_text("", encoding="utf-8")
    assert ops.unique_name(a, "uno.txt") == "uno (3).txt"
    assert ops.unique_name(a, "uno (2).txt") == "uno (3).txt"
    assert ops.unique_name(a, "sub") == "sub (2)"


def test_create_and_rename(tree):
    folder = ops.create_folder(tree / "b")
    assert os.path.basename(folder) == "Carpeta nueva"
    assert os.path.basename(ops.create_folder(tree / "b")) == "Carpeta nueva (2)"
    renamed = ops.rename(folder, "Fotos")
    assert os.path.isdir(renamed) and not os.path.exists(folder)
    with pytest.raises(FileExistsError):
        ops.rename(renamed, "Carpeta nueva (2)")
    with pytest.raises(ValueError):
        ops.rename(renamed, "a:b")
    assert ops.rename(renamed, "FOTOS").endswith("FOTOS")  # solo mayúsculas: se permite


def test_copy_with_progress_and_duplicate(tree):
    seen = []
    done = ops.transfer([str(tree / "a")], str(tree / "b"), False, None, None, lambda d, t, c: seen.append((d, t)))
    assert (tree / "b" / "a" / "sub" / "dos.md").read_text(encoding="utf-8") == "# dos"
    assert done == [(str(tree / "a"), str(tree / "b" / "a"))]
    assert seen[-1][0] == seen[-1][1] == 3005
    again = ops.transfer([str(tree / "a" / "uno.txt")], str(tree / "a"), False, None, None)
    assert os.path.basename(again[0][1]) == "uno (2).txt"  # copiar en la misma carpeta = duplicar


def test_conflicts_replace_both_skip(tree):
    (tree / "b" / "uno.txt").write_text("viejo", encoding="utf-8")
    src = [str(tree / "a" / "uno.txt")]
    assert ops.transfer(src, str(tree / "b"), False, lambda s, d: "skip", None) == []
    done = ops.transfer(src, str(tree / "b"), False, lambda s, d: "both", None)
    assert os.path.basename(done[0][1]) == "uno (2).txt"
    ops.transfer(src, str(tree / "b"), False, lambda s, d: ("replace", True), fake_recycle(tree / "bin"))
    assert (tree / "b" / "uno.txt").read_text(encoding="utf-8") == "1" * 3000
    assert len(list((tree / "bin").iterdir())) == 1  # lo reemplazado fue a la papelera


def test_move_and_folder_into_itself(tree):
    done = ops.transfer([str(tree / "a" / "sub")], str(tree / "b"), True, None, None)
    assert not (tree / "a" / "sub").exists() and (tree / "b" / "sub" / "dos.md").exists()
    assert done == [(str(tree / "a" / "sub"), str(tree / "b" / "sub"))]
    with pytest.raises(ValueError):
        ops.transfer([str(tree / "b")], str(tree / "b" / "sub"), True, None, None)


def test_cancel_leaves_nothing_half_copied(tree, monkeypatch):
    monkeypatch.setattr(ops, "CHUNK", 1000)
    cancel = threading.Event()

    def report(done, total, current):
        if done >= 1000:
            cancel.set()

    with pytest.raises(ops.Cancelled):
        ops.transfer([str(tree / "a")], str(tree / "b"), False, None, None, report, cancel)
    assert not (tree / "b" / "a").exists()


def test_undo_rename_move_and_create(tree):
    stack = UndoStack(fake_recycle(tree / "bin"))
    new = ops.rename(str(tree / "a" / "uno.txt"), "otro.txt")
    stack.push("rename", (str(tree / "a" / "uno.txt"), new), "Renombrar")
    moved = ops.transfer([str(tree / "a" / "sub")], str(tree / "b"), True, None, None)
    stack.push("move", moved, "Mover")
    made = ops.create_folder(tree / "b")
    stack.push("create", [made], "Crear")
    assert stack.undo() == "Crear" and not os.path.exists(made)
    assert stack.undo() == "Mover" and (tree / "a" / "sub" / "dos.md").exists()
    assert stack.undo() == "Renombrar" and (tree / "a" / "uno.txt").exists()
    assert stack.undo() is None


def test_multi_selection_across_folders():
    s = MultiSelection()
    s.replace([r"C:\x\1.txt", r"C:\x\2.txt"])
    s.set_folder(r"C:\y", [r"C:\y\3.txt"])
    assert len(s) == 3 and s.summary() == "3 seleccionados en 2 carpetas"
    s.set_folder(r"C:\x", [r"C:\x\2.txt"])  # en x ahora solo queda la 2
    assert sorted(s.paths()) == [r"C:\x\2.txt", r"C:\y\3.txt"]
    s.replace([r"C:\y\3.txt"])
    assert s.summary() == "" and len(s) == 1


def test_search_finds_by_name_in_subfolders(tree):
    found = [p for batch in search(str(tree), "DOS") for p in batch]
    assert found == [str(tree / "a" / "sub" / "dos.md")]
    assert list(search(str(tree), "  ")) == []


def test_state_pins_and_prefs_persist(tree):
    state = DirectoryState(tree / "directory.json")
    state.pin(str(tree / "a"))
    state.pin(str(tree / "a"))
    state.view = "list"
    state.save()
    again = DirectoryState(tree / "directory.json")
    assert again.pinned == [str(tree / "a")] and again.view == "list"
    with pytest.raises(ValueError):
        state.pin(str(tree / "a" / "uno.txt"))


def test_service_transfer_asks_on_conflict_and_can_undo(tree):
    events = []
    service = DirectoryService(tree, events.append, lambda key: None, fake_recycle(tree / "bin"), lambda p: None)
    registry = ActionRegistry()
    service.register(registry)
    (tree / "b" / "uno.txt").write_text("viejo", encoding="utf-8")
    assert registry.invoke("directory.transfer", {"sources": [str(tree / "a" / "uno.txt")], "dest": str(tree / "b")})["ok"]
    deadline = time.monotonic() + 5
    while not any(e["kind"] == "conflict" for e in events) and time.monotonic() < deadline:
        time.sleep(0.01)
    registry.invoke("directory.resolve", {"choice": "both"})
    while not any(e["kind"] == "done" for e in events) and time.monotonic() < deadline:
        time.sleep(0.01)
    done = next(e for e in events if e["kind"] == "done")
    assert done["paths"] == [str(tree / "b" / "uno (2).txt")]
    assert registry.invoke("directory.undo")["data"].startswith("Deshecho")
    assert not (tree / "b" / "uno (2).txt").exists()
    assert registry.invoke("directory.undo")["error"]["code"] == "nothing"

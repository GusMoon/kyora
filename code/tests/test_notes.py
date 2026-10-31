from datetime import datetime, timedelta

import pytest

from kyora.core.actions import ActionError, ActionRegistry
from kyora.notes.service import NotesService
from kyora.notes.store import NotesStore, legacy_to_markdown


class Clock:
    def __init__(self):
        self.t = datetime(2026, 10, 23, 9, 0)

    def __call__(self):
        self.t += timedelta(minutes=1)
        return self.t


def test_create_save_list_and_delete(tmp_path):
    recycled = []
    store = NotesStore(str(tmp_path / "Notas Kyora"), recycled.extend, now=Clock())
    assert store.list() == []
    first = store.create("Ideas", "una\ndos")
    second = store.create()
    assert second["title"] == "" and second["text"] == ""
    assert [n["id"] for n in store.list()] == [second["id"], first["id"]]  # la más nueva primero
    assert first["title"] == "Ideas" and first["text"] == "una\ndos" and first["created"] == "2026-10-23 09:01"
    assert first["color"] != second["color"]
    saved = store.save(second["id"], "Compra", "pan\nleche")
    assert saved["title"] == "Compra" and saved["text"] == "pan\nleche" and saved["updated"] == "2026-10-23 09:03"
    text = (tmp_path / "Notas Kyora" / second["id"]).read_text(encoding="utf-8")
    assert text.startswith("---\n") and "# Compra\n\npan\nleche" in text and "formato: md" in text
    assert saved["markdown"]
    store.delete(first["id"])
    assert recycled == [str(tmp_path / "Notas Kyora" / first["id"])]
    with pytest.raises(ActionError):
        store.save("../fuera.md", "x", "y")


def test_service_registers_actions(tmp_path):
    registry = ActionRegistry()
    NotesService(str(tmp_path), lambda paths: None).register(registry)
    made = registry.invoke("notes.create", {"title": "Hola"})
    assert made["ok"] and registry.invoke("notes.list")["data"][0]["title"] == "Hola"
    assert registry.is_destructive("notes.delete")


def test_old_plain_notes_keep_their_lines_as_markdown(tmp_path):
    folder = tmp_path / "Notas Kyora"
    folder.mkdir()
    (folder / "20261020-090000-abcd.md").write_text("---\ncreada: 2026-10-20 09:00\n---\n# Compra\npan\nleche\n\nfin",
                                                    encoding="utf-8")
    note = NotesStore(str(folder), lambda paths: None).list()[0]
    assert note["title"] == "Compra" and not note["markdown"]  # de antes: texto plano
    assert legacy_to_markdown(note["text"]) == "pan  \nleche\n\nfin"

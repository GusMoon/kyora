import os
import time
from datetime import datetime

import pytest

from kyora.brain import links, vault
from kyora.brain.service import BrainService
from kyora.core.actions import ActionError, ActionRegistry

NOW = datetime(2026, 10, 21, 22, 45)


@pytest.fixture
def brain(tmp_path):
    recycled = []
    service = BrainService(tmp_path / "data", recycle=lambda paths: recycled.extend(paths), now=lambda: NOW)
    (tmp_path / "data").mkdir()
    service.setup(str(tmp_path / "Segundo Cerebro"))
    service.recycled = recycled
    return service


def test_setup_creates_layout_and_remembers(tmp_path, brain):
    root = tmp_path / "Segundo Cerebro"
    for part in ("Notas", os.path.join("Notas", "Impulsos"), "Corteza"):
        assert (root / part).is_dir()
    again = BrainService(tmp_path / "data", recycle=lambda paths: None)
    assert again.status()["configured"] and again.root == str(root)


def test_front_matter_round_trip():
    meta = {"tipo": "neurona", "etiquetas": ["a", "b"], "origen": "[[Madre]]", "creada": "2026-10-21 22:45"}
    text = vault.join_front(meta, "# Hola\n\ntexto\n")
    back, body = vault.split_front(text)
    assert back == meta and body == "# Hola\n\ntexto\n"
    assert vault.split_front("sin metadatos") == ({}, "sin metadatos")


def test_neuron_template_and_tree(brain):
    area = brain.create_area("Física")
    branch = brain.create_dendrite(area, "Óptica")
    path = brain.create_neuron(branch, "Refracción")
    note = brain.read(path)
    assert note["meta"]["tipo"] == "neurona"
    assert note["meta"]["corteza"] == "Física" and note["meta"]["dendrita"] == "Óptica"
    assert note["meta"]["creada"] == "2026-10-21 22:45"
    assert note["body"] == "# Refracción\n"
    tree = brain.tree()
    assert tree["cortex"][0]["dendrites"][0]["notes"][0]["title"] == "Refracción"
    with pytest.raises(ActionError):
        brain.create_neuron(area, "Fuera de dendrita")
    with pytest.raises(ActionError):
        brain.create_note("refraccion")  # mismo título sin tilde: las sinapsis no sabrían a cuál apuntar


def test_safe_save_detects_outside_changes(brain):
    path = brain.create_note("Diario")
    note = brain.read(path)
    saved = brain.save(path, "# Diario\n\nhoy\n", mtime=note["mtime"])
    assert "hoy" in vault.read_note(path)["body"]
    time.sleep(0.02)
    with open(path, "a", encoding="utf-8") as f:
        f.write("otro programa\n")
    os.utime(path, (saved["mtime"] + 5, saved["mtime"] + 5))
    with pytest.raises(ActionError) as err:
        brain.save(path, "pisado", mtime=saved["mtime"])
    assert err.value.code == "changed"
    brain.save(path, "pisado", mtime=saved["mtime"], force=True)
    assert vault.read_note(path)["body"] == "pisado"
    assert not any(name.endswith(".kyora-tmp") for name in os.listdir(os.path.dirname(path)))


def test_synapses_backlinks_and_rename(brain):
    a = brain.create_note("Luz")
    b = brain.create_note("Color")
    brain.save(b, "El [[luz]] y el [[Luz|brillo]] y [[Nada]].\n")
    note = brain.read(a)
    assert [x["title"] for x in note["backlinks"]] == ["Color"]
    color = brain.read(b)
    assert [(s["title"], bool(s["path"])) for s in color["synapses"]] == [("luz", True), ("Nada", False)]
    new = brain.rename(a, "Fotón")
    assert os.path.basename(new) == "Fotón.md"
    assert brain.read(b)["body"] == "El [[Fotón]] y el [[Fotón|brillo]] y [[Nada]].\n"


def test_axon_impulse_nucleus_and_search(brain):
    branch = brain.create_dendrite(brain.create_area("Música"), "Armonía")
    neuron = brain.create_neuron(branch, "Acordes")
    brain.save(neuron, "# Acordes\n## Tríadas\n- mayor\n- menor\n")
    axon = brain.derive(neuron, "Séptimas")
    assert brain.read(axon)["meta"]["origen"] == "[[Acordes]]"
    assert brain.read(axon)["kind"] == "axón"
    rows = brain.nucleus(branch)
    assert [r["title"] for r in rows] == ["Acordes", "Séptimas"]
    assert rows[0]["headings"][1]["text"] == "Tríadas"
    idea = brain.impulse("Probar la escala dórica en la guitarra eléctrica mañana")
    assert os.path.basename(idea) == "2026-10-21 2245 Probar la escala dórica en la.md"
    assert brain.read(idea)["kind"] == "impulso"
    hits = brain.search("DORICA")
    assert [h["title"] for h in hits] == [vault.title_of(idea)]
    assert [h["title"] for h in brain.search("triadas")] == ["Acordes"]


def test_rename_area_updates_meta_and_delete_guards(brain):
    area = brain.create_area("Viejo")
    branch = brain.create_dendrite(area, "Rama")
    neuron = brain.create_neuron(branch, "Idea")
    new_area = brain.rename(area, "Nuevo")
    moved = os.path.join(new_area, "Rama", "Idea.md")
    assert brain.read(moved)["meta"]["corteza"] == "Nuevo"
    assert not os.path.exists(neuron)
    with pytest.raises(ActionError):
        brain.delete(brain.root)
    with pytest.raises(ActionError):
        brain.delete(os.path.join(brain.root, "Corteza"))
    with pytest.raises(ActionError):
        brain.read(os.path.join(brain.root, "..", "fuera.md"))
    brain.delete(moved)
    assert brain.recycled == [moved]


def test_links_helpers():
    body = "Ver [[Mi nota]] y [[Otra|esa]]."
    anchors = links.wiki_to_anchor(body)
    assert anchors == "Ver [Mi nota](sinapsis:Mi%20nota) y [esa](sinapsis:Otra)."
    assert links.anchor_to_wiki(anchors) == body
    assert links.anchor_to_wiki("[x](<sinapsis:Mi%20nota>)") == "[[Mi nota|x]]"
    assert links.extract_links("[[A]] [[a]] [[B|b]]") == ["A", "B"]
    soma = links.soma("# T\ntexto\n## Sub\n```\n# no\n```\n> cita\n| a | b |\n|---|---|\n- x\n- y\n")
    assert [h["text"] for h in soma["headings"]] == ["T", "Sub"]
    assert soma["parts"] == {"Listas": 1, "Tablas": 1, "Bloques de código": 1, "Citas": 1}


def test_service_registers_actions(brain):
    registry = ActionRegistry()
    brain.register(registry)
    assert registry.invoke("brain.status")["data"]["configured"]
    assert registry.is_destructive("brain.delete")
    assert registry.invoke("brain.create_note", {"title": "  "})["error"]["code"] == "empty_name"


def test_unwrap_joins_editor_line_wrapping_only():
    wrapped = ("Un párrafo largo que el editor\ncortó en dos.\n\n- punto que\n  sigue aquí\n- otro\n\n"
               "> cita que\n> sigue\n\n```\nlinea\ncódigo\n```\n\n| a | b |\n|---|---|\n\nsalto  \nforzado\n")
    assert links.unwrap(wrapped) == (
        "Un párrafo largo que el editor cortó en dos.\n\n- punto que sigue aquí\n- otro\n\n> cita que sigue\n\n"
        "```\nlinea\ncódigo\n```\n\n| a | b |\n|---|---|\n\nsalto  \nforzado\n")

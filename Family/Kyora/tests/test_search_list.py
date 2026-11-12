from PySide6.QtWidgets import QApplication

from kyora.ui.search_list import ResultList, section_of
from kyora.ui.theme import THEME

app = QApplication.instance() or QApplication([])


def row(kind, name, **extra):
    return {"kind": kind, "id": name, "name": name, "detail": "", "exe": "", "hwnd": 0, **extra}


def test_results_are_grouped_by_section_in_order_of_appearance():
    found = []
    lst = ResultList(THEME, found.append)
    lst.set_results([row("app", "Chrome"), row("window", "Code"), row("app", "Word"),
                     row("path", "Docs", is_dir=True)])
    assert [r["name"] for r in lst.results] == ["Chrome", "Word", "Code", "Docs"]  # Aplicaciones, Ventanas, Carpetas
    assert [e[3] for e in lst._entries if e[2] == "head"] == ["Aplicaciones", "Ventanas", "Carpetas"]
    lst.move(1)
    lst.move(1)
    assert lst.current()["name"] == "Code"  # las flechas recorren de arriba abajo, saltando los títulos
    assert section_of(row("path", "x", drive=True)) == "Unidades"


def test_height_is_capped_and_notes_take_one_row():
    lst = ResultList(THEME, lambda r: None)
    lst.set_results([row("window", f"w{i}") for i in range(40)])
    assert lst.wanted_height() == 320
    lst.set_results([], "Sin resultados")
    assert 0 < lst.wanted_height() < 100
    lst.set_results([], "")
    assert lst.wanted_height() == 0

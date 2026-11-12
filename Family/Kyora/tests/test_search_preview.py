"""La vista previa del buscador: un clic en un archivo lo muestra a la derecha y otro clic sobre el mismo lo abre."""
from PySide6.QtCore import QEvent, QPointF, Qt
from PySide6.QtGui import QMouseEvent
from PySide6.QtWidgets import QApplication

from kyora.ui import search
from kyora.ui.search_list import ROW_H
from kyora.ui.theme import THEME
from kyora.ui.win import ScreenMap

app = QApplication.instance() or QApplication([])


def row(path, is_dir=False):
    return {"kind": "path", "id": str(path), "name": path.name, "detail": "", "is_dir": is_dir}


def popout(results, launched):
    pop = search.SearchPopout(THEME, ScreenMap(app.primaryScreen()),
                              query=lambda text, mode="": {"results": results, "indexing": False},
                              launch=lambda r, files: launched.append(r["id"]), close=lambda refocus: None)
    pop.open()
    app.processEvents()
    settle(pop)
    return pop


def settle(pop):
    """La lista crece con una animación: se salta al alto final para que los clics caigan dentro."""
    pop._rows.stop()
    pop._set_list_h(pop._fit_h(pop._max_list))


def click(widget, y):
    point = QPointF(20, y)
    event = QMouseEvent(QEvent.MouseButtonRelease, point, widget.mapToGlobal(point), Qt.LeftButton, Qt.NoButton,
                        Qt.NoModifier)
    widget.mouseReleaseEvent(event)


def first_row_y(pop):
    return pop.list._row_entry(0)[0] + ROW_H // 2


def test_first_click_previews_the_file_and_second_click_opens_it(tmp_path):
    note = tmp_path / "nota.txt"
    note.write_text("hola mundo", encoding="utf-8")
    launched = []
    pop = popout([row(note)], launched)
    click(pop.list, first_row_y(pop))
    assert launched == [] and pop._pv_path == str(note)
    assert pop.preview.path == str(note) and "hola mundo" in pop.preview.text.toPlainText()
    assert pop._width_to == pop._wide                                  # el buscador se ensancha para la vista previa
    click(pop.list, first_row_y(pop))                                   # un doble clic de costumbre: sigue la vista previa
    assert launched == [] and pop._pv_path == str(note)
    pop._pv_at -= search.PV_OPEN_DELAY                                  # pasado un momento, otro clic sí lo abre
    click(pop.list, first_row_y(pop))
    assert launched == [str(note)]


def test_folders_still_open_on_the_first_click(tmp_path):
    folder = tmp_path / "docs"
    folder.mkdir()
    launched = []
    pop = popout([row(folder, is_dir=True)], launched)
    click(pop.list, first_row_y(pop))
    assert pop._pv_path is None and pop.mode == "tree"                  # una carpeta se abre como árbol, sin vista previa


def test_the_preview_goes_away_when_the_text_changes_or_the_popout_closes(tmp_path):
    note = tmp_path / "nota.txt"
    note.write_text("hola", encoding="utf-8")
    pop = popout([row(note)], [])
    click(pop.list, first_row_y(pop))
    assert pop._previewing()
    pop.edit.setText("otra cosa")
    assert pop._pv_path is None and not pop._previewing()
    pop._run_query()
    settle(pop)
    click(pop.list, first_row_y(pop))
    assert pop._previewing()
    pop.close_popout()
    assert pop._pv_path is None


def test_tree_files_are_previewed_on_click_but_enter_opens_directly(tmp_path):
    note = tmp_path / "nota.txt"
    note.write_text("hola", encoding="utf-8")
    launched = []
    pop = popout([], launched)
    pop.tree.set_roots([row(note)])
    pop._show("tree", pop.tree.wanted_height())
    settle(pop)
    click(pop.tree, 6 + 5)
    assert launched == [] and pop._pv_path == str(note)
    pop._pv_at -= search.PV_OPEN_DELAY
    click(pop.tree, 6 + 5)                                              # otro clic, pasado el doble clic: lo abre
    assert launched == [str(note)]
    launched.clear()
    pop.tree.enter()                                                  # Enter: abre sin pasar por la vista previa
    assert launched == [str(note)]


def test_the_preview_sits_beside_the_list_inside_the_panel(tmp_path):
    note = tmp_path / "nota.txt"
    note.write_text("hola", encoding="utf-8")
    pop = popout([row(note)], [])
    click(pop.list, first_row_y(pop))
    settle(pop)
    assert pop.preview.isVisibleTo(pop) and pop.list.isVisibleTo(pop)
    assert pop.preview.height() == pop.list.height()                    # ni más alta ni más baja que la lista
    assert pop.preview.x() >= pop.list.x() + pop.list.width()           # a su derecha, sin taparla


def test_slash_tree_opens_with_the_listed_roots_expanded(tmp_path):
    docs, pc = tmp_path / "Documentos", "equipos:"
    docs.mkdir()
    (docs / "a.txt").write_text("x", encoding="utf-8")
    roots = [row(docs, is_dir=True), {"kind": "path", "id": pc, "name": "Equipos", "detail": "", "is_dir": True}]
    kids = {str(docs): [row(docs / "a.txt")], pc: [{"kind": "path", "id": "C:\\", "name": "C:", "detail": "Unidad",
                                                     "is_dir": True, "drive": True}]}
    pop = search.SearchPopout(THEME, ScreenMap(app.primaryScreen()),
                              query=lambda text, mode="": {"mode": "tree", "roots": roots, "results": [], "indexing": False,
                                                           "expanded": [str(docs), pc]} if text == "/" else
                              {"results": [], "indexing": False},
                              children=lambda path: kids[path], launch=lambda *a, **k: None, close=lambda r: None)
    pop.open()
    pop.edit.setText("/")
    pop._run_query()
    assert pop.mode == "tree"
    assert [(n["row"]["name"], n["depth"]) for n in pop.tree.nodes] == [("Documentos", 0), ("a.txt", 1), ("Equipos", 0),
                                                                        ("C:", 1)]


def test_losing_focus_right_after_a_preview_does_not_close_the_popout(tmp_path, monkeypatch):
    note = tmp_path / "nota.txt"
    note.write_text("hola", encoding="utf-8")
    closes = []
    pop = search.SearchPopout(THEME, ScreenMap(app.primaryScreen()),
                              query=lambda text, mode="": {"results": [row(note)], "indexing": False},
                              launch=lambda *a, **k: None, close=closes.append)
    pop.open()
    app.processEvents()
    settle(pop)
    monkeypatch.setattr(pop, "isActiveWindow", lambda: False)
    monkeypatch.setattr(search, "force_foreground", lambda hwnd: None)
    monkeypatch.setattr(search, "foreground_owner", lambda: (1, "Notepad «nota»", False))
    click(pop.list, first_row_y(pop))
    pop._check_blur()
    assert closes == []                                                 # el PDF (PDFium) se lleva el foco: sigue abierto
    pop._pv_at -= search.PV_FOCUS_GRACE
    monkeypatch.setattr(search, "foreground_owner", lambda: (1, "GDI+ Hook Window Class «»", True))
    pop._check_blur()
    assert closes == []                                                 # una ventana oculta nuestra tampoco lo cierra
    monkeypatch.setattr(search, "foreground_owner", lambda: (1, "Notepad «nota»", False))
    pop._check_blur()
    assert closes == [False]                                            # irse de verdad a otra ventana sí lo cierra


def press(pop, key):
    from PySide6.QtGui import QKeyEvent
    return pop.eventFilter(pop.edit, QKeyEvent(QEvent.KeyPress, key, Qt.NoModifier))


def test_right_arrow_previews_and_enter_opens_in_the_tree(tmp_path):
    folder, note = tmp_path / "docs", tmp_path / "docs" / "nota.md"
    folder.mkdir()
    note.write_text("# hola", encoding="utf-8")
    launched = []
    pop = search.SearchPopout(THEME, ScreenMap(app.primaryScreen()),
                              query=lambda text, mode="": {"results": [], "indexing": False},
                              children=lambda path: [row(note)], launch=lambda r, files=False: launched.append(r["id"]),
                              close=lambda r: None)
    pop.open()
    pop.tree.set_roots([row(folder, is_dir=True)])
    pop._show("tree", pop.tree.wanted_height())
    assert press(pop, Qt.Key_Right) and pop._pv_path is None             # → en una carpeta: la despliega
    assert [n["row"]["name"] for n in pop.tree.nodes] == ["docs", "nota.md"]
    press(pop, Qt.Key_Down)
    press(pop, Qt.Key_Right)
    assert pop._pv_path == str(note) and launched == []                  # → en un archivo: vista previa
    press(pop, Qt.Key_Right)
    assert launched == []                                                # → otra vez no lo abre
    press(pop, Qt.Key_Return)
    assert launched == [str(note)]                                       # Enter lo abre


def test_right_arrow_previews_a_result_only_with_the_cursor_at_the_end(tmp_path):
    note = tmp_path / "nota.txt"
    note.write_text("hola", encoding="utf-8")
    launched = []
    pop = popout([row(note)], launched)
    pop.edit.setText("nota")
    pop._run_query()
    pop.edit.setCursorPosition(1)
    assert not press(pop, Qt.Key_Right) and pop._pv_path is None         # en medio del texto: mueve el cursor
    pop.edit.setCursorPosition(4)
    assert press(pop, Qt.Key_Right) and pop._pv_path == str(note)        # al final: vista previa
    press(pop, Qt.Key_Return)
    assert launched == [str(note)]


def test_ctrl_enter_on_a_file_in_the_tree_sends_it_to_the_chat_without_opening_it(tmp_path):
    from PySide6.QtGui import QKeyEvent

    folder, note = tmp_path / "docs", tmp_path / "docs" / "nota.md"
    folder.mkdir()
    note.write_text("# hola", encoding="utf-8")
    launched, calls, toasts = [], [], []

    def core(action, **payload):
        calls.append((action, payload))
        return {"ok": True, "data": None}

    pop = search.SearchPopout(THEME, ScreenMap(app.primaryScreen()),
                              query=lambda text, mode="": {"results": [], "indexing": False},
                              children=lambda path: [row(note)], launch=lambda r, files=False: launched.append(r["id"]),
                              close=lambda r: None, call=core)
    pop.chat.notify.connect(toasts.append)
    pop.open()
    pop.tree.set_roots([row(folder, is_dir=True)])
    pop._show("tree", pop.tree.wanted_height())

    def ctrl_enter():
        return pop.eventFilter(pop.edit, QKeyEvent(QEvent.KeyPress, Qt.Key_Return, Qt.ControlModifier))

    assert ctrl_enter() and calls == [] and launched == [str(folder)]  # sobre una carpeta no manda nada: sigue abriéndola
    launched.clear()
    pop.tree.right()
    pop.tree.move(1)
    assert pop.tree.current()["name"] == "nota.md"
    assert ctrl_enter()
    assert calls == [("chat.send", {"text": "", "paths": [str(note)]})] and launched == []
    assert toasts == ["Enviado al chat · nota.md"] and pop.opened                    # avisa y el buscador sigue abierto
    pop._pick(row(note))
    assert "Ctrl+Enter" in pop.preview.info.text()                                     # el atajo se enseña en la vista previa

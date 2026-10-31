"""Editar un atajo desde la página de configuración (Qt fuera de pantalla)."""
from PySide6.QtCore import QEvent, Qt
from PySide6.QtGui import QKeyEvent
from PySide6.QtWidgets import QApplication

from kyora.config import DEFAULTS
from kyora.core.commands import config_data
from kyora.ui import configpage
from kyora.ui.theme import THEME

app = QApplication.instance() or QApplication([])


def make(monkeypatch, free=True):
    monkeypatch.setattr(configpage, "is_free", lambda combo: free)
    calls = []
    page = configpage.ConfigPage(THEME, lambda action, **payload: calls.append((action, payload)),
                                 lambda: config_data(DEFAULTS["hotkeys"]))
    page.setFixedSize(880, 340)
    page.activate()
    return page, calls


def row_of(page, text):
    for group in page._groups():
        for row in group["rows"]:
            if row["text"].startswith(text):
                return group, row
    raise AssertionError(text)


def press(page, key, modifiers=Qt.NoModifier):
    page.keyPressEvent(QKeyEvent(QEvent.KeyPress, key, modifiers))


def test_editing_a_single_shortcut_saves_the_new_combination(monkeypatch):
    page, calls = make(monkeypatch)
    group, row = row_of(page, "Cerrar la ventana con foco")
    page._start_edit(group, row)
    press(page, Qt.Key_K, Qt.ControlModifier | Qt.AltModifier)
    assert page._editing["ok"] and page._editing["candidate"] == "ctrl+alt+k"
    press(page, Qt.Key_Return)                                   # Enter guarda
    assert page._editing is None
    action, payload = calls[-1]
    assert action == "config.set_hotkeys" and payload["hotkeys"]["ctrl+alt+k"] == ["wm.close", {}]
    assert "ctrl+shift+q" not in payload["hotkeys"]
    assert row_of(page, "Cerrar la ventana con foco")[1]["combos"] == ["ctrl+alt+k"]   # la página ya lo enseña


def test_a_combination_already_used_is_refused_and_nothing_is_saved(monkeypatch):
    page, calls = make(monkeypatch)
    group, row = row_of(page, "Cerrar la ventana con foco")
    page._start_edit(group, row)
    press(page, Qt.Key_F, Qt.ControlModifier | Qt.ShiftModifier)    # ctrl+shift+f: ya es "foco siguiente"
    assert not page._editing["ok"] and "Ya lo usa" in page._editing["message"]
    press(page, Qt.Key_Return)
    assert page._editing is not None and not calls


def test_windows_and_reserved_combinations_are_refused(monkeypatch):
    page, calls = make(monkeypatch)
    group, row = row_of(page, "Cerrar la ventana con foco")
    page._start_edit(group, row)
    press(page, Qt.Key_T, Qt.MetaModifier)
    assert not page._editing["ok"] and "Windows" in page._editing["message"]
    press(page, Qt.Key_C, Qt.ControlModifier)
    assert not page._editing["ok"] and "casi todas las apps" in page._editing["message"]
    press(page, Qt.Key_J, Qt.ShiftModifier)
    assert not page._editing["ok"] and "Ctrl o Alt" in page._editing["message"]
    assert not calls


def test_a_combination_taken_by_another_program_is_refused(monkeypatch):
    page, _ = make(monkeypatch, free=False)
    group, row = row_of(page, "Cerrar la ventana con foco")
    page._start_edit(group, row)
    press(page, Qt.Key_J, Qt.ControlModifier | Qt.AltModifier)
    assert not page._editing["ok"] and "Otro programa" in page._editing["message"]


def test_escape_cancels_and_a_group_changes_only_its_modifiers(monkeypatch):
    page, calls = make(monkeypatch)
    group, row = row_of(page, "Mover la ventana con foco")
    page._start_edit(group, row)
    press(page, Qt.Key_Escape)
    assert page._editing is None and not calls
    page._start_edit(group, row)
    press(page, Qt.Key_X, Qt.ControlModifier | Qt.AltModifier)      # solo cuentan ctrl+alt
    press(page, Qt.Key_Return)
    hotkeys = calls[-1][1]["hotkeys"]
    assert hotkeys["ctrl+alt+left"] == ["wm.move", {"dir": "left"}] and "ctrl+shift+left" not in hotkeys


def test_restore_asks_first_and_then_resets(monkeypatch):
    page, calls = make(monkeypatch)
    page._reset_ask = True
    page.mouseReleaseEvent(_click(page, page._reset_rects()["reset_yes"].center()))
    assert calls[-1] == ("config.reset_hotkeys", {})


def _click(page, point):
    from PySide6.QtGui import QMouseEvent
    return QMouseEvent(QEvent.MouseButtonRelease, point, page.mapToGlobal(point), Qt.LeftButton, Qt.NoButton, Qt.NoModifier)


def test_wallpapers_and_options_areas_invoke_their_actions(monkeypatch):
    monkeypatch.setattr(configpage, "is_free", lambda combo: True)
    calls = []

    def data():
        d = config_data(DEFAULTS["hotkeys"])
        d["wallpapers"] = [{"title": "wallpapers", "info": "carpeta", "rows": [
            {"keys": "a.jpg", "text": "a", "action": "wallpaper.set", "payload": {"path": "a"}, "current": True},
            {"keys": "b.jpg", "text": "b", "action": "wallpaper.set", "payload": {"path": "b"}, "current": False}]}]
        d["options"] = [{"title": "Rendimiento", "info": "", "rows": [
            {"keys": "Modo ligero", "text": "x", "option": "light_mode", "value": True}]}]
        return d

    page = configpage.ConfigPage(THEME, lambda action, **payload: calls.append((action, payload)), data)
    page.setFixedSize(864, 424)
    page.activate()
    page._set_area(configpage.FONDOS)
    assert page._sel == 0                                             # empieza en el que está puesto
    top = page._list_top() + configpage.HEAD_H + 5
    left = page._content_x() + configpage.THUMB_W + configpage.THUMB_GAP + 10   # la segunda miniatura (b.jpg)
    page.mouseReleaseEvent(_click(page, _point(left, top)))
    assert calls[-1] == ("wallpaper.set", {"path": "b"}) and page._sel == 1
    assert [r["current"] for r in page.data["wallpapers"][0]["rows"]] == [False, True]
    calls.clear()
    press(page, Qt.Key_Left)                                          # las flechas solo mueven la elección
    assert page._sel == 0 and not calls
    press(page, Qt.Key_Return)                                        # Enter sí lo pone
    assert calls[-1] == ("wallpaper.set", {"path": "a"})
    page._set_area(configpage.RENDIMIENTO)
    top = page._list_top() + configpage.HEAD_H + 5
    page.mouseReleaseEvent(_click(page, _point(page._content_x() + 40, top)))
    assert calls[-1] == ("config.set_option", {"key": "light_mode", "value": False})


def _point(x, y):
    from PySide6.QtCore import QPointF
    return QPointF(x, y)


def test_a_group_keeps_its_keys_and_only_takes_the_modifiers(monkeypatch):
    page, calls = make(monkeypatch)
    group, row = row_of(page, "Mover la ventana con foco")
    page._start_edit(group, row)
    assert [t for t in page._fixed_tokens(row)] == [("fixed", "←/→/↑/↓")]        # las flechas se quedan
    press(page, Qt.Key_Control, Qt.ControlModifier)                              # solo se pulsan modificadores
    press(page, Qt.Key_Alt, Qt.ControlModifier | Qt.AltModifier)
    assert page._editing["ok"] and page._editing["candidate"] == "ctrl+alt+left"
    press(page, Qt.Key_Return)
    hotkeys = calls[-1][1]["hotkeys"]
    assert all(hotkeys[f"ctrl+alt+{d}"] == ["wm.move", {"dir": d}] for d in ("left", "right", "up", "down"))


def test_a_group_refuses_a_prefix_already_used_by_another_group(monkeypatch):
    page, calls = make(monkeypatch)
    group, row = row_of(page, "Mover la ventana con foco")
    page._start_edit(group, row)
    press(page, Qt.Key_Shift, Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier)   # ctrl+shift+alt+flechas ya es otra cosa
    assert not page._editing["ok"] and "Ya lo usa" in page._editing["message"]
    press(page, Qt.Key_Return)
    assert not calls

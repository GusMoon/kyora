"""El panel de la esquina de abajo a la derecha y la fila de accesos del de arriba (Qt fuera de pantalla)."""
from PySide6.QtCore import QEvent, QPointF, Qt
from PySide6.QtGui import QMouseEvent
from PySide6.QtWidgets import QApplication

from kyora.ui import quickdock, topdock
from kyora.ui.theme import THEME
from kyora.ui.win import ScreenMap

app = QApplication.instance() or QApplication([])


def make():
    return quickdock.QuickDock(THEME, ScreenMap(app.primaryScreen()), lambda *a, **k: None, lambda: {"hotkeys": {}})


def test_the_corner_panel_sits_at_the_bottom_right_and_its_zone_is_the_corner():
    dock = make()
    g = dock.map.geometry
    dock.place(None)
    assert dock.x() + dock.width() == g.x() + g.width() and dock.y() + dock.height() == g.y() + g.height()
    zone = dock._zone()
    assert zone.right() == g.x() + g.width() - 1 and zone.bottom() == g.y() + g.height() - 1
    start, end, *_ = dock._target("main")
    assert end == dock._along and start == end - dock.pages["main"].size[1]


def test_main_page_shows_the_system_data_and_its_tiles_open_their_pages():
    dock = make()
    model = {"devices": {"ram": 91, "battery": 12, "plugged": False}, "weather": {"icon": "sun", "temp": 28, "text": "x"},
             "wifi": {"connected": True, "ssid": "Casa"}}
    dock.on_devices(model["devices"])
    dock.on_weather(model["weather"])
    dock.model["wifi"] = model["wifi"]
    dock.main.apply(dock.model)
    dock.main.resize(380, 300)
    dock.main.grab()                                              # pinta (y calcula dónde se pulsa)
    names = {name for name, _ in dock.main._hits}
    assert names == {"clock", "wifi", "bluetooth", "config"}
    opened = []
    dock.main.go.connect(opened.append)
    rect = dict(dock.main._hits)["bluetooth"]
    point = rect.center()
    event = QMouseEvent(QEvent.MouseButtonRelease, QPointF(point), QPointF(point), Qt.LeftButton, Qt.NoButton, Qt.NoModifier)
    dock.main.mouseReleaseEvent(event)
    assert opened == ["bluetooth"]


def test_detail_pages_have_a_back_arrow_to_the_main_page():
    dock = make()
    page = dock.pages["wifi"]
    assert page.size[1] > 0 and page.size[0] > page.sub.height()
    seen = []
    page.back.connect(lambda: seen.append("back"))
    page.button.click()
    assert seen == ["back"]


def test_top_panel_row_only_has_the_access_icons_and_runs_their_actions():
    calls = []
    dock = topdock.TopDock(THEME, ScreenMap(app.primaryScreen()), lambda action, **k: calls.append((action, k)))
    assert set(dock.pages) == {"main", "music"}
    row = dock.pages["main"].row
    row.search.click()
    row.tasks.click()
    row.notes.click()
    assert [c[0] for c in calls] == ["search.toggle", "search.open_mode", "search.open_mode"]
    assert calls[1][1] == {"mode": "task"} and calls[2][1] == {"mode": "notes"}


def test_the_section_pill_stays_inside_the_search_and_highlights_the_open_section():
    from kyora.ui import search

    def call(action, **payload):
        data = [] if action == "tasks.list" else None
        return {"ok": True, "data": data}

    picked = []
    popout = search.SearchPopout(THEME, ScreenMap(app.primaryScreen()), query=lambda text, mode="": {"mode": "tasks"}
                                 if mode == "task" else {"results": [], "indexing": False},
                                 launch=lambda *a, **k: None, close=lambda refocus: None, call=call)
    popout.on_section = picked.append
    popout.open("task")
    app.processEvents()                           # la primera consulta llega justo después de abrir
    assert popout.mode == "kanban" and popout.pill.chips["task"].active and not popout.pill.chips["notes"].active
    popout._section("task")                       # la que ya está abierta no hace nada
    assert picked == []
    popout._section("notes")                      # otra: se pide a la interfaz abrirla
    assert picked == ["notes"]

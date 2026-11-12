"""El tablero Kanban, las etiquetas del detalle y el buscador en modo tareas (Qt fuera de pantalla)."""
from PySide6.QtCore import QEvent, QPoint, Qt
from PySide6.QtGui import QKeyEvent, QWheelEvent
from PySide6.QtWidgets import QApplication

from kyora.ui import kanban
from kyora.ui.task_detail import TaskDetail
from kyora.ui.theme import THEME

app = QApplication.instance() or QApplication([])


def task(i, status="pending", **extra):
    return {"id": i, "name": f"Tarea {i}", "status": status, "due": None, "description": "", "subtasks": 0,
            "subtasks_done": 0, "tags": [], **extra}


def board(counts):
    data = {key: [task(100 * n + i, key) for i in range(count)] for n, (key, count) in enumerate(counts.items())}
    calls = []

    def call(action, **payload):
        calls.append((action, payload))
        return {"ok": True, "data": data[payload["status"]] if action == "tasks.list" else None}

    widget = kanban.KanbanBoard(THEME, call)
    widget.setFixedSize(980, 560)
    widget.reload()
    return widget, calls, data


def test_cards_are_small_and_a_long_column_scrolls_with_the_wheel():
    widget, _, _ = board({"pending": 14, "doing": 1, "review": 0, "done": 2})
    assert kanban.CARD_H <= 80
    column = widget._column_rects()["pending"]
    assert widget._limit("pending", column) > 0 and widget._limit("doing", widget._column_rects()["doing"]) == 0
    point = column.center()
    event = QWheelEvent(point, widget.mapToGlobal(point), QPoint(0, 0), QPoint(0, -240), Qt.NoButton, Qt.NoModifier,
                        Qt.NoScrollPhase, False)
    widget.wheelEvent(event)
    assert widget.scroll["pending"] > 0
    widget.grab()                                                    # pinta con el efecto sin fallar


def test_the_keyboard_moves_between_cards_and_columns_and_changes_status():
    widget, calls, data = board({"pending": 3, "doing": 2, "review": 0, "done": 1})
    widget.move_sel(0, 1)
    assert widget.sel == [0, 1] and widget.selected()[1]["id"] == 1
    widget.move_sel(1, 0)                                            # a la columna de al lado
    assert widget.sel[0] == 1
    widget.move_sel(1, 0)                                            # "En revisión" está vacía: salta a "Finalizada"
    assert widget.sel[0] == 3
    widget.move_sel(-1, 0)
    widget.shift_status(1)                                           # Ctrl+→: pasa a "En revisión"
    assert ("tasks.set_status", {"task_id": data["doing"][0]["id"], "status": "review"}) in calls


def test_ctrl_delete_asks_twice_and_ctrl_enter_finishes():
    widget, calls, _ = board({"pending": 2, "doing": 0, "review": 0, "done": 0})
    widget.arm_delete()
    assert widget.armed == 0 and not any(c[0] == "tasks.delete" for c in calls)
    widget.arm_delete()
    assert ("tasks.delete", {"task_id": 0}) in calls
    widget.toggle_done()
    assert ("tasks.set_status", {"task_id": 0, "status": "done"}) in calls


def test_enter_opens_the_selected_card():
    widget, _, _ = board({"pending": 2, "doing": 0, "review": 0, "done": 0})
    opened = []
    widget.open_task.connect(opened.append)
    widget.move_sel(0, 1)
    assert widget.open_selected() and opened == [1]


def test_a_task_gets_tags_from_the_detail_and_creates_missing_ones():
    calls = []
    current = {"id": 7, "name": "T", "description": "", "due": None, "status": "pending", "created": "2026-10-20T10:00",
               "children": [], "tags": [{"id": 1, "name": "Trabajo", "color": "#5b8def"}]}

    def call(action, **payload):
        calls.append((action, payload))
        data = {"tasks.get": current, "tags.list": [{"id": 1, "name": "Trabajo", "color": "#5b8def"}],
                "tags.create": 2}.get(action)
        return {"ok": True, "data": data}

    detail = TaskDetail(THEME, call)
    detail.resize(920, 460)
    assert detail.show_task(7)
    assert [t["name"] for t in detail.tag_bar.tags] == ["Trabajo"] and "Trabajo" in detail.tag_names.stringList()
    detail.tag_input.setText("Urgente")
    detail._add_tag()
    assert ("tags.create", {"name": "Urgente"}) in calls and ("tags.assign", {"task_id": 7, "tag_id": 2}) in calls
    detail._remove_tag(1)
    assert ("tags.unassign", {"task_id": 7, "tag_id": 1}) in calls
    assert detail.tag_input.text() == ""


def test_search_in_task_mode_opens_the_board_and_a_task_replaces_the_field():
    from kyora.ui import search
    from kyora.ui.win import ScreenMap

    screen = ScreenMap(app.primaryScreen())
    tasks = []

    def call(action, **payload):
        if action == "tasks.list":
            return {"ok": True, "data": [task(1)] if payload["status"] == "pending" else []}
        if action == "tasks.get":
            return {"ok": True, "data": {**task(1), "created": "2026-10-20T10:00", "children": [], "tags": []}}
        return {"ok": True, "data": []}

    popout = search.SearchPopout(THEME, screen, lambda text, mode="": {"mode": "tasks", "results": [], "indexing": False},
                                 lambda *a: None, lambda *a: None, call=call,
                                 act=lambda kind, ident: tasks.append((kind, ident)) or {"ok": True, "data": 5})
    popout.open("task")
    popout._run_query()
    assert popout.mode == "kanban" and popout.edit.placeholderText().startswith("Escribe aquí para crear")
    popout.edit.setText("Comprar pan")
    event = QKeyEvent(QEvent.KeyPress, Qt.Key_Return, Qt.NoModifier)
    assert popout._kanban_key(event)
    assert tasks == [("task_new", "Comprar pan")] and popout.mode == "task"          # crea y la abre
    popout._band_anim.stop()
    popout._set_band(0.0)
    assert popout._bandf == 0.0 and not popout.edit.isVisible()                      # sin campo encima
    popout._detail_back()
    assert popout.mode == "kanban"


def test_date_picker_marks_a_band_from_today_and_accepts_or_cancels():
    from datetime import date, timedelta

    from kyora.ui import datepicker

    picker = datepicker.DatePicker(THEME)
    picker.open(None)
    assert picker.grid.chosen is None and picker.grid.view == picker.today.replace(day=1)
    target = picker.today + timedelta(days=4)
    picker._pick(target)
    assert datepicker.band(picker.today, target) == (picker.today, target)
    assert datepicker.band(picker.today, None) is None
    got = []
    picker.accepted.connect(got.append)
    picker.hour.setText("09:30")
    picker._accept()
    assert got == [f"{target:%Y-%m-%d}T09:30"]
    picker._clear()
    picker._accept()
    assert got[-1] is None
    assert len(datepicker.month_cells(date(2026, 11, 1))) == 42 and datepicker.shift_month(date(2026, 12, 5), 1) == date(2027, 1, 1)


def test_one_click_on_the_status_moves_to_the_next_one_and_the_list_rows_grow_with_their_text():
    calls = []
    current = {"id": 7, "name": "T", "description": "", "due": None, "status": "pending", "created": "2026-10-20T10:00",
               "children": [{"id": 8, "name": "corta", "status": "pending"},
                            {"id": 9, "name": "una subtarea con un nombre larguísimo " * 6, "status": "pending"}],
               "tags": []}

    def call(action, **payload):
        calls.append((action, payload))
        return {"ok": True, "data": {"tasks.get": current, "tags.list": []}.get(action)}

    detail = TaskDetail(THEME, call)
    detail.resize(920, 460)
    detail.show_task(7)
    detail.status_button.clicked.emit()
    assert ("tasks.set_status", {"task_id": 7, "status": "doing"}) in calls
    hs = detail.subtasks._hs()
    assert hs[1] > hs[0]
    detail.begin_subtask()
    assert detail.subtasks._adding and detail.subtasks._new is not None
    detail.subtasks.end_new()
    assert not detail.subtasks._adding

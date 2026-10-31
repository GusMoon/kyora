from kyora.core.subtasks import drop_index, reordered
from kyora.tasks import model


def test_drop_index_follows_the_dragged_row_centre():
    tops = [0, 40, 80]
    assert drop_index(5, tops, 40) == 0
    assert drop_index(45, tops, 40) == 1       # justo en medio de la segunda: se queda ahí
    assert drop_index(70, tops, 40) == 2
    assert drop_index(999, tops, 40) == 2      # nunca pasa de la última


def test_reordered_moves_one_item():
    assert reordered([1, 2, 3, 4], 0, 2) == [2, 3, 1, 4]
    assert reordered([1, 2, 3, 4], 3, 0) == [4, 1, 2, 3]
    assert reordered([1, 2], 5, 0) == [1, 2]


def test_progress_counts_finished_subtasks():
    kids = [{"status": "done"}, {"status": "doing"}, {"status": "pending", "finished": "2026-10-26"}]
    assert model.progress(kids) == (2, 3)
    assert model.progress([]) == (0, 0)


# ---------- la lista de subtareas (Qt, fuera de pantalla) ----------
from PySide6.QtCore import QEvent, QPointF, Qt
from PySide6.QtGui import QMouseEvent
from PySide6.QtWidgets import QApplication

from kyora.ui import subtask_list
from kyora.ui.theme import THEME

app = QApplication.instance() or QApplication([])


def _list(statuses=("pending", "doing", "done")):
    widget = subtask_list.SubtaskList(THEME)
    widget.resize(400, 200)
    widget.set_items([{"id": i + 1, "name": f"t{i + 1}", "status": s} for i, s in enumerate(statuses)])
    seen = {"cycled": [], "removed": [], "moved": []}
    widget.status_cycled.connect(seen["cycled"].append)
    widget.removed.connect(seen["removed"].append)
    widget.moved.connect(lambda i, pos: seen["moved"].append((i, pos)))
    return widget, seen


def _mouse(widget, kind, x, y):
    event = QMouseEvent(kind, QPointF(x, y), widget.mapToGlobal(QPointF(x, y)), Qt.LeftButton,
                        Qt.LeftButton if kind != QEvent.MouseButtonRelease else Qt.NoButton, Qt.NoModifier)
    {QEvent.MouseButtonPress: widget.mousePressEvent, QEvent.MouseMove: widget.mouseMoveEvent,
     QEvent.MouseButtonRelease: widget.mouseReleaseEvent}[kind](event)


def test_clicking_the_icon_asks_for_the_next_status():
    widget, seen = _list()
    centre = widget._icon_center(1)
    _mouse(widget, QEvent.MouseButtonPress, centre.x(), centre.y())
    _mouse(widget, QEvent.MouseButtonRelease, centre.x(), centre.y())
    assert seen["cycled"] == [2]


def test_the_cross_removes_a_hovered_row():
    widget, seen = _list()
    box = widget._close_rect(0)
    widget._hover = 0
    _mouse(widget, QEvent.MouseButtonPress, box.center().x(), box.center().y())
    assert seen["removed"] == [1]


def test_dragging_a_row_down_reorders_it():
    widget, seen = _list()
    x, y0 = 120, widget._top(0) + 25
    _mouse(widget, QEvent.MouseButtonPress, x, y0)
    _mouse(widget, QEvent.MouseMove, x, y0 + 30)
    _mouse(widget, QEvent.MouseMove, x, y0 + subtask_list.ROW_H * 2)
    _mouse(widget, QEvent.MouseButtonRelease, x, y0 + subtask_list.ROW_H * 2)
    assert seen["moved"] == [(1, 2)]


def test_status_icons_paint_for_the_four_states():
    from kyora.ui.status_icon import status_pixmap

    images = [status_pixmap(THEME, status, 24).toImage() for status in ("pending", "doing", "review", "done")]
    assert all(not image.isNull() for image in images)
    assert all(images[i] != images[j] for i in range(4) for j in range(i + 1, 4))  # cada estado, su estilo

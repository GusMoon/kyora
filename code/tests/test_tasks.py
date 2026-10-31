from datetime import datetime, timedelta

import pytest

from kyora.core.actions import ActionError, ActionRegistry
from kyora.tasks import model
from kyora.tasks.service import TaskService
from kyora.tasks.store import TaskStore


class Clock:
    def __init__(self):
        self.t = datetime(2026, 10, 21, 10, 0, 0)

    def __call__(self):
        return self.t

    def advance(self, seconds):
        self.t += timedelta(seconds=seconds)


@pytest.fixture
def clock():
    return Clock()


@pytest.fixture
def store(clock):
    s = TaskStore(":memory:", now=clock)
    yield s
    s.close()


def test_create_update_and_dates(store, clock):
    tid = store.create("Informe", description="del trimestre", expected_min=90)
    task = store.get(tid)
    assert task["name"] == "Informe" and task["description"] == "del trimestre"
    assert task["created"] == task["updated"] == "2026-10-21T10:00:00"
    clock.advance(60)
    store.update(tid, name="Informe final", due="2026-10-25T18:00")
    task = store.get(tid)
    assert task["name"] == "Informe final" and task["due"] == "2026-10-25T18:00"
    assert task["updated"] == "2026-10-21T10:01:00"
    with pytest.raises(ActionError):
        store.update(tid, name="  ")
    with pytest.raises(ActionError):
        store.update(tid, finished="x")


def test_subtasks_keep_order_and_cascade(store):
    tid = store.create("Mudanza")
    a = store.create("Cajas", parent_id=tid)
    b = store.create("Camión", parent_id=tid)
    c = store.create("Llaves", parent_id=tid)
    assert [x["id"] for x in store.get(tid)["children"]] == [a, b, c]
    store.move(c, 0)
    assert [x["id"] for x in store.get(tid)["children"]] == [c, a, b]
    with pytest.raises(ActionError):
        store.create("Nieta", parent_id=a)  # un solo nivel
    assert store.tasks()[0]["subtasks"] == 3
    store.delete(tid)
    assert store.tasks() == []
    assert store.db.execute("SELECT COUNT(*) FROM tasks").fetchone()[0] == 0


def test_tags_survive_task_delete(store):
    tid = store.create("Llamar")
    tag = store.tag_create("Casa")
    assert store.tag_create("casa") == tag  # sin distinguir mayúsculas
    store.tag_assign(tid, tag)
    assert store.get(tid)["tags"][0]["name"] == "Casa"
    assert store.tags()[0]["count"] == 1
    store.delete(tid)
    assert [t["name"] for t in store.tags()] == ["Casa"]
    assert store.tags()[0]["count"] == 0


def test_finish_and_reopen(store, clock):
    tid = store.create("Pagar")
    clock.advance(30)
    store.finish(tid)
    assert store.get(tid)["finished"] == "2026-10-21T10:00:30"
    store.reopen(tid)
    assert store.get(tid)["finished"] is None


def test_timer_adds_real_time_one_at_a_time(store, clock):
    a = store.create("A")
    b = store.create("B")
    store.timer_start(a)
    clock.advance(120)
    assert model.real_seconds(store.get(a), clock()) == 120
    store.timer_start(b)  # para el de A
    assert store.get(a)["real_s"] == 120 and store.get(a)["timer_started"] is None
    clock.advance(30)
    store.timer_stop()
    assert store.get(b)["real_s"] == 30
    store.timer_start(a)
    clock.advance(10)
    store.finish(a)  # finalizar para el cronómetro
    assert store.get(a)["real_s"] == 130
    with pytest.raises(ActionError):
        store.timer_start(a)


def test_filters(clock):
    now = clock()
    base = {"finished": None, "tags": [{"id": 1}]}
    today = dict(base, due="2026-10-21T18:00")
    late = dict(base, due="2026-10-20T09:00")
    sunday = dict(base, due="2026-10-25T09:00")
    nodate = dict(base, due=None)
    done = dict(today, finished="2026-10-21T09:00:00")
    assert model.matches(today, [], "today", now, False)
    assert not model.matches(sunday, [], "today", now, False)
    assert model.matches(sunday, [], "week", now, False)
    assert model.matches(late, [], "overdue", now, False)
    assert not model.matches(today, [], "overdue", now, False)
    assert model.matches(nodate, [], "none", now, False)
    assert not model.matches(done, [], "all", now, False)
    assert model.matches(done, [], "all", now, True)
    assert model.matches(today, [1, 7], "all", now, False)
    assert not model.matches(today, [7], "all", now, False)


def test_durations():
    assert model.parse_duration("") is None
    assert model.parse_duration("90") == 90
    assert model.parse_duration("1:30") == 90
    assert model.parse_duration("1 h 30 min") == 90
    assert model.parse_duration("1h30") == 90
    assert model.parse_duration("2 h") == 120
    assert model.parse_duration("45 min") == 45
    assert model.parse_duration("1,5 h") == 90
    with pytest.raises(ValueError):
        model.parse_duration("mañana")
    assert model.format_duration(90) == "1 h 30 min"
    assert model.format_duration(120) == "2 h"
    assert model.format_duration(45) == "45 min"
    assert model.format_seconds(3723) == "1:02:03"
    assert model.format_seconds(125) == "2:05"


def test_due_label():
    today = datetime(2026, 10, 21).date()
    assert model.due_label("2026-10-21T18:00", today) == "Hoy 18:00"
    assert model.due_label("2026-10-22T09:30", today) == "Mañana 09:30"
    assert model.due_label("2026-10-30T09:30", today) == "30/10 09:30"
    assert model.due_label(None, today) == ""


def test_service_actions(clock):
    registry = ActionRegistry()
    service = TaskService(":memory:", now=clock)
    service.register(registry)
    made = registry.invoke("tasks.create", {"name": "Correo", "expected_min": "1 h"})
    assert made["ok"]
    tid = made["data"]
    assert service.store.get(tid)["expected_min"] == 60
    assert registry.invoke("tasks.update", {"task_id": tid, "expected_min": "nada"})["error"]["code"] == "bad_duration"
    registry.invoke("tasks.update", {"task_id": tid, "due": "2026-10-21T20:00"})
    assert [t["id"] for t in registry.invoke("tasks.list", {"due": "today"})["data"]] == [tid]
    assert registry.invoke("tasks.list", {"due": "none"})["data"] == []
    assert registry.invoke("tasks.add_subtask", {"task_id": tid, "name": "Adjuntar"})["ok"]
    assert registry.is_destructive("tasks.delete")


def test_statuses_and_counts(store, clock):
    a = store.create("A")
    b = store.create("B")
    assert store.get(a)["status"] == "pending"
    store.timer_start(a)
    store.set_status(a, "doing")
    assert store.get(a)["timer_started"] is not None  # en proceso el cronómetro sigue
    clock.advance(60)
    store.set_status(a, "done")
    task = store.get(a)
    assert task["status"] == "done" and task["finished"] == "2026-10-21T10:01:00" and task["real_s"] == 60
    store.set_status(a, "review")
    assert store.get(a)["finished"] is None
    store.set_status(b, "doing")
    assert store.counts() == {"pending": 0, "doing": 1, "review": 1, "done": 0}
    with pytest.raises(ActionError):
        store.set_status(a, "archivada")
    assert model.next_status("pending") == "doing" and model.next_status("done") == "pending"


def test_old_database_is_migrated(tmp_path, clock):
    import sqlite3

    path = tmp_path / "tasks.db"
    old = sqlite3.connect(path)
    old.executescript(
        "CREATE TABLE tasks (id INTEGER PRIMARY KEY, parent_id INTEGER, position INTEGER NOT NULL DEFAULT 0,"
        " name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', expected_min INTEGER,"
        " real_s INTEGER NOT NULL DEFAULT 0, timer_started TEXT, created TEXT NOT NULL, updated TEXT NOT NULL,"
        " due TEXT, finished TEXT);"
        "INSERT INTO tasks (name, created, updated, finished) VALUES ('hecha', 'x', 'x', '2026-10-20T10:00:00');"
        "INSERT INTO tasks (name, created, updated) VALUES ('abierta', 'x', 'x');"
        "PRAGMA user_version = 1;")
    old.commit()
    old.close()
    store = TaskStore(path, now=clock)
    assert {t["name"]: t["status"] for t in store.tasks()} == {"hecha": "done", "abierta": "pending"}
    assert store.db.execute("PRAGMA user_version").fetchone()[0] == 2
    store.close()


def test_list_by_status(clock):
    registry = ActionRegistry()
    service = TaskService(":memory:", now=clock)
    service.register(registry)
    a = registry.invoke("tasks.create", {"name": "Uno"})["data"]
    registry.invoke("tasks.create", {"name": "Dos"})
    registry.invoke("tasks.set_status", {"task_id": a, "status": "review"})
    assert [t["name"] for t in registry.invoke("tasks.list", {"status": "review"})["data"]] == ["Uno"]
    assert [t["name"] for t in registry.invoke("tasks.list", {"status": "pending"})["data"]] == ["Dos"]
    assert registry.invoke("tasks.counts")["data"]["review"] == 1

"""El módulo Tareas como acciones con nombre (tasks.* y tags.*), sobre TaskStore.

`tasks.list` filtra por estado (pending/doing/review/done) y, si se pide, por etiquetas (vale con una), fecha de
entrega (all/today/week/overdue/none) y finalizadas.
"""
from datetime import datetime

from kyora.core.actions import ActionError
from kyora.tasks import model
from kyora.tasks.store import TaskStore


class TaskService:
    def __init__(self, data_dir, now=datetime.now):
        self._now = now
        self.store = TaskStore(data_dir / "tasks.db" if data_dir != ":memory:" else ":memory:", now=now)

    def register(self, registry):
        r, s = registry, self.store
        r.register("tasks.list", self.list)
        r.register("tasks.get", s.get)
        r.register("tasks.create", self.create)
        r.register("tasks.update", self.update)
        r.register("tasks.delete", s.delete, destructive=True)
        r.register("tasks.finish", s.finish)
        r.register("tasks.reopen", s.reopen)
        r.register("tasks.set_status", s.set_status)
        r.register("tasks.counts", s.counts)
        r.register("tasks.add_subtask", lambda task_id, name: s.create(name, parent_id=task_id))
        r.register("tasks.move", s.move)
        r.register("tasks.timer_start", s.timer_start)
        r.register("tasks.timer_stop", s.timer_stop)
        r.register("tags.list", s.tags)
        r.register("tags.create", s.tag_create)
        r.register("tags.rename", s.tag_rename)
        r.register("tags.delete", s.tag_delete)
        r.register("tags.assign", s.tag_assign)
        r.register("tags.unassign", s.tag_unassign)

    def list(self, status=None, tags=(), due="all", finished=False):
        if due not in dict(model.DUE_FILTERS):
            raise ActionError("bad_filter", f"Filtro de entrega desconocido: {due}")
        if status is not None and status not in model.STATUS_KEYS:
            raise ActionError("bad_status", f"Estado desconocido: {status}")
        now = self._now()
        found = [t for t in self.store.tasks() if model.matches(t, tags, due, now, finished, status)]
        return sorted(found, key=model.sort_key)

    @staticmethod
    def _expected(fields):
        """El tiempo esperado puede llegar como texto ("1 h 30 min"): se pasa a minutos."""
        if isinstance(fields.get("expected_min"), str):
            try:
                fields["expected_min"] = model.parse_duration(fields["expected_min"])
            except ValueError as err:
                raise ActionError("bad_duration", str(err)) from err
        return fields

    def create(self, name, **fields):
        return self.store.create(name, **self._expected(fields))

    def update(self, task_id, **fields):
        self.store.update(task_id, **self._expected(fields))

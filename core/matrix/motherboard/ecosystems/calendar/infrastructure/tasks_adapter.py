from typing import List

from core.matrix.motherboard.ecosystems.calendar.domain.entities import TaskItem
from core.matrix.motherboard.ecosystems.calendar.domain.task_source import TaskSource


class TasksEcosystemAdapter(TaskSource):
    """
    Lee las tareas directamente del repositorio del ecosistema Tareas.

    Consulta en cada llamada, por lo que siempre refleja el estado actual sin
    guardar copias.
    """

    def __init__(self, task_repository):
        """
        Args:
            task_repository: Objeto con `get_all_tasks()` (contrato TaskRepository de Tareas).
        """
        self._task_repository = task_repository

    def list_tasks_with_due_date(self) -> List[TaskItem]:
        """Devuelve las tareas con fecha límite, separando la fecha de la hora."""
        items = []
        for task in self._task_repository.get_all_tasks():
            due = (task.due_date or "").strip()
            if len(due) < 10:
                continue
            due_time = due[11:16] if len(due) >= 16 and due[10] in ("T", " ") else ""
            subtasks = [
                (sub.title, bool(sub.is_completed)) for sub in (getattr(task, "subtasks", None) or [])
            ]
            items.append(TaskItem(
                task_id=task.id, title=task.title, due_date=due[:10],
                due_time=due_time, status=task.status_name,
                description=getattr(task, "description", "") or "", subtasks=subtasks,
            ))
        return items

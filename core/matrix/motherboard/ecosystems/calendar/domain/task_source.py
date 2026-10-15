from abc import ABC, abstractmethod
from typing import List

from core.matrix.motherboard.ecosystems.calendar.domain.entities import TaskItem


class TaskSource(ABC):
    """
    Puerto de lectura hacia el ecosistema Tareas.

    El calendario solo consulta: nunca copia ni modifica las tareas, de modo que
    los cambios hechos en Tareas se reflejan sin duplicados.
    """

    @abstractmethod
    def list_tasks_with_due_date(self) -> List[TaskItem]:
        """Devuelve las tareas que tienen fecha límite."""

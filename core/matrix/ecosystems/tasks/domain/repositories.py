from abc import ABC, abstractmethod
from typing import List, Optional
from core.matrix.ecosystems.tasks.domain.entities import Task, SubTask, TaskStatus

class TaskRepository(ABC):
    """
    Contrato abstracto que define las operaciones de persistencia para el ecosistema de tareas.
    Permite desacoplar las capas de Dominio y Casos de Uso de la implementación técnica (SQLite).
    """

    @abstractmethod
    def get_all_tasks(self) -> List[Task]:
        """Recupera todas las tareas registradas con sus respectivas subtareas."""
        pass

    @abstractmethod
    def get_task_by_id(self, task_id: str) -> Optional[Task]:
        """Obtiene una tarea por su identificador único."""
        pass

    @abstractmethod
    def save_task(self, task: Task) -> None:
        """Crea o actualiza una tarea en la fuente de datos."""
        pass

    @abstractmethod
    def update_task_status(self, task_id: str, new_status_id: int) -> None:
        """Modifica el estado de una tarea."""
        pass

    @abstractmethod
    def delete_task(self, task_id: str) -> None:
        """Elimina una tarea y sus subtareas asociadas."""
        pass

    @abstractmethod
    def get_statuses(self) -> List[TaskStatus]:
        """Obtiene el catálogo de estados disponibles."""
        pass

    @abstractmethod
    def save_subtask(self, subtask: SubTask) -> None:
        """Crea o actualiza una subtarea asociada a una tarea."""
        pass

    @abstractmethod
    def delete_subtask(self, subtask_id: str) -> None:
        """Elimina una subtarea por su identificador."""
        pass

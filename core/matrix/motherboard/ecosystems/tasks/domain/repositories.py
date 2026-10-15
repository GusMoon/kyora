from abc import ABC, abstractmethod
from typing import List, Optional
from core.matrix.motherboard.ecosystems.tasks.domain.entities import Task, SubTask, TaskStatus, Category, TimeEntry

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
    def reorder_subtasks(self, task_id: str, ordered_subtask_ids: List[str]) -> None:
        """Persiste el orden de las subtareas de una tarea."""
        pass

    @abstractmethod
    def delete_subtask(self, subtask_id: str) -> None:
        """Elimina una subtarea por su identificador."""
        pass

    @abstractmethod
    def get_all_categories(self) -> List[Category]:
        """Obtiene el catálogo de categorías disponibles."""
        pass

    @abstractmethod
    def save_category(self, category: Category) -> None:
        """Registra o actualiza una categoría personalizada."""
        pass

    @abstractmethod
    def delete_category(self, category_id: str) -> None:
        """Elimina una categoría por su identificador."""
        pass

    @abstractmethod
    def add_time_entry(self, entry: TimeEntry) -> None:
        """Registra una sesión de tiempo para una tarea."""
        pass

    @abstractmethod
    def get_time_entries_for_task(self, task_id: str) -> List[TimeEntry]:
        """Recupera el historial de registros de tiempo de una tarea."""
        pass


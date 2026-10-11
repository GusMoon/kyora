from typing import Optional
from PySide6.QtCore import QObject, Signal
from core.matrix.ecosystems.tasks.use_cases.manage_tasks import TaskUseCases
from core.matrix.ecosystems.tasks.domain.entities import Task


class TasksViewModel(QObject):
    """
    ViewModel para el ecosistema de Tareas.

    Conecta la interfaz gráfica (Views) con los Casos de Uso (TaskUseCases)
    mediante el patrón reactivo de Qt Señales y Slots.
    """
    tasks_updated = Signal(dict)
    task_error = Signal(str)

    def __init__(self, use_cases: TaskUseCases):
        """
        Inicializa el ViewModel inyectando los casos de uso.

        Args:
            use_cases: Instancia de TaskUseCases que orquesta la lógica de negocio.
        """
        super().__init__()
        self._use_cases = use_cases

    def is_configured(self) -> bool:
        """
        Verifica si el sistema de almacenamiento está disponible.

        Returns:
            bool: True si la base de datos está inicializada y accesible.
        """
        return self._use_cases.is_configured()

    def configure_directory(self, path: str) -> None:
        """
        Establece la ruta de directorio y recarga la lista de tareas.

        Args:
            path: Ruta del directorio de tareas.
        """
        self._use_cases.configure_directory(path)
        self.load_tasks()

    def load_tasks(self) -> None:
        """
        Carga las tareas agrupadas por estado y emite la señal tasks_updated
        para notificar a la vista.
        """
        try:
            tasks_grouped = self._use_cases.get_tasks_grouped_by_status()
            self.tasks_updated.emit(tasks_grouped)
        except Exception as e:
            self.task_error.emit(f"Error al cargar tareas: {str(e)}")

    def create_new_task(
        self,
        title: str,
        description: str = "",
        due_date: Optional[str] = None,
        status: str = "pending",
        priority: int = 0,
        subtasks: Optional[list] = None
    ) -> str:
        """
        Crea una nueva tarea, persiste su información y actualiza la vista.

        Args:
            title: Título de la tarea.
            description: Descripción detallada opcional.
            due_date: Fecha límite opcional (ISO-8601).
            status: Estado inicial (por defecto 'pending').
            priority: Nivel de prioridad.
            subtasks: Lista opcional de títulos de subtareas iniciales.

        Returns:
            str: Identificador único asignado a la tarea.
        """
        try:
            task = self._use_cases.create_task(
                title=title,
                description=description,
                due_date=due_date,
                status=status,
                priority=priority,
                subtasks=subtasks
            )
            self.load_tasks()
            return task.id
        except Exception as e:
            self.task_error.emit(f"Error al crear tarea: {str(e)}")
            return ""

    def move_task_status(self, task_id: str, new_status: str) -> None:
        """
        Modifica el estado de una tarea y refresca la vista.

        Args:
            task_id: Identificador de la tarea.
            new_status: Nombre del nuevo estado.
        """
        try:
            self._use_cases.update_task_status(task_id, new_status)
            self.load_tasks()
        except Exception as e:
            self.task_error.emit(f"Error al mover tarea: {str(e)}")

    def delete_task(self, task_id: str) -> None:
        """
        Elimina una tarea y refresca la vista.

        Args:
            task_id: Identificador de la tarea.
        """
        try:
            self._use_cases.delete_task(task_id)
            self.load_tasks()
        except Exception as e:
            self.task_error.emit(f"Error al eliminar tarea: {str(e)}")

    def get_task_by_id(self, task_id: str) -> Optional[Task]:
        """
        Recupera los datos de una tarea por su identificador.

        Args:
            task_id: Identificador de la tarea.

        Returns:
            Optional[Task]: Tarea encontrada o None.
        """
        return self._use_cases.get_task(task_id)

    def update_task_details(
        self,
        task_id: str,
        title: str,
        description: str = "",
        due_date: Optional[str] = None,
        status: Optional[str] = None,
        subtasks: Optional[list] = None
    ) -> bool:
        """
        Actualiza los datos descriptivos y subtareas de una tarea y refresca el tablero.

        Args:
            task_id: Identificador de la tarea.
            title: Título modificado.
            description: Descripción detallada.
            due_date: Fecha límite de entrega opcional.
            status: Nombre del estado opcional.
            subtasks: Lista actualizada de subtareas opcional.

        Returns:
            bool: True si la operación fue exitosa, False en caso de fallo.
        """
        try:
            res = self._use_cases.update_task_details(
                task_id=task_id,
                title=title,
                description=description,
                due_date=due_date,
                status=status,
                subtasks=subtasks
            )
            if res:
                self.load_tasks()
                return True
            return False
        except Exception as e:
            self.task_error.emit(f"Error al actualizar tarea: {str(e)}")
            return False

    def toggle_subtask_status(self, task_id: str, subtask_id: str, is_completed: bool) -> bool:
        """
        Modifica el estado completado/pendiente de una subtarea y refresca el tablero.

        Args:
            task_id: Identificador de la tarea padre.
            subtask_id: Identificador de la subtarea.
            is_completed: True si está completada, False si está pendiente.

        Returns:
            bool: True si se actualizó con éxito.
        """
        try:
            res = self._use_cases.toggle_subtask_status(task_id, subtask_id, is_completed)
            if res:
                self.load_tasks()
                return True
            return False
        except Exception as e:
            self.task_error.emit(f"Error al alternar subtarea: {str(e)}")
            return False


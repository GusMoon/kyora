from typing import List, Optional, Dict
from datetime import datetime
import uuid
import re

from core.matrix.motherboard.ecosystems.tasks.domain.entities import Task, SubTask, Category, TimeEntry
from core.matrix.motherboard.ecosystems.tasks.domain.repositories import TaskRepository


class TaskUseCases:
    """
    Casos de uso para la administración y seguimiento de tareas en Kiora.
    Contiene la lógica de negocio y coordina operaciones a través de TaskRepository.
    """

    def __init__(self, repository: TaskRepository):
        """
        Inyecta el repositorio abstracto de tareas.

        Args:
            repository: Abstracción de persistencia que implementa TaskRepository.
        """
        self.repository = repository

    def is_configured(self) -> bool:
        """
        Verifica si la persistencia de tareas está lista para su uso.
        Con SQLite la inicialización es automática.

        Returns:
            bool: True indicando que el repositorio está disponible.
        """
        return True

    def configure_directory(self, path: str) -> None:
        """
        Método de compatibilidad con configuraciones de carpetas previas.

        Args:
            path: Ruta del directorio proporcionado.
        """
        # Si el repositorio admite cambio de ruta o directorio
        if hasattr(self.repository, "set_directory"):
            self.repository.set_directory(path)

    def get_tasks_grouped_by_status(self, category_id_filter: Optional[str] = None) -> Dict[str, List[Task]]:
        """
        Recupera todas las tareas y las agrupa por estado (pending, in_progress, completed).
        Permite filtrar por categoría específica o consultar todas (TAR-029).
        Ordena las tareas por fecha límite más cercana (las sin fecha al final).

        Args:
            category_id_filter: ID de categoría para filtrar opcionalmente.

        Returns:
            Dict[str, List[Task]]: Tareas agrupadas por su nombre de estado.
        """
        tasks = self.repository.get_all_tasks()

        # Filtrado por categoría si se especificó (TAR-029)
        if category_id_filter:
            if category_id_filter == "__none__":
                tasks = [t for t in tasks if not t.category_id]
            else:
                tasks = [t for t in tasks if t.category_id == category_id_filter]

        def sort_key(t: Task) -> float:
            if t.due_date:
                try:
                    return datetime.fromisoformat(t.due_date).timestamp()
                except ValueError:
                    pass
            return float('inf')

        tasks.sort(key=sort_key)

        pending_tasks = [t for t in tasks if t.status_name == "pending"]
        in_progress_tasks = [t for t in tasks if t.status_name in ("in_progress", "in-progress")]
        completed_tasks = [t for t in tasks if t.status_name == "completed"]

        return {
            "pending": pending_tasks,
            "in_progress": in_progress_tasks,
            "in-progress": in_progress_tasks,  # Alias retrocompatible con columnas UI
            "completed": completed_tasks
        }

    def create_task(
        self,
        title: str,
        description: str = "",
        due_date: Optional[str] = None,
        subtasks: Optional[List[str]] = None,
        status: str = "pending",
        priority: int = 0,
        category_id: Optional[str] = None,
        estimated_duration_minutes: Optional[int] = None
    ) -> Task:
        """
        Crea y persiste una nueva tarea en el sistema (TAR-001 al TAR-006, TAR-026, TAR-032).

        Args:
            title: Título de la tarea.
            description: Descripción detallada.
            due_date: Fecha límite de entrega opcional.
            subtasks: Lista de títulos de subtareas a crear.
            status: Estado inicial ('pending', 'in_progress', 'completed').
            priority: Nivel de prioridad.
            category_id: Clave de la categoría asignada opcional (TAR-026).
            estimated_duration_minutes: Duración estimada en minutos opcional (TAR-032, TAR-033).

        Returns:
            Task: La entidad persistida con identificador asignado.
        """
        now = datetime.now().isoformat()
        clean_title = re.sub(r'[^a-zA-Z0-9_\- ]', '', title).strip().replace(' ', '_')
        task_id = clean_title if clean_title else f"task_{uuid.uuid4().hex[:8]}"

        norm_status = status.strip().lower().replace("-", "_")

        subs: List[SubTask] = []
        if subtasks:
            for idx, st_title in enumerate(subtasks):
                subs.append(
                    SubTask(
                        id=str(uuid.uuid4()),
                        task_id=task_id,
                        title=st_title,
                        position=idx,
                        created_at=now,
                        updated_at=now
                    )
                )

        task = Task(
            id=task_id,
            title=title,
            description=description,
            created_at=now,
            updated_at=now,
            due_date=due_date,
            status_name=norm_status,
            priority=priority,
            category_id=category_id if category_id else None,
            estimated_duration_minutes=estimated_duration_minutes,
            time_spent_seconds=0,
            subtasks=subs
        )

        self.repository.save_task(task)
        return task


    def update_task_status(self, task_id: str, new_status: str) -> None:
        """
        Actualiza el estado de una tarea existente.

        Args:
            task_id: Identificador de la tarea.
            new_status: Nombre del nuevo estado.
        """
        norm_status = new_status.strip().lower().replace("-", "_")
        if hasattr(self.repository, "update_task_status_by_name"):
            self.repository.update_task_status_by_name(task_id, norm_status)
        else:
            # Fallback en caso de usar otra implementación
            task = self.repository.get_task_by_id(task_id)
            if task:
                task.status_name = norm_status
                self.repository.save_task(task)

    def delete_task(self, task_id: str) -> None:
        """
        Elimina permanentemente una tarea.

        Args:
            task_id: Identificador de la tarea.
        """
        self.repository.delete_task(task_id)

    def get_task(self, task_id: str) -> Optional[Task]:
        """
        Obtiene los detalles de una tarea específica.

        Args:
            task_id: Identificador de la tarea.

        Returns:
            Optional[Task]: Tarea encontrada o None.
        """
        return self.repository.get_task_by_id(task_id)

    def update_task_details(
        self,
        task_id: str,
        title: str,
        description: str = "",
        due_date: Optional[str] = None,
        status: Optional[str] = None,
        priority: Optional[int] = None,
        subtasks: Optional[List[SubTask]] = None,
        category_id: Optional[str] = None,
        estimated_duration_minutes: Optional[int] = None
    ) -> Optional[Task]:
        """
        Actualiza la información descriptiva, fecha límite, categoría y subtareas de una tarea existente
        (TAR-007, TAR-008, TAR-030).

        Args:
            task_id: Identificador de la tarea.
            title: Nuevo título.
            description: Nueva descripción.
            due_date: Nueva fecha límite en formato ISO o YYYY-MM-DD.
            status: Nombre del nuevo estado opcional.
            priority: Nivel de prioridad opcional.
            subtasks: Lista actualizada de subtareas opcional.
            category_id: Nueva categoría asignada o None/vacío para desasignar (TAR-030, TAR-031).
            estimated_duration_minutes: Nueva duración estimada en minutos opcional.

        Returns:
            Optional[Task]: Tarea actualizada o None si no existe.
        """
        task = self.repository.get_task_by_id(task_id)
        if not task:
            return None

        task.title = title
        task.description = description
        task.due_date = due_date
        task.category_id = category_id if category_id else None
        if estimated_duration_minutes is not None:
            task.estimated_duration_minutes = estimated_duration_minutes
        if status is not None:
            task.status_name = status.strip().lower().replace("-", "_")
        if priority is not None:
            task.priority = priority
        if subtasks is not None:
            task.subtasks = subtasks

        self.repository.save_task(task)
        return task

    def toggle_subtask_status(self, task_id: str, subtask_id: str, is_completed: bool) -> bool:
        """
        Modifica el estado completado/pendiente de una subtarea.

        Args:
            task_id: Identificador de la tarea padre.
            subtask_id: Identificador de la subtarea.
            is_completed: True si la subtarea fue completada, False si está pendiente.

        Returns:
            bool: True si la subtarea fue encontrada y actualizada con éxito.
        """
        task = self.repository.get_task_by_id(task_id)
        if not task:
            return False

        target_st = None
        for st in task.subtasks:
            if st.id == subtask_id:
                st.is_completed = is_completed
                target_st = st
                break

        if not target_st:
            return False

        if hasattr(self.repository, "save_subtask"):
            self.repository.save_subtask(target_st)
        else:
            self.repository.save_task(task)
        return True

    def reorder_subtasks(self, task_id: str, ordered_subtask_ids: List[str]) -> None:
        """
        Guarda el nuevo orden de las subtareas de una tarea.

        Args:
            task_id: Identificador de la tarea padre.
            ordered_subtask_ids: Identificadores en el orden deseado; los repetidos se descartan.
        """
        seen = set()
        unique_ids = []
        for subtask_id in ordered_subtask_ids:
            if subtask_id and subtask_id not in seen:
                seen.add(subtask_id)
                unique_ids.append(subtask_id)

        if not unique_ids:
            return
        self.repository.reorder_subtasks(task_id, unique_ids)

    def get_categories(self) -> List[Category]:
        """Recupera el catálogo completo de categorías disponibles (TAR-028)."""
        return self.repository.get_all_categories()

    def create_category(self, name: str, color: str = "#FFAA77") -> Category:
        """
        Registra una nueva categoría personalizada (TAR-027).

        Args:
            name: Nombre de la categoría (ej. 'Materias', 'Proyectos').
            color: Color hexadecimal asignado.

        Returns:
            Category: Instancia creada y persistida.
        """
        now = datetime.now().isoformat()
        cat_id = f"cat-{str(uuid.uuid4())[:8]}"
        category = Category(id=cat_id, name=name.strip(), color=color, created_at=now)
        self.repository.save_category(category)
        return category

    def delete_category(self, category_id: str) -> None:
        """Elimina una categoría del sistema."""
        self.repository.delete_category(category_id)

    def update_category(self, category_id: str, name: str) -> Optional[Category]:
        """Modifica el nombre de una categoría existente."""
        cats = self.repository.get_all_categories()
        target = next((c for c in cats if c.id == category_id), None)
        if target:
            target.name = name.strip()
            self.repository.save_category(target)
            return target
        return None

    def add_time_session(
        self,
        task_id: str,
        duration_seconds: int,
        started_at: str = "",
        ended_at: str = ""
    ) -> None:
        """
        Registra una sesión de tiempo transcurrido en el cronómetro y actualiza
        el acumulado total de la tarea (TAR-042, TAR-043).

        Args:
            task_id: Identificador de la tarea vinculada.
            duration_seconds: Tiempo efectivo registrado en segundos.
            started_at: Marca temporal de inicio de la sesión.
            ended_at: Marca temporal de finalización.
        """
        if duration_seconds <= 0:
            return

        now = datetime.now().isoformat()
        entry = TimeEntry(
            id=str(uuid.uuid4()),
            task_id=task_id,
            duration_seconds=duration_seconds,
            started_at=started_at or now,
            ended_at=ended_at or now,
            created_at=now
        )
        self.repository.add_time_entry(entry)

    def get_task_time_entries(self, task_id: str) -> List[TimeEntry]:
        """Obtiene el historial de sesiones de tiempo registradas para una tarea (TAR-042, TAR-043)."""
        return self.repository.get_time_entries_for_task(task_id)



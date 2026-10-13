from typing import Optional, List, Dict
from datetime import datetime
from PySide6.QtCore import QObject, Signal, QTimer
from core.matrix.ecosystems.tasks.use_cases.manage_tasks import TaskUseCases
from core.matrix.ecosystems.tasks.domain.entities import Task, Category, TimeEntry


class TasksViewModel(QObject):
    """
    ViewModel para el ecosistema de Tareas.

    Conecta la interfaz gráfica (Views) con los Casos de Uso (TaskUseCases)
    mediante el patrón reactivo de Qt Señales y Slots.
    Gestiona el estado reactivo del tablero Kanban, filtros de categoría y el cronómetro activo.
    """
    tasks_updated = Signal(dict)
    task_error = Signal(str)
    categories_updated = Signal(list)
    timer_tick = Signal(dict)
    timer_finished = Signal(str, str)
    timer_state_changed = Signal(dict)

    def __init__(self, use_cases: TaskUseCases):
        """
        Inicializa el ViewModel inyectando los casos de uso.

        Args:
            use_cases: Instancia de TaskUseCases que orquesta la lógica de negocio.
        """
        super().__init__()
        self._use_cases = use_cases
        self._selected_category_id: Optional[str] = None

        # Temporizador reactivo centralizado para cronómetro (TAR-038 a TAR-044)
        self._timer = QTimer(self)
        self._timer.setInterval(1000)
        self._timer.timeout.connect(self._on_timer_tick)
        self._active_timer: Optional[Dict] = None

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
        Carga las tareas agrupadas por estado respetando el filtro de categoría actual
        y emite la señal tasks_updated para notificar a la vista.
        """
        try:
            tasks_grouped = self._use_cases.get_tasks_grouped_by_status(
                category_id_filter=self._selected_category_id
            )
            self.tasks_updated.emit(tasks_grouped)
        except Exception as e:
            self.task_error.emit(f"Error al cargar tareas: {str(e)}")

    def get_selected_category_id(self) -> Optional[str]:
        """Devuelve el ID de la categoría actualmente filtrada o None si son todas."""
        return self._selected_category_id

    def filter_by_category(self, category_id: Optional[str]) -> None:
        """
        Aplica un filtro por categoría en el tablero Kanban (TAR-029).

        Args:
            category_id: ID de la categoría a mostrar, '__none__' para sin categoría, o None para todas.
        """
        self._selected_category_id = category_id
        self.load_tasks()

    def get_categories(self) -> List[Category]:
        """Obtiene la lista completa de categorías disponibles (TAR-028)."""
        try:
            return self._use_cases.get_categories()
        except Exception as e:
            self.task_error.emit(f"Error al obtener categorías: {str(e)}")
            return []

    def create_category(self, name: str, color: str = "#FFAA77") -> Optional[Category]:
        """
        Crea una nueva categoría personalizada (TAR-027).

        Args:
            name: Nombre de la categoría.
            color: Color hexadecimal asignado.

        Returns:
            Optional[Category]: Instancia creada o None en caso de fallo.
        """
        try:
            cat = self._use_cases.create_category(name=name, color=color)
            self.categories_updated.emit(self.get_categories())
            return cat
        except Exception as e:
            self.task_error.emit(f"Error al crear categoría: {str(e)}")
            return None

    def delete_category(self, category_id: str) -> None:
        """
        Elimina una categoría del catálogo.

        Args:
            category_id: Identificador de la categoría.
        """
        try:
            self._use_cases.delete_category(category_id)
            if self._selected_category_id == category_id:
                self._selected_category_id = None
            self.categories_updated.emit(self.get_categories())
            self.load_tasks()
        except Exception as e:
            self.task_error.emit(f"Error al eliminar categoría: {str(e)}")

    def update_category(self, category_id: str, name: str) -> Optional[Category]:
        """
        Modifica el nombre de una categoría existente y actualiza la vista.
        """
        try:
            cat = self._use_cases.update_category(category_id, name)
            self.categories_updated.emit(self.get_categories())
            self.load_tasks()
            return cat
        except Exception as e:
            self.task_error.emit(f"Error al editar categoría: {str(e)}")
            return None

    def create_new_task(
        self,
        title: str,
        description: str = "",
        due_date: Optional[str] = None,
        status: str = "pending",
        priority: int = 0,
        subtasks: Optional[list] = None,
        category_id: Optional[str] = None,
        estimated_duration_minutes: Optional[int] = None
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
            category_id: Categoría asignada opcional.
            estimated_duration_minutes: Duración estimada en minutos opcional.

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
                subtasks=subtasks,
                category_id=category_id,
                estimated_duration_minutes=estimated_duration_minutes
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
        Elimina una tarea y refresca la vista. Si tenía un cronómetro activo, lo detiene.

        Args:
            task_id: Identificador de la tarea.
        """
        try:
            if self._active_timer and self._active_timer.get("task_id") == task_id:
                self.stop_timer()
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
        subtasks: Optional[list] = None,
        category_id: Optional[str] = None,
        estimated_duration_minutes: Optional[int] = None
    ) -> bool:
        """
        Actualiza los datos descriptivos, categoría y tiempo estimado de una tarea y refresca el tablero.

        Args:
            task_id: Identificador de la tarea.
            title: Título modificado.
            description: Descripción detallada.
            due_date: Fecha límite de entrega opcional.
            status: Nombre del estado opcional.
            subtasks: Lista actualizada de subtareas opcional.
            category_id: Identificador de categoría o None para quitarla.
            estimated_duration_minutes: Tiempo estimado en minutos.

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
                subtasks=subtasks,
                category_id=category_id,
                estimated_duration_minutes=estimated_duration_minutes
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

    def reorder_subtasks(self, task_id: str, ordered_subtask_ids: list) -> bool:
        """
        Persiste de inmediato el orden de las subtareas tras un arrastre.

        No recarga el tablero: las tarjetas solo muestran contadores y no dependen del orden.

        Returns:
            bool: True si se guardó, False en caso de error.
        """
        try:
            self._use_cases.reorder_subtasks(task_id, ordered_subtask_ids)
            return True
        except Exception as e:
            self.task_error.emit(f"Error al reordenar subtareas: {str(e)}")
            return False

    # =========================================================================
    # SECCIÓN E: CRONÓMETRO Y SEGUIMIENTO DE TIEMPO (TAR-035 A TAR-044)
    # =========================================================================

    def get_active_timer(self) -> Optional[Dict]:
        """
        Devuelve el estado del cronómetro en ejecución actualmente, o None si no hay ninguno.
        """
        if self._active_timer:
            return self._active_timer.copy()
        return None

    def start_timer(self, task_id: str, duration_minutes: int) -> bool:
        """
        Inicia un cronómetro para una tarea con una duración fijada en minutos (TAR-035, TAR-038).
        Evita múltiples cronómetros simultáneos para la misma tarea (TAR-044).
        Si había un cronómetro corriendo para otra tarea, guarda su sesión primero.

        Args:
            task_id: Identificador de la tarea.
            duration_minutes: Tiempo disponible en minutos.

        Returns:
            bool: True si se inició correctamente, False si ya estaba activo en esta tarea.
        """
        if self._active_timer and self._active_timer.get("task_id") == task_id:
            # Ya existe un cronómetro activo para esta misma tarea (TAR-044)
            if self._active_timer.get("is_paused"):
                self.resume_timer()
                return True
            return False

        # Si había otra sesión corriendo, guardarla antes de iniciar la nueva
        if self._active_timer:
            self.stop_timer()

        task = self.get_task_by_id(task_id)
        task_title = task.title if task else "Tarea"
        total_seconds = max(60, duration_minutes * 60)

        now = datetime.now().isoformat()
        self._active_timer = {
            "task_id": task_id,
            "task_title": task_title,
            "total_seconds": total_seconds,
            "remaining_seconds": total_seconds,
            "elapsed_seconds": 0,
            "is_paused": False,
            "started_at": now
        }

        self._timer.start()
        self.timer_state_changed.emit(self._active_timer.copy())
        return True

    def pause_timer(self) -> None:
        """Pausa el cronómetro actualmente activo (TAR-039)."""
        if self._active_timer and not self._active_timer.get("is_paused"):
            self._active_timer["is_paused"] = True
            self._timer.stop()
            self.timer_state_changed.emit(self._active_timer.copy())

    def resume_timer(self) -> None:
        """Reanuda el cronómetro en pausa (TAR-039)."""
        if self._active_timer and self._active_timer.get("is_paused"):
            self._active_timer["is_paused"] = False
            self._timer.start()
            self.timer_state_changed.emit(self._active_timer.copy())

    def stop_timer(self) -> None:
        """
        Detiene el cronómetro actual sin registrar sesión en el historial.
        El registro del historial de sesiones se realiza únicamente de forma interna
        cuando el contador finaliza su ciclo completo (desde su ejecución hasta su término).
        """
        if not self._active_timer:
            return

        self._timer.stop()
        self._active_timer = None
        self.timer_state_changed.emit({})
        self.load_tasks()

    def _on_timer_tick(self) -> None:
        """Slot ejecutado cada segundo para actualizar el cronómetro activo."""
        if not self._active_timer or self._active_timer.get("is_paused"):
            return

        self._active_timer["elapsed_seconds"] += 1
        self._active_timer["remaining_seconds"] -= 1

        self.timer_tick.emit(self._active_timer.copy())

        # Si se agotó el tiempo establecido (TAR-041)
        if self._active_timer["remaining_seconds"] <= 0:
            self._timer.stop()
            task_id = self._active_timer["task_id"]
            task_title = self._active_timer["task_title"]
            elapsed = self._active_timer["elapsed_seconds"]
            started_at = self._active_timer["started_at"]
            ended_at = datetime.now().isoformat()

            # Guardar sesión en base de datos
            try:
                self._use_cases.add_time_session(
                    task_id=task_id,
                    duration_seconds=elapsed,
                    started_at=started_at,
                    ended_at=ended_at
                )
            except Exception:
                pass

            self._active_timer = None
            self.timer_finished.emit(task_id, task_title)
            self.timer_state_changed.emit({})
            self.load_tasks()

    def get_task_time_entries(self, task_id: str) -> List[TimeEntry]:
        """
        Recupera el historial de sesiones de tiempo registradas para una tarea (TAR-042).
        """
        try:
            return self._use_cases.get_task_time_entries(task_id)
        except Exception as e:
            self.task_error.emit(f"Error al obtener sesiones de tiempo: {str(e)}")
            return []

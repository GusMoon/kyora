import os
import json
import uuid
from datetime import datetime
from typing import List, Optional, Dict
from core.matrix.motherboard.ecosystems.tasks.domain.entities import Task, SubTask, TaskStatus, Category, TimeEntry
from core.matrix.motherboard.ecosystems.tasks.domain.repositories import TaskRepository
from core.matrix.motherboard.ecosystems.tasks.infrastructure.database import DatabaseManager


class SqliteTaskRepository(TaskRepository):
    """
    Implementación concreta de TaskRepository respaldada por SQLite.

    Gestiona la persistencia relacional de tareas, subtareas y estados respetando
    integridad referencial, transacciones ACID y sincronización opcional con archivos .task.
    """

    def __init__(self, config_path: str = "", db_manager: Optional[DatabaseManager] = None):
        """
        Inicializa el repositorio con configuración opcional y DatabaseManager.

        Args:
            config_path: Ruta al archivo JSON de configuración global.
            db_manager: Administrador de base de datos. Si no se suministra, se crea uno por defecto.
        """
        self.config_path = config_path
        self.directory_path = ""
        self.db_manager = db_manager if db_manager is not None else DatabaseManager()
        
        self._load_config()
        self._migrate_existing_files_if_needed()

    def _load_config(self) -> None:
        """Carga la ruta del directorio de tareas desde el archivo de configuración."""
        if self.config_path and os.path.exists(self.config_path):
            try:
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    self.directory_path = config.get("tasks_directory", "")
            except Exception:
                pass

    def _save_config(self) -> None:
        """Persiste la configuración del directorio en el archivo JSON."""
        if not self.config_path:
            return
        config = {}
        if os.path.exists(self.config_path):
            try:
                with open(self.config_path, 'r', encoding='utf-8') as f:
                    config = json.load(f)
            except Exception:
                pass
        config["tasks_directory"] = self.directory_path
        try:
            with open(self.config_path, 'w', encoding='utf-8') as f:
                json.dump(config, f, indent=4)
        except Exception:
            pass

    def set_directory(self, path: str) -> None:
        """
        Establece y persiste el directorio de almacenamiento de archivos de tareas.

        Args:
            path: Ruta del directorio.
        """
        self.directory_path = path
        if not os.path.exists(self.directory_path):
            try:
                os.makedirs(self.directory_path, exist_ok=True)
            except Exception:
                pass
        self._save_config()
        self._migrate_existing_files_if_needed()

    def _migrate_existing_files_if_needed(self) -> None:
        """
        Importa automáticamente tareas desde archivos .task a SQLite
        si la base de datos está vacía y existen archivos en el directorio.
        """
        if not self.directory_path or not os.path.exists(self.directory_path):
            return

        # Solo migramos si la base de datos aún no tiene tareas
        existing = self.get_all_tasks()
        if existing:
            return

        try:
            for filename in os.listdir(self.directory_path):
                if filename.endswith(".task"):
                    filepath = os.path.join(self.directory_path, filename)
                    try:
                        with open(filepath, 'r', encoding='utf-8') as f:
                            content = f.read()
                        task_id = filename.replace(".task", "")
                        task = Task.from_markdown(content, task_id)
                        self.save_task(task)
                    except Exception:
                        pass
        except Exception:
            pass

    def get_statuses(self) -> List[TaskStatus]:
        """
        Obtiene el catálogo de estados disponibles.

        Returns:
            List[TaskStatus]: Colección ordenada de estados.
        """
        query = "SELECT id, name, color FROM task_statuses ORDER BY id ASC;"
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            rows = cursor.execute(query).fetchall()
            return [
                TaskStatus(id=row["id"], name=row["name"], color=row["color"])
                for row in rows
            ]

    def get_status_id_by_name(self, status_name: str) -> int:
        """
        Normaliza y busca el identificador de estado según su nombre.
        Soporta 'in-progress' normalizándolo a 'in_progress'.

        Args:
            status_name: Nombre del estado ('pending', 'in_progress', 'completed').

        Returns:
            int: ID numérico del estado o 1 si no se encuentra.
        """
        normalized = status_name.strip().lower().replace("-", "_")
        query = "SELECT id FROM task_statuses WHERE name = ?;"
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            row = cursor.execute(query, (normalized,)).fetchone()
            if row:
                return row["id"]
        return 1

    def get_all_tasks(self) -> List[Task]:
        """
        Recupera todas las tareas registradas con sus respectivas subtareas.

        Returns:
            List[Task]: Lista de entidades Task pobladas con sus subtareas.
        """
        tasks_query = """
        SELECT t.id, t.title, t.description, t.status_id, t.priority,
               t.due_date, t.category_id, t.estimated_duration_minutes, t.time_spent_seconds,
               t.created_at, t.updated_at, s.name as status_name,
               c.name as category_name, c.color as category_color
        FROM tasks t
        JOIN task_statuses s ON t.status_id = s.id
        LEFT JOIN categories c ON t.category_id = c.id
        ORDER BY t.created_at DESC;
        """
        subtasks_query = """
        SELECT id, task_id, title, description, is_completed, position, created_at, updated_at
        FROM subtasks
        ORDER BY task_id, position ASC, created_at ASC, rowid ASC;
        """

        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            task_rows = cursor.execute(tasks_query).fetchall()
            subtask_rows = cursor.execute(subtasks_query).fetchall()

        subtasks_map: Dict[str, List[SubTask]] = {}
        for row in subtask_rows:
            st = SubTask(
                id=row["id"],
                task_id=row["task_id"],
                title=row["title"],
                description=row["description"] or "",
                is_completed=bool(row["is_completed"]),
                position=row["position"],
                created_at=row["created_at"] or "",
                updated_at=row["updated_at"] or ""
            )
            subtasks_map.setdefault(row["task_id"], []).append(st)

        tasks = []
        for row in task_rows:
            t_id = row["id"]
            task = Task(
                id=t_id,
                title=row["title"],
                description=row["description"] or "",
                status_id=row["status_id"],
                status_name=row["status_name"],
                priority=row["priority"] or 0,
                due_date=row["due_date"],
                category_id=row["category_id"],
                category_name=row["category_name"],
                category_color=row["category_color"],
                estimated_duration_minutes=row["estimated_duration_minutes"],
                time_spent_seconds=row["time_spent_seconds"] or 0,
                created_at=row["created_at"] or "",
                updated_at=row["updated_at"] or "",
                subtasks=subtasks_map.get(t_id, [])
            )
            tasks.append(task)

        return tasks

    def get_task_by_id(self, task_id: str) -> Optional[Task]:
        """
        Recupera una tarea individual junto a sus subtareas por su identificador único.

        Args:
            task_id: Identificador de la tarea.

        Returns:
            Optional[Task]: Tarea encontrada o None.
        """
        task_query = """
        SELECT t.id, t.title, t.description, t.status_id, t.priority,
               t.due_date, t.category_id, t.estimated_duration_minutes, t.time_spent_seconds,
               t.created_at, t.updated_at, s.name as status_name,
               c.name as category_name, c.color as category_color
        FROM tasks t
        JOIN task_statuses s ON t.status_id = s.id
        LEFT JOIN categories c ON t.category_id = c.id
        WHERE t.id = ?;
        """
        subtasks_query = """
        SELECT id, task_id, title, description, is_completed, position, created_at, updated_at
        FROM subtasks
        WHERE task_id = ?
        ORDER BY position ASC, created_at ASC, rowid ASC;
        """

        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            row = cursor.execute(task_query, (task_id,)).fetchone()
            if not row:
                return None

            subtask_rows = cursor.execute(subtasks_query, (task_id,)).fetchall()

        subtasks = [
            SubTask(
                id=st["id"],
                task_id=st["task_id"],
                title=st["title"],
                description=st["description"] or "",
                is_completed=bool(st["is_completed"]),
                position=st["position"],
                created_at=st["created_at"] or "",
                updated_at=st["updated_at"] or ""
            )
            for st in subtask_rows
        ]

        return Task(
            id=row["id"],
            title=row["title"],
            description=row["description"] or "",
            status_id=row["status_id"],
            status_name=row["status_name"],
            priority=row["priority"] or 0,
            due_date=row["due_date"],
            category_id=row["category_id"],
            category_name=row["category_name"],
            category_color=row["category_color"],
            estimated_duration_minutes=row["estimated_duration_minutes"],
            time_spent_seconds=row["time_spent_seconds"] or 0,
            created_at=row["created_at"] or "",
            updated_at=row["updated_at"] or "",
            subtasks=subtasks
        )


    def save_task(self, task: Task) -> None:
        """
        Persiste una tarea e inserta/actualiza sus subtareas asociadas en SQLite.
        Si hay un directorio configurado, sincroniza el archivo .task correspondiente.

        Args:
            task: Instancia de tarea a registrar.
        """
        now = datetime.now().isoformat()
        if not task.id:
            task.id = str(uuid.uuid4())
        if not task.created_at:
            task.created_at = now
        task.updated_at = now

        if task.status_name:
            task.status_id = self.get_status_id_by_name(task.status_name)

        upsert_task_sql = """
        INSERT INTO tasks (
            id, title, description, status_id, priority, due_date,
            category_id, estimated_duration_minutes, time_spent_seconds,
            created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            description = excluded.description,
            status_id = excluded.status_id,
            priority = excluded.priority,
            due_date = excluded.due_date,
            category_id = excluded.category_id,
            estimated_duration_minutes = excluded.estimated_duration_minutes,
            time_spent_seconds = excluded.time_spent_seconds,
            updated_at = excluded.updated_at;
        """

        upsert_subtask_sql = """
        INSERT INTO subtasks (id, task_id, title, description, is_completed, position, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            description = excluded.description,
            is_completed = excluded.is_completed,
            position = excluded.position,
            updated_at = excluded.updated_at;
        """

        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                upsert_task_sql,
                (
                    task.id,
                    task.title,
                    task.description,
                    task.status_id,
                    task.priority,
                    task.due_date,
                    task.category_id,
                    task.estimated_duration_minutes,
                    task.time_spent_seconds,
                    task.created_at,
                    task.updated_at
                )
            )


            current_subtask_ids = []
            for idx, st in enumerate(task.subtasks):
                if not st.id:
                    st.id = str(uuid.uuid4())
                st.task_id = task.id
                st.position = idx
                if not st.created_at:
                    st.created_at = now
                st.updated_at = now

                current_subtask_ids.append(st.id)
                cursor.execute(
                    upsert_subtask_sql,
                    (
                        st.id,
                        st.task_id,
                        st.title,
                        st.description,
                        1 if st.is_completed else 0,
                        st.position,
                        st.created_at,
                        st.updated_at
                    )
                )

            if current_subtask_ids:
                placeholders = ",".join("?" for _ in current_subtask_ids)
                cursor.execute(
                    f"DELETE FROM subtasks WHERE task_id = ? AND id NOT IN ({placeholders});",
                    [task.id, *current_subtask_ids]
                )
            else:
                cursor.execute("DELETE FROM subtasks WHERE task_id = ?;", (task.id,))

        # Sincronización opcional con archivo .task para visores de archivos
        if self.directory_path and os.path.exists(self.directory_path):
            filepath = os.path.join(self.directory_path, f"{task.id}.task")
            try:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(task.to_markdown())
            except Exception:
                pass

    def update_task_status(self, task_id: str, new_status_id: int) -> None:
        """
        Modifica el estado de una tarea por ID de estado numérico.

        Args:
            task_id: Identificador de la tarea.
            new_status_id: Nuevo ID de estado (1, 2 o 3).
        """
        sql = "UPDATE tasks SET status_id = ?, updated_at = datetime('now') WHERE id = ?;"
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(sql, (new_status_id, task_id))

        # Sincronizar archivo .task si existe
        if self.directory_path and os.path.exists(self.directory_path):
            task = self.get_task_by_id(task_id)
            if task:
                filepath = os.path.join(self.directory_path, f"{task.id}.task")
                try:
                    with open(filepath, 'w', encoding='utf-8') as f:
                        f.write(task.to_markdown())
                except Exception:
                    pass

    def update_task_status_by_name(self, task_id: str, new_status_name: str) -> None:
        """
        Modifica el estado de una tarea recibiendo el nombre textual del estado.

        Args:
            task_id: Identificador de la tarea.
            new_status_name: Nombre del nuevo estado ('pending', 'in_progress', 'completed').
        """
        status_id = self.get_status_id_by_name(new_status_name)
        self.update_task_status(task_id, status_id)

    def delete_task(self, task_id: str) -> None:
        """
        Elimina una tarea de la base de datos y su archivo .task asociado si existe.

        Args:
            task_id: Identificador de la tarea a remover.
        """
        sql = "DELETE FROM tasks WHERE id = ?;"
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(sql, (task_id,))

        if self.directory_path and os.path.exists(self.directory_path):
            filepath = os.path.join(self.directory_path, f"{task_id}.task")
            if os.path.exists(filepath):
                try:
                    os.remove(filepath)
                except Exception:
                    pass

    def save_subtask(self, subtask: SubTask) -> None:
        """
        Inserta o actualiza una subtarea individual.

        Args:
            subtask: Instancia de SubTask.
        """
        now = datetime.now().isoformat()
        if not subtask.id:
            subtask.id = str(uuid.uuid4())
        if not subtask.created_at:
            subtask.created_at = now
        subtask.updated_at = now

        sql = """
        INSERT INTO subtasks (id, task_id, title, description, is_completed, position, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            description = excluded.description,
            is_completed = excluded.is_completed,
            position = excluded.position,
            updated_at = excluded.updated_at;
        """
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(
                sql,
                (
                    subtask.id,
                    subtask.task_id,
                    subtask.title,
                    subtask.description,
                    1 if subtask.is_completed else 0,
                    subtask.position,
                    subtask.created_at,
                    subtask.updated_at
                )
            )

    def reorder_subtasks(self, task_id: str, ordered_subtask_ids: List[str]) -> None:
        """
        Persiste el orden de las subtareas de una tarea en una sola transacción.

        Los identificadores que aún no existen en la base (subtareas añadidas en un diálogo
        sin guardar) se ignoran; recibirán su posición cuando la tarea se guarde.

        Args:
            task_id: Identificador de la tarea propietaria.
            ordered_subtask_ids: Identificadores de subtareas en el orden deseado.
        """
        now = datetime.now().isoformat()
        sql = "UPDATE subtasks SET position = ?, updated_at = ? WHERE id = ? AND task_id = ?;"
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            for position, subtask_id in enumerate(ordered_subtask_ids):
                cursor.execute(sql, (position, now, subtask_id, task_id))

    def delete_subtask(self, subtask_id: str) -> None:
        """
        Elimina una subtarea individual por su identificador.

        Args:
            subtask_id: Identificador de la subtarea.
        """
        sql = "DELETE FROM subtasks WHERE id = ?;"
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(sql, (subtask_id,))

    def get_all_categories(self) -> List[Category]:
        """Obtiene el catálogo de categorías disponibles."""
        sql = "SELECT id, name, color, created_at FROM categories ORDER BY name ASC;"
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            rows = cursor.execute(sql).fetchall()
            return [
                Category(
                    id=row["id"],
                    name=row["name"],
                    color=row["color"] or "#FFAA77",
                    created_at=row["created_at"] or ""
                )
                for row in rows
            ]

    def save_category(self, category: Category) -> None:
        """Registra o actualiza una categoría en la base de datos."""
        now = datetime.now().isoformat()
        if not category.id:
            category.id = f"cat-{str(uuid.uuid4())[:8]}"
        if not category.created_at:
            category.created_at = now

        sql = """
        INSERT INTO categories (id, name, color, created_at)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            color = excluded.color;
        """
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(sql, (category.id, category.name, category.color, category.created_at))

    def delete_category(self, category_id: str) -> None:
        """Elimina una categoría por su identificador y desvincula las tareas asociadas."""
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("UPDATE tasks SET category_id = NULL WHERE category_id = ?;", (category_id,))
            cursor.execute("DELETE FROM categories WHERE id = ?;", (category_id,))

    def add_time_entry(self, entry: TimeEntry) -> None:
        """
        Registra una sesión de cronómetro e incrementa transaccionalmente
        el tiempo total acumulado (time_spent_seconds) en la tarea.
        """
        now = datetime.now().isoformat()
        if not entry.id:
            entry.id = str(uuid.uuid4())
        if not entry.created_at:
            entry.created_at = now

        sql_entry = """
        INSERT INTO time_entries (id, task_id, duration_seconds, started_at, ended_at, created_at)
        VALUES (?, ?, ?, ?, ?, ?);
        """
        sql_update_task = """
        UPDATE tasks
        SET time_spent_seconds = COALESCE(time_spent_seconds, 0) + ?,
            updated_at = ?
        WHERE id = ?;
        """
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute(sql_entry, (
                entry.id, entry.task_id, entry.duration_seconds,
                entry.started_at, entry.ended_at, entry.created_at
            ))
            cursor.execute(sql_update_task, (entry.duration_seconds, now, entry.task_id))

    def get_time_entries_for_task(self, task_id: str) -> List[TimeEntry]:
        """Recupera el historial de registros de tiempo asociados a una tarea."""
        sql = """
        SELECT id, task_id, duration_seconds, started_at, ended_at, created_at
        FROM time_entries
        WHERE task_id = ?
        ORDER BY created_at DESC;
        """
        with self.db_manager.get_connection() as conn:
            cursor = conn.cursor()
            rows = cursor.execute(sql, (task_id,)).fetchall()
            return [
                TimeEntry(
                    id=row["id"],
                    task_id=row["task_id"],
                    duration_seconds=row["duration_seconds"],
                    started_at=row["started_at"] or "",
                    ended_at=row["ended_at"] or "",
                    created_at=row["created_at"] or ""
                )
                for row in rows
            ]


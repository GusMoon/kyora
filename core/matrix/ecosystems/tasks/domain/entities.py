from dataclasses import dataclass, field
from typing import List, Optional
from datetime import datetime


@dataclass
class TaskStatus:
    """
    Representa un estado catalogado en el sistema de tareas.

    Attributes:
        id: Identificador numérico del estado.
        name: Clave textual del estado (ej. 'pending', 'in_progress', 'completed').
        color: Código de color hexadecimal para representación en interfaz de usuario.
    """
    id: int
    name: str
    color: Optional[str] = None


@dataclass
class Category:
    """
    Representa una categoría de clasificación para tareas.

    Attributes:
        id: Identificador único de la categoría.
        name: Nombre descriptivo de la categoría.
        color: Código de color hexadecimal para la interfaz de usuario.
        created_at: Fecha de creación en formato ISO-8601.
    """
    name: str
    id: str = ""
    color: Optional[str] = "#FFAA77"
    created_at: str = ""


@dataclass
class TimeEntry:
    """
    Representa un registro de sesión de tiempo invertido en una tarea.

    Attributes:
        id: Identificador único del registro de tiempo.
        task_id: Identificador de la tarea vinculada.
        duration_seconds: Duración efectiva de la sesión en segundos.
        started_at: Marca temporal de inicio en formato ISO-8601.
        ended_at: Marca temporal de fin en formato ISO-8601.
        created_at: Marca temporal de creación en formato ISO-8601.
    """
    task_id: str
    duration_seconds: int
    id: str = ""
    started_at: str = ""
    ended_at: str = ""
    created_at: str = ""


@dataclass
class SubTask:
    """
    Representa una subtarea perteneciente a una tarea principal.

    Attributes:
        id: Identificador único (UUID o slug).
        task_id: Identificador de la tarea padre.
        title: Nombre de la subtarea.
        description: Descripción opcional con detalles adicionales.
        is_completed: Indica si la subtarea fue finalizada.
        position: Índice de ordenamiento para la visualización en listas.
        created_at: Marca temporal de creación en formato ISO-8601.
        updated_at: Marca temporal de última modificación en formato ISO-8601.
    """
    title: str
    id: str = ""
    task_id: str = ""
    description: Optional[str] = ""
    is_completed: bool = False
    position: int = 0
    created_at: str = ""
    updated_at: str = ""


@dataclass
class Task:
    """
    Entidad principal de tarea en el dominio de Kiora.

    Attributes:
        id: Identificador único de la tarea.
        title: Título o nombre descriptivo.
        description: Descripción detallada de la actividad.
        status_id: Clave foránea al catálogo de estados (1=pending, 2=in_progress, 3=completed).
        status_name: Nombre legible del estado actual.
        priority: Nivel de prioridad de la tarea (0=normal, mayor=más urgente).
        due_date: Fecha límite de entrega en formato ISO-8601 o YYYY-MM-DD.
        category_id: Clave de la categoría asignada (opcional).
        category_name: Nombre legible de la categoría.
        category_color: Color distintivo de la categoría.
        estimated_duration_minutes: Duración estimada total en minutos.
        time_spent_seconds: Tiempo total invertido acumulado en segundos.
        created_at: Marca temporal de creación.
        updated_at: Marca temporal de última modificación.
        subtasks: Colección de subtareas asociadas.
        raw_tasks_text: Bloque de texto plano para compatibilidad con visores Markdown.
    """
    id: str
    title: str
    description: str = ""
    status_id: int = 1
    status_name: str = "pending"
    priority: int = 0
    due_date: Optional[str] = None
    category_id: Optional[str] = None
    category_name: Optional[str] = None
    category_color: Optional[str] = None
    estimated_duration_minutes: Optional[int] = None
    time_spent_seconds: int = 0
    created_at: str = ""
    updated_at: str = ""
    subtasks: List[SubTask] = field(default_factory=list)
    raw_tasks_text: str = ""

    # Propiedades de compatibilidad con código preexistente
    @property
    def status(self) -> str:
        """Alias para mantener compatibilidad con componentes que leen task.status."""
        return self.status_name

    @status.setter
    def status(self, val: str) -> None:
        self.status_name = val

    @property
    def creation_date(self) -> str:
        """Alias para mantener compatibilidad con componentes que leen creation_date."""
        return self.created_at

    @creation_date.setter
    def creation_date(self, val: str) -> None:
        self.created_at = val

    def to_markdown(self) -> str:
        """
        Serializa la tarea al formato Markdown tradicional de Kiora (.task).

        Returns:
            str: Contenido formateado con metadatos y lista de tareas.
        """
        lines = []
        lines.append(f"Status: {self.status_name}")
        
        start = self.created_at[:10] if self.created_at else ""
        end = self.due_date[:10] if self.due_date else ""
        lines.append(f"Start Date: {start}")
        if end:
            lines.append(f"End Date: {end}")
        lines.append("")
        
        if self.description:
            lines.append("Description:")
            lines.append(self.description)
            lines.append("")
            
        lines.append("Tasks:")
        if self.raw_tasks_text:
            lines.append(self.raw_tasks_text)
        else:
            for st in self.subtasks:
                mark = "x" if st.is_completed else " "
                lines.append(f"- [{mark}] {st.title}")
            
        return "\n".join(lines)

    @staticmethod
    def from_markdown(content: str, task_id: str) -> "Task":
        """
        Construye una entidad Task a partir del contenido de un archivo Markdown.

        Args:
            content: Texto plano del archivo .task.
            task_id: Identificador asignado a la tarea.

        Returns:
            Task: Instancia reconstruida.
        """
        lines = content.split('\n')
        status = "pending"
        start_date = ""
        end_date = ""
        desc_lines = []
        subtasks = []
        raw_tasks = []
        
        in_desc = False
        in_tasks = False
        
        for line in lines:
            line_s = line.strip()
            if line_s.startswith("Status:"):
                status = line_s.replace("Status:", "").strip()
            elif line_s.startswith("Start Date:"):
                start_date = line_s.replace("Start Date:", "").strip()
            elif line_s.startswith("End Date:"):
                end_date = line_s.replace("End Date:", "").strip()
            elif line_s == "Description:":
                in_desc = True
                in_tasks = False
            elif line_s == "Tasks:":
                in_desc = False
                in_tasks = True
            elif in_desc:
                desc_lines.append(line_s)
            elif in_tasks:
                raw_tasks.append(line)
                if line_s.startswith("- ["):
                    is_done = "- [x]" in line_s.lower()
                    text = line_s.split("]", 1)[1].strip()
                    subtasks.append(SubTask(title=text, is_completed=is_done))
                
        return Task(
            id=task_id,
            title=task_id,
            created_at=start_date,
            description="\n".join(desc_lines).strip(),
            due_date=end_date if end_date else None,
            status_name=status,
            subtasks=subtasks,
            raw_tasks_text="\n".join(raw_tasks).strip()
        )

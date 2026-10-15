from dataclasses import dataclass, field
from typing import List, Tuple

EVENT_KINDS = ("event", "birthday")
RECURRENCES = ("none", "yearly")
ITEM_KINDS = ("task", "event", "birthday", "reminder")


@dataclass
class CalendarEvent:
    """
    Evento personal o fecha importante, independiente de las tareas.

    Attributes:
        title: Nombre del evento.
        event_date: Fecha ISO (AAAA-MM-DD). En eventos anuales es la fecha original.
        start_time: Hora de inicio "HH:MM"; vacía si dura todo el día.
        end_time: Hora de fin "HH:MM"; vacía si no se definió.
        description: Texto opcional.
        kind: "event" o "birthday".
        recurrence: "none" o "yearly".
        id: Identificador único (vacío si aún no se ha persistido).
        created_at: Marca temporal de creación.
    """
    title: str
    event_date: str
    start_time: str = ""
    end_time: str = ""
    description: str = ""
    kind: str = "event"
    recurrence: str = "none"
    id: str = ""
    created_at: str = ""


@dataclass
class Reminder:
    """
    Recordatorio con fecha y hora, independiente o asociado a un evento.

    Attributes:
        text: Motivo que se muestra al notificar.
        remind_at: Fecha y hora ISO "AAAA-MM-DDTHH:MM".
        id: Identificador único (vacío si aún no se ha persistido).
        event_id: Evento que lo originó; vacío si es independiente.
        advance_minutes: Minutos de anticipación respecto al evento, si aplica.
        notified_at: Marca temporal en que se notificó; vacía si está pendiente.
    """
    text: str
    remind_at: str
    id: str = ""
    event_id: str = ""
    advance_minutes: int = 0
    notified_at: str = ""


@dataclass
class Notification:
    """
    Aviso generado al disparar un recordatorio.

    Se guarda en una bandeja de salida para que un mecanismo futuro (celular)
    pueda entregarlo, sabiendo qué actividad lo originó.

    Attributes:
        reminder_id: Recordatorio que lo disparó.
        source_type: "event" o "reminder".
        source_id: Identificador del evento o recordatorio de origen.
        title: Título corto del aviso.
        body: Detalle del aviso.
    """
    reminder_id: str
    source_type: str
    source_id: str
    title: str
    body: str


@dataclass
class TaskItem:
    """
    Vista de solo lectura de una tarea del ecosistema Tareas.

    Attributes:
        task_id: Identificador de la tarea original.
        title: Título de la tarea.
        due_date: Fecha límite ISO (AAAA-MM-DD).
        due_time: Hora "HH:MM" si la fecha límite incluye hora; vacía si no.
        status: "pending", "in_progress" o "completed".
        description: Descripción de la tarea.
        subtasks: Subtareas como tuplas `(título, completada)`.
    """
    task_id: str
    title: str
    due_date: str
    due_time: str = ""
    status: str = "pending"
    description: str = ""
    subtasks: List[Tuple[str, bool]] = field(default_factory=list)


@dataclass
class AgendaItem:
    """
    Actividad ya preparada para mostrarse en el calendario.

    Attributes:
        kind: "task", "event", "birthday" o "reminder".
        title: Texto principal.
        item_date: Fecha ISO en la que se muestra.
        time: Hora "HH:MM"; vacía si es de todo el día o es una fecha límite.
        end_time: Hora de fin "HH:MM", si existe.
        source_id: Identificador del elemento original (tarea, evento o recordatorio).
        status: Estado de la tarea; vacío en el resto.
        overdue: True si es una tarea vencida sin completar.
        detail: Descripción opcional.
        recurring: True si se repite cada año.
        checklist: Subtareas `(título, completada)` de una tarea, en solo lectura.
    """
    kind: str
    title: str
    item_date: str
    time: str = ""
    end_time: str = ""
    source_id: str = ""
    status: str = ""
    overdue: bool = False
    detail: str = ""
    recurring: bool = False
    checklist: List[Tuple[str, bool]] = field(default_factory=list)

"""
Módulo principal taskMetadataMain que orquesta y expone los componentes de metadatos de tareas.
"""
from .base_modal import SciFiBaseModal
from .folder_container import FolderContainer
from .fading_text_edit import FadingScrollTextEdit, FadingScrollArea, ScrollFadeOverlay

# Submódulo General (parámetros de tarea, categorías, switch y diálogos principales)
from .general import (
    PillToggleSwitch,
    CategoryCreateDialog,
    TaskCreateDialog,
    TaskDetailDialog,
    DescriptionReader,
)

# Submódulo SubTasks (gestión de subtareas)
from .subTasks import (
    SubtaskEditorItem,
    AutoResizeSubtaskEdit,
)

# Submódulo Chronometer (diálogos y controles de tiempo)
from .chronometer import (
    TimerDurationDialog,
)

__all__ = [
    "SciFiBaseModal",
    "PillToggleSwitch",
    "FolderContainer",
    "SubtaskEditorItem",
    "AutoResizeSubtaskEdit",
    "TaskCreateDialog",
    "TaskDetailDialog",
    "FadingScrollTextEdit",
    "FadingScrollArea",
    "ScrollFadeOverlay",
    "CategoryCreateDialog",
    "TimerDurationDialog",
    "DescriptionReader",
]

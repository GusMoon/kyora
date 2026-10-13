"""
Módulo principal taskMetadataMain que orquesta y expone los componentes de metadatos de tareas.
"""
from .base_modal import SciFiBaseModal
from .toggle_switch import PillToggleSwitch
from .folder_container import FolderContainer
from .subtask_item import SubtaskEditorItem
from .task_create_dialog import TaskCreateDialog
from .task_detail_dialog import TaskDetailDialog
from .fading_text_edit import FadingScrollTextEdit, FadingScrollArea, ScrollFadeOverlay
from .category_dialog import CategoryCreateDialog
from .timer_dialog import TimerDurationDialog

__all__ = [
    "SciFiBaseModal",
    "PillToggleSwitch",
    "FolderContainer",
    "SubtaskEditorItem",
    "TaskCreateDialog",
    "TaskDetailDialog",
    "FadingScrollTextEdit",
    "FadingScrollArea",
    "ScrollFadeOverlay",
    "CategoryCreateDialog",
    "TimerDurationDialog",
]

"""
Submódulo general de taskMetadata (información general, categorías, fecha límite y diálogos principales).
"""
from .toggle_switch import PillToggleSwitch
from .category_dialog import CategoryCreateDialog
from .task_create_dialog import TaskCreateDialog
from .task_detail_dialog import TaskDetailDialog
from .description_reader import DescriptionReader
from .workspace_panel import WorkspacePanel

__all__ = [
    "DescriptionReader",
    "WorkspacePanel",
    "PillToggleSwitch",
    "CategoryCreateDialog",
    "TaskCreateDialog",
    "TaskDetailDialog",
]

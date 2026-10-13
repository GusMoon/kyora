"""
Módulo de metadatos y diálogos de tareas (taskMetadata).
Expone los componentes principales a través de taskMetadataMain.
"""
from .taskMetadataMain import (
    SciFiBaseModal,
    PillToggleSwitch,
    FolderContainer,
    SubtaskEditorItem,
    TaskCreateDialog,
    TaskDetailDialog,
    FadingScrollTextEdit,
    FadingScrollArea,
    ScrollFadeOverlay,
)

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
]

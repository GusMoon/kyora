from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, 
    QScrollArea, QPushButton, QFileDialog, QDialog
)
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QPainter, QColor

from core.matrix.ecosystems.tasks.presentation.tasks_viewmodel import TasksViewModel
from core.matrix.ecosystems.tasks.presentation.task_card import TaskCard
from core.matrix.ecosystems.tasks.presentation.task_dialogs import TaskCreateDialog, TaskDetailDialog
from core.matrix.ecosystems.motherBoard.globalComponents.styles import get_minimal_scrollbar_style
from core.matrix.ecosystems.motherBoard.globalComponents.simple_dialogs import SciFiConfirmDialog


class DropColumn(QWidget):
    add_task_requested = Signal(str)

    def __init__(self, status: str, viewmodel: TasksViewModel):
        super().__init__()
        self.status = status
        self.viewmodel = viewmodel
        self.setAcceptDrops(True)
        self.setFixedWidth(380)

        self.setStyleSheet("background-color: transparent;")

        layout = QVBoxLayout(self)
        layout.setContentsMargins(5, 5, 5, 5)

        # Botón de encabezado de columna
        self.title_btn = QPushButton(status.upper().replace("_", " "))
        self.title_btn.setStyleSheet("""
            QPushButton { 
                color: #FFFFFF; 
                font-weight: bold; 
                font-size: 15px; 
                font-family: 'Space Grotesk'; 
                border: none; 
                background: transparent; 
                padding: 6px; 
                letter-spacing: 1px;
            }
            QPushButton:hover { 
                color: #A31F34; 
            }
        """)
        self.title_btn.setCursor(Qt.PointingHandCursor)
        self.title_btn.setToolTip(f"Crear nueva tarea en {status}")
        self.title_btn.clicked.connect(lambda: self.add_task_requested.emit(self.status))
        layout.addWidget(self.title_btn)

        self.scroll = QScrollArea()
        self.scroll.setWidgetResizable(True)
        self.scroll.setStyleSheet(get_minimal_scrollbar_style() + "QScrollArea { border: none; background: transparent; }")

        self.scroll_content = QWidget()
        self.scroll_content.setStyleSheet("background: transparent;")

        self.items_layout = QVBoxLayout(self.scroll_content)
        self.items_layout.setAlignment(Qt.AlignTop)

        self.scroll.setWidget(self.scroll_content)
        layout.addWidget(self.scroll)

    def dragEnterEvent(self, event):
        if event.mimeData().hasText():
            event.acceptProposedAction()

    def dropEvent(self, event):
        task_id = event.mimeData().text()
        self.viewmodel.move_task_status(task_id, self.status)
        event.acceptProposedAction()


class TasksView(QWidget):
    """
    Vista principal del ecosistema de tareas (Tablero Kanban).
    Coordina la interacción visual de columnas, tarjetas y modales.
    """
    open_task_requested = Signal(str)

    def __init__(self, viewmodel: TasksViewModel, parent=None):
        super().__init__(parent)
        self.viewmodel = viewmodel

        self.resize(850, 550)
        self.move(15, 15)

        self._setup_ui()
        self._connect_signals()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor(18, 18, 18, 240))

    def _setup_ui(self):
        self.body_layout = QVBoxLayout(self)
        self.body_layout.setContentsMargins(20, 20, 20, 20)

        # Board (Kanban) Centrado
        self.board_layout = QHBoxLayout()
        self.board_layout.addStretch()

        self.columns = {}
        for status in ["pending", "in-progress", "completed"]:
            col_widget = DropColumn(status, self.viewmodel)
            self.columns[status] = col_widget
            self.board_layout.addWidget(col_widget)

        self.board_layout.addStretch()
        self.body_layout.addLayout(self.board_layout)

    def _connect_signals(self):
        self.viewmodel.tasks_updated.connect(self._on_tasks_updated)
        for status, col in self.columns.items():
            col.add_task_requested.connect(self._on_add_task_clicked)

    def _on_add_task_clicked(self, status: str):
        """
        Abre el modal de creación de tareas (TAR-001 al TAR-006).
        """
        dialog = TaskCreateDialog(self, initial_status=status)
        if dialog.exec() == QDialog.Accepted:
            data = dialog.get_data()
            if data["title"]:
                self.viewmodel.create_new_task(
                    title=data["title"],
                    description=data["description"] or "",
                    due_date=data["due_date"],
                    status=status,
                    subtasks=data.get("subtasks", [])
                )

    def _on_card_double_clicked(self, task_id: str):
        """
        Abre el modal de consulta y modificación de detalles de la tarea (TAR-007, TAR-008, TAR-018 al TAR-024).
        """
        task = self.viewmodel.get_task_by_id(task_id)
        if not task:
            return

        dialog = TaskDetailDialog(task, self)
        dialog.delete_requested.connect(self._on_delete_task_requested)

        if dialog.exec() == QDialog.Accepted:
            updated_data = dialog.get_updated_data()
            self.viewmodel.update_task_details(
                task_id=task_id,
                title=updated_data["title"],
                description=updated_data["description"] or "",
                due_date=updated_data["due_date"],
                subtasks=updated_data.get("subtasks", [])
            )

    def _on_delete_task_requested(self, task_id: str):
        """
        Solicita confirmación antes de eliminar permanentemente la tarea (TAR-009, TAR-010).
        """
        task = self.viewmodel.get_task_by_id(task_id)
        title_display = task.title if task else task_id

        confirm_dialog = SciFiConfirmDialog(
            self,
            "CONFIRMAR ELIMINACIÓN",
            f"¿Deseas eliminar permanentemente la tarea '{title_display}'?\n\nEsta acción no se puede deshacer."
        )

        if confirm_dialog.exec() == QDialog.Accepted:
            self.viewmodel.delete_task(task_id)

    def _on_tasks_updated(self, tasks_grouped: dict):
        """
        Renderiza las tarjetas actualizadas en sus respectivas columnas.
        """
        for status, col in self.columns.items():
            layout = col.items_layout
            while layout.count():
                child = layout.takeAt(0)
                if child.widget():
                    child.widget().deleteLater()

            for task in tasks_grouped.get(status, []):
                card = TaskCard(
                    task_id=task.id,
                    title=task.title,
                    status=task.status,
                    due_date=task.due_date,
                    description=task.description,
                    created_at=task.created_at,
                    subtasks=task.subtasks
                )
                card.move_status_requested.connect(self.viewmodel.move_task_status)
                card.open_requested.connect(self._on_card_double_clicked)
                card.delete_requested.connect(self._on_delete_task_requested)
                card.toggle_subtask_requested.connect(self.viewmodel.toggle_subtask_status)
                layout.addWidget(card)

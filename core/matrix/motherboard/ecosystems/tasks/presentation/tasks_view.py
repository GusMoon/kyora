from typing import Optional
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, 
    QScrollArea, QPushButton, QFileDialog, QDialog, QGraphicsBlurEffect
)
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QPainter, QColor

from core.matrix.motherboard.ecosystems.tasks.presentation.tasks_viewmodel import TasksViewModel
from core.matrix.motherboard.ecosystems.tasks.presentation.taskCard import TaskCard
from core.matrix.motherboard.ecosystems.tasks.presentation.rootComponents.taskMetadata.taskMetadataMain import (
    TaskCreateDialog, TaskDetailDialog, CategoryCreateDialog, DescriptionReader
)
from core.matrix.motherboard.modules.styles import get_minimal_scrollbar_style
from core.matrix.motherboard.modules.simple_dialogs import SciFiConfirmDialog


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
                font-family: 'Prototype'; 
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
    Coordina la interacción visual de columnas, tarjetas, categorías y modales.
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
        self.body_layout.setContentsMargins(20, 16, 20, 20)
        self.body_layout.setSpacing(10)

        # =============================================================
        # TABLERO KANBAN CENTRADO (Las categorías se visualizan en los cards)
        # =============================================================

        # =============================================================
        # TABLERO KANBAN CENTRADO
        # =============================================================
        # Contenedor propio para poder desenfocar el tablero al abrir el modo enfoque
        self.board_container = QWidget()
        self.board_container.setStyleSheet("background: transparent;")
        self.board_layout = QHBoxLayout(self.board_container)
        self.board_layout.setContentsMargins(0, 0, 0, 0)
        self.board_layout.addStretch()

        self.columns = {}
        for status in ["pending", "in-progress", "completed"]:
            col_widget = DropColumn(status, self.viewmodel)
            self.columns[status] = col_widget
            self.board_layout.addWidget(col_widget)

        self.board_layout.addStretch()
        self.body_layout.addWidget(self.board_container)

        # Overlay de enfoque: se superpone al tablero (desenfocado) sin alterar los cards
        self.description_reader = DescriptionReader(self)
        self.description_reader.closed.connect(lambda: self._set_board_blur(False))
        self.description_reader.open_task_requested.connect(self._on_card_double_clicked)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        if self.description_reader.isVisible():
            self.description_reader.reposition()

    def _set_board_blur(self, enabled: bool):
        """Activa o retira el desenfoque del tablero mientras el overlay está abierto."""
        if enabled:
            blur = QGraphicsBlurEffect(self.board_container)
            blur.setBlurRadius(14)
            self.board_container.setGraphicsEffect(blur)
        else:
            self.board_container.setGraphicsEffect(None)

    def _on_description_requested(self, task_id: str):
        """Abre el modo enfoque con la descripción y la réplica de la tarea seleccionada."""
        task = self.viewmodel.get_task_by_id(task_id)
        if not task or not (task.description or "").strip():
            return

        preview = self._build_card(task)
        preview.setFixedWidth(DescriptionReader.SIDE_WIDTH)
        # La réplica es solo informativa: sin clics, arrastre ni borrado
        preview.setAttribute(Qt.WA_TransparentForMouseEvents, True)

        self._set_board_blur(True)
        self.description_reader.show_description(task.id, task.title, task.description, preview)

    def _build_card(self, task) -> TaskCard:
        """Construye un TaskCard a partir de una entidad Task."""
        return TaskCard(
            task_id=task.id,
            title=task.title,
            status=task.status,
            due_date=task.due_date,
            description=task.description,
            created_at=task.created_at,
            subtasks=task.subtasks,
            priority=getattr(task, "priority", 0),
            category_name=getattr(task, "category_name", None),
            category_color=getattr(task, "category_color", None),
            estimated_duration_minutes=getattr(task, "estimated_duration_minutes", None),
            time_spent_seconds=getattr(task, "time_spent_seconds", 0)
        )

    def _connect_signals(self):
        self.viewmodel.tasks_updated.connect(self._on_tasks_updated)
        self.viewmodel.categories_updated.connect(self._on_categories_updated)
        self.viewmodel.timer_finished.connect(self._on_timer_finished)

        for status, col in self.columns.items():
            col.add_task_requested.connect(self._on_add_task_clicked)

    def _refresh_category_chips(self):
        """No-op: Las categorías ya no se muestran en una barra superior, sino en cada tarjeta (TaskCard)."""
        pass

    def _select_category_filter(self, category_id: Optional[str]):
        self.viewmodel.filter_by_category(category_id)

    def _on_categories_updated(self, categories: list):
        pass

    def _on_add_category_clicked(self):
        diag = CategoryCreateDialog(self)
        if diag.exec() == QDialog.Accepted:
            data = diag.get_data()
            self.viewmodel.create_category(data["name"], data["color"])

    def _on_timer_finished(self, task_id: str, task_title: str):
        """Notifica al usuario que se ha completado la sesión de cronómetro (TAR-041)."""
        confirm = SciFiConfirmDialog(
            self,
            "SESIÓN COMPLETADA",
            f"✦ ¡El tiempo programado para la tarea ha finalizado!\n\nTarea: '{task_title.upper()}'\nEl tiempo de trabajo ha sido registrado exitosamente."
        )
        confirm.exec()

    def _on_add_task_clicked(self, status: str):
        """
        Abre el modal de creación de tareas con categoría y duración estimada (TAR-001 al TAR-006, TAR-026, TAR-032).
        """
        dialog = TaskCreateDialog(
            parent=self,
            initial_status=status,
            categories=self.viewmodel.get_categories(),
            create_category_callback=self.viewmodel.create_category,
            viewmodel=self.viewmodel
        )
        if dialog.exec() == QDialog.Accepted:
            data = dialog.get_data()
            if data["title"]:
                self.viewmodel.create_new_task(
                    title=data["title"],
                    description=data["description"] or "",
                    due_date=data["due_date"],
                    status=status,
                    subtasks=data.get("subtasks", []),
                    category_id=data.get("category_id"),
                    estimated_duration_minutes=data.get("estimated_duration_minutes")
                )

    def open_task_detail(self, task_id: str) -> None:
        """
        Abre el detalle de una tarea desde otro ecosistema (por ejemplo, el calendario).

        Args:
            task_id: Identificador de la tarea a abrir.
        """
        self._on_card_double_clicked(task_id)

    def _on_card_double_clicked(self, task_id: str):
        """
        Abre el modal de consulta, modificación y cronómetro de la tarea (TAR-007, TAR-028, TAR-035 a TAR-044).
        """
        task = self.viewmodel.get_task_by_id(task_id)
        if not task:
            return

        dialog = TaskDetailDialog(
            task=task,
            parent=self,
            categories=self.viewmodel.get_categories(),
            create_category_callback=self.viewmodel.create_category,
            viewmodel=self.viewmodel
        )
        dialog.delete_requested.connect(self._on_delete_task_requested)
        # La tarea abierta ocupa toda la ventana para maximizar la visibilidad del contenido
        dialog.fit_to_rect(self.window().frameGeometry())

        if dialog.exec() == QDialog.Accepted:
            updated_data = dialog.get_updated_data()
            self.viewmodel.update_task_details(
                task_id=task_id,
                title=updated_data["title"],
                description=updated_data["description"] or "",
                due_date=updated_data["due_date"],
                subtasks=updated_data.get("subtasks", []),
                category_id=updated_data.get("category_id"),
                estimated_duration_minutes=updated_data.get("estimated_duration_minutes")
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
        Cierra el modo enfoque si estaba abierto para no mostrar datos obsoletos.
        """
        self.description_reader.close_reader()

        for status, col in self.columns.items():
            layout = col.items_layout
            while layout.count():
                child = layout.takeAt(0)
                if child.widget():
                    child.widget().deleteLater()

            for task in tasks_grouped.get(status, []):
                card = self._build_card(task)
                card.move_status_requested.connect(self.viewmodel.move_task_status)
                card.open_requested.connect(self._on_card_double_clicked)
                card.description_requested.connect(self._on_description_requested)
                card.delete_requested.connect(self._on_delete_task_requested)
                card.toggle_subtask_requested.connect(self.viewmodel.toggle_subtask_status)
                layout.addWidget(card)

from typing import Optional
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, 
    QScrollArea, QPushButton, QFileDialog, QDialog
)
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QPainter, QColor

from core.matrix.ecosystems.tasks.presentation.tasks_viewmodel import TasksViewModel
from core.matrix.ecosystems.tasks.presentation.taskCard import TaskCard
from core.matrix.ecosystems.tasks.presentation.rootComponents.taskMetadata.taskMetadataMain import (
    TaskCreateDialog, TaskDetailDialog, CategoryCreateDialog
)
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
        self._refresh_category_chips()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor(18, 18, 18, 240))

    def _setup_ui(self):
        self.body_layout = QVBoxLayout(self)
        self.body_layout.setContentsMargins(20, 16, 20, 20)
        self.body_layout.setSpacing(10)

        # =============================================================
        # BARRA DE FILTRADO POR CATEGORÍAS (TAR-029)
        # =============================================================
        self.category_bar_layout = QHBoxLayout()
        self.category_bar_layout.setContentsMargins(4, 0, 4, 0)
        self.category_bar_layout.setSpacing(8)

        lbl_cat_title = QLabel("CATEGORÍAS:")
        lbl_cat_title.setStyleSheet("color: #777777; font-size: 11px; font-weight: bold; font-family: 'Space Grotesk'; letter-spacing: 0.8px;")
        self.category_bar_layout.addWidget(lbl_cat_title)

        self.chips_container = QWidget()
        self.chips_layout = QHBoxLayout(self.chips_container)
        self.chips_layout.setContentsMargins(0, 0, 0, 0)
        self.chips_layout.setSpacing(6)
        self.category_bar_layout.addWidget(self.chips_container)

        self.category_bar_layout.addStretch()

        btn_add_cat = QPushButton("+ NUEVA CATEGORÍA")
        btn_add_cat.setFixedHeight(26)
        btn_add_cat.setCursor(Qt.PointingHandCursor)
        btn_add_cat.setStyleSheet("""
            QPushButton {
                background-color: #1A1A1A;
                border: 1px solid #333333;
                color: #FFAA77;
                font-size: 10px;
                font-weight: bold;
                font-family: 'Space Grotesk';
                padding: 0 10px;
                border-radius: 4px;
            }
            QPushButton:hover {
                background-color: #262626;
                border-color: #FFAA77;
            }
        """)
        btn_add_cat.clicked.connect(self._on_add_category_clicked)
        self.category_bar_layout.addWidget(btn_add_cat)

        self.body_layout.addLayout(self.category_bar_layout)

        # =============================================================
        # TABLERO KANBAN CENTRADO
        # =============================================================
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
        self.viewmodel.categories_updated.connect(self._on_categories_updated)
        self.viewmodel.timer_finished.connect(self._on_timer_finished)

        for status, col in self.columns.items():
            col.add_task_requested.connect(self._on_add_task_clicked)

    def _refresh_category_chips(self):
        """Renderiza los botones de filtrado rápido por categoría en el tablero (TAR-029)."""
        while self.chips_layout.count():
            child = self.chips_layout.takeAt(0)
            if child.widget():
                child.widget().deleteLater()

        selected_id = self.viewmodel.get_selected_category_id()

        # Botón "TODAS"
        btn_all = QPushButton("TODAS")
        btn_all.setFixedHeight(24)
        btn_all.setCursor(Qt.PointingHandCursor)
        is_all_active = (selected_id is None)
        btn_all.setStyleSheet(f"""
            QPushButton {{
                background-color: {"#A31F34" if is_all_active else "#1A1A1A"};
                border: 1px solid {"#C42B42" if is_all_active else "#2D2D2D"};
                color: {"#FFFFFF" if is_all_active else "#999999"};
                font-size: 10px;
                font-weight: bold;
                font-family: 'Space Grotesk';
                padding: 0 10px;
                border-radius: 12px;
            }}
            QPushButton:hover {{
                border-color: #FFAA77;
                color: #FFFFFF;
            }}
        """)
        btn_all.clicked.connect(lambda: self._select_category_filter(None))
        self.chips_layout.addWidget(btn_all)

        # Categorías dinámicas
        categories = self.viewmodel.get_categories()
        for cat in categories:
            is_active = (selected_id == cat.id)
            col = cat.color or "#FFAA77"
            btn_cat = QPushButton(f"● {cat.name.upper()}")
            btn_cat.setFixedHeight(24)
            btn_cat.setCursor(Qt.PointingHandCursor)
            btn_cat.setStyleSheet(f"""
                QPushButton {{
                    background-color: {"#242424" if is_active else "#161616"};
                    border: 1px solid {col if is_active else "#2E2E2E"};
                    color: {col if is_active else "#AAAAAA"};
                    font-size: 10px;
                    font-weight: bold;
                    font-family: 'Space Grotesk';
                    padding: 0 10px;
                    border-radius: 12px;
                }}
                QPushButton:hover {{
                    border-color: {col};
                    color: {col};
                }}
            """)
            btn_cat.clicked.connect(lambda _, c_id=cat.id: self._select_category_filter(c_id))
            self.chips_layout.addWidget(btn_cat)

        # Botón "SIN CATEGORÍA"
        is_none_active = (selected_id == "__none__")
        btn_none = QPushButton("SIN CATEGORÍA")
        btn_none.setFixedHeight(24)
        btn_none.setCursor(Qt.PointingHandCursor)
        btn_none.setStyleSheet(f"""
            QPushButton {{
                background-color: {"#2A2A2A" if is_none_active else "#161616"};
                border: 1px solid {"#888888" if is_none_active else "#2A2A2A"};
                color: {"#FFFFFF" if is_none_active else "#666666"};
                font-size: 10px;
                font-weight: bold;
                font-family: 'Space Grotesk';
                padding: 0 8px;
                border-radius: 12px;
            }}
            QPushButton:hover {{
                border-color: #AAAAAA;
                color: #DDDDDD;
            }}
        """)
        btn_none.clicked.connect(lambda: self._select_category_filter("__none__"))
        self.chips_layout.addWidget(btn_none)

    def _select_category_filter(self, category_id: Optional[str]):
        self.viewmodel.filter_by_category(category_id)
        self._refresh_category_chips()

    def _on_categories_updated(self, categories: list):
        self._refresh_category_chips()

    def _on_add_category_clicked(self):
        diag = CategoryCreateDialog(self)
        if diag.exec() == QDialog.Accepted:
            data = diag.get_data()
            new_cat = self.viewmodel.create_category(data["name"], data["color"])
            if new_cat:
                self._select_category_filter(new_cat.id)

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
            create_category_callback=self.viewmodel.create_category
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
                    subtasks=task.subtasks,
                    priority=getattr(task, "priority", 0),
                    category_name=getattr(task, "category_name", None),
                    category_color=getattr(task, "category_color", None),
                    estimated_duration_minutes=getattr(task, "estimated_duration_minutes", None),
                    time_spent_seconds=getattr(task, "time_spent_seconds", 0)
                )
                card.move_status_requested.connect(self.viewmodel.move_task_status)
                card.open_requested.connect(self._on_card_double_clicked)
                card.delete_requested.connect(self._on_delete_task_requested)
                card.toggle_subtask_requested.connect(self.viewmodel.toggle_subtask_status)
                layout.addWidget(card)

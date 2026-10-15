"""
Componente visual de tarjeta de tarea (TaskCard) dentro del tablero Kanban.
Diseño SciFi de Kiora con altura uniforme (84px) y tres filas de información:
título, categoría/tiempo y progreso de subtareas.
- El panel de fecha límite solo se muestra cuando la tarea tiene fecha.
- 1 Clic: Con descripción abre el modo enfoque (la tarjeta nunca cambia de tamaño);
  sin descripción abre directamente la tarea.
- 2 Clics: Abre el modal de metadatos y edición completa (taskMetadata).
- Arrastrar (Drag & Drop): Mueve la tarea entre columnas Kanban.
"""
from typing import Optional, List
from datetime import datetime

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QLabel, QHBoxLayout,
    QFrame, QPushButton
)
from PySide6.QtCore import Qt, Signal, QMimeData, QPoint, QTimer
from PySide6.QtGui import QDrag

from core.matrix.motherboard.ecosystems.tasks.domain.entities import SubTask
from core.matrix.motherboard.globalComponents.gradient_progress_bar import GradientProgressBar


class TaskCard(QWidget):
    """
    Tarjeta de tarea interactiva dentro del tablero Kanban.

    Interacciones:
    - 1 Clic: Si la tarea tiene descripción, emite description_requested.
    - 2 Clics (Doble clic): Abre el modal flotante de metadatos y edición completa.
    - Arrastrar: Mueve la tarjeta entre columnas de estado.
    - Botón ✕: Solicita la eliminación de la tarea.
    """
    move_status_requested = Signal(str, str)
    open_requested = Signal(str)
    delete_requested = Signal(str)
    toggle_subtask_requested = Signal(str, str, bool)
    description_requested = Signal(str)

    CARD_HEIGHT = 84
    DATE_PANEL_WIDTH = 65

    def __init__(
        self,
        task_id: str,
        title: str,
        status: str,
        due_date: str = None,
        description: str = "",
        created_at: str = "",
        subtasks: Optional[List[SubTask]] = None,
        priority: int = 0,
        category_name: Optional[str] = None,
        category_color: Optional[str] = None,
        estimated_duration_minutes: Optional[int] = None,
        time_spent_seconds: int = 0,
        parent=None
    ):
        super().__init__(parent)
        self.task_id = task_id
        self.title_text = title or ""
        self.current_status = status or "pending"
        self.due_date_str = due_date
        self.description_text = (description or "").strip()
        self.has_description = bool(self.description_text)
        self.created_at_str = created_at or ""
        self.subtasks = subtasks or []
        self.priority = priority
        self.category_name = category_name
        self.category_color = category_color or "#FFAA77"
        self.estimated_duration_minutes = estimated_duration_minutes
        self.time_spent_seconds = time_spent_seconds

        self.drag_start_position = QPoint()
        self._drag_started = False
        self._subtasks_bar: Optional[GradientProgressBar] = None

        self.setAttribute(Qt.WA_StyledBackground, True)
        self.setCursor(Qt.PointingHandCursor)
        self._set_default_style()
        self.setFixedHeight(self.CARD_HEIGHT)

        # Timer para desacoplar 1 clic (leer descripción) de 2 clics (abrir detalle en modal)
        self._click_timer = QTimer(self)
        self._click_timer.setSingleShot(True)
        self._click_timer.setInterval(220)
        self._click_timer.timeout.connect(self._handle_single_click)

        self._setup_ui()

    # ------------------------------------------------------------------
    # Construcción de la interfaz
    # ------------------------------------------------------------------
    def _resolve_accent_color(self) -> str:
        status_norm = self.current_status.strip().lower().replace("-", "_")
        if status_norm == "completed":
            return "#00FA9A"
        if status_norm == "in_progress":
            return "#00BFFF"
        return "#FFA500"

    def _setup_ui(self):
        accent_color = self._resolve_accent_color()

        main_layout = QHBoxLayout(self)
        main_layout.setContentsMargins(0, 0, 0, 0)
        main_layout.setSpacing(0)

        # Barra lateral de estado Kanban
        accent_bar = QFrame()
        accent_bar.setFixedWidth(5)
        accent_bar.setStyleSheet(f"background-color: {accent_color};")
        main_layout.addWidget(accent_bar)

        center_layout = QVBoxLayout()
        center_layout.setContentsMargins(12, 8, 8, 8)
        center_layout.setSpacing(4)
        center_layout.setAlignment(Qt.AlignVCenter)
        center_layout.addLayout(self._build_title_row())
        center_layout.addLayout(self._build_info_row())

        if self.subtasks:
            center_layout.addLayout(self._build_subtasks_row())

        main_layout.addLayout(center_layout, 1)

        # Panel de fecha límite: solo existe si la tarea tiene fecha
        if self.due_date_str:
            date_frame = self._build_date_panel(accent_color)
            if date_frame:
                main_layout.addWidget(date_frame)

    def _build_title_row(self) -> QHBoxLayout:
        row = QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(4)

        title_label = QLabel(self.title_text.upper())
        title_label.setWordWrap(False)
        title_label.setStyleSheet(
            "font-weight: 900; font-size: 13px; font-family: 'Prototype'; "
            "color: #FFFFFF; letter-spacing: 0.8px;"
        )
        row.addWidget(title_label, 1)

        self.btn_delete = QPushButton("✕")
        self.btn_delete.setFixedSize(18, 18)
        self.btn_delete.setCursor(Qt.PointingHandCursor)
        self.btn_delete.setToolTip("Eliminar tarea")
        self.btn_delete.setStyleSheet("""
            QPushButton {
                background: transparent;
                color: #555555;
                border: none;
                font-size: 11px;
                font-weight: bold;
                padding: 0px;
            }
            QPushButton:hover {
                color: #FF5555;
                background-color: #2A1111;
                border-radius: 2px;
            }
        """)
        self.btn_delete.clicked.connect(lambda: self.delete_requested.emit(self.task_id))
        row.addWidget(self.btn_delete)
        return row

    def _build_info_row(self) -> QHBoxLayout:
        """Fila de categoría, tiempo estimado/invertido e indicador de descripción."""
        row = QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(8)

        if self.category_name:
            lbl_cat_badge = QLabel(self.category_name.upper())
            lbl_cat_badge.setFixedHeight(17)
            lbl_cat_badge.setToolTip(f"Categoría: {self.category_name}")
            lbl_cat_badge.setStyleSheet("""
                QLabel {
                    color: #CCCCCC;
                    font-size: 9px;
                    font-weight: bold;
                    font-family: 'Prototype';
                    letter-spacing: 0.6px;
                    background-color: #1A1A1A;
                    border: 1px solid #383838;
                    border-radius: 3px;
                    padding: 1px 6px;
                }
            """)
            row.addWidget(lbl_cat_badge)

        time_text = self._format_time_badge()
        if time_text:
            lbl_time_badge = QLabel(time_text)
            lbl_time_badge.setStyleSheet(
                "color: #999999; font-size: 10px; font-family: 'Prototype';"
            )
            row.addWidget(lbl_time_badge)

        row.addStretch()

        if self.has_description:
            lbl_desc = QLabel("≡ DESCRIPCIÓN")
            lbl_desc.setToolTip("Clic para leer la descripción")
            lbl_desc.setStyleSheet(
                "color: #777777; font-size: 9px; font-weight: bold; "
                "font-family: 'Prototype'; letter-spacing: 0.6px;"
            )
            row.addWidget(lbl_desc)
        return row

    def _format_time_badge(self) -> str:
        """Texto de tiempo invertido/estimado (TAR-032, TAR-042). Vacío si no aplica."""
        if self.time_spent_seconds > 0:
            spent_minutes = self.time_spent_seconds // 60
            if self.estimated_duration_minutes:
                return f"⏱ {spent_minutes}m/{self.estimated_duration_minutes}m"
            return f"⏱ {spent_minutes}m"

        if self.estimated_duration_minutes:
            hours = self.estimated_duration_minutes // 60
            minutes = self.estimated_duration_minutes % 60
            if hours > 0 and minutes > 0:
                return f"⏱ {hours}h{minutes}m"
            if hours > 0:
                return f"⏱ {hours}h"
            return f"⏱ {minutes}m"
        return ""

    def _build_subtasks_row(self) -> QHBoxLayout:
        """Fila de progreso de subtareas con texto legible y barra fina."""
        total = len(self.subtasks)
        done = sum(1 for st in self.subtasks if st.is_completed)

        row = QHBoxLayout()
        row.setContentsMargins(0, 0, 0, 0)
        row.setSpacing(8)

        lbl_progress = QLabel(f"SUBTAREAS {done}/{total}")
        lbl_progress.setStyleSheet(
            "color: #E0E0E0; font-size: 11px; font-weight: bold; "
            "font-family: 'Prototype'; letter-spacing: 0.5px;"
        )
        row.addWidget(lbl_progress)

        bar = GradientProgressBar()
        self._subtasks_bar = bar
        bar.setRange(0, total)
        bar.setValue(done)
        bar.setFixedHeight(4)
        row.addWidget(bar, 1)
        return row

    def _build_date_panel(self, accent_color: str) -> Optional[QFrame]:
        try:
            due = datetime.strptime(self.due_date_str[:10], "%Y-%m-%d")
        except ValueError:
            return None

        date_frame = QFrame()
        date_frame.setFixedWidth(self.DATE_PANEL_WIDTH)
        date_frame.setStyleSheet("background-color: #1A1A1A; border-left: 1px solid #333333;")

        layout = QVBoxLayout(date_frame)
        layout.setContentsMargins(0, 8, 0, 8)
        layout.setSpacing(2)

        day_lbl = QLabel(due.strftime("%d"))
        day_lbl.setAlignment(Qt.AlignCenter)
        day_lbl.setStyleSheet(
            "font-size: 18px; font-family: 'Prototype'; color: #FFFFFF; font-weight: 900;"
        )

        month_lbl = QLabel(due.strftime("%b").upper())
        month_lbl.setAlignment(Qt.AlignCenter)
        month_lbl.setStyleSheet(
            "font-size: 10px; font-family: 'Prototype'; color: #AAAAAA; "
            "font-weight: bold; letter-spacing: 1px;"
        )

        dot = QLabel()
        dot.setFixedSize(6, 6)
        dot.setStyleSheet(f"background-color: {accent_color}; border-radius: 3px;")

        dot_layout = QHBoxLayout()
        dot_layout.setContentsMargins(0, 0, 0, 0)
        dot_layout.setAlignment(Qt.AlignCenter)
        dot_layout.addWidget(dot)

        layout.addWidget(day_lbl)
        layout.addWidget(month_lbl)
        layout.addStretch()
        layout.addLayout(dot_layout)
        return date_frame

    # ------------------------------------------------------------------
    # Estilos
    # ------------------------------------------------------------------
    def _set_default_style(self):
        if self._subtasks_bar is not None:
            self._subtasks_bar.setVisible(True)
        self.setStyleSheet("""
            TaskCard {
                background-color: #222222;
                border: 1px solid #333333;
                border-radius: 4px;
            }
            TaskCard:hover {
                background-color: #262626;
                border: 1px solid #4E4E4E;
            }
        """)

    def _set_ghost_style(self):
        # La barra se pinta a mano y no obedece al QSS, por lo que se oculta aparte
        if self._subtasks_bar is not None:
            self._subtasks_bar.setVisible(False)
        self.setStyleSheet("""
            TaskCard {
                background-color: transparent;
                border: 1px dashed #666666;
            }
            QLabel, QFrame, QPushButton {
                background-color: transparent;
                color: transparent;
                border: none;
            }
        """)

    # ------------------------------------------------------------------
    # Interacción
    # ------------------------------------------------------------------
    def _handle_single_click(self):
        """Manejador ejecutado al detectar 1 solo clic tras el timeout."""
        if self.has_description:
            self.description_requested.emit(self.task_id)

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.drag_start_position = event.pos()
            self._drag_started = False
        super().mousePressEvent(event)

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            if not self._drag_started and (event.pos() - self.drag_start_position).manhattanLength() < 8:
                if not self.has_description:
                    # Sin descripción no hay nada que leer: no se espera al doble clic
                    event.accept()
                    self.open_requested.emit(self.task_id)
                    return
                if self._click_timer.isActive():
                    self._click_timer.stop()
                self._click_timer.start(220)
        super().mouseReleaseEvent(event)

    def mouseDoubleClickEvent(self, event):
        if event.button() == Qt.LeftButton:
            # Un doble clic cancela la lectura pendiente y abre el modal de detalle
            if self._click_timer.isActive():
                self._click_timer.stop()
            event.accept()
            self.open_requested.emit(self.task_id)
            return
        super().mouseDoubleClickEvent(event)

    def mouseMoveEvent(self, event):
        if not (event.buttons() & Qt.LeftButton):
            return
        if (event.pos() - self.drag_start_position).manhattanLength() >= 8:
            if self._click_timer.isActive():
                self._click_timer.stop()
            self._drag_started = True

            drag = QDrag(self)
            mime_data = QMimeData()
            mime_data.setText(self.task_id)
            drag.setMimeData(mime_data)

            pixmap = self.grab()
            drag.setPixmap(pixmap)
            drag.setHotSpot(event.pos())

            self._set_ghost_style()
            drag.exec(Qt.MoveAction)
            self._set_default_style()

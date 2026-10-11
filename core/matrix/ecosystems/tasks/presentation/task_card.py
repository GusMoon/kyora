from typing import Optional, List
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QLabel, QHBoxLayout, 
    QFrame, QPushButton, QScrollArea
)
from PySide6.QtCore import Qt, Signal, QMimeData, QPoint
from PySide6.QtGui import QDrag, QPixmap
from datetime import datetime

from core.matrix.ecosystems.tasks.domain.entities import SubTask


class TaskCard(QWidget):
    """
    Componente visual de tarjeta de tarea dentro del tablero Kanban.
    
    Interacciones soportadas:
    - 1 Clic: Despliega / colapsa la información descriptiva y checklist interactivo de subtareas.
    - 2 Clics (Doble clic): Abre el panel flotante y movible de edición completa.
    - Arrastrar (Drag & Drop): Mueve la tarea entre columnas de estado.
    - Botón ✕: Solicita la eliminación de la tarea con confirmación.
    - Checkbox de Subtarea: Alterna el estado completado/pendiente directamente desde el tablero.
    """
    move_status_requested = Signal(str, str)
    open_requested = Signal(str)
    delete_requested = Signal(str)
    toggle_subtask_requested = Signal(str, str, bool) # (task_id, subtask_id, is_completed)

    def __init__(
        self, 
        task_id: str, 
        title: str, 
        status: str, 
        due_date: str = None, 
        description: str = "", 
        created_at: str = "",
        subtasks: Optional[List[SubTask]] = None,
        parent=None
    ):
        super().__init__(parent)
        self.task_id = task_id
        self.title_text = title
        self.current_status = status
        self.due_date_str = due_date
        self.description_text = description or ""
        self.created_at_str = created_at or ""
        self.subtasks = subtasks or []

        self.is_expanded = False
        self.drag_start_position = QPoint()
        self._drag_started = False

        self.setAttribute(Qt.WA_StyledBackground, True)
        self.setFixedHeight(65)
        self._set_default_style()

        # Layout Principal Vertical
        self.card_main_layout = QVBoxLayout(self)
        self.card_main_layout.setContentsMargins(0, 0, 0, 0)
        self.card_main_layout.setSpacing(0)

        # -------------------------------------------------------------
        # 1. FILA COMPACTA (Cabecera siempre visible)
        # -------------------------------------------------------------
        self.compact_widget = QWidget()
        self.compact_widget.setFixedHeight(65)
        compact_layout = QHBoxLayout(self.compact_widget)
        compact_layout.setContentsMargins(0, 0, 0, 0)
        compact_layout.setSpacing(0)

        # Barra de acento lateral según estado
        self.accent_bar = QFrame()
        self.accent_bar.setFixedWidth(5)
        accent_color = (
            "#00FA9A" if status == "completed" 
            else ("#00BFFF" if status in ("in_progress", "in-progress") else "#FFA500")
        )
        self.accent_bar.setStyleSheet(f"background-color: {accent_color};")
        compact_layout.addWidget(self.accent_bar)

        # Contenido Central (Título + Indicadores + Botón Eliminar)
        center_layout = QVBoxLayout()
        center_layout.setContentsMargins(10, 8, 8, 8)
        center_layout.setSpacing(2)
        center_layout.setAlignment(Qt.AlignVCenter)

        top_row = QHBoxLayout()
        top_row.setContentsMargins(0, 0, 0, 0)

        title_label = QLabel(self.title_text.upper())
        title_label.setStyleSheet(
            "font-weight: 900; font-size: 13px; font-family: 'Space Grotesk'; "
            "color: #FFFFFF; letter-spacing: 1px;"
        )
        top_row.addWidget(title_label)

        # Resumen de subtareas compacto si existen (ej. [2/3])
        if self.subtasks:
            done_cnt = sum(1 for st in self.subtasks if st.is_completed)
            tot_cnt = len(self.subtasks)
            sub_tag = QLabel(f"[{done_cnt}/{tot_cnt}]")
            sub_tag.setStyleSheet("color: #00BFFF; font-size: 10px; font-weight: bold; padding-left: 4px;")
            top_row.addWidget(sub_tag)

        # Indicador de acordeón desplegable
        self.arrow_lbl = QLabel("▼")
        self.arrow_lbl.setStyleSheet(
            "color: #666666; font-size: 10px; font-weight: bold; padding-left: 6px;"
        )
        top_row.addWidget(self.arrow_lbl)
        top_row.addStretch()

        # Botón de eliminación
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
            }
            QPushButton:hover {
                color: #FF5555;
                background-color: #2A1111;
                border-radius: 2px;
            }
        """)
        self.btn_delete.clicked.connect(lambda: self.delete_requested.emit(self.task_id))
        top_row.addWidget(self.btn_delete)

        center_layout.addLayout(top_row)
        compact_layout.addLayout(center_layout)

        # Panel de Fecha Límite a la derecha
        if self.due_date_str:
            try:
                dt = datetime.strptime(self.due_date_str[:10], "%Y-%m-%d")
                month_str = dt.strftime("%b").upper()
                day_str = dt.strftime("%d")
            except Exception:
                month_str = "---"
                day_str = "--"
        else:
            month_str = "TBD"
            day_str = "--"

        date_frame = QFrame()
        date_frame.setFixedWidth(65)
        date_frame.setStyleSheet("background-color: #1A1A1A; border-left: 1px solid #333333;")

        date_layout = QVBoxLayout(date_frame)
        date_layout.setContentsMargins(0, 10, 0, 10)
        date_layout.setSpacing(2)

        day_lbl = QLabel(day_str)
        day_lbl.setAlignment(Qt.AlignCenter)
        day_lbl.setStyleSheet("font-size: 20px; font-family: 'Space Grotesk'; color: #FFFFFF; font-weight: 900;")

        month_lbl = QLabel(month_str)
        month_lbl.setAlignment(Qt.AlignCenter)
        month_lbl.setStyleSheet("font-size: 10px; font-family: 'Space Grotesk'; color: #AAAAAA; font-weight: bold; letter-spacing: 1px;")

        dot = QLabel()
        dot.setFixedSize(6, 6)
        dot.setStyleSheet(f"background-color: {accent_color}; border-radius: 3px;")

        dot_layout = QHBoxLayout()
        dot_layout.setContentsMargins(0, 0, 0, 0)
        dot_layout.setAlignment(Qt.AlignCenter)
        dot_layout.addWidget(dot)

        date_layout.addWidget(day_lbl)
        date_layout.addWidget(month_lbl)
        date_layout.addStretch()
        date_layout.addLayout(dot_layout)

        compact_layout.addWidget(date_frame)
        self.card_main_layout.addWidget(self.compact_widget)

        # -------------------------------------------------------------
        # 2. CONTENEDOR DESPLEGABLE (Oculto por defecto, visible con 1 clic)
        # -------------------------------------------------------------
        self.expanded_container = QFrame()
        self.expanded_container.setStyleSheet("background-color: #1A1A1A; border-top: 1px solid #333333;")
        self.expanded_container.hide()

        expanded_layout = QVBoxLayout(self.expanded_container)
        expanded_layout.setContentsMargins(15, 10, 15, 12)
        expanded_layout.setSpacing(8)

        # Descripción
        desc_title = QLabel("DESCRIPCIÓN:")
        desc_title.setStyleSheet("font-size: 10px; font-family: 'Space Grotesk'; color: #888888; font-weight: bold;")
        expanded_layout.addWidget(desc_title)

        if self.description_text.strip():
            desc_text_lbl = QLabel(self.description_text)
            desc_text_lbl.setStyleSheet("color: #DDDDDD; font-size: 12px; font-family: 'Space Grotesk'; line-height: 1.3;")
            desc_text_lbl.setWordWrap(True)
        else:
            desc_text_lbl = QLabel("Sin descripción detallada.")
            desc_text_lbl.setStyleSheet("color: #666666; font-size: 11px; font-style: italic; font-family: 'Space Grotesk';")
        expanded_layout.addWidget(desc_text_lbl)

        # Subtareas Interactivas (TAR-021, TAR-024)
        if self.subtasks:
            done_cnt = sum(1 for st in self.subtasks if st.is_completed)
            tot_cnt = len(self.subtasks)
            pct = int((done_cnt / tot_cnt) * 100) if tot_cnt > 0 else 0

            sub_head = QHBoxLayout()
            sub_head.setContentsMargins(0, 4, 0, 0)
            sub_title = QLabel(f"SUBTAREAS ({done_cnt}/{tot_cnt} • {pct}%):")
            sub_title.setStyleSheet("font-size: 10px; font-family: 'Space Grotesk'; color: #00BFFF; font-weight: bold;")
            sub_head.addWidget(sub_title)
            sub_head.addStretch()
            expanded_layout.addLayout(sub_head)

            for st in self.subtasks:
                st_row = QHBoxLayout()
                st_row.setContentsMargins(4, 2, 4, 2)
                st_row.setSpacing(6)

                chk_btn = QPushButton("✔" if st.is_completed else "")
                chk_btn.setFixedSize(16, 16)
                chk_btn.setCursor(Qt.PointingHandCursor)
                chk_btn.setToolTip("Marcar como completada / pendiente")
                if st.is_completed:
                    chk_btn.setStyleSheet(
                        "background-color: #00FA9A; color: #121212; border: 1px solid #00FA9A; "
                        "border-radius: 2px; font-size: 10px; font-weight: bold;"
                    )
                else:
                    chk_btn.setStyleSheet(
                        "background-color: #141414; color: transparent; border: 1px solid #555555; "
                        "border-radius: 2px;"
                    )

                st_id = st.id
                is_done_val = st.is_completed
                chk_btn.clicked.connect(
                    lambda _, sid=st_id, done=is_done_val: self.toggle_subtask_requested.emit(self.task_id, sid, not done)
                )

                st_lbl = QLabel(st.title)
                if st.is_completed:
                    st_lbl.setStyleSheet("color: #777777; font-size: 11px; font-family: 'Space Grotesk'; text-decoration: line-through;")
                else:
                    st_lbl.setStyleSheet("color: #E0E0E0; font-size: 11px; font-family: 'Space Grotesk';")

                st_row.addWidget(chk_btn)
                st_row.addWidget(st_lbl)
                st_row.addStretch()
                expanded_layout.addLayout(st_row)

        # Metadatos inferiores (Fecha de creación y sugerencia de edición)
        footer_layout = QHBoxLayout()
        created_display = self.created_at_str[:16].replace("T", " ") if self.created_at_str else "---"
        created_lbl = QLabel(f"Registrada: {created_display}")
        created_lbl.setStyleSheet("color: #666666; font-size: 10px; font-family: 'Space Grotesk';")

        hint_edit_lbl = QLabel("• 2 clics para editar")
        hint_edit_lbl.setStyleSheet("color: #888888; font-size: 10px; font-family: 'Space Grotesk'; font-weight: bold;")

        footer_layout.addWidget(created_lbl)
        footer_layout.addStretch()
        footer_layout.addWidget(hint_edit_lbl)
        expanded_layout.addLayout(footer_layout)

        self.card_main_layout.addWidget(self.expanded_container)

    def toggle_expand(self):
        """Alterna el despliegue del acordeón de información de la tarea."""
        self.is_expanded = not self.is_expanded
        if self.is_expanded:
            self.expanded_container.show()
            self.arrow_lbl.setText("▲")
            extra_h = len(self.subtasks) * 22
            self.setMinimumHeight(130 + extra_h)
            self.setMaximumHeight(350 + extra_h)
        else:
            self.expanded_container.hide()
            self.arrow_lbl.setText("▼")
            self.setFixedHeight(65)
        self.updateGeometry()

    def _set_default_style(self):
        self.setStyleSheet("""
            TaskCard {
                background-color: #222222;
                border: 1px solid #333333;
                border-radius: 3px;
            }
            TaskCard:hover {
                background-color: #262626;
                border: 1px solid #4E4E4E;
            }
        """)

    def _set_ghost_style(self):
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

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.drag_start_position = event.pos()
            self._drag_started = False

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            if not self._drag_started and (event.pos() - self.drag_start_position).manhattanLength() < 8:
                self.toggle_expand()

    def mouseDoubleClickEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.open_requested.emit(self.task_id)

    def mouseMoveEvent(self, event):
        if not (event.buttons() & Qt.LeftButton):
            return
        if (event.pos() - self.drag_start_position).manhattanLength() >= 8:
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

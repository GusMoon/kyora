"""
Componente visual de tarjeta de tarea (TaskCard) dentro del tablero Kanban.
Diseño SciFi de Kiora con altura uniforme y vista extendida adaptable con scroll:
- Vista principal compacta (68px fija): barra de acento, título, subtareas, fecha.
  Sin preview de descripción en la vista principal para mantener consistencia visual.
- 1 Clic: Abre/cierra la vista extendida con la descripción completa.
  El contenedor adapta su alto al texto hasta un límite con scroll vertical fluido.
- 2 Clics: Abre el modal de metadatos y edición completa (taskMetadata).
- Arrastrar (Drag & Drop): Mueve la tarea entre columnas Kanban.
"""
from typing import Optional, List
from datetime import datetime

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QLabel, QHBoxLayout, 
    QFrame, QPushButton, QSizePolicy, QScrollArea
)
from PySide6.QtCore import Qt, Signal, QMimeData, QPoint, QRect, QTimer
from PySide6.QtGui import QDrag, QPixmap, QFont, QFontMetrics, QColor

from core.matrix.ecosystems.tasks.domain.entities import SubTask
from core.matrix.ecosystems.motherBoard.globalComponents.styles import get_minimal_scrollbar_style
from core.matrix.ecosystems.tasks.presentation.rootComponents.taskMetadata.fading_text_edit import FadingScrollArea


class TaskCard(QWidget):
    """
    Tarjeta de tarea interactiva dentro del tablero Kanban.

    Interacciones:
    - 1 Clic: Si la tarea tiene descripción, expande/colapsa la vista de descripción.
    - 2 Clics (Doble clic): Abre el modal flotante de metadatos y edición completa.
    - Arrastrar: Mueve la tarjeta entre columnas de estado.
    - Botón ✕: Solicita la eliminación de la tarea.
    """
    move_status_requested = Signal(str, str)
    open_requested = Signal(str)
    delete_requested = Signal(str)
    toggle_subtask_requested = Signal(str, str, bool)

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

        self.is_expanded = False
        self.drag_start_position = QPoint()
        self._drag_started = False

        # Altura fija de la vista principal cerrada
        self.base_height = 68
        self.calculated_desc_height = self._compute_description_height()

        self.setAttribute(Qt.WA_StyledBackground, True)
        self.setCursor(Qt.PointingHandCursor)
        self._set_default_style()
        self.setFixedHeight(self.base_height)

        # Timer para desacoplar 1 clic (expandir) de 2 clics (abrir detalle en modal)
        self._click_timer = QTimer(self)
        self._click_timer.setSingleShot(True)
        self._click_timer.setInterval(220)
        self._click_timer.timeout.connect(self._handle_single_click)

        self._setup_ui()

    def _compute_description_height(self) -> int:
        """
        Calcula la altura adaptada para el contenedor de descripción según el texto,
        garantizando un rango visualmente balanceado (65px - 180px) con scroll.
        """
        if not self.has_description:
            return 0

        font = QFont("Space Grotesk", 12)
        fm = QFontMetrics(font)
        # Ancho utilizable dentro del área de texto del card
        usable_width = 300
        bounding = fm.boundingRect(QRect(0, 0, usable_width, 10000), Qt.TextWordWrap, self.description_text)
        # Altura del texto + etiqueta de encabezado + padding superior/inferior
        needed_height = bounding.height() + 52
        return max(65, min(needed_height, 180))

    def _setup_ui(self):
        # Layout principal vertical del Card
        self.card_main_layout = QVBoxLayout(self)
        self.card_main_layout.setContentsMargins(0, 0, 0, 0)
        self.card_main_layout.setSpacing(0)

        # =============================================================
        # 1. FILA COMPACTA (Vista principal sin descripción)
        # =============================================================
        self.compact_widget = QWidget()
        self.compact_widget.setFixedHeight(self.base_height)
        compact_layout = QHBoxLayout(self.compact_widget)
        compact_layout.setContentsMargins(0, 0, 0, 0)
        compact_layout.setSpacing(0)

        # Barra lateral de estado Kanban
        status_norm = self.current_status.strip().lower().replace("-", "_")
        if status_norm == "completed":
            accent_color = "#00FA9A"
        elif status_norm in ("in_progress", "in-progress"):
            accent_color = "#00BFFF"
        else:
            accent_color = "#FFA500"

        self.accent_bar = QFrame()
        self.accent_bar.setFixedWidth(5)
        self.accent_bar.setFixedHeight(self.base_height)
        self.accent_bar.setStyleSheet(f"background-color: {accent_color};")
        compact_layout.addWidget(self.accent_bar)

        # Contenido Central (Título + Subtareas + Indicador Expandir)
        center_layout = QVBoxLayout()
        center_layout.setContentsMargins(12, 8, 8, 8)
        center_layout.setSpacing(4)
        center_layout.setAlignment(Qt.AlignVCenter)

        # Fila superior: Título y botón ✕
        top_row = QHBoxLayout()
        top_row.setContentsMargins(0, 0, 0, 0)
        top_row.setSpacing(4)

        title_label = QLabel(self.title_text.upper())
        title_label.setWordWrap(False)
        title_label.setStyleSheet(
            "font-weight: 900; font-size: 13px; font-family: 'Space Grotesk'; "
            "color: #FFFFFF; letter-spacing: 0.8px;"
        )
        top_row.addWidget(title_label)
        top_row.addStretch()

        # Botón de eliminación (✕)
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
        top_row.addWidget(self.btn_delete)
        center_layout.addLayout(top_row)

        # Fila inferior: Categoría, Subtareas, Tiempo e indicador de descripción
        footer_info_row = QHBoxLayout()
        footer_info_row.setContentsMargins(0, 0, 0, 0)
        footer_info_row.setSpacing(6)

        # Badge de Categoría (TAR-026, TAR-047)
        if self.category_name:
            cat_color = self.category_color or "#FFAA77"
            lbl_cat_badge = QLabel(f"● {self.category_name.upper()}")
            lbl_cat_badge.setStyleSheet(f"""
                QLabel {{
                    color: {cat_color};
                    font-size: 9px;
                    font-weight: bold;
                    font-family: 'Space Grotesk';
                    background-color: #121212;
                    border: 1px solid {cat_color};
                    border-radius: 3px;
                    padding: 1px 4px;
                }}
            """)
            footer_info_row.addWidget(lbl_cat_badge)

        if self.subtasks:
            done_cnt = sum(1 for st in self.subtasks if st.is_completed)
            tot_cnt = len(self.subtasks)
            sub_text = f"☑ {done_cnt}/{tot_cnt}" if done_cnt > 0 else f"☑ {tot_cnt}"

            lbl_sub_info = QLabel(sub_text)
            lbl_sub_info.setStyleSheet("""
                QLabel {
                    color: #FFAA77;
                    font-size: 10px;
                    font-weight: bold;
                    font-family: 'Space Grotesk';
                }
            """)
            footer_info_row.addWidget(lbl_sub_info)

        # Badge de Tiempo estimado / invertido (TAR-032, TAR-042)
        time_badge_txt = ""
        if self.time_spent_seconds > 0:
            sp_m = self.time_spent_seconds // 60
            if self.estimated_duration_minutes:
                time_badge_txt = f"⏱ {sp_m}m/{self.estimated_duration_minutes}m"
            else:
                time_badge_txt = f"⏱ {sp_m}m"
        elif self.estimated_duration_minutes:
            h = self.estimated_duration_minutes // 60
            m = self.estimated_duration_minutes % 60
            dur_txt = f"{h}h{m}m" if h > 0 and m > 0 else (f"{h}h" if h > 0 else f"{m}m")
            time_badge_txt = f"⏱ {dur_txt}"

        if time_badge_txt:
            lbl_time_badge = QLabel(time_badge_txt)
            lbl_time_badge.setStyleSheet("""
                QLabel {
                    color: #999999;
                    font-size: 10px;
                    font-family: 'Space Grotesk';
                }
            """)
            footer_info_row.addWidget(lbl_time_badge)

        footer_info_row.addStretch()

        # Indicador para desplegar descripción si la tarea la contiene
        if self.has_description:
            self.arrow_lbl = QLabel("▼")
            self.arrow_lbl.setStyleSheet("""
                QLabel {
                    color: #777777;
                    font-size: 10px;
                    font-weight: bold;
                    font-family: 'Space Grotesk';
                }
            """)
            footer_info_row.addWidget(self.arrow_lbl)

        center_layout.addLayout(footer_info_row)
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
        date_frame.setFixedHeight(self.base_height)
        date_frame.setStyleSheet("background-color: #1A1A1A; border-left: 1px solid #333333;")

        date_layout = QVBoxLayout(date_frame)
        date_layout.setContentsMargins(0, 8, 0, 8)
        date_layout.setSpacing(2)

        day_lbl = QLabel(day_str)
        day_lbl.setAlignment(Qt.AlignCenter)
        day_lbl.setStyleSheet("font-size: 18px; font-family: 'Space Grotesk'; color: #FFFFFF; font-weight: 900;")

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

        # =============================================================
        # 2. VISTA EXTENDIDA: DESCRIPCIÓN COMPLETA CON SCROLL ADAPTABLE
        # =============================================================
        if self.has_description:
            self.expanded_container = QFrame()
            self.expanded_container.setStyleSheet(
                "background-color: #141414; border-top: 1px solid #2A2A2A; "
                "border-bottom-left-radius: 4px; border-bottom-right-radius: 4px;"
            )
            self.expanded_container.hide()

            expanded_layout = QVBoxLayout(self.expanded_container)
            expanded_layout.setContentsMargins(0, 0, 0, 0)
            expanded_layout.setSpacing(0)

            # Scroll Area Sci-Fi con barras minimalistas y efecto sutil de desvanecimiento
            self.desc_scroll = FadingScrollArea(bg_color=QColor(20, 20, 20))
            self.desc_scroll.setWidgetResizable(True)
            self.desc_scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
            self.desc_scroll.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
            self.desc_scroll.setFixedHeight(self.calculated_desc_height)
            self.desc_scroll.setStyleSheet(
                get_minimal_scrollbar_style() + """
                QScrollArea {
                    border: none;
                    background-color: transparent;
                }
                QWidget {
                    background-color: transparent;
                }
                """
            )

            desc_content_widget = QWidget()
            desc_content_widget.setStyleSheet("background: transparent;")
            desc_content_layout = QVBoxLayout(desc_content_widget)
            desc_content_layout.setContentsMargins(14, 10, 14, 10)
            desc_content_layout.setSpacing(6)

            desc_title = QLabel("DESCRIPCIÓN COMPLETA:")
            desc_title.setStyleSheet(
                "font-size: 10px; font-family: 'Space Grotesk'; color: #FFAA77; "
                "font-weight: bold; letter-spacing: 1px;"
            )
            desc_content_layout.addWidget(desc_title)

            self.desc_text_lbl = QLabel(self.description_text)
            self.desc_text_lbl.setWordWrap(True)
            self.desc_text_lbl.setStyleSheet("""
                QLabel {
                    color: #E2E2E2;
                    font-size: 12px;
                    font-family: 'Space Grotesk';
                    line-height: 1.45;
                }
            """)
            desc_content_layout.addWidget(self.desc_text_lbl)
            desc_content_layout.addStretch()

            self.desc_scroll.setWidget(desc_content_widget)
            self.desc_scroll.viewport().installEventFilter(self)
            expanded_layout.addWidget(self.desc_scroll)

            self.card_main_layout.addWidget(self.expanded_container)
        else:
            self.expanded_container = None
            self.desc_scroll = None

    def toggle_expand(self):
        """
        Alterna la vista extendida mostrando/ocultando la descripción completa.
        Adapta la altura del contenedor al texto sin romper proporciones.
        """
        if not self.has_description or not self.expanded_container:
            return

        self.is_expanded = not self.is_expanded
        if self.is_expanded:
            self.expanded_container.show()
            if hasattr(self, "arrow_lbl"):
                self.arrow_lbl.setText("▲ Ocultar")
            self.setFixedHeight(self.base_height + self.calculated_desc_height)
        else:
            self.expanded_container.hide()
            if hasattr(self, "arrow_lbl"):
                self.arrow_lbl.setText("▼ Descripción")
            self.setFixedHeight(self.base_height)
        self.updateGeometry()

    def _set_default_style(self):
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

    def _handle_single_click(self):
        """Manejador ejecutado al detectar 1 solo clic tras el timeout."""
        if self.has_description:
            self.toggle_expand()

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.drag_start_position = event.pos()
            self._drag_started = False
        super().mousePressEvent(event)

    def mouseReleaseEvent(self, event):
        if event.button() == Qt.LeftButton:
            if not self._drag_started and (event.pos() - self.drag_start_position).manhattanLength() < 8:
                # Inicia el timer de un solo clic si no se disparó ya
                if self._click_timer.isActive():
                    self._click_timer.stop()
                self._click_timer.start(220)
        super().mouseReleaseEvent(event)

    def mouseDoubleClickEvent(self, event):
        if event.button() == Qt.LeftButton:
            # Si hay doble clic, cancelar el timer de 1 clic y abrir el modal
            if self._click_timer.isActive():
                self._click_timer.stop()
            self.open_requested.emit(self.task_id)
        super().mouseDoubleClickEvent(event)

    def eventFilter(self, watched, event):
        """Permite que el doble clic sobre el área de descripción también abra taskMetadata."""
        if hasattr(self, "desc_scroll") and self.desc_scroll and watched == self.desc_scroll.viewport():
            if event.type() == event.Type.MouseButtonDblClick and event.button() == Qt.LeftButton:
                if self._click_timer.isActive():
                    self._click_timer.stop()
                self.open_requested.emit(self.task_id)
                return True
        return super().eventFilter(watched, event)

    def mouseMoveEvent(self, event):
        if not (event.buttons() & Qt.LeftButton):
            return
        if (event.pos() - self.drag_start_position).manhattanLength() >= 8:
            # Al iniciar arrastre, cancelar cualquier click pendiente
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

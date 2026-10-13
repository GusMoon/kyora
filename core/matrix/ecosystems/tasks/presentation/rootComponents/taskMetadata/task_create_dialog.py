"""
Diálogo modal para el registro y creación de una nueva tarea.
Diseño Split-Panel con FolderContainer a la izquierda y notas extensas a la derecha.
Incluye selección y creación de categorías (TAR-026 a TAR-028) y estimación de tiempo (TAR-032 a TAR-034).
"""
import uuid
from typing import Optional, Dict, List, Callable

from PySide6.QtWidgets import (
    QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QTextEdit, QPushButton, QDateEdit, QWidget, QFrame,
    QScrollArea, QStackedWidget, QProgressBar, QComboBox, QSpinBox
)
from PySide6.QtCore import Qt, QDate, Signal, QPointF, QCoreApplication, QEvent
from PySide6.QtGui import QMouseEvent
from core.matrix.ecosystems.motherBoard.globalComponents.styles import get_minimal_scrollbar_style
from core.matrix.ecosystems.motherBoard.globalComponents.icons.calendar import get_calendar_icon
from core.matrix.ecosystems.tasks.domain.entities import SubTask, Category

from .base_modal import SciFiBaseModal
from .toggle_switch import PillToggleSwitch
from .folder_container import FolderContainer
from .subtask_item import SubtaskEditorItem
from .fading_text_edit import FadingScrollTextEdit
from .category_dialog import CategoryCreateDialog


class TaskCreateDialog(SciFiBaseModal):
    """
    Diálogo para registrar una nueva tarea.
    Panel Izquierdo: FolderContainer continuo con pestañas ('General' y 'Subtareas').
    Panel Derecho: Gran área de descripción y notas con scroll en fondo negro puro.
    """

    def __init__(
        self,
        parent=None,
        initial_status: str = "pending",
        categories: Optional[List[Category]] = None,
        create_category_callback: Optional[Callable[[str, str], Optional[Category]]] = None
    ):
        super().__init__(parent, width=940, height=580)
        self.initial_status = initial_status
        self.categories = categories or []
        self.create_category_callback = create_category_callback
        self.subtask_items: List[SubtaskEditorItem] = []
        self._setup_ui()

    def _setup_ui(self):
        root_layout = QVBoxLayout(self)
        root_layout.setContentsMargins(14, 12, 14, 14)
        root_layout.setSpacing(8)

        # =============================================================
        # BARRA SUPERIOR DE VENTANA: Título unificado y botón de cierre
        # =============================================================
        window_header = QHBoxLayout()
        window_header.setContentsMargins(4, 0, 4, 0)
        window_header.setSpacing(10)

        title_box = QHBoxLayout()
        title_box.setSpacing(8)
        title_lbl = QLabel("CREAR NUEVA TAREA")
        title_lbl.setObjectName("Title")
        title_lbl.setCursor(Qt.SizeAllCursor)
        title_lbl.setToolTip("Haz clic y arrastra para mover esta ventana por la pantalla")

        title_box.addWidget(title_lbl)
        window_header.addLayout(title_box)
        window_header.addStretch()

        btn_close = QPushButton("✕")
        btn_close.setFixedSize(24, 24)
        btn_close.setCursor(Qt.PointingHandCursor)
        btn_close.setStyleSheet("""
            QPushButton {
                background: transparent;
                color: #888888;
                border: none;
                font-size: 13px;
                font-weight: bold;
                padding: 0px;
            }
            QPushButton:hover {
                color: #FFFFFF;
                background-color: #2D2D2D;
                border-radius: 3px;
            }
        """)
        btn_close.clicked.connect(self.reject)
        window_header.addWidget(btn_close)
        root_layout.addLayout(window_header)

        # =============================================================
        # CONTENIDO PRINCIPAL: Split-Panel (46% Izquierdo / 54% Derecho)
        # =============================================================
        content_layout = QHBoxLayout()
        content_layout.setContentsMargins(0, 4, 0, 0)
        content_layout.setSpacing(12)

        # PANEL IZQUIERDO: FolderContainer que integra las pestañas en su borde
        self.folder_container = FolderContainer(
            self,
            tabs_def=[
                ("General", "Parámetros y fecha"),
                ("Subtareas", "Sin subtareas")
            ]
        )

        # Stack de contenidos según la pestaña seleccionada
        self.stack = QStackedWidget(self.folder_container)

        # -------------------------------------------------------------
        # PESTAÑA 0: GENERAL (Nombre, categoría, duración y fecha)
        # -------------------------------------------------------------
        page_general = QWidget()
        page_gen_layout = QVBoxLayout(page_general)
        page_gen_layout.setContentsMargins(0, 2, 0, 2)
        page_gen_layout.setSpacing(8)

        # Campo: Nombre de la tarea
        lbl_title = QLabel("NOMBRE DE LA TAREA *:")
        lbl_title.setStyleSheet("font-size: 11px; font-weight: bold; color: #CCCCCC;")
        self.title_input = QLineEdit()
        self.title_input.setPlaceholderText("Ej. Implementar arquitectura relacional...")
        page_gen_layout.addWidget(lbl_title)
        page_gen_layout.addWidget(self.title_input)

        # Campo: Categoría (TAR-026, TAR-028, TAR-031)
        lbl_cat = QLabel("CATEGORÍA (OPCIONAL):")
        lbl_cat.setStyleSheet("font-size: 11px; font-weight: bold; color: #CCCCCC;")
        page_gen_layout.addWidget(lbl_cat)

        cat_row = QHBoxLayout()
        cat_row.setSpacing(6)

        self.combo_category = QComboBox()
        self.combo_category.setFixedHeight(28)
        self.combo_category.setStyleSheet("""
            QComboBox {
                background-color: #171717;
                border: 1px solid #2A2A2A;
                border-radius: 4px;
                color: #E0E0E0;
                font-family: 'Space Grotesk';
                font-size: 11px;
                padding-left: 8px;
            }
            QComboBox:hover {
                border-color: #3E3E3E;
            }
            QComboBox::drop-down {
                border: none;
                width: 20px;
            }
            QComboBox QAbstractItemView {
                background-color: #1A1A1A;
                border: 1px solid #333333;
                selection-background-color: #2D2D2D;
                color: #FFFFFF;
                outline: none;
            }
        """)
        self._populate_categories()
        cat_row.addWidget(self.combo_category, 1)

        self.btn_new_cat = QPushButton("+ NUEVA")
        self.btn_new_cat.setFixedHeight(28)
        self.btn_new_cat.setCursor(Qt.PointingHandCursor)
        self.btn_new_cat.setToolTip("Crear una categoría personalizada")
        self.btn_new_cat.setStyleSheet("""
            QPushButton {
                background-color: #222222;
                border: 1px solid #383838;
                color: #FFAA77;
                font-size: 10px;
                font-weight: bold;
                padding: 0 10px;
                border-radius: 4px;
            }
            QPushButton:hover {
                background-color: #2D2D2D;
                border-color: #FFAA77;
            }
        """)
        self.btn_new_cat.clicked.connect(self._on_create_category_clicked)
        cat_row.addWidget(self.btn_new_cat)
        page_gen_layout.addLayout(cat_row)

        # Contenedor de Duración Estimada con PillToggleSwitch (TAR-032 a TAR-034)
        time_card = QFrame()
        time_card.setStyleSheet("""
            QFrame {
                background-color: #171717;
                border: 1px solid #2A2A2A;
                border-radius: 5px;
                padding: 2px;
            }
        """)
        time_card_layout = QVBoxLayout(time_card)
        time_card_layout.setContentsMargins(10, 6, 10, 6)
        time_card_layout.setSpacing(6)

        self.toggle_duration = PillToggleSwitch("Activar tiempo del cronómetro", checked=False)
        self.toggle_duration.toggled.connect(self._on_duration_toggled)
        time_card_layout.addWidget(self.toggle_duration)

        self.duration_container = QWidget()
        duration_sublayout = QVBoxLayout(self.duration_container)
        duration_sublayout.setContentsMargins(0, 2, 0, 0)
        duration_sublayout.setSpacing(4)

        dur_row = QHBoxLayout()
        dur_row.setSpacing(8)
        lbl_h = QLabel("Horas:")
        lbl_h.setStyleSheet("color: #888888; font-size: 11px;")
        self.spin_hours = QSpinBox()
        self.spin_hours.setRange(0, 23)
        self.spin_hours.setValue(0)
        self.spin_hours.setFixedWidth(52)
        self.spin_hours.setFixedHeight(26)
        self.spin_hours.setStyleSheet("background-color: #222222; border: 1px solid #3A3A3A; color: #FFFFFF;")

        lbl_m = QLabel("Minutos:")
        lbl_m.setStyleSheet("color: #888888; font-size: 11px;")
        self.spin_mins = QSpinBox()
        self.spin_mins.setRange(0, 59)
        self.spin_mins.setValue(30)
        self.spin_mins.setFixedWidth(52)
        self.spin_mins.setFixedHeight(26)
        self.spin_mins.setStyleSheet("background-color: #222222; border: 1px solid #3A3A3A; color: #FFFFFF;")

        dur_row.addWidget(lbl_h)
        dur_row.addWidget(self.spin_hours)
        dur_row.addWidget(lbl_m)
        dur_row.addWidget(self.spin_mins)
        dur_row.addStretch()
        duration_sublayout.addLayout(dur_row)

        self.duration_container.setVisible(False)
        time_card_layout.addWidget(self.duration_container)
        page_gen_layout.addWidget(time_card)

        # Contenedor de Fecha de Entrega con PillToggleSwitch
        date_card = QFrame()
        date_card.setStyleSheet("""
            QFrame {
                background-color: #171717;
                border: 1px solid #2A2A2A;
                border-radius: 5px;
                padding: 2px;
            }
        """)
        date_card_layout = QVBoxLayout(date_card)
        date_card_layout.setContentsMargins(10, 6, 10, 6)
        date_card_layout.setSpacing(6)

        self.toggle_due_date = PillToggleSwitch("Activar fecha de entrega", checked=False)
        self.toggle_due_date.toggled.connect(self._on_due_date_toggled)
        date_card_layout.addWidget(self.toggle_due_date)

        # Contenedor desplegable del selector de fecha
        self.date_picker_container = QWidget()
        date_picker_sublayout = QVBoxLayout(self.date_picker_container)
        date_picker_sublayout.setContentsMargins(0, 2, 0, 0)
        date_picker_sublayout.setSpacing(4)

        date_input_row = QHBoxLayout()
        date_input_row.setSpacing(8)

        self.btn_calendar = QPushButton()
        self.btn_calendar.setIcon(get_calendar_icon(size=18, color="#FFAA77"))
        self.btn_calendar.setFixedSize(28, 28)
        self.btn_calendar.setCursor(Qt.PointingHandCursor)
        self.btn_calendar.setToolTip("Abrir selector de calendario")
        self.btn_calendar.setStyleSheet("""
            QPushButton {
                background-color: #242424;
                border: 1px solid #3E3E3E;
                border-radius: 4px;
                padding: 0px;
            }
            QPushButton:hover {
                background-color: #2E2E2E;
                border: 1px solid #FFAA77;
            }
        """)
        self.btn_calendar.clicked.connect(self._toggle_calendar_popup)

        self.date_edit = QDateEdit(QDate.currentDate().addDays(3))
        self.date_edit.setCalendarPopup(True)
        self.date_edit.setFixedWidth(130)
        self.date_edit.setFixedHeight(28)

        date_input_row.addWidget(self.btn_calendar)
        date_input_row.addWidget(self.date_edit)
        date_input_row.addStretch()
        date_picker_sublayout.addLayout(date_input_row)

        quick_grid = QVBoxLayout()
        quick_grid.setSpacing(3)
        row1 = QHBoxLayout()
        row1.setSpacing(4)
        row2 = QHBoxLayout()
        row2.setSpacing(4)

        for label, days, target_row in [
            ("+1 DÍA", 1, row1), ("+3 DÍAS", 3, row1), ("+5 DÍAS", 5, row1),
            ("+7 DÍAS", 7, row2), ("+15 DÍAS", 15, row2), ("+30 DÍAS", 30, row2)
        ]:
            b = QPushButton(label)
            b.setStyleSheet("font-size: 9px; padding: 3px 6px; background-color: #262626; border: 1px solid #3A3A3A;")
            b.clicked.connect(lambda _, d=days: self.date_edit.setDate(QDate.currentDate().addDays(d)))
            target_row.addWidget(b)

        quick_grid.addLayout(row1)
        quick_grid.addLayout(row2)
        date_picker_sublayout.addLayout(quick_grid)

        self.date_picker_container.setVisible(False)
        date_card_layout.addWidget(self.date_picker_container)
        page_gen_layout.addWidget(date_card)

        page_gen_layout.addStretch()
        self.stack.addWidget(page_general)

        # -------------------------------------------------------------
        # PESTAÑA 1: SUBTAREAS (CRUD COMPLETO)
        # -------------------------------------------------------------
        page_subtasks = QWidget()
        page_sub_layout = QVBoxLayout(page_subtasks)
        page_sub_layout.setContentsMargins(0, 2, 0, 4)
        page_sub_layout.setSpacing(8)

        stats_row = QHBoxLayout()
        self.lbl_subtasks_stats = QLabel("0 subtareas registradas")
        self.lbl_subtasks_stats.setStyleSheet("font-size: 11px; color: #888888; font-weight: bold;")

        self.subtasks_progress = QProgressBar()
        self.subtasks_progress.setFixedHeight(6)
        self.subtasks_progress.setTextVisible(False)
        self.subtasks_progress.setStyleSheet("""
            QProgressBar {
                background-color: #222222;
                border: none;
                border-radius: 3px;
            }
            QProgressBar::chunk {
                background-color: #FFAA77;
                border-radius: 3px;
            }
        """)
        self.subtasks_progress.setValue(0)

        stats_row.addWidget(self.lbl_subtasks_stats)
        stats_row.addSpacing(10)
        stats_row.addWidget(self.subtasks_progress)
        page_sub_layout.addLayout(stats_row)

        add_box = QHBoxLayout()
        self.new_subtask_input = QLineEdit()
        self.new_subtask_input.setPlaceholderText("Nueva subtarea (presiona Enter o Añadir)...")
        self.new_subtask_input.returnPressed.connect(self._on_add_subtask_from_input)

        btn_add = QPushButton("+ AÑADIR")
        btn_add.setStyleSheet("background-color: #2C2C2C; border: 1px solid #444444; color: #FFFFFF; font-size: 11px; padding: 6px 12px;")
        btn_add.clicked.connect(self._on_add_subtask_from_input)

        add_box.addWidget(self.new_subtask_input)
        add_box.addWidget(btn_add)
        page_sub_layout.addLayout(add_box)

        self.subtasks_scroll = QScrollArea()
        self.subtasks_scroll.setWidgetResizable(True)
        self.subtasks_scroll.setStyleSheet(
            get_minimal_scrollbar_style() +
            "QScrollArea { border: 1px solid #2C2C2C; background-color: #161616; border-radius: 4px; }"
        )

        self.subtasks_container = QWidget()
        self.subtasks_container.setStyleSheet("background: transparent;")
        self.subtasks_layout = QVBoxLayout(self.subtasks_container)
        self.subtasks_layout.setContentsMargins(6, 6, 6, 6)
        self.subtasks_layout.setSpacing(6)
        self.subtasks_layout.setAlignment(Qt.AlignTop)

        self.empty_subtasks_lbl = QLabel("✦ No hay subtareas añadidas.\nUsa el campo superior para desglosar la tarea.")
        self.empty_subtasks_lbl.setAlignment(Qt.AlignCenter)
        self.empty_subtasks_lbl.setStyleSheet("color: #555555; font-size: 11px; padding: 30px;")
        self.subtasks_layout.addWidget(self.empty_subtasks_lbl)
        self.subtasks_layout.addStretch()

        self.subtasks_scroll.setWidget(self.subtasks_container)
        page_sub_layout.addWidget(self.subtasks_scroll)

        self.stack.addWidget(page_subtasks)
        self.folder_container.layout_inner.addWidget(self.stack)

        self.folder_container.tabChanged.connect(self.stack.setCurrentIndex)
        content_layout.addWidget(self.folder_container, 46)

        # =============================================================
        # PANEL DERECHO: Descripción extensa (Notas) y Botones inferiores
        # =============================================================
        right_panel = QWidget()
        right_panel_layout = QVBoxLayout(right_panel)
        right_panel_layout.setContentsMargins(0, 0, 0, 0)
        right_panel_layout.setSpacing(8)

        lbl_desc_title = QLabel("DESCRIPCIÓN Y NOTAS DE LA ACTIVIDAD:")
        lbl_desc_title.setStyleSheet("font-size: 11px; font-weight: bold; color: #CCCCCC; letter-spacing: 0.5px;")
        right_panel_layout.addWidget(lbl_desc_title)

        self.desc_input = FadingScrollTextEdit()
        self.desc_input.setPlaceholderText(
            "Detalla la actividad, requerimientos, enlaces o criterios de aceptación...\n\n"
            "• Soporta múltiples párrafos y listas\n"
            "• Desplazamiento vertical fluido con efecto sutil"
        )
        self.desc_input.setStyleSheet("""
            QTextEdit {
                background-color: #0D0D0D;
                border: 1px solid #282828;
                border-radius: 5px;
                color: #DDDDDD;
                font-family: 'Space Grotesk';
                font-size: 12px;
                padding: 10px;
                line-height: 1.4;
            }
            QTextEdit:focus {
                border: 1px solid #FFAA77;
            }
        """)
        right_panel_layout.addWidget(self.desc_input, 1)

        bottom_actions = QHBoxLayout()
        bottom_actions.setContentsMargins(0, 4, 0, 0)
        bottom_actions.setSpacing(10)

        self.error_lbl = QLabel("")
        self.error_lbl.setStyleSheet("color: #FF5555; font-size: 11px;")
        bottom_actions.addWidget(self.error_lbl)
        bottom_actions.addStretch()

        btn_cancel = QPushButton("CANCELAR")
        btn_cancel.setStyleSheet("""
            QPushButton {
                background: transparent;
                border: 1px solid #333333;
                color: #888888;
                padding: 7px 16px;
                font-size: 11px;
                font-weight: bold;
                border-radius: 4px;
            }
            QPushButton:hover {
                color: #FFFFFF;
                border-color: #555555;
            }
        """)
        btn_cancel.clicked.connect(self.reject)
        bottom_actions.addWidget(btn_cancel)

        btn_create = QPushButton("CREAR TAREA")
        btn_create.setStyleSheet("""
            QPushButton {
                background-color: #A31F34;
                border: 1px solid #C42B42;
                color: #FFFFFF;
                font-weight: bold;
                padding: 7px 20px;
                font-size: 11px;
                border-radius: 4px;
                letter-spacing: 0.5px;
            }
            QPushButton:hover {
                background-color: #B9263D;
            }
        """)
        btn_create.clicked.connect(self._on_save_clicked)
        bottom_actions.addWidget(btn_create)

        right_panel_layout.addLayout(bottom_actions)
        content_layout.addWidget(right_panel, 54)
        root_layout.addLayout(content_layout)

        self.title_input.setFocus()

    def _populate_categories(self):
        self.combo_category.clear()
        self.combo_category.addItem("[Sin categoría]", None)
        for cat in self.categories:
            self.combo_category.addItem(f"● {cat.name}", cat.id)

    def _on_create_category_clicked(self):
        diag = CategoryCreateDialog(self)
        if diag.exec() == SciFiBaseModal.Accepted:
            data = diag.get_data()
            if self.create_category_callback:
                new_cat = self.create_category_callback(data["name"], data["color"])
                if new_cat:
                    self.categories.append(new_cat)
                    self._populate_categories()
                    # Seleccionar la nueva categoría
                    idx = self.combo_category.findData(new_cat.id)
                    if idx >= 0:
                        self.combo_category.setCurrentIndex(idx)

    def _on_duration_toggled(self, active: bool):
        self.duration_container.setVisible(active)

    def _on_due_date_toggled(self, active: bool):
        self.date_picker_container.setVisible(active)

    def _toggle_calendar_popup(self):
        cal_container = self.date_edit.findChild(QWidget, "qt_datetimedit_calendar")
        if cal_container and cal_container.isVisible():
            cal_container.hide()
            return

        pt = QPointF(self.date_edit.width() - 8, self.date_edit.height() / 2.0)
        ev_press = QMouseEvent(
            QEvent.Type.MouseButtonPress, pt, pt,
            Qt.MouseButton.LeftButton, Qt.MouseButton.LeftButton,
            Qt.KeyboardModifier.NoModifier
        )
        ev_release = QMouseEvent(
            QEvent.Type.MouseButtonRelease, pt, pt,
            Qt.MouseButton.LeftButton, Qt.MouseButton.LeftButton,
            Qt.KeyboardModifier.NoModifier
        )
        QCoreApplication.sendEvent(self.date_edit, ev_press)
        QCoreApplication.sendEvent(self.date_edit, ev_release)

    def _on_add_subtask_from_input(self):
        text = self.new_subtask_input.text().strip()
        if not text:
            return

        dummy_subtask = SubTask(
            id=str(uuid.uuid4()),
            task_id="",
            title=text,
            is_completed=False
        )
        item = SubtaskEditorItem(subtask=dummy_subtask, parent=self.subtasks_container)
        item.remove_requested.connect(self._remove_subtask_item)
        item.status_changed.connect(lambda _: self._update_subtasks_stats())

        self.subtasks_layout.insertWidget(len(self.subtask_items) + 1, item)
        self.subtask_items.append(item)
        self.new_subtask_input.clear()
        self.new_subtask_input.setFocus()
        self._update_subtasks_stats()

    def _remove_subtask_item(self, item: SubtaskEditorItem):
        if item in self.subtask_items:
            self.subtask_items.remove(item)
        item.deleteLater()
        self._update_subtasks_stats()

    def _update_subtasks_stats(self):
        total = len(self.subtask_items)
        self.empty_subtasks_lbl.setVisible(total == 0)

        completed = sum(1 for item in self.subtask_items if item.is_completed())
        pct = int((completed / total) * 100) if total > 0 else 0

        self.subtasks_progress.setValue(pct)
        if total == 0:
            self.lbl_subtasks_stats.setText("0 subtareas registradas")
        else:
            self.lbl_subtasks_stats.setText(f"{completed} de {total} completadas ({pct}%)")

        self.folder_container.update_subtasks_count(total, completed)

    def _on_save_clicked(self):
        title = self.title_input.text().strip()
        if not title:
            self.error_lbl.setText("El nombre de la tarea no puede estar vacío.")
            self.folder_container.set_current_index(0)
            self.title_input.setFocus()
            return

        self.accept()

    def get_data(self) -> Dict[str, Optional[object]]:
        due_date = None
        if self.toggle_due_date.isChecked():
            due_date = self.date_edit.date().toString("yyyy-MM-dd")

        estimated_duration = None
        if self.toggle_duration.isChecked():
            total_m = (self.spin_hours.value() * 60) + self.spin_mins.value()
            if total_m > 0:
                estimated_duration = total_m

        subs = []
        for item in self.subtask_items:
            st = item.to_subtask(position=len(subs))
            if st and st.title:
                subs.append(st.title)

        cat_id = self.combo_category.currentData()

        return {
            "title": self.title_input.text().strip(),
            "description": self.desc_input.toPlainText().strip(),
            "due_date": due_date,
            "status": self.initial_status,
            "subtasks": subs,
            "category_id": cat_id,
            "estimated_duration_minutes": estimated_duration
        }

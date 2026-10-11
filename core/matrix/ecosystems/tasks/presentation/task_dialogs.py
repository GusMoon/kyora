import uuid
from typing import Optional, Dict, List
from datetime import datetime

from PySide6.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit,
    QTextEdit, QPushButton, QDateEdit, QWidget, QFrame,
    QScrollArea, QStackedWidget, QProgressBar, QSizePolicy
)
from PySide6.QtCore import Qt, QDate, Signal, QRectF
from PySide6.QtGui import QPainter, QColor, QPen, QBrush, QFont, QPainterPath

from core.matrix.ecosystems.motherBoard.globalComponents.styles import get_minimal_scrollbar_style
from core.matrix.ecosystems.tasks.domain.entities import Task, SubTask


class SciFiBaseModal(QDialog):
    """
    Modal base con estilo Sci-Fi para el ecosistema de tareas.
    Permite arrastre interactivo por pantalla para ser completamente flotante y movible.
    """

    def __init__(self, parent=None, width=920, height=550):
        super().__init__(parent)
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.Dialog)
        self.resize(width, height)
        self._drag_pos = None
        self._apply_base_style()

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self._drag_pos = event.globalPosition().toPoint() - self.frameGeometry().topLeft()
            event.accept()
        else:
            super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        if (event.buttons() & Qt.LeftButton) and self._drag_pos is not None:
            self.move(event.globalPosition().toPoint() - self._drag_pos)
            event.accept()
        else:
            super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        self._drag_pos = None
        super().mouseReleaseEvent(event)

    def _apply_base_style(self):
        self.setStyleSheet(f"""
            QDialog {{
                background-color: #141414;
                border: 1px solid #444444;
                border-radius: 6px;
            }}
            QLabel {{
                color: #FFFFFF;
                font-family: 'Space Grotesk';
                font-size: 13px;
                background-color: transparent;
            }}
            QLabel#Title {{
                color: #FFFFFF;
                font-weight: 900;
                font-size: 14px;
                letter-spacing: 2px;
                font-family: 'Space Grotesk';
            }}
            QLabel#SubInfo {{
                color: #888888;
                font-size: 11px;
                font-family: 'Space Grotesk';
            }}
            QLineEdit {{
                background-color: #242424;
                border: 1px solid #3E3E3E;
                color: #FFFFFF;
                padding: 7px 10px;
                font-family: 'Space Grotesk';
                font-size: 13px;
                border-radius: 4px;
            }}
            QLineEdit:focus {{
                border: 1px solid #A31F34;
            }}
            QDateEdit {{
                background-color: #242424;
                border: 1px solid #3E3E3E;
                color: #FFFFFF;
                padding: 6px 10px;
                font-family: 'Space Grotesk';
                font-size: 12px;
                border-radius: 4px;
            }}
            QPushButton {{
                background-color: #242424;
                color: #FFFFFF;
                border: 1px solid #444444;
                padding: 7px 18px;
                font-weight: bold;
                font-family: 'Space Grotesk';
                font-size: 12px;
                border-radius: 4px;
                letter-spacing: 1px;
            }}
            QPushButton:hover {{
                background-color: #333333;
                border: 1px solid #888888;
            }}
            QPushButton#PrimaryBtn {{
                background-color: #A31F34;
                border: 1px solid #C02E44;
                color: #FFFFFF;
            }}
            QPushButton#PrimaryBtn:hover {{
                background-color: #B8253D;
            }}
            QPushButton#DangerBtn {{
                background-color: transparent;
                border: 1px solid #662222;
                color: #FF5555;
            }}
            QPushButton#DangerBtn:hover {{
                background-color: #441111;
                border: 1px solid #FF5555;
            }}
            {get_minimal_scrollbar_style()}
        """)


class PillToggleSwitch(QWidget):
    """
    Control de interruptor tipo píldora moderno y estilizado,
    inspirado en el diseño minimalista de toggle cálido (terracota / durazno) de la referencia.
    """
    toggled = Signal(bool)

    def __init__(self, text: str = "Fecha límite de entrega", checked: bool = False, parent=None):
        super().__init__(parent)
        self._checked = checked
        self._text = text
        self.setFixedHeight(34)
        self.setCursor(Qt.PointingHandCursor)
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

    def isChecked(self) -> bool:
        return self._checked

    def setChecked(self, checked: bool):
        if self._checked != checked:
            self._checked = checked
            self.toggled.emit(self._checked)
            self.update()

    def setText(self, text: str):
        self._text = text
        self.update()

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.setChecked(not self._checked)
            event.accept()
        else:
            super().mousePressEvent(event)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        w = float(self.width())
        h = float(self.height())

        # Configuración del track (píldora) a la derecha
        track_w = 46.0
        track_h = 24.0
        track_x = w - track_w - 4.0
        track_y = (h - track_h) / 2.0

        # 1. Dibujar el texto / etiqueta a la izquierda
        label_rect = QRectF(4.0, 0.0, track_x - 12.0, h)
        painter.setFont(QFont("Space Grotesk", 10, QFont.Bold if self._checked else QFont.Normal))
        # Color del texto: tono durazno/naranja #FFAA77 si está activo, o #888888 si inactivo
        text_color = QColor("#FFAA77") if self._checked else QColor("#888888")
        painter.setPen(text_color)
        painter.drawText(label_rect, Qt.AlignVCenter | Qt.AlignLeft, self._text)

        # 2. Dibujar el track tipo píldora (cápsula redondeada)
        track_path = QPainterPath()
        track_path.addRoundedRect(QRectF(track_x, track_y, track_w, track_h), track_h / 2.0, track_h / 2.0)

        if self._checked:
            track_brush = QBrush(QColor("#5C3424"))  # Terracota oscuro cálido
            painter.fillPath(track_path, track_brush)
            painter.setPen(QPen(QColor("#7A4530"), 1.0))
            painter.drawPath(track_path)
        else:
            track_brush = QBrush(QColor("#222222"))
            painter.fillPath(track_path, track_brush)
            painter.setPen(QPen(QColor("#3A3A3A"), 1.0))
            painter.drawPath(track_path)

        # 3. Dibujar el thumb circular
        thumb_diameter = 18.0
        thumb_y = track_y + (track_h - thumb_diameter) / 2.0
        if self._checked:
            thumb_x = track_x + track_w - thumb_diameter - 3.0
            thumb_color = QColor("#FFAA77")  # Naranja durazno suave como la referencia
        else:
            thumb_x = track_x + 3.0
            thumb_color = QColor("#666666")

        thumb_rect = QRectF(thumb_x, thumb_y, thumb_diameter, thumb_diameter)
        painter.setBrush(QBrush(thumb_color))
        painter.setPen(Qt.NoPen)
        painter.drawEllipse(thumb_rect)


class FolderTabButton(QWidget):
    """
    Botón individual de pestaña con silueta de solapa de carpeta (Folder tab).
    Inspirado en la primera imagen con corte diagonal achaflanado superior derecho,
    título principal en negrita y subtítulo descriptivo.
    """
    clicked = Signal(int)

    def __init__(self, index: int, title: str, subtitle: str, parent=None):
        super().__init__(parent)
        self.index = index
        self.title = title
        self.subtitle = subtitle
        self.is_active = False
        self.setFixedHeight(50)
        self.setCursor(Qt.PointingHandCursor)
        self._hover = False
        self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)

    def set_active(self, active: bool):
        self.is_active = active
        self.update()

    def set_subtitle(self, subtitle: str):
        self.subtitle = subtitle
        self.update()

    def enterEvent(self, event):
        self._hover = True
        self.update()
        super().enterEvent(event)

    def leaveEvent(self, event):
        self._hover = False
        self.update()
        super().leaveEvent(event)

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            self.clicked.emit(self.index)
            event.accept()
        else:
            super().mousePressEvent(event)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        w = float(self.width())
        h = float(self.height())
        chamfer = 16.0

        path = QPainterPath()
        if self.is_active:
            # Silueta estilo carpeta de archivo (Folder Tab activa con corte achaflanado a la derecha):
            path.moveTo(0.0, h)
            path.lineTo(0.0, 10.0)
            path.quadTo(0.0, 0.0, 10.0, 0.0)
            path.lineTo(w - chamfer, 0.0)
            path.quadTo(w - chamfer * 0.4, chamfer * 0.4, w, chamfer + 8.0)
            path.lineTo(w, h)
            path.closeSubpath()

            # Fondo activo elevado
            painter.fillPath(path, QBrush(QColor("#242424")))
            painter.setPen(QPen(QColor("#3E3E3E"), 1.0))
            painter.drawPath(path)

            # Título principal activo (Blanco, Space Grotesk Bold)
            painter.setPen(QColor("#FFFFFF"))
            painter.setFont(QFont("Space Grotesk", 11, QFont.Bold))
            painter.drawText(QRectF(14.0, 8.0, w - chamfer - 12.0, 18.0), Qt.AlignLeft | Qt.AlignVCenter, self.title)

            # Subtítulo activo (Gris claro)
            painter.setPen(QColor("#9E9E9E"))
            painter.setFont(QFont("Space Grotesk", 9))
            painter.drawText(QRectF(14.0, 26.0, w - chamfer - 12.0, 16.0), Qt.AlignLeft | Qt.AlignVCenter, self.subtitle)
        else:
            # Pestaña inactiva: aspecto sutil y plano
            bg_col = QColor("#161616") if not self._hover else QColor("#1E1E1E")
            path.addRoundedRect(QRectF(2.0, 4.0, w - 4.0, h - 6.0), 6.0, 6.0)
            painter.fillPath(path, QBrush(bg_col))
            painter.setPen(QPen(QColor("#2D2D2D"), 1.0))
            painter.drawPath(path)

            # Título inactivo
            painter.setPen(QColor("#CCCCCC") if self._hover else QColor("#777777"))
            painter.setFont(QFont("Space Grotesk", 11, QFont.Bold))
            painter.drawText(QRectF(14.0, 8.0, w - 24.0, 18.0), Qt.AlignLeft | Qt.AlignVCenter, self.title)

            # Subtítulo inactivo
            painter.setPen(QColor("#888888") if self._hover else QColor("#555555"))
            painter.setFont(QFont("Space Grotesk", 9))
            painter.drawText(QRectF(14.0, 26.0, w - 24.0, 16.0), Qt.AlignLeft | Qt.AlignVCenter, self.subtitle)


class FolderTabBar(QWidget):
    """
    Barra contenedora de pestañas estilo carpeta que gestiona el cambio entre 'General' y 'Subtareas'.
    """
    currentChanged = Signal(int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFixedHeight(52)
        layout = QHBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(6)

        self.tab_general = FolderTabButton(0, "General", "Parámetros y fecha", self)
        self.tab_subtasks = FolderTabButton(1, "Subtareas", "Checklist CRUD (0)", self)

        self.tab_general.clicked.connect(self.setCurrentIndex)
        self.tab_subtasks.clicked.connect(self.setCurrentIndex)

        layout.addWidget(self.tab_general)
        layout.addWidget(self.tab_subtasks)

        self.currentIndex = 0
        self.tab_general.set_active(True)
        self.tab_subtasks.set_active(False)

    def setCurrentIndex(self, index: int):
        if self.currentIndex != index:
            self.currentIndex = index
            self.tab_general.set_active(index == 0)
            self.tab_subtasks.set_active(index == 1)
            self.currentChanged.emit(index)

    def update_subtasks_count(self, total: int, completed: int):
        if total == 0:
            self.tab_subtasks.set_subtitle("Sin subtareas")
        else:
            self.tab_subtasks.set_subtitle(f"{completed}/{total} completadas")


class SubtaskEditorItem(QFrame):
    """
    Fila interactiva de subtarea con soporte completo de operaciones CRUD:
    - C (Create): generada con datos iniciales o en blanco.
    - R (Read): visualiza estado de completado, título y nota descriptiva.
    - U (Update): alternar checklist, editar título y descripción in-place.
    - D (Delete): botón ✕ para eliminar la fila.
    """
    remove_requested = Signal(object)
    status_changed = Signal(bool)

    def __init__(self, subtask: Optional[SubTask] = None, task_id: str = "", parent=None):
        super().__init__(parent)
        self.subtask_id = subtask.id if subtask and subtask.id else str(uuid.uuid4())
        self.task_id = task_id
        self.created_at = subtask.created_at if subtask else ""

        self.setStyleSheet("""
            QFrame {
                background-color: #242424;
                border: 1px solid #363636;
                border-radius: 4px;
            }
        """)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 6, 8, 6)
        layout.setSpacing(4)

        top_row = QHBoxLayout()
        top_row.setContentsMargins(0, 0, 0, 0)
        top_row.setSpacing(8)

        # Checkbox completado/pendiente (TAR-021)
        is_done = subtask.is_completed if subtask else False
        self.btn_check = QPushButton("✔" if is_done else "")
        self.btn_check.setFixedSize(22, 22)
        self.btn_check.setCheckable(True)
        self.btn_check.setChecked(is_done)
        self.btn_check.setCursor(Qt.PointingHandCursor)
        self._update_check_style()
        self.btn_check.clicked.connect(self._on_check_clicked)
        top_row.addWidget(self.btn_check)

        # Título de subtarea (TAR-019, TAR-022)
        init_title = subtask.title if subtask else ""
        self.title_input = QLineEdit(init_title)
        self.title_input.setPlaceholderText("Nombre de la subtarea...")
        self.title_input.setStyleSheet("""
            QLineEdit {
                background: transparent;
                border: none;
                color: #FFFFFF;
                font-family: 'Space Grotesk';
                font-weight: bold;
                font-size: 12px;
                padding: 2px 4px;
            }
            QLineEdit:focus {
                border-bottom: 1px solid #A31F34;
            }
        """)
        top_row.addWidget(self.title_input)

        # Botón para eliminar subtarea (TAR-023)
        self.btn_del = QPushButton("✕")
        self.btn_del.setFixedSize(18, 18)
        self.btn_del.setCursor(Qt.PointingHandCursor)
        self.btn_del.setToolTip("Eliminar subtarea")
        self.btn_del.setStyleSheet("""
            QPushButton {
                background: transparent;
                color: #777777;
                border: none;
                font-size: 11px;
                font-weight: bold;
            }
            QPushButton:hover {
                color: #FF5555;
            }
        """)
        self.btn_del.clicked.connect(lambda: self.remove_requested.emit(self))
        top_row.addWidget(self.btn_del)

        layout.addLayout(top_row)

        # Descripción opcional (TAR-020)
        init_desc = subtask.description if subtask and subtask.description else ""
        self.desc_input = QLineEdit(init_desc)
        self.desc_input.setPlaceholderText("Descripción / nota opcional...")
        self.desc_input.setStyleSheet("""
            QLineEdit {
                background: transparent;
                border: none;
                color: #888888;
                font-family: 'Space Grotesk';
                font-size: 11px;
                padding-left: 30px;
            }
            QLineEdit:focus {
                color: #DDDDDD;
            }
        """)
        layout.addWidget(self.desc_input)

    def _on_check_clicked(self):
        is_done = self.btn_check.isChecked()
        self.btn_check.setText("✔" if is_done else "")
        self._update_check_style()
        self.status_changed.emit(is_done)

    def _update_check_style(self):
        if self.btn_check.isChecked():
            self.btn_check.setStyleSheet(
                "background-color: #A31F34; color: #FFFFFF; "
                "border: 1px solid #C02E44; border-radius: 2px; font-size: 11px; font-weight: bold;"
            )
        else:
            self.btn_check.setStyleSheet(
                "background-color: #141414; color: transparent; "
                "border: 1px solid #444444; border-radius: 2px;"
            )

    def is_completed(self) -> bool:
        return self.btn_check.isChecked()

    def to_subtask(self, position: int = 0) -> Optional[SubTask]:
        title = self.title_input.text().strip()
        if not title:
            return None
        return SubTask(
            id=self.subtask_id,
            task_id=self.task_id,
            title=title,
            description=self.desc_input.text().strip(),
            is_completed=self.btn_check.isChecked(),
            position=position,
            created_at=self.created_at
        )


class TaskCreateDialog(SciFiBaseModal):
    """
    Diálogo para registrar una nueva tarea.
    Panel Izquierdo: Pestañas 'General' (nombre y toggle de fecha) y 'Subtareas' (CRUD completo).
    Panel Derecho: Descripción y documentación extensa con scroll en fondo negro puro.
    """

    def __init__(self, parent=None, initial_status: str = "pending"):
        super().__init__(parent, width=920, height=550)
        self.initial_status = initial_status
        self.subtask_items: List[SubtaskEditorItem] = []
        self._setup_ui()

    def _setup_ui(self):
        root_layout = QHBoxLayout(self)
        root_layout.setContentsMargins(12, 12, 12, 12)
        root_layout.setSpacing(12)

        # =============================================================
        # PANEL IZQUIERDO: Gris Oscuro (#1C1C1C) - PESTAÑAS Y CONTROLES
        # =============================================================
        left_panel = QFrame()
        left_panel.setStyleSheet("""
            QFrame#LeftPanel {
                background-color: #1C1C1C;
                border: 1px solid #333333;
                border-radius: 6px;
            }
        """)
        left_panel.setObjectName("LeftPanel")

        left_layout = QVBoxLayout(left_panel)
        left_layout.setContentsMargins(16, 14, 16, 14)
        left_layout.setSpacing(10)

        # Encabezado panel izquierdo
        header_row = QHBoxLayout()
        title_lbl = QLabel(f"⋮⋮ NUEVA TAREA [{self.initial_status.upper()}]")
        title_lbl.setObjectName("Title")
        title_lbl.setCursor(Qt.SizeAllCursor)
        title_lbl.setToolTip("Haz clic y arrastra para mover esta ventana por la pantalla")

        status_tag = QLabel(f"[{self.initial_status.upper()}]")
        status_tag.setStyleSheet("color: #00BFFF; font-weight: bold; font-size: 11px;")

        header_row.addWidget(title_lbl)
        header_row.addSpacing(8)
        header_row.addWidget(status_tag)
        header_row.addStretch()
        left_layout.addLayout(header_row)

        # Barra de pestañas estilo carpeta (Imagen 1)
        self.tab_bar = FolderTabBar(self)
        left_layout.addWidget(self.tab_bar)

        # Stack de contenidos según la pestaña seleccionada
        self.stack = QStackedWidget(self)

        # -------------------------------------------------------------
        # PESTAÑA 0: GENERAL (Nombre de tarea y fecha con toggle)
        # -------------------------------------------------------------
        page_general = QWidget()
        page_gen_layout = QVBoxLayout(page_general)
        page_gen_layout.setContentsMargins(4, 8, 4, 4)
        page_gen_layout.setSpacing(12)

        # Campo: Nombre de la tarea
        lbl_title = QLabel("NOMBRE DE LA TAREA *:")
        lbl_title.setStyleSheet("font-size: 11px; font-weight: bold; color: #CCCCCC;")
        self.title_input = QLineEdit()
        self.title_input.setPlaceholderText("Ej. Implementar arquitectura relacional...")
        page_gen_layout.addWidget(lbl_title)
        page_gen_layout.addWidget(self.title_input)

        # Contenedor de Fecha de Entrega con PillToggleSwitch (Imagen 2)
        date_card = QFrame()
        date_card.setStyleSheet("""
            QFrame {
                background-color: #171717;
                border: 1px solid #2A2A2A;
                border-radius: 5px;
                padding: 4px;
            }
        """)
        date_card_layout = QVBoxLayout(date_card)
        date_card_layout.setContentsMargins(10, 8, 10, 8)
        date_card_layout.setSpacing(8)

        # Interruptor estilizado
        self.toggle_due_date = PillToggleSwitch("Activar fecha de entrega", checked=False)
        self.toggle_due_date.toggled.connect(self._on_due_date_toggled)
        date_card_layout.addWidget(self.toggle_due_date)

        # Contenedor desplegable del selector de fecha
        self.date_picker_container = QWidget()
        date_picker_sublayout = QVBoxLayout(self.date_picker_container)
        date_picker_sublayout.setContentsMargins(0, 4, 0, 0)
        date_picker_sublayout.setSpacing(6)

        date_input_row = QHBoxLayout()
        date_lbl = QLabel("Fecha límite:")
        date_lbl.setStyleSheet("color: #AAAAAA; font-size: 11px;")
        self.date_edit = QDateEdit(QDate.currentDate().addDays(3))
        self.date_edit.setCalendarPopup(True)

        date_input_row.addWidget(date_lbl)
        date_input_row.addWidget(self.date_edit)
        date_input_row.addStretch()
        date_picker_sublayout.addLayout(date_input_row)

        # Botones de acceso rápido para fecha
        quick_dates_row = QHBoxLayout()
        quick_dates_row.setSpacing(6)
        btn_d1 = QPushButton("+1 DÍA")
        btn_d3 = QPushButton("+3 DÍAS")
        btn_d7 = QPushButton("+1 SEMANA")
        for b, days in [(btn_d1, 1), (btn_d3, 3), (btn_d7, 7)]:
            b.setStyleSheet("font-size: 10px; padding: 3px 8px; background-color: #262626; border: 1px solid #3A3A3A;")
            b.clicked.connect(lambda _, d=days: self.date_edit.setDate(QDate.currentDate().addDays(d)))
            quick_dates_row.addWidget(b)
        quick_dates_row.addStretch()
        date_picker_sublayout.addLayout(quick_dates_row)

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
        page_sub_layout.setContentsMargins(4, 6, 4, 4)
        page_sub_layout.setSpacing(8)

        # Cabecera de estadísticas y progreso
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
                background-color: #A31F34;
                border-radius: 3px;
            }
        """)
        self.subtasks_progress.setValue(0)

        stats_row.addWidget(self.lbl_subtasks_stats)
        stats_row.addSpacing(10)
        stats_row.addWidget(self.subtasks_progress)
        page_sub_layout.addLayout(stats_row)

        # Barra para añadir nueva subtarea (CREATE)
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

        # Área scrolleable de subtareas (READ & UPDATE & DELETE)
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

        self.subtasks_scroll.setWidget(self.subtasks_container)
        page_sub_layout.addWidget(self.subtasks_scroll)

        self.stack.addWidget(page_subtasks)
        left_layout.addWidget(self.stack)

        # Conectar cambio de pestañas
        self.tab_bar.currentChanged.connect(self.stack.setCurrentIndex)

        # Mensaje de error
        self.error_lbl = QLabel("")
        self.error_lbl.setStyleSheet("color: #FF5555; font-size: 11px;")
        left_layout.addWidget(self.error_lbl)

        # Botones inferiores del panel izquierdo
        btn_layout = QHBoxLayout()
        btn_layout.addStretch()

        btn_cancel = QPushButton("CANCELAR")
        btn_cancel.clicked.connect(self.reject)

        self.btn_save = QPushButton("GUARDAR TAREA")
        self.btn_save.setObjectName("PrimaryBtn")
        self.btn_save.clicked.connect(self._on_save_clicked)

        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(self.btn_save)
        left_layout.addLayout(btn_layout)

        # =============================================================
        # PANEL DERECHO: Negro Puro (#0A0A0A) - DESCRIPCIÓN CON SCROLL
        # =============================================================
        right_panel = QFrame()
        right_panel.setStyleSheet("""
            QFrame#RightPanel {
                background-color: #0A0A0A;
                border: 1px solid #282828;
                border-radius: 6px;
            }
        """)
        right_panel.setObjectName("RightPanel")

        right_layout = QVBoxLayout(right_panel)
        right_layout.setContentsMargins(16, 14, 16, 14)
        right_layout.setSpacing(10)

        # Barra superior del panel derecho
        desc_top_bar = QHBoxLayout()
        pill_lbl = QLabel("● DESCRIPCIÓN & ESPECIFICACIONES")
        pill_lbl.setStyleSheet("color: #00BFFF; font-size: 11px; font-weight: bold; font-family: 'Space Grotesk'; letter-spacing: 1px;")

        btn_close_x = QPushButton("✕")
        btn_close_x.setFixedSize(22, 22)
        btn_close_x.setCursor(Qt.PointingHandCursor)
        btn_close_x.setStyleSheet("QPushButton { background: transparent; color: #888; border: none; font-weight: bold; } QPushButton:hover { color: #FFF; background: #333; }")
        btn_close_x.clicked.connect(self.reject)

        desc_top_bar.addWidget(pill_lbl)
        desc_top_bar.addStretch()
        desc_top_bar.addWidget(btn_close_x)
        right_layout.addLayout(desc_top_bar)

        # Área amplia de descripción con scroll
        self.desc_input = QTextEdit()
        self.desc_input.setPlaceholderText(
            "Escribe aquí la descripción detallada de la tarea...\n\n"
            "Puedes redactar textos extensos, requerimientos, casos de uso o notas técnicas. "
            "Si el texto supera el alto del contenedor, se activará el scroll fluido automáticamente."
        )
        self.desc_input.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.desc_input.setStyleSheet(f"""
            QTextEdit {{
                background-color: transparent;
                border: none;
                color: #E6E6E6;
                font-family: 'Space Grotesk';
                font-size: 13px;
                padding: 6px;
                line-height: 1.5;
            }}
            QTextEdit:focus {{
                color: #FFFFFF;
            }}
            {get_minimal_scrollbar_style()}
        """)
        right_layout.addWidget(self.desc_input)

        # Barra de pie del panel de descripción
        desc_footer = QHBoxLayout()
        hint_desc = QLabel("Área de notas expandida con scroll")
        hint_desc.setStyleSheet("color: #555555; font-size: 10px; font-family: 'Space Grotesk';")
        desc_footer.addWidget(hint_desc)
        desc_footer.addStretch()
        right_layout.addLayout(desc_footer)

        # Proporción split equilibrada (45% inputs / 55% descripción)
        root_layout.addWidget(left_panel, 45)
        root_layout.addWidget(right_panel, 55)

        self.title_input.setFocus()

    def _on_due_date_toggled(self, active: bool):
        self.date_picker_container.setVisible(active)

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

        self.subtasks_layout.addWidget(item)
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

        self.tab_bar.update_subtasks_count(total, completed)

    def _on_save_clicked(self):
        title = self.title_input.text().strip()
        if not title:
            self.error_lbl.setText("El nombre de la tarea no puede estar vacío.")
            self.tab_bar.setCurrentIndex(0)
            self.title_input.setFocus()
            return

        self.accept()

    def get_data(self) -> Dict[str, Optional[object]]:
        due_date = None
        if self.toggle_due_date.isChecked():
            due_date = self.date_edit.date().toString("yyyy-MM-dd")

        subs = []
        for item in self.subtask_items:
            st = item.to_subtask(position=len(subs))
            if st and st.title:
                subs.append(st.title)

        return {
            "title": self.title_input.text().strip(),
            "description": self.desc_input.toPlainText().strip(),
            "due_date": due_date,
            "status": self.initial_status,
            "subtasks": subs
        }


class TaskDetailDialog(SciFiBaseModal):
    """
    Diálogo para consultar y modificar una tarea existente y sus subtareas.
    Panel Izquierdo: Pestañas 'General' (metadatos, nombre y toggle de fecha) y 'Subtareas' (CRUD completo).
    Panel Derecho: Gran área de descripción y notas con scroll en fondo negro puro.
    """
    delete_requested = Signal(str)

    def __init__(self, task: Task, parent=None):
        super().__init__(parent, width=920, height=560)
        self.task = task
        self.subtask_items: List[SubtaskEditorItem] = []
        self._setup_ui()

    def _setup_ui(self):
        root_layout = QHBoxLayout(self)
        root_layout.setContentsMargins(12, 12, 12, 12)
        root_layout.setSpacing(12)

        # =============================================================
        # PANEL IZQUIERDO: Gris Oscuro (#1C1C1C) - PESTAÑAS Y CONTROLES
        # =============================================================
        left_panel = QFrame()
        left_panel.setStyleSheet("""
            QFrame#LeftPanel {
                background-color: #1C1C1C;
                border: 1px solid #333333;
                border-radius: 6px;
            }
        """)
        left_panel.setObjectName("LeftPanel")

        left_layout = QVBoxLayout(left_panel)
        left_layout.setContentsMargins(16, 14, 16, 14)
        left_layout.setSpacing(10)

        # Encabezado panel izquierdo
        header_row = QHBoxLayout()
        title_lbl = QLabel("⋮⋮ DETALLES DE TAREA")
        title_lbl.setObjectName("Title")
        title_lbl.setCursor(Qt.SizeAllCursor)
        title_lbl.setToolTip("Haz clic y arrastra para mover esta ventana por la pantalla")

        status_tag = QLabel(f"[{self.task.status_name.upper()}]")
        status_tag.setStyleSheet("color: #00BFFF; font-weight: bold; font-size: 11px;")

        header_row.addWidget(title_lbl)
        header_row.addSpacing(8)
        header_row.addWidget(status_tag)
        header_row.addStretch()
        left_layout.addLayout(header_row)

        # Barra de pestañas estilo carpeta (Imagen 1)
        self.tab_bar = FolderTabBar(self)
        left_layout.addWidget(self.tab_bar)

        # Stack de contenidos según la pestaña seleccionada
        self.stack = QStackedWidget(self)

        # -------------------------------------------------------------
        # PESTAÑA 0: GENERAL (Metadatos, nombre y toggle de fecha)
        # -------------------------------------------------------------
        page_general = QWidget()
        page_gen_layout = QVBoxLayout(page_general)
        page_gen_layout.setContentsMargins(4, 6, 4, 4)
        page_gen_layout.setSpacing(10)

        # Metadato: Fecha de creación
        created_str = self.task.created_at[:16].replace("T", " ") if self.task.created_at else "---"
        created_lbl = QLabel(f"REGISTRADA: {created_str}")
        created_lbl.setObjectName("SubInfo")
        page_gen_layout.addWidget(created_lbl)

        # Campo: Nombre de la tarea
        lbl_title = QLabel("NOMBRE DE LA TAREA *:")
        lbl_title.setStyleSheet("font-size: 11px; font-weight: bold; color: #CCCCCC;")
        self.title_input = QLineEdit(self.task.title)
        page_gen_layout.addWidget(lbl_title)
        page_gen_layout.addWidget(self.title_input)

        # Contenedor de Fecha de Entrega con PillToggleSwitch (Imagen 2)
        date_card = QFrame()
        date_card.setStyleSheet("""
            QFrame {
                background-color: #171717;
                border: 1px solid #2A2A2A;
                border-radius: 5px;
                padding: 4px;
            }
        """)
        date_card_layout = QVBoxLayout(date_card)
        date_card_layout.setContentsMargins(10, 8, 10, 8)
        date_card_layout.setSpacing(8)

        # Interruptor estilizado
        has_due_date = bool(self.task.due_date)
        self.toggle_due_date = PillToggleSwitch("Activar fecha de entrega", checked=has_due_date)
        self.toggle_due_date.toggled.connect(self._on_due_date_toggled)
        date_card_layout.addWidget(self.toggle_due_date)

        # Contenedor desplegable del selector de fecha
        self.date_picker_container = QWidget()
        date_picker_sublayout = QVBoxLayout(self.date_picker_container)
        date_picker_sublayout.setContentsMargins(0, 4, 0, 0)
        date_picker_sublayout.setSpacing(6)

        date_input_row = QHBoxLayout()
        date_lbl = QLabel("Fecha límite:")
        date_lbl.setStyleSheet("color: #AAAAAA; font-size: 11px;")
        self.date_edit = QDateEdit()
        self.date_edit.setCalendarPopup(True)

        if has_due_date:
            try:
                dt = datetime.strptime(self.task.due_date[:10], "%Y-%m-%d")
                self.date_edit.setDate(QDate(dt.year, dt.month, dt.day))
            except Exception:
                self.date_edit.setDate(QDate.currentDate())
        else:
            self.date_edit.setDate(QDate.currentDate().addDays(3))

        date_input_row.addWidget(date_lbl)
        date_input_row.addWidget(self.date_edit)
        date_input_row.addStretch()
        date_picker_sublayout.addLayout(date_input_row)

        # Botones de acceso rápido para fecha
        quick_dates_row = QHBoxLayout()
        quick_dates_row.setSpacing(6)
        btn_d1 = QPushButton("+1 DÍA")
        btn_d3 = QPushButton("+3 DÍAS")
        btn_d7 = QPushButton("+1 SEMANA")
        for b, days in [(btn_d1, 1), (btn_d3, 3), (btn_d7, 7)]:
            b.setStyleSheet("font-size: 10px; padding: 3px 8px; background-color: #262626; border: 1px solid #3A3A3A;")
            b.clicked.connect(lambda _, d=days: self.date_edit.setDate(QDate.currentDate().addDays(d)))
            quick_dates_row.addWidget(b)
        quick_dates_row.addStretch()
        date_picker_sublayout.addLayout(quick_dates_row)

        self.date_picker_container.setVisible(has_due_date)
        date_card_layout.addWidget(self.date_picker_container)

        page_gen_layout.addWidget(date_card)
        page_gen_layout.addStretch()
        self.stack.addWidget(page_general)

        # -------------------------------------------------------------
        # PESTAÑA 1: SUBTAREAS (CRUD COMPLETO)
        # -------------------------------------------------------------
        page_subtasks = QWidget()
        page_sub_layout = QVBoxLayout(page_subtasks)
        page_sub_layout.setContentsMargins(4, 6, 4, 4)
        page_sub_layout.setSpacing(8)

        # Cabecera de estadísticas y progreso
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
                background-color: #A31F34;
                border-radius: 3px;
            }
        """)
        self.subtasks_progress.setValue(0)

        stats_row.addWidget(self.lbl_subtasks_stats)
        stats_row.addSpacing(10)
        stats_row.addWidget(self.subtasks_progress)
        page_sub_layout.addLayout(stats_row)

        # Barra para añadir nueva subtarea (CREATE)
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

        # Área scrolleable de subtareas (READ, UPDATE, DELETE)
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

        # Cargar subtareas existentes de la tarea
        for st in self.task.subtasks:
            item = SubtaskEditorItem(subtask=st, task_id=self.task.id, parent=self.subtasks_container)
            item.remove_requested.connect(self._remove_subtask_item)
            item.status_changed.connect(lambda _: self._update_subtasks_stats())
            self.subtasks_layout.addWidget(item)
            self.subtask_items.append(item)

        self.subtasks_scroll.setWidget(self.subtasks_container)
        page_sub_layout.addWidget(self.subtasks_scroll)

        self.stack.addWidget(page_subtasks)
        left_layout.addWidget(self.stack)

        # Conectar cambio de pestañas
        self.tab_bar.currentChanged.connect(self.stack.setCurrentIndex)
        self._update_subtasks_stats()

        # Mensaje de error
        self.error_lbl = QLabel("")
        self.error_lbl.setStyleSheet("color: #FF5555; font-size: 11px;")
        left_layout.addWidget(self.error_lbl)

        # Botones inferiores del panel izquierdo
        btn_layout = QHBoxLayout()

        btn_delete = QPushButton("ELIMINAR TAREA")
        btn_delete.setObjectName("DangerBtn")
        btn_delete.clicked.connect(self._on_delete_clicked)

        btn_cancel = QPushButton("CANCELAR")
        btn_cancel.clicked.connect(self.reject)

        btn_save = QPushButton("GUARDAR CAMBIOS")
        btn_save.setObjectName("PrimaryBtn")
        btn_save.clicked.connect(self._on_save_clicked)

        btn_layout.addWidget(btn_delete)
        btn_layout.addStretch()
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_save)
        left_layout.addLayout(btn_layout)

        # =============================================================
        # PANEL DERECHO: Negro Puro (#0A0A0A) - DESCRIPCIÓN CON SCROLL
        # =============================================================
        right_panel = QFrame()
        right_panel.setStyleSheet("""
            QFrame#RightPanel {
                background-color: #0A0A0A;
                border: 1px solid #282828;
                border-radius: 6px;
            }
        """)
        right_panel.setObjectName("RightPanel")

        right_layout = QVBoxLayout(right_panel)
        right_layout.setContentsMargins(16, 14, 16, 14)
        right_layout.setSpacing(10)

        # Barra superior del panel derecho
        desc_top_bar = QHBoxLayout()
        pill_lbl = QLabel("● DESCRIPCIÓN & NOTAS EXTENSAS")
        pill_lbl.setStyleSheet("color: #00BFFF; font-size: 11px; font-weight: bold; font-family: 'Space Grotesk'; letter-spacing: 1px;")

        btn_close_x = QPushButton("✕")
        btn_close_x.setFixedSize(22, 22)
        btn_close_x.setCursor(Qt.PointingHandCursor)
        btn_close_x.setStyleSheet("QPushButton { background: transparent; color: #888; border: none; font-weight: bold; } QPushButton:hover { color: #FFF; background: #333; }")
        btn_close_x.clicked.connect(self.reject)

        desc_top_bar.addWidget(pill_lbl)
        desc_top_bar.addStretch()
        desc_top_bar.addWidget(btn_close_x)
        right_layout.addLayout(desc_top_bar)

        # Área amplia de descripción con scroll
        self.desc_input = QTextEdit()
        self.desc_input.setPlainText(self.task.description)
        self.desc_input.setPlaceholderText(
            "Detalles completos, documentación y especificaciones de la tarea...\n\n"
            "Este panel permite escribir grandes cantidades de texto y notas técnicas. "
            "Si el contenido excede el alto del contenedor, puedes desplazarte con la rueda del ratón o la barra de scroll."
        )
        self.desc_input.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.desc_input.setStyleSheet(f"""
            QTextEdit {{
                background-color: transparent;
                border: none;
                color: #E6E6E6;
                font-family: 'Space Grotesk';
                font-size: 13px;
                padding: 6px;
                line-height: 1.5;
            }}
            QTextEdit:focus {{
                color: #FFFFFF;
            }}
            {get_minimal_scrollbar_style()}
        """)
        right_layout.addWidget(self.desc_input)

        # Barra de pie del panel de descripción
        desc_footer = QHBoxLayout()
        hint_desc = QLabel("Área de notas completa con scroll")
        hint_desc.setStyleSheet("color: #555555; font-size: 10px; font-family: 'Space Grotesk';")
        desc_footer.addWidget(hint_desc)
        desc_footer.addStretch()
        right_layout.addLayout(desc_footer)

        # Proporción split equilibrada (45% inputs / 55% descripción)
        root_layout.addWidget(left_panel, 45)
        root_layout.addWidget(right_panel, 55)

    def _on_due_date_toggled(self, active: bool):
        self.date_picker_container.setVisible(active)

    def _on_add_subtask_from_input(self):
        text = self.new_subtask_input.text().strip()
        if not text:
            return

        dummy_subtask = SubTask(
            id=str(uuid.uuid4()),
            task_id=self.task.id,
            title=text,
            is_completed=False
        )
        item = SubtaskEditorItem(subtask=dummy_subtask, task_id=self.task.id, parent=self.subtasks_container)
        item.remove_requested.connect(self._remove_subtask_item)
        item.status_changed.connect(lambda _: self._update_subtasks_stats())

        self.subtasks_layout.addWidget(item)
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

        self.tab_bar.update_subtasks_count(total, completed)

    def _on_save_clicked(self):
        title = self.title_input.text().strip()
        if not title:
            self.error_lbl.setText("El nombre no puede estar vacío.")
            self.tab_bar.setCurrentIndex(0)
            self.title_input.setFocus()
            return
        self.accept()

    def _on_delete_clicked(self):
        self.reject()
        self.delete_requested.emit(self.task.id)

    def get_updated_data(self) -> Dict[str, object]:
        """
        Retorna la información modificada de la tarea incluyendo subtareas.

        Returns:
            Dict con 'title', 'description', 'due_date' y 'subtasks'.
        """
        due_date = None
        if self.toggle_due_date.isChecked():
            due_date = self.date_edit.date().toString("yyyy-MM-dd")

        updated_subtasks: List[SubTask] = []
        for pos, item in enumerate(self.subtask_items):
            st = item.to_subtask(position=pos)
            if st:
                updated_subtasks.append(st)

        return {
            "title": self.title_input.text().strip(),
            "description": self.desc_input.toPlainText().strip(),
            "due_date": due_date,
            "subtasks": updated_subtasks
        }

"""
Componente editable e interactivo para una fila de subtarea (CRUD).
- Checklist con icono ✓ nítido.
- Descripción multilínea que adapta su altura al contenido. Arranca siempre colapsada
  y el usuario decide cuándo abrirla.
- Botón de ampliar para llevar la subtarea al espacio de trabajo del detalle de tarea.
"""
import uuid
from typing import Optional
from PySide6.QtWidgets import (
    QFrame, QVBoxLayout, QHBoxLayout, QPushButton, 
    QLineEdit, QTextEdit, QWidget, QLabel, QSizePolicy, QGraphicsOpacityEffect
)
from PySide6.QtCore import Qt, Signal, QMimeData, QPoint
from PySide6.QtGui import QDrag
from ..drag_handle import DragHandle, SUBTASK_MIME
from core.matrix.motherboard.ecosystems.tasks.domain.entities import SubTask
from core.matrix.motherboard.modules.styles import get_minimal_scrollbar_style

CHECKED_STYLE = """
    QPushButton {
        background-color: #A04A2C;
        color: #FFFFFF;
        border: 1px solid #FFAA77;
        border-radius: 3px;
        font-size: 13px;
        font-weight: 900;
        padding: 0px;
        text-align: center;
    }
"""

UNCHECKED_STYLE = """
    QPushButton {
        background-color: #141414;
        color: transparent;
        border: 1px solid #444444;
        border-radius: 3px;
        padding: 0px;
    }
    QPushButton:hover {
        border: 1px solid #777777;
    }
"""


class AutoResizeSubtaskEdit(QTextEdit):
    """
    QTextEdit adaptativo que ajusta su altura automáticamente al texto real,
    evitando espacios vacíos desproporcionados en notas cortas y expandiéndose
    según la cantidad de líneas escritas.
    """
    def __init__(self, parent=None):
        super().__init__(parent)
        self.document().setDocumentMargin(2)
        self.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Fixed)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.textChanged.connect(self.adjust_height)

    def resizeEvent(self, event):
        super().resizeEvent(event)
        self.adjust_height()

    def adjust_height(self):
        vp_width = self.viewport().width()
        if vp_width > 0:
            self.document().setTextWidth(vp_width)

        text = self.toPlainText().strip()
        if not text:
            target_h = 24
        else:
            doc_h = int(self.document().size().height())
            # Ajuste reactivo entre 24px (1 línea compacta) y 110px (con scroll si excede)
            target_h = max(24, min(doc_h + 4, 110))

        if self.height() != target_h:
            self.setFixedHeight(target_h)
            self.updateGeometry()


class SubtaskEditorItem(QFrame):
    """
    Fila interactiva de subtarea con soporte completo de operaciones CRUD:
    - C (Create): generada con datos iniciales o en blanco.
    - R (Read): visualiza estado de completado, título y nota descriptiva.
    - U (Update): alternar checklist (✓), editar título y descripción in-place.
    - D (Delete): botón ✕ para eliminar la fila.
    """
    remove_requested = Signal(object)
    status_changed = Signal(bool)
    focus_requested = Signal(object)

    def __init__(self, subtask: Optional[SubTask] = None, task_id: str = "", parent=None):
        super().__init__(parent)
        self.subtask_id = subtask.id if subtask and subtask.id else str(uuid.uuid4())
        self.task_id = task_id
        self.created_at = subtask.created_at if subtask else ""

        self.setStyleSheet("""
            SubtaskEditorItem {
                background-color: #202020;
                border: 1px solid #333333;
                border-radius: 4px;
            }
            SubtaskEditorItem:hover {
                border: 1px solid #444444;
            }
        """)

        self.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Maximum)

        self.main_layout = QVBoxLayout(self)
        self.main_layout.setContentsMargins(8, 6, 8, 6)
        self.main_layout.setSpacing(4)
        self.main_layout.setAlignment(Qt.AlignTop)

        # Fila Superior: Checkbox, Título, Toggle Nota, Botón Eliminar
        top_row = QHBoxLayout()
        top_row.setContentsMargins(0, 0, 0, 0)
        top_row.setSpacing(6)

        # 0. Asa de arrastre y número de orden
        self.drag_handle = DragHandle(self, tooltip="Arrastra para reordenar o llevar al espacio de trabajo")
        self.drag_handle.drag_requested.connect(self._start_drag)
        top_row.addWidget(self.drag_handle)

        self.lbl_number = QLabel("")
        self.lbl_number.setFixedWidth(18)
        self.lbl_number.setAlignment(Qt.AlignCenter)
        self.lbl_number.setStyleSheet(
            "color: #777777; font-size: 11px; font-weight: bold; "
            "font-family: 'Prototype'; background: transparent;"
        )
        top_row.addWidget(self.lbl_number)

        # 1. Checkbox con icono ✓ garantizado
        is_done = subtask.is_completed if subtask else False
        self.btn_check = QPushButton()
        self.btn_check.setFixedSize(22, 22)
        self.btn_check.setCheckable(True)
        self.btn_check.setChecked(is_done)
        self.btn_check.setCursor(Qt.PointingHandCursor)
        self._update_check_style()
        self.btn_check.clicked.connect(self._on_check_clicked)
        top_row.addWidget(self.btn_check)

        # 2. Título de subtarea
        init_title = subtask.title if subtask else ""
        self.title_input = QLineEdit(init_title)
        self.title_input.setPlaceholderText("Nombre de la subtarea...")
        self.title_input.setStyleSheet("""
            QLineEdit {
                background: transparent;
                border: none;
                color: #FFFFFF;
                font-family: 'Prototype';
                font-weight: bold;
                font-size: 12px;
                padding: 2px 4px;
            }
            QLineEdit:focus {
                border-bottom: 1px solid #FFAA77;
            }
        """)
        top_row.addWidget(self.title_input)

        # 3. Botón para abrir / cerrar la descripción
        init_desc = (subtask.description if subtask and subtask.description else "").strip()
        self.has_desc = bool(init_desc)

        self.btn_toggle_desc = QPushButton("▾ Nota" if self.has_desc else "+ Nota")
        self.btn_toggle_desc.setFixedHeight(20)
        self.btn_toggle_desc.setCursor(Qt.PointingHandCursor)
        self.btn_toggle_desc.setToolTip("Mostrar / Ocultar descripción de la subtarea")
        self.btn_toggle_desc.setStyleSheet("""
            QPushButton {
                background-color: #282828;
                color: #AAAAAA;
                border: 1px solid #3D3D3D;
                border-radius: 3px;
                font-size: 10px;
                font-family: 'Prototype';
                padding: 2px 6px;
            }
            QPushButton:hover {
                background-color: #333333;
                color: #FFAA77;
                border: 1px solid #FFAA77;
            }
        """)
        self.btn_toggle_desc.clicked.connect(self._toggle_description)
        top_row.addWidget(self.btn_toggle_desc)

        # 3b. Botón para ampliar la subtarea en el espacio de trabajo
        self.btn_focus = QPushButton("⤢")
        self.btn_focus.setFixedSize(22, 20)
        self.btn_focus.setCursor(Qt.PointingHandCursor)
        self.btn_focus.setToolTip("Ampliar esta subtarea en el espacio de trabajo")
        self.btn_focus.setStyleSheet("""
            QPushButton {
                background-color: #282828;
                color: #AAAAAA;
                border: 1px solid #3D3D3D;
                border-radius: 3px;
                font-size: 12px;
                padding: 0px;
            }
            QPushButton:hover {
                background-color: #333333;
                color: #FFAA77;
                border: 1px solid #FFAA77;
            }
        """)
        self.btn_focus.clicked.connect(lambda: self.focus_requested.emit(self))
        top_row.addWidget(self.btn_focus)

        # 4. Botón para eliminar subtarea
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

        self.main_layout.addLayout(top_row)

        # Contenedor de Descripción adaptable y colapsable
        self.desc_container = QWidget()
        self.desc_container.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Maximum)
        desc_layout = QVBoxLayout(self.desc_container)
        desc_layout.setContentsMargins(28, 0, 0, 0)
        desc_layout.setSpacing(0)
        desc_layout.setAlignment(Qt.AlignTop)

        self.desc_edit = AutoResizeSubtaskEdit()
        self.desc_edit.setPlaceholderText("Descripción / notas detalladas de la subtarea...")
        if init_desc:
            self.desc_edit.setPlainText(init_desc)

        self.desc_edit.setStyleSheet(
            get_minimal_scrollbar_style() + """
            QTextEdit {
                background-color: #171717;
                border: 1px solid #2F2F2F;
                border-radius: 3px;
                color: #CCCCCC;
                font-family: 'Prototype';
                font-size: 11px;
                line-height: 1.4;
                padding: 4px 6px;
            }
            QTextEdit:focus {
                border: 1px solid #FFAA77;
                color: #FFFFFF;
            }
            """
        )
        desc_layout.addWidget(self.desc_edit)

        self.main_layout.addWidget(self.desc_container)

        # Cerrada por defecto aunque tenga nota: la lista se ve compacta y el usuario la abre a demanda
        self.desc_container.setVisible(False)
        self.desc_edit.adjust_height()
        self.desc_edit.textChanged.connect(self._refresh_note_button)

    def set_number(self, number: int) -> None:
        """Muestra la posición (1, 2, 3...) de la subtarea dentro de su lista."""
        self.lbl_number.setText(str(number))

    def _start_drag(self) -> None:
        """Inicia el arrastre de la subtarea (reordenar o llevar al espacio de trabajo)."""
        drag = QDrag(self)
        mime = QMimeData()
        mime.setData(SUBTASK_MIME, self.subtask_id.encode("utf-8"))
        drag.setMimeData(mime)

        pixmap = self.grab()
        drag.setPixmap(pixmap)
        drag.setHotSpot(QPoint(16, pixmap.height() // 2))

        # Atenúa el ítem original mientras dura el arrastre
        effect = QGraphicsOpacityEffect(self)
        effect.setOpacity(0.35)
        self.setGraphicsEffect(effect)
        try:
            drag.exec(Qt.MoveAction)
        finally:
            self.setGraphicsEffect(None)

    def _adjust_desc_height(self):
        """Notifica al editor para recalcular y adaptar su altura al texto."""
        self.desc_edit.adjust_height()
        self.updateGeometry()

    def _toggle_description(self):
        """Muestra u oculta la descripción de la subtarea."""
        is_open = not self.desc_container.isHidden()
        self.desc_container.setVisible(not is_open)
        if not is_open:
            self.desc_edit.adjust_height()
            self.desc_edit.setFocus()
        self._refresh_note_button()

    def _refresh_note_button(self):
        """Mantiene el texto del botón de nota acorde a si está abierta y si tiene contenido."""
        if not self.desc_container.isHidden():
            self.btn_toggle_desc.setText("▲ Ocultar")
            return
        has_text = bool(self.desc_edit.toPlainText().strip())
        self.btn_toggle_desc.setText("▾ Nota" if has_text else "+ Nota")

    def _on_check_clicked(self):
        is_done = self.btn_check.isChecked()
        self._update_check_style()
        self.status_changed.emit(is_done)

    def _update_check_style(self):
        if self.btn_check.isChecked():
            self.btn_check.setText("✓")
            self.btn_check.setStyleSheet(CHECKED_STYLE)
        else:
            self.btn_check.setText("")
            self.btn_check.setStyleSheet(UNCHECKED_STYLE)

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
            description=self.desc_edit.toPlainText().strip(),
            is_completed=self.btn_check.isChecked(),
            position=position,
            created_at=self.created_at
        )

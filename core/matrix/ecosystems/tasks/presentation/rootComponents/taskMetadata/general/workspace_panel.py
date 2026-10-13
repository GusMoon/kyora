"""
Espacio de trabajo dinámico de la zona derecha del detalle de tarea.

Permite decidir qué se muestra: la descripción de la tarea, una subtarea ampliada,
o ambas al mismo tiempo repartiendo el espacio 50/50. La posición se decide solo
arrastrando, al estilo de un IDE: al arrastrar un panel (o una subtarea de la lista)
sobre el espacio aparecen las zonas izquierda, derecha, arriba y abajo; soltar en
izquierda/derecha los deja lado a lado y arriba/abajo los apila.

Los ítems de la pestaña Subtareas siguen siendo la única fuente de verdad: el panel
de subtarea es un espejo sincronizado.
"""
from typing import Callable, Optional

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QBoxLayout, QLabel, QPushButton,
    QLineEdit, QSizePolicy
)
from PySide6.QtCore import Qt, Signal, QRect, QMimeData, QPoint
from PySide6.QtGui import QFontMetrics, QPainter, QColor, QPen, QDrag

from core.matrix.ecosystems.motherBoard.globalComponents.styles import get_minimal_scrollbar_style

from ..drag_handle import DragHandle, SUBTASK_MIME, PANE_MIME
from ..fading_text_edit import FadingScrollTextEdit
from ..subTasks.subtask_item import SubtaskEditorItem, CHECKED_STYLE, UNCHECKED_STYLE

_CAPTION_STYLE = "font-size: 11px; font-weight: bold; color: #CCCCCC; letter-spacing: 0.5px;"

_EDITOR_STYLE = get_minimal_scrollbar_style() + """
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
"""

_CHIP_STYLE = """
    QPushButton {
        background-color: #1A1A1A;
        border: 1px solid #333333;
        color: #888888;
        font-size: 10px;
        font-weight: bold;
        font-family: 'Space Grotesk';
        letter-spacing: 0.6px;
        padding: 4px 10px;
        border-radius: 4px;
    }
    QPushButton:hover {
        color: #FFFFFF;
        border-color: #555555;
    }
    QPushButton:checked {
        background-color: #2A1D16;
        border-color: #FFAA77;
        color: #FFAA77;
    }
"""

_HINT_STYLE = "font-size: 9px; color: #666666; font-family: 'Space Grotesk'; letter-spacing: 0.5px;"

KIND_DESCRIPTION = "description"
KIND_SUBTASK = "subtask"


def _disable_text_drops(editor) -> None:
    """
    Los editores aceptan soltar texto por defecto y absorberían (rechazándolo) los eventos
    de arrastre antes de que lleguen al espacio de trabajo.
    """
    editor.setAcceptDrops(False)
    editor.viewport().setAcceptDrops(False)


class DescriptionPane(QWidget):
    """Panel con el editor de la descripción y notas de la tarea."""
    drag_requested = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        header = QHBoxLayout()
        header.setSpacing(6)

        self.drag_handle = DragHandle(self, tooltip="Arrastra para reubicar este panel")
        self.drag_handle.drag_requested.connect(self.drag_requested.emit)
        header.addWidget(self.drag_handle)

        caption = QLabel("DESCRIPCIÓN Y NOTAS:")
        caption.setStyleSheet(_CAPTION_STYLE)
        # Ignored: el rótulo no impone un ancho mínimo que rompa el reparto 50/50
        caption.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        header.addWidget(caption, 1)
        layout.addLayout(header)

        self.editor = FadingScrollTextEdit()
        self.editor.setPlaceholderText("Detalla la actividad, requerimientos, enlaces o notas...")
        self.editor.setStyleSheet(_EDITOR_STYLE)
        _disable_text_drops(self.editor)
        layout.addWidget(self.editor, 1)


class SubtaskPane(QWidget):
    """
    Panel de una subtarea ampliada: check, título y nota en grande.
    Refleja y edita en ambos sentidos al SubtaskEditorItem enlazado.
    """
    close_requested = Signal()
    drag_requested = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._item: Optional[SubtaskEditorItem] = None

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(8)

        caption_row = QHBoxLayout()
        caption_row.setSpacing(6)

        self.drag_handle = DragHandle(self, tooltip="Arrastra para reubicar este panel")
        self.drag_handle.drag_requested.connect(self.drag_requested.emit)
        caption_row.addWidget(self.drag_handle)

        caption = QLabel("SUBTAREA:")
        caption.setStyleSheet(_CAPTION_STYLE)
        caption_row.addWidget(caption, 1)
        layout.addLayout(caption_row)

        header = QHBoxLayout()
        header.setSpacing(8)

        self.btn_check = QPushButton()
        self.btn_check.setFixedSize(24, 24)
        self.btn_check.setCheckable(True)
        self.btn_check.setCursor(Qt.PointingHandCursor)
        self.btn_check.clicked.connect(self._push_check)
        header.addWidget(self.btn_check)

        self.title_edit = QLineEdit()
        self.title_edit.setPlaceholderText("Nombre de la subtarea...")
        self.title_edit.setAcceptDrops(False)
        self.title_edit.textEdited.connect(self._push_title)
        header.addWidget(self.title_edit, 1)

        btn_close = QPushButton("✕")
        btn_close.setFixedSize(22, 22)
        btn_close.setCursor(Qt.PointingHandCursor)
        btn_close.setToolTip("Quitar del espacio de trabajo")
        btn_close.setStyleSheet("""
            QPushButton {
                background: transparent;
                color: #777777;
                border: none;
                font-size: 12px;
                font-weight: bold;
                padding: 0px;
            }
            QPushButton:hover { color: #FFFFFF; }
        """)
        btn_close.clicked.connect(self.close_requested.emit)
        header.addWidget(btn_close)
        layout.addLayout(header)

        self.editor = FadingScrollTextEdit()
        self.editor.setPlaceholderText("Descripción / notas detalladas de la subtarea...")
        self.editor.setStyleSheet(_EDITOR_STYLE)
        _disable_text_drops(self.editor)
        self.editor.textChanged.connect(self._push_note)
        layout.addWidget(self.editor, 1)

        self._apply_check_style(False)

    # ------------------------------------------------------------------
    # Enlace con el ítem
    # ------------------------------------------------------------------
    @property
    def item(self) -> Optional[SubtaskEditorItem]:
        return self._item

    def bind(self, item: SubtaskEditorItem) -> None:
        """Enlaza el panel a una subtarea y copia su estado actual."""
        self.unbind()

        for widget in (self.title_edit, self.editor, self.btn_check):
            widget.blockSignals(True)
        self.title_edit.setText(item.title_input.text())
        self.editor.setPlainText(item.desc_edit.toPlainText())
        self.btn_check.setChecked(item.is_completed())
        for widget in (self.title_edit, self.editor, self.btn_check):
            widget.blockSignals(False)
        self._apply_check_style(item.is_completed())

        self._item = item
        item.title_input.textChanged.connect(self._on_item_title_changed)
        item.desc_edit.textChanged.connect(self._on_item_note_changed)
        item.status_changed.connect(self._on_item_status_changed)

    def unbind(self) -> None:
        item = self._item
        if item is None:
            return
        self._item = None
        try:
            item.title_input.textChanged.disconnect(self._on_item_title_changed)
            item.desc_edit.textChanged.disconnect(self._on_item_note_changed)
            item.status_changed.disconnect(self._on_item_status_changed)
        except (RuntimeError, TypeError):
            # El ítem pudo destruirse antes de desenlazarse
            pass

    # ------------------------------------------------------------------
    # Panel -> ítem
    # ------------------------------------------------------------------
    def _push_title(self, text: str) -> None:
        if self._item and self._item.title_input.text() != text:
            self._item.title_input.setText(text)

    def _push_note(self) -> None:
        if not self._item:
            return
        text = self.editor.toPlainText()
        if self._item.desc_edit.toPlainText() != text:
            self._item.desc_edit.setPlainText(text)

    def _push_check(self) -> None:
        checked = self.btn_check.isChecked()
        self._apply_check_style(checked)
        if self._item and self._item.is_completed() != checked:
            # click() reutiliza la lógica del ítem (estilo, estadísticas y señal)
            self._item.btn_check.click()

    # ------------------------------------------------------------------
    # Ítem -> panel
    # ------------------------------------------------------------------
    def _on_item_title_changed(self, text: str) -> None:
        if self.title_edit.text() != text:
            self.title_edit.setText(text)

    def _on_item_note_changed(self) -> None:
        if not self._item:
            return
        text = self._item.desc_edit.toPlainText()
        if self.editor.toPlainText() != text:
            self.editor.setPlainText(text)

    def _on_item_status_changed(self, checked: bool) -> None:
        if self.btn_check.isChecked() != checked:
            self.btn_check.setChecked(checked)
        self._apply_check_style(checked)

    def _apply_check_style(self, checked: bool) -> None:
        self.btn_check.setText("✓" if checked else "")
        self.btn_check.setStyleSheet(CHECKED_STYLE if checked else UNCHECKED_STYLE)


class DockOverlay(QWidget):
    """Resalta la mitad del espacio de trabajo donde caerá el panel arrastrado."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAttribute(Qt.WA_TransparentForMouseEvents, True)
        self.hide()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.setPen(QPen(QColor("#FFAA77"), 1.5))
        painter.setBrush(QColor(255, 170, 119, 46))
        painter.drawRoundedRect(self.rect().adjusted(1, 1, -1, -1), 5, 5)


class WorkspacePanel(QWidget):
    """
    Zona derecha del detalle: descripción y/o una subtarea ampliada.

    Reglas: por defecto solo la descripción; siempre hay al menos un panel visible;
    con dos paneles se reparten el espacio por igual y su posición se decide arrastrando.
    """

    def __init__(self, parent=None):
        super().__init__(parent)
        self._show_description = True
        self._show_subtask = False
        self._horizontal = True
        self._description_first = True
        self._subtask_resolver: Optional[Callable[[str], Optional[SubtaskEditorItem]]] = None

        self.description_pane = DescriptionPane()
        self.subtask_pane = SubtaskPane()
        self.description_pane.drag_requested.connect(lambda: self._start_pane_drag(KIND_DESCRIPTION))
        self.subtask_pane.drag_requested.connect(lambda: self._start_pane_drag(KIND_SUBTASK))
        self.subtask_pane.close_requested.connect(lambda: self.release_subtask())
        self.subtask_pane.title_edit.textChanged.connect(self._refresh_subtask_chip)

        self.setAcceptDrops(True)

        root = QVBoxLayout(self)
        root.setContentsMargins(0, 0, 0, 0)
        root.setSpacing(8)
        root.addLayout(self._build_header())

        self.content = QWidget()
        self.content_layout = QBoxLayout(QBoxLayout.LeftToRight, self.content)
        self.content_layout.setContentsMargins(0, 0, 0, 0)
        self.content_layout.setSpacing(10)
        root.addWidget(self.content, 1)

        self.dock_overlay = DockOverlay(self.content)

        self._relayout()

    # ------------------------------------------------------------------
    # API pública
    # ------------------------------------------------------------------
    @property
    def description_editor(self) -> FadingScrollTextEdit:
        return self.description_pane.editor

    @property
    def focused_item(self) -> Optional[SubtaskEditorItem]:
        return self.subtask_pane.item

    def set_subtask_resolver(self, resolver: Callable[[str], Optional[SubtaskEditorItem]]) -> None:
        """Registra cómo traducir el id de una subtarea soltada al ítem de la lista."""
        self._subtask_resolver = resolver

    def focus_subtask(self, item: SubtaskEditorItem) -> None:
        """Amplía una subtarea en el espacio de trabajo, manteniendo lo que ya estaba visible."""
        if self.subtask_pane.item is not item:
            self.subtask_pane.bind(item)
        self._show_subtask = True
        self._relayout()

    def release_subtask(self, item: Optional[SubtaskEditorItem] = None) -> None:
        """
        Quita la subtarea ampliada. Si se indica `item`, solo actúa cuando es la enlazada
        (p. ej. al eliminarse esa subtarea de la lista).
        """
        if item is not None and self.subtask_pane.item is not item:
            return
        self.subtask_pane.unbind()
        self._show_subtask = False
        self._show_description = True
        self._relayout()

    # ------------------------------------------------------------------
    # Construcción
    # ------------------------------------------------------------------
    def _build_header(self) -> QHBoxLayout:
        header = QHBoxLayout()
        header.setContentsMargins(0, 0, 0, 0)
        header.setSpacing(6)

        self.chip_description = QPushButton("DESCRIPCIÓN")
        self.chip_description.setCheckable(True)
        self.chip_description.setCursor(Qt.PointingHandCursor)
        self.chip_description.setStyleSheet(_CHIP_STYLE)
        self.chip_description.clicked.connect(self._on_description_chip)
        header.addWidget(self.chip_description)

        self.chip_subtask = QPushButton("SUBTAREA")
        self.chip_subtask.setCheckable(True)
        self.chip_subtask.setCursor(Qt.PointingHandCursor)
        self.chip_subtask.setStyleSheet(_CHIP_STYLE)
        self.chip_subtask.clicked.connect(self._on_subtask_chip)
        header.addWidget(self.chip_subtask)

        header.addStretch()

        self.lbl_hint = QLabel("ARRASTRA UN PANEL PARA REUBICARLO")
        self.lbl_hint.setStyleSheet(_HINT_STYLE)
        self.lbl_hint.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        header.addWidget(self.lbl_hint)
        return header

    # ------------------------------------------------------------------
    # Chips de visibilidad
    # ------------------------------------------------------------------
    def _on_description_chip(self) -> None:
        wants_visible = self.chip_description.isChecked()
        if not wants_visible and not self._show_subtask:
            # Siempre debe quedar al menos un panel visible
            self.chip_description.setChecked(True)
            return
        self._show_description = wants_visible
        self._relayout()

    def _on_subtask_chip(self) -> None:
        wants_visible = self.chip_subtask.isChecked()
        if not wants_visible and not self._show_description:
            self.chip_subtask.setChecked(True)
            return
        self._show_subtask = wants_visible
        self._relayout()

    def _refresh_subtask_chip(self) -> None:
        title = self.subtask_pane.title_edit.text().strip() or "SIN NOMBRE"
        text = f"SUBTAREA: {title.upper()}"
        metrics = QFontMetrics(self.chip_subtask.font())
        self.chip_subtask.setText(metrics.elidedText(text, Qt.ElideRight, 240))
        self.chip_subtask.setToolTip(text)

    # ------------------------------------------------------------------
    # Arrastre: origen (paneles)
    # ------------------------------------------------------------------
    def _both_visible(self) -> bool:
        return self.description_pane.isVisibleTo(self) and self.subtask_pane.isVisibleTo(self)

    def _start_pane_drag(self, kind: str) -> None:
        """Arrastra un panel; solo tiene sentido reubicarlo cuando hay dos visibles."""
        if not self._both_visible():
            return

        pane = self.description_pane if kind == KIND_DESCRIPTION else self.subtask_pane
        drag = QDrag(self)
        mime = QMimeData()
        mime.setData(PANE_MIME, kind.encode("utf-8"))
        drag.setMimeData(mime)

        pixmap = pane.grab().scaledToWidth(
            min(280, max(120, pane.width())), Qt.SmoothTransformation
        )
        drag.setPixmap(pixmap)
        drag.setHotSpot(QPoint(16, 12))
        drag.exec(Qt.MoveAction)
        self.dock_overlay.hide()

    # ------------------------------------------------------------------
    # Arrastre: destino (zonas de acoplamiento)
    # ------------------------------------------------------------------
    def dragEnterEvent(self, event):
        if self._accepts(event.mimeData()):
            event.acceptProposedAction()
        else:
            event.ignore()

    def dragMoveEvent(self, event):
        if not self._accepts(event.mimeData()):
            event.ignore()
            return
        zone = self._zone_at(event.position().toPoint())
        self._show_zone(zone)
        event.acceptProposedAction()

    def dragLeaveEvent(self, event):
        self.dock_overlay.hide()
        super().dragLeaveEvent(event)

    def dropEvent(self, event):
        self.dock_overlay.hide()
        mime = event.mimeData()
        if not self._accepts(mime):
            event.ignore()
            return

        zone = self._zone_at(event.position().toPoint())
        if mime.hasFormat(SUBTASK_MIME):
            subtask_id = bytes(mime.data(SUBTASK_MIME)).decode("utf-8")
            if not self.drop_subtask(subtask_id, zone):
                event.ignore()
                return
        else:
            kind = bytes(mime.data(PANE_MIME)).decode("utf-8")
            self.dock_pane(kind, zone)
        event.acceptProposedAction()

    def drop_subtask(self, subtask_id: str, zone: str) -> bool:
        """Amplía la subtarea soltada y la coloca en la zona indicada."""
        item = self._subtask_resolver(subtask_id) if self._subtask_resolver else None
        if item is None:
            return False
        if self.subtask_pane.item is not item:
            self.subtask_pane.bind(item)
        self._show_subtask = True
        self._place(KIND_SUBTASK, zone)
        return True

    def dock_pane(self, kind: str, zone: str) -> None:
        """Reubica un panel ya visible en la zona indicada."""
        self._place(kind, zone)

    def _place(self, dragged_kind: str, zone: str) -> None:
        """Izquierda/derecha = lado a lado; arriba/abajo = apilado. El arrastrado va en ese lado."""
        self._horizontal = zone in ("left", "right")
        dragged_first = zone in ("left", "top")
        if dragged_kind == KIND_DESCRIPTION:
            self._description_first = dragged_first
        else:
            self._description_first = not dragged_first
        self._relayout()

    def _accepts(self, mime: QMimeData) -> bool:
        if mime.hasFormat(SUBTASK_MIME):
            return True
        return mime.hasFormat(PANE_MIME) and self._both_visible()

    def _zone_at(self, pos: QPoint) -> str:
        """Zona = borde del espacio de trabajo más cercano al cursor."""
        rect = self.content.geometry()
        width = max(1, rect.width())
        height = max(1, rect.height())
        nx = min(1.0, max(0.0, (pos.x() - rect.left()) / width))
        ny = min(1.0, max(0.0, (pos.y() - rect.top()) / height))
        distances = {"left": nx, "right": 1.0 - nx, "top": ny, "bottom": 1.0 - ny}
        return min(distances, key=distances.get)

    def _show_zone(self, zone: str) -> None:
        width = self.content.width()
        height = self.content.height()
        half_w, half_h = width // 2, height // 2
        rects = {
            "left": QRect(0, 0, half_w, height),
            "right": QRect(width - half_w, 0, half_w, height),
            "top": QRect(0, 0, width, half_h),
            "bottom": QRect(0, height - half_h, width, half_h),
        }
        self.dock_overlay.setGeometry(rects[zone])
        self.dock_overlay.show()
        self.dock_overlay.raise_()

    # ------------------------------------------------------------------
    # Distribución
    # ------------------------------------------------------------------
    def _relayout(self) -> None:
        has_subtask = self.subtask_pane.item is not None
        show_subtask = self._show_subtask and has_subtask
        show_description = self._show_description or not show_subtask

        # Retira los paneles del layout sin destruirlos
        while self.content_layout.count():
            self.content_layout.takeAt(0)
        self.description_pane.hide()
        self.subtask_pane.hide()

        panes = []
        if show_description:
            panes.append(self.description_pane)
        if show_subtask:
            panes.append(self.subtask_pane)
        if len(panes) == 2 and not self._description_first:
            panes.reverse()

        self.content_layout.setDirection(
            QBoxLayout.LeftToRight if self._horizontal else QBoxLayout.TopToBottom
        )
        for pane in panes:
            # Stretch idéntico: cada panel ocupa exactamente la mitad cuando hay dos
            self.content_layout.addWidget(pane, 1)
            pane.show()

        both = len(panes) == 2
        self.chip_description.setChecked(show_description)
        self.chip_subtask.setVisible(has_subtask)
        self.chip_subtask.setChecked(show_subtask)
        self._refresh_subtask_chip()
        self.lbl_hint.setVisible(both)
        self.dock_overlay.hide()

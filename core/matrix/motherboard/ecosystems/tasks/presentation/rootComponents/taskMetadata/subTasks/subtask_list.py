"""
Contenedor de la lista de subtareas con reordenamiento por arrastre.

Muestra una línea indicadora de la posición de destino, desplaza el área de scroll
cuando el cursor se acerca a sus bordes y notifica el nuevo orden al soltar.
"""
from typing import List, Optional

from PySide6.QtWidgets import QWidget, QFrame, QAbstractScrollArea
from PySide6.QtCore import Signal

from ..drag_handle import SUBTASK_MIME
from .subtask_item import SubtaskEditorItem


class SubtaskListContainer(QWidget):
    """
    Widget contenedor de SubtaskEditorItem dentro de un QVBoxLayout.

    El layout lo define quien lo hospeda; este widget solo asume que los ítems son
    sus hijos directos en el layout, en el orden visual que representan.

    Signals:
        order_changed(list): identificadores de subtareas en el nuevo orden, tras soltar.
    """
    order_changed = Signal(list)

    AUTOSCROLL_MARGIN = 28
    AUTOSCROLL_STEP = 14

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAcceptDrops(True)

        self._indicator = QFrame(self)
        self._indicator.setFixedHeight(2)
        self._indicator.setStyleSheet("background-color: #FFAA77; border-radius: 1px;")
        self._indicator.hide()

    # ------------------------------------------------------------------
    # API pública
    # ------------------------------------------------------------------
    def items(self) -> List[SubtaskEditorItem]:
        """Ítems en su orden visual actual."""
        found = []
        layout = self.layout()
        if layout is None:
            return found
        for index in range(layout.count()):
            widget = layout.itemAt(index).widget()
            if isinstance(widget, SubtaskEditorItem):
                found.append(widget)
        return found

    def renumber(self) -> None:
        for number, item in enumerate(self.items(), start=1):
            item.set_number(number)

    # ------------------------------------------------------------------
    # Eventos de arrastre
    # ------------------------------------------------------------------
    def dragEnterEvent(self, event):
        if event.mimeData().hasFormat(SUBTASK_MIME):
            event.acceptProposedAction()
        else:
            event.ignore()

    def dragMoveEvent(self, event):
        if not event.mimeData().hasFormat(SUBTASK_MIME):
            event.ignore()
            return

        dragged = self._find_item(self._payload_id(event))
        position = event.position().toPoint()
        others = [item for item in self.items() if item is not dragged]
        self._show_indicator(others, self._target_index(others, position.y()))
        self._autoscroll(position)
        event.acceptProposedAction()

    def dragLeaveEvent(self, event):
        self._indicator.hide()
        super().dragLeaveEvent(event)

    def dropEvent(self, event):
        self._indicator.hide()
        if not event.mimeData().hasFormat(SUBTASK_MIME):
            event.ignore()
            return

        dragged = self._find_item(self._payload_id(event))
        if dragged is None:
            event.ignore()
            return

        others = [item for item in self.items() if item is not dragged]
        target_index = self._target_index(others, event.position().toPoint().y())

        layout = self.layout()
        layout.removeWidget(dragged)
        if others:
            base_index = layout.indexOf(others[0])
        else:
            # Sin otros ítems: queda justo antes del espaciador final
            base_index = max(0, layout.count() - 1)
        layout.insertWidget(base_index + target_index, dragged)

        self.renumber()
        event.acceptProposedAction()
        self.order_changed.emit([item.subtask_id for item in self.items()])

    # ------------------------------------------------------------------
    # Auxiliares
    # ------------------------------------------------------------------
    @staticmethod
    def _payload_id(event) -> str:
        return bytes(event.mimeData().data(SUBTASK_MIME)).decode("utf-8")

    def _find_item(self, subtask_id: str) -> Optional[SubtaskEditorItem]:
        return next((item for item in self.items() if item.subtask_id == subtask_id), None)

    @staticmethod
    def _target_index(others: List[SubtaskEditorItem], cursor_y: int) -> int:
        """Cantidad de ítems cuyo centro queda por encima del cursor = posición de inserción."""
        index = 0
        for item in others:
            if item.geometry().center().y() < cursor_y:
                index += 1
        return index

    def _show_indicator(self, others: List[SubtaskEditorItem], target_index: int) -> None:
        if not others:
            self._indicator.hide()
            return

        if target_index == 0:
            boundary = others[0].geometry().top() - 3
        else:
            boundary = others[target_index - 1].geometry().bottom() + 3

        margin = 6
        self._indicator.setGeometry(margin, boundary - 1, max(0, self.width() - 2 * margin), 2)
        self._indicator.show()
        self._indicator.raise_()

    def _autoscroll(self, position) -> None:
        area = self.parentWidget()
        while area is not None and not isinstance(area, QAbstractScrollArea):
            area = area.parentWidget()
        if area is None:
            return

        viewport = area.viewport()
        local_y = self.mapTo(viewport, position).y()
        bar = area.verticalScrollBar()
        if local_y < self.AUTOSCROLL_MARGIN:
            bar.setValue(bar.value() - self.AUTOSCROLL_STEP)
        elif local_y > viewport.height() - self.AUTOSCROLL_MARGIN:
            bar.setValue(bar.value() + self.AUTOSCROLL_STEP)

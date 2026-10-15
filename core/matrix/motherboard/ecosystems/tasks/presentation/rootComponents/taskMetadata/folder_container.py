"""
Contenedor con diseño de archivador (Folder Container).
Integra las pestañas configurables ('General', 'Subtareas', 'Cronómetro')
directamente en su contorno superior perimetral.
"""
from typing import Optional, List, Tuple
from PySide6.QtWidgets import QWidget, QVBoxLayout
from PySide6.QtCore import Qt, Signal, QRectF
from PySide6.QtGui import QPainter, QColor, QPen, QBrush, QFont, QPainterPath


class FolderContainer(QWidget):
    """
    Contenedor principal del panel izquierdo con pestañas de archivador (Folder Card).
    Las pestañas forman parte del contorno superior del cuadro como parte de su diseño exterior,
    unificando la solapa activa y el contenido en una sola superficie continua.
    """
    tabChanged = Signal(int)

    def __init__(self, parent=None, tabs_def: Optional[List[Tuple[str, str]]] = None):
        super().__init__(parent)
        self.active_tab = 0
        self.hover_tab = -1
        
        # Lista de tuplas: (título, subtítulo)
        if tabs_def:
            self.tabs: List[List[str]] = [[t[0], t[1]] for t in tabs_def]
        else:
            self.tabs = [
                ["General", "Parámetros y fecha"],
                ["Subtareas", "Sin subtareas"]
            ]

        self.setMouseTracking(True)
        self.setAttribute(Qt.WA_Hover, True)

        self.layout_inner = QVBoxLayout(self)
        self.layout_inner.setContentsMargins(14, 56, 14, 12)
        self.layout_inner.setSpacing(8)

    def set_current_index(self, index: int):
        if 0 <= index < len(self.tabs) and self.active_tab != index:
            self.active_tab = index
            self.tabChanged.emit(index)
            self.update()

    def update_tab_subtitle(self, index: int, subtitle: str):
        if 0 <= index < len(self.tabs):
            self.tabs[index][1] = subtitle
            self.update()

    def update_subtasks_count(self, total: int, completed: int):
        # Compatibilidad con código previo
        if len(self.tabs) > 1:
            if total == 0:
                self.tabs[1][1] = "Sin subtareas"
            else:
                self.tabs[1][1] = f"{completed}/{total} completadas"
            self.update()

    def _get_tab_width(self) -> float:
        n = len(self.tabs)
        if n == 2:
            return 155.0
        elif n == 3:
            return 124.0
        return max(100.0, 310.0 / n)

    def mouseMoveEvent(self, event):
        pos = event.position()
        x, y = pos.x(), pos.y()
        step_y = 46.0
        tab_w = self._get_tab_width()
        new_hover = -1

        if y <= step_y:
            for i in range(len(self.tabs)):
                if (i * tab_w) <= x < ((i + 1) * tab_w):
                    if self.active_tab != i:
                        new_hover = i
                    break

        if new_hover != self.hover_tab:
            self.hover_tab = new_hover
            self.setCursor(Qt.PointingHandCursor if new_hover != -1 else Qt.ArrowCursor)
            self.update()
        super().mouseMoveEvent(event)

    def leaveEvent(self, event):
        self.hover_tab = -1
        self.setCursor(Qt.ArrowCursor)
        self.update()
        super().leaveEvent(event)

    def mousePressEvent(self, event):
        if event.button() == Qt.LeftButton:
            pos = event.position()
            x, y = pos.x(), pos.y()
            step_y = 46.0
            tab_w = self._get_tab_width()
            if y <= step_y:
                for i in range(len(self.tabs)):
                    if (i * tab_w) <= x < ((i + 1) * tab_w):
                        self.set_current_index(i)
                        event.accept()
                        return
        super().mousePressEvent(event)

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        w = float(self.width())
        h = float(self.height())
        step_y = 46.0
        tab_w = self._get_tab_width()
        chamfer = 14.0
        r = 6.0
        num_tabs = len(self.tabs)
        act = self.active_tab

        bg_card = QColor("#1C1C1C")
        border_col = QColor("#333333")
        pen_border = QPen(border_col, 1.0)

        # 1. Dibujar solapas secundarias inactivas primero
        for i in range(num_tabs):
            if i == act:
                continue

            tab_x = (i * tab_w) + (4.0 if i > 0 else 2.0)
            tab_bg = QColor("#141414") if self.hover_tab != i else QColor("#1E1E1E")
            p_tab = QPainterPath()
            p_tab.moveTo(tab_x, step_y)
            p_tab.lineTo(tab_x, 10.0 + r)
            p_tab.quadTo(tab_x, 10.0, tab_x + r, 10.0)
            p_tab.lineTo(tab_x + tab_w - 6.0 - r, 10.0)
            p_tab.quadTo(tab_x + tab_w - 6.0, 10.0, tab_x + tab_w - 6.0, 10.0 + r)
            p_tab.lineTo(tab_x + tab_w - 6.0, step_y)
            p_tab.closeSubpath()

            painter.fillPath(p_tab, QBrush(tab_bg))
            painter.setPen(QPen(QColor("#2A2A2A"), 1.0))
            painter.drawPath(p_tab)

            # Textos inactivos
            painter.setPen(QColor("#CCCCCC") if self.hover_tab == i else QColor("#777777"))
            painter.setFont(QFont("Prototype", 10, QFont.Bold))
            painter.drawText(
                QRectF(tab_x + 10.0, 12.0, tab_w - 20.0, 16.0),
                Qt.AlignLeft | Qt.AlignVCenter,
                self.tabs[i][0]
            )

            painter.setPen(QColor("#888888") if self.hover_tab == i else QColor("#555555"))
            painter.setFont(QFont("Prototype", 8))
            painter.drawText(
                QRectF(tab_x + 10.0, 28.0, tab_w - 20.0, 14.0),
                Qt.AlignLeft | Qt.AlignVCenter,
                self.tabs[i][1]
            )

        # 2. Trazar el cuerpo unificado que integra la pestaña activa
        path = QPainterPath()
        act_x = act * tab_w

        if act == 0:
            path.moveTo(0.0, step_y)
            path.lineTo(0.0, r)
            path.quadTo(0.0, 0.0, r, 0.0)
            path.lineTo(tab_w - chamfer, 0.0)
            path.quadTo(tab_w - chamfer * 0.4, chamfer * 0.4, tab_w, chamfer + 8.0)
            path.lineTo(tab_w, step_y)
        else:
            path.moveTo(0.0, step_y + r)
            path.quadTo(0.0, step_y, r, step_y)
            path.lineTo(act_x, step_y)
            path.lineTo(act_x, r)
            path.quadTo(act_x, 0.0, act_x + r, 0.0)
            path.lineTo(act_x + tab_w - chamfer, 0.0)
            path.quadTo(act_x + tab_w - chamfer * 0.4, chamfer * 0.4, act_x + tab_w, chamfer + 8.0)
            path.lineTo(act_x + tab_w, step_y)

        path.lineTo(w - r, step_y)
        path.quadTo(w, step_y, w, step_y + r)
        path.lineTo(w, h - r)
        path.quadTo(w, h, w - r, h)
        path.lineTo(r, h)
        path.quadTo(0.0, h, 0.0, h - r)
        path.lineTo(0.0, step_y + r if act > 0 else step_y)
        path.closeSubpath()

        painter.fillPath(path, QBrush(bg_card))
        painter.setPen(pen_border)
        painter.drawPath(path)

        # 3. Textos de la Pestaña Activa
        painter.setPen(QColor("#FFFFFF"))
        painter.setFont(QFont("Prototype", 11, QFont.Bold))
        painter.drawText(
            QRectF(act_x + 12.0, 6.0, tab_w - chamfer - 10.0, 18.0),
            Qt.AlignLeft | Qt.AlignVCenter,
            self.tabs[act][0]
        )

        painter.setPen(QColor("#FFAA77" if act == 2 else "#9E9E9E"))
        painter.setFont(QFont("Prototype", 9))
        painter.drawText(
            QRectF(act_x + 12.0, 24.0, tab_w - chamfer - 10.0, 16.0),
            Qt.AlignLeft | Qt.AlignVCenter,
            self.tabs[act][1]
        )

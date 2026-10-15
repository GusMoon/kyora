"""
Componente base modal con estilo Sci-Fi y soporte de arrastre flotante interactivo.
"""
from PySide6.QtWidgets import QDialog
from PySide6.QtCore import Qt
from core.matrix.motherboard.globalComponents.styles import get_minimal_scrollbar_style


class SciFiBaseModal(QDialog):
    """
    Modal base con estilo Sci-Fi para el ecosistema de tareas.
    Permite arrastre interactivo por pantalla para ser completamente flotante y movible.
    """

    def __init__(self, parent=None, width=920, height=550):
        super().__init__(parent)
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.Dialog)
        self.resize(width, height)
        # No permitir tamaño menor a las dimensiones originales
        self.setMinimumSize(width, height)
        self.setMouseTracking(True)

        self._drag_pos = None
        self._margin = 8
        self._hover_edge = None
        self._active_resize_edge = None
        self._resize_start_pos = None
        self._resize_start_geo = None
        self._is_geometry_locked = False

        self._apply_base_style()

    def fit_to_rect(self, rect):
        """
        Ajusta el modal a un rectángulo (p. ej. toda la ventana) y bloquea
        arrastre y redimensionado mientras permanezca maximizado.

        Args:
            rect: QRect en coordenadas globales de pantalla.
        """
        self._is_geometry_locked = True
        self.setMinimumSize(min(self.minimumWidth(), rect.width()), min(self.minimumHeight(), rect.height()))
        self.setGeometry(rect)

    def _determine_edge(self, pos):
        x, y = pos.x(), pos.y()
        w, h = self.width(), self.height()
        m = self._margin

        on_left = (x <= m)
        on_right = (x >= w - m)
        on_top = (y <= m)
        on_bottom = (y >= h - m)

        if on_top and on_left:
            return "top_left"
        elif on_bottom and on_right:
            return "bottom_right"
        elif on_top and on_right:
            return "top_right"
        elif on_bottom and on_left:
            return "bottom_left"
        elif on_left:
            return "left"
        elif on_right:
            return "right"
        elif on_top:
            return "top"
        elif on_bottom:
            return "bottom"
        return None

    def _update_cursor_for_edge(self, edge):
        if edge in ("top_left", "bottom_right"):
            self.setCursor(Qt.SizeFDiagCursor)
        elif edge in ("top_right", "bottom_left"):
            self.setCursor(Qt.SizeBDiagCursor)
        elif edge in ("left", "right"):
            self.setCursor(Qt.SizeHorCursor)
        elif edge in ("top", "bottom"):
            self.setCursor(Qt.SizeVerCursor)
        else:
            self.setCursor(Qt.ArrowCursor)

    def mousePressEvent(self, event):
        if self._is_geometry_locked:
            super().mousePressEvent(event)
            return
        if event.button() == Qt.LeftButton:
            edge = self._determine_edge(event.position().toPoint())
            if edge:
                self._active_resize_edge = edge
                self._resize_start_pos = event.globalPosition().toPoint()
                self._resize_start_geo = self.geometry()
                event.accept()
                return
            else:
                self._active_resize_edge = None
                self._drag_pos = event.globalPosition().toPoint() - self.frameGeometry().topLeft()
                event.accept()
                return
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event):
        if self._is_geometry_locked:
            super().mouseMoveEvent(event)
            return
        pos = event.position().toPoint()

        # Si se está redimensionando
        if (event.buttons() & Qt.LeftButton) and self._active_resize_edge:
            diff = event.globalPosition().toPoint() - self._resize_start_pos
            geo = self._resize_start_geo
            x, y, w, h = geo.x(), geo.y(), geo.width(), geo.height()
            min_w, min_h = self.minimumWidth(), self.minimumHeight()

            edge = self._active_resize_edge
            new_x, new_y, new_w, new_h = x, y, w, h

            if "left" in edge:
                new_w = max(min_w, w - diff.x())
                new_x = x + (w - new_w)
            elif "right" in edge:
                new_w = max(min_w, w + diff.x())

            if "top" in edge:
                new_h = max(min_h, h - diff.y())
                new_y = y + (h - new_h)
            elif "bottom" in edge:
                new_h = max(min_h, h + diff.y())

            self.setGeometry(new_x, new_y, new_w, new_h)
            event.accept()
            return

        # Si se está moviendo la ventana
        elif (event.buttons() & Qt.LeftButton) and self._drag_pos is not None:
            self.move(event.globalPosition().toPoint() - self._drag_pos)
            event.accept()
            return

        # Si solo se está moviendo el ratón sin presionar: actualizar cursor según el borde
        edge = self._determine_edge(pos)
        self._hover_edge = edge
        self._update_cursor_for_edge(edge)
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event):
        self._active_resize_edge = None
        self._drag_pos = None
        edge = self._determine_edge(event.position().toPoint())
        self._update_cursor_for_edge(edge)
        super().mouseReleaseEvent(event)

    def leaveEvent(self, event):
        if not self._active_resize_edge:
            self.setCursor(Qt.ArrowCursor)
            self._hover_edge = None
        super().leaveEvent(event)

    def _apply_base_style(self):
        self.setStyleSheet(f"""
            QDialog {{
                background-color: #121212;
                border: 1px solid #444444;
                border-radius: 6px;
            }}
            QLabel {{
                color: #FFFFFF;
                font-family: 'Prototype';
                font-size: 13px;
                background-color: transparent;
            }}
            QLabel#Title {{
                color: #FFFFFF;
                font-weight: 900;
                font-size: 13px;
                letter-spacing: 2px;
                font-family: 'Prototype';
            }}
            QLabel#SubInfo {{
                color: #888888;
                font-size: 11px;
                font-family: 'Prototype';
            }}
            QLineEdit {{
                background-color: #242424;
                border: 1px solid #3E3E3E;
                color: #FFFFFF;
                padding: 7px 10px;
                font-family: 'Prototype';
                font-size: 12px;
                border-radius: 4px;
            }}
            QLineEdit:focus {{
                border: 1px solid #FFAA77;
            }}
            QDateEdit {{
                background-color: #242424;
                border: 1px solid #3E3E3E;
                color: #FFFFFF;
                padding: 4px 8px;
                font-family: 'Prototype';
                font-size: 12px;
                border-radius: 4px;
                min-width: 80px;
            }}
            QDateEdit:focus {{
                border: 1px solid #FFAA77;
            }}
            QDateEdit::drop-down {{
                width: 0px;
                height: 0px;
                border: none;
                background: transparent;
            }}
            QCalendarWidget QWidget#qt_datetimedit_calendar {{
                background-color: #161616;
            }}
            QCalendarWidget QAbstractItemView:enabled {{
                background-color: #1A1A1A;
                color: #EEEEEE;
                selection-background-color: #A04A2C;
                selection-color: #FFFFFF;
            }}
            QCalendarWidget QToolButton {{
                background-color: #222222;
                color: #FFFFFF;
                border: 1px solid #333333;
                border-radius: 3px;
                font-size: 11px;
                padding: 2px 4px;
            }}
            QCalendarWidget QToolButton:hover {{
                border: 1px solid #FFAA77;
            }}
            QCalendarWidget QMenu {{
                background-color: #1E1E1E;
                color: #FFFFFF;
                border: 1px solid #3E3E3E;
            }}
            QCalendarWidget QSpinBox {{
                background-color: #242424;
                color: #FFFFFF;
                border: 1px solid #3E3E3E;
            }}
            QPushButton {{
                background-color: #242424;
                color: #FFFFFF;
                border: 1px solid #444444;
                padding: 7px 16px;
                font-weight: bold;
                font-family: 'Prototype';
                font-size: 11px;
                border-radius: 4px;
                letter-spacing: 1px;
            }}
            QPushButton:hover {{
                background-color: #333333;
                border: 1px solid #888888;
            }}
            QPushButton#PrimaryBtn {{
                background-color: #A04A2C;
                border: 1px solid #D46B3C;
                color: #FFFFFF;
            }}
            QPushButton#PrimaryBtn:hover {{
                background-color: #B85834;
                border: 1px solid #FFAA77;
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

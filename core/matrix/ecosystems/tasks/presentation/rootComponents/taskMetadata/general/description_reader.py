"""
Overlay de enfoque para la lectura de la descripción de una tarea.

Cubre el área de TasksView con un velo oscuro y muestra dos zonas a la izquierda:
la tarjeta de descripción (solo título y texto) y, a su lado, una réplica de la tarea
a la que pertenece con las acciones "abrir tarea" y "cerrar". Al ser independiente del
TaskCard, la lectura no altera la altura ni las proporciones de las tarjetas del tablero.
"""
from typing import Optional

from PySide6.QtWidgets import (
    QWidget, QFrame, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QTextEdit
)
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor, QFontMetrics, QPainter, QTextOption

from ..fading_text_edit import FadingScrollTextEdit


class DescriptionReader(QWidget):
    """
    Overlay de lectura de descripción con identificación de la tarea.

    Se cierra con el botón ✕ / CERRAR, la tecla Esc o un clic en el área vacía.
    El desenfoque del fondo lo gestiona quien lo hospeda, escuchando `closed`.
    """
    open_task_requested = Signal(str)
    closed = Signal()

    DESCRIPTION_WIDTH = 520
    SIDE_WIDTH = 372
    OUTER_MARGIN = 24
    COLUMN_SPACING = 16

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setFocusPolicy(Qt.StrongFocus)

        self._task_id = ""
        self._title_text = ""
        self._preview: Optional[QWidget] = None

        self._setup_ui()
        self.hide()

    # ------------------------------------------------------------------
    # Construcción
    # ------------------------------------------------------------------
    def _setup_ui(self):
        root = QHBoxLayout(self)
        root.setContentsMargins(
            self.OUTER_MARGIN, self.OUTER_MARGIN, self.OUTER_MARGIN, self.OUTER_MARGIN
        )
        root.setSpacing(self.COLUMN_SPACING)

        self.description_card = self._build_description_card()
        root.addWidget(self.description_card)

        self.side_column = self._build_side_column()
        root.addWidget(self.side_column)
        root.addStretch()

    def _build_description_card(self) -> QFrame:
        card = QFrame()
        card.setObjectName("DescriptionCard")
        card.setAttribute(Qt.WA_StyledBackground, True)
        card.setFixedWidth(self.DESCRIPTION_WIDTH)
        card.setStyleSheet("""
            QFrame#DescriptionCard {
                background-color: #141414;
                border: 1px solid #444444;
                border-radius: 6px;
            }
            QLabel {
                background: transparent;
                font-family: 'Space Grotesk';
            }
        """)

        layout = QVBoxLayout(card)
        layout.setContentsMargins(16, 12, 16, 16)
        layout.setSpacing(10)

        header = QHBoxLayout()
        caption = QLabel("DESCRIPCIÓN")
        caption.setStyleSheet(
            "color: #FFAA77; font-size: 10px; font-weight: bold; letter-spacing: 2px;"
        )
        header.addWidget(caption)
        header.addStretch()

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
        btn_close.clicked.connect(self.close_reader)
        header.addWidget(btn_close)
        layout.addLayout(header)

        self.title_lbl = QLabel()
        self.title_lbl.setStyleSheet(
            "color: #FFFFFF; font-size: 15px; font-weight: 900; letter-spacing: 0.8px;"
        )
        layout.addWidget(self.title_lbl)

        separator = QFrame()
        separator.setFixedHeight(1)
        separator.setStyleSheet("background-color: #2A2A2A;")
        layout.addWidget(separator)

        # QTextEdit de solo lectura: ajusta el texto al ancho (incluso palabras largas)
        # y nunca muestra scroll horizontal.
        self.text_view = FadingScrollTextEdit(card, bg_color=QColor(10, 10, 10))
        self.text_view.setReadOnly(True)
        self.text_view.setFrameShape(QFrame.NoFrame)
        self.text_view.setLineWrapMode(QTextEdit.WidgetWidth)
        self.text_view.setWordWrapMode(QTextOption.WrapAtWordBoundaryOrAnywhere)
        self.text_view.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self.text_view.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        layout.addWidget(self.text_view, 1)
        return card

    def _build_side_column(self) -> QWidget:
        column = QWidget()
        column.setFixedWidth(self.SIDE_WIDTH)

        self.side_layout = QVBoxLayout(column)
        self.side_layout.setContentsMargins(0, 0, 0, 0)
        self.side_layout.setSpacing(12)

        caption = QLabel("PERTENECE A LA TAREA")
        caption.setStyleSheet(
            "color: #FFAA77; font-size: 10px; font-weight: bold; "
            "font-family: 'Space Grotesk'; letter-spacing: 2px; background: transparent;"
        )
        self.side_layout.addWidget(caption)

        # Marcador donde se inserta la réplica de la tarea (índice 1)
        actions = QHBoxLayout()
        actions.setSpacing(10)

        self.btn_open = QPushButton("ABRIR TAREA")
        self.btn_open.setCursor(Qt.PointingHandCursor)
        self.btn_open.setStyleSheet("""
            QPushButton {
                background-color: #A31F34;
                border: 1px solid #C42B42;
                color: #FFFFFF;
                font-weight: bold;
                padding: 8px 18px;
                font-size: 11px;
                font-family: 'Space Grotesk';
                letter-spacing: 0.8px;
                border-radius: 4px;
            }
            QPushButton:hover { background-color: #B9263D; }
        """)
        self.btn_open.clicked.connect(self._on_open_clicked)
        actions.addWidget(self.btn_open)

        self.btn_dismiss = QPushButton("CERRAR")
        self.btn_dismiss.setCursor(Qt.PointingHandCursor)
        self.btn_dismiss.setStyleSheet("""
            QPushButton {
                background-color: #242424;
                border: 1px solid #3E3E3E;
                color: #CCCCCC;
                font-weight: bold;
                padding: 8px 18px;
                font-size: 11px;
                font-family: 'Space Grotesk';
                letter-spacing: 0.8px;
                border-radius: 4px;
            }
            QPushButton:hover { background-color: #303030; color: #FFFFFF; }
        """)
        self.btn_dismiss.clicked.connect(self.close_reader)
        actions.addWidget(self.btn_dismiss)
        actions.addStretch()

        self.side_layout.addLayout(actions)
        self.side_layout.addStretch()
        return column

    # ------------------------------------------------------------------
    # API pública
    # ------------------------------------------------------------------
    def show_description(self, task_id: str, title: str, description: str, preview: QWidget) -> None:
        """
        Muestra el overlay para una tarea.

        Args:
            task_id: Identificador de la tarea (se emite al pulsar ABRIR TAREA).
            title: Nombre de la tarea.
            description: Texto completo a leer.
            preview: Réplica visual de la tarea; el overlay toma su propiedad.
        """
        self._discard_preview()
        self._task_id = task_id
        self._title_text = (title or "").upper()
        self.text_view.setPlainText(description or "")

        self._preview = preview
        self._preview.setParent(self.side_column)
        # Inserta la réplica entre el rótulo y los botones
        self.side_layout.insertWidget(1, self._preview)
        self._preview.show()

        self.reposition()
        self.show()
        self.raise_()
        self.setFocus()

    def reposition(self) -> None:
        """Cubre por completo el widget padre."""
        parent = self.parentWidget()
        if parent is None:
            return
        self.setGeometry(0, 0, parent.width(), parent.height())
        self._refresh_title()

    def close_reader(self) -> None:
        if not self.isVisible():
            return
        self.hide()
        self._discard_preview()
        self.closed.emit()

    # ------------------------------------------------------------------
    # Eventos
    # ------------------------------------------------------------------
    def paintEvent(self, event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor(0, 0, 0, 110))

    def mousePressEvent(self, event):
        # Un clic fuera de las tarjetas cierra el enfoque
        if event.button() == Qt.LeftButton:
            pos = event.position().toPoint()
            inside_cards = (
                self.description_card.geometry().contains(pos)
                or self.side_column.geometry().contains(pos)
            )
            if not inside_cards:
                self.close_reader()
        event.accept()

    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Escape:
            self.close_reader()
            event.accept()
            return
        super().keyPressEvent(event)

    # ------------------------------------------------------------------
    # Auxiliares
    # ------------------------------------------------------------------
    def _on_open_clicked(self):
        task_id = self._task_id
        self.close_reader()
        self.open_task_requested.emit(task_id)

    def _discard_preview(self) -> None:
        if self._preview is None:
            return
        self.side_layout.removeWidget(self._preview)
        self._preview.setParent(None)
        self._preview.deleteLater()
        self._preview = None

    def _refresh_title(self) -> None:
        """Recorta el título con puntos suspensivos para que nunca desborde la tarjeta."""
        metrics = QFontMetrics(self.title_lbl.font())
        available = self.DESCRIPTION_WIDTH - 40
        self.title_lbl.setText(metrics.elidedText(self._title_text, Qt.ElideRight, available))
